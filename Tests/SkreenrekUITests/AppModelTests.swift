import CoreGraphics
import Foundation
import SkreenrekControl
import SkreenrekCore
import SkreenrekTesting
import SkreenrekUI
import Synchronization
import Testing

/// A test wait that took longer than its watchdog.
struct WaitTimedOut: Error, CustomStringConvertible {
    var what: String
    var seconds: Double
    var description: String { "Gave up after \(seconds) s waiting for \(what)." }
}

/// Runs `body` on the main actor, failing with `WaitTimedOut` after `seconds` of real time instead of hanging. The
/// caller isn't on the main actor, so the watchdog still fires when the main actor is stuck; it only bounds the wait
/// and never drives the test's timing.
func onMain<T: Sendable>(
    _ what: String, seconds: Double = 30, _ body: @escaping @MainActor @Sendable () async throws -> T
) async throws -> T {
    let gate = ResumeOnce<T>()
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
        gate.set(continuation)
        let task = Task { @MainActor in
            do {
                gate.finish(.success(try await body()))
            } catch {
                gate.finish(.failure(error))
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            if gate.finish(.failure(WaitTimedOut(what: what, seconds: seconds))) { task.cancel() }
        }
    }
}

private final class ResumeOnce<T: Sendable>: Sendable {
    private let state = Mutex<(continuation: CheckedContinuation<T, any Error>?, done: Bool)>((nil, false))

    func set(_ continuation: CheckedContinuation<T, any Error>) {
        state.withLock { $0.continuation = continuation }
    }

    @discardableResult
    func finish(_ result: Result<T, any Error>) -> Bool {
        let continuation = state.withLock { s -> CheckedContinuation<T, any Error>? in
            guard !s.done else { return nil }
            s.done = true
            return s.continuation
        }
        continuation?.resume(with: result)
        return continuation != nil
    }
}

/// Records what the model asked the system to do.
@MainActor
final class RecordingEffects: UIEffects {
    var revealed: [String] = []
    var opened: [URL] = []
    var copied: [String] = []
    var settingsOpened = 0
    var discardAnswer = false
    var discardAsked = 0
    var folderAnswer: URL?
    var sizeAnswer: PixelSize?
    var sizeAsked: [(PixelSize?, Double)] = []
    var quitCalls = 0

    func revealInFinder(_ path: String) { revealed.append(path) }
    func open(_ url: URL) { opened.append(url) }
    func copy(_ text: String) { copied.append(text) }
    func openSettings() { settingsOpened += 1 }
    func confirmDiscard() async -> Bool {
        discardAsked += 1
        return discardAnswer
    }
    func chooseFolder(current: URL) async -> URL? { folderAnswer }
    func askCustomSize(current: PixelSize?, scale: Double) async -> PixelSize? {
        sizeAsked.append((current, scale))
        return sizeAnswer
    }
    func scale(of display: DisplayID?) -> Double { 2 }
    func quit() { quitCalls += 1 }
}

/// An `AppModel` over the real controller with the fakes.
@MainActor
struct MenuHarness {
    static let display = DisplayInfo(
        id: 1, name: "Built-in Retina Display", scale: 2, frame: PointRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: PointRect(x: 0, y: 33, width: 1512, height: 949))

    let resizer = FakeWindowResizer()
    let permissions = FakePermissionProbe()
    let picker = FakeWindowPicker(result: .window(UIFixtures.safari.id))
    let effects = RecordingEffects()
    let controller: SkreenrekController
    let model: AppModel
    let defaultsName = "skreenrek.tests.\(UUID().uuidString)"

    init() {
        let clock = ManualClock()
        let seams = ControllerSeams(
            catalog: FakeWindowCatalog(windows: [UIFixtures.safari], displays: [Self.display]), resizer: resizer,
            frameSource: SyntheticFrameSource(count: 1, fps: 30), mouse: FakeMouseEventSource(), clock: clock,
            permissions: permissions, disk: FakeDiskSpaceProbe(), picker: picker, ownPid: 99, encoder: .software)
        controller = SkreenrekController(seams: seams)
        let store = SettingsStore(defaults: UserDefaults(suiteName: defaultsName)!)
        model = AppModel(controller: controller, settings: store, effects: effects)
    }

    /// Performs an action, then takes the controller's snapshot (as the stream would deliver it).
    func perform(_ action: MenuAction) async {
        await model.perform(action)
        model.apply(await controller.snapshot())
    }

    var firstLine: String { model.entries.first?.line ?? "" }

    func cleanUp() {
        UserDefaults.standard.removePersistentDomain(forName: defaultsName)
    }
}

/// Each test runs its body on the main actor under a hard timeout.
@Suite struct AppModelTests {
    @Test func pickArmsTheWindow() async throws {
        try await onMain("pickArmsTheWindow") {
            let h = MenuHarness()
            defer { h.cleanUp() }
            await h.perform(.pickWindow)
            #expect(h.model.context.displayState == .armed)
            #expect(h.firstLine == "[viewfinder] Safari — localhost:3000 | 1280 × 800 px")
            #expect(h.model.icon.sentence == "Skreenrek is ready to record Safari at 1280 × 800 pixels.")
        }
    }

    @Test func choosingASizeWhileArmedResizesNow() async throws {
        try await onMain("choosingASizeWhileArmedResizesNow") {
            let h = MenuHarness()
            defer { h.cleanUp() }
            await h.perform(.pickWindow)
            await h.perform(.chooseSize(.size(PixelSize(width: 1280, height: 720))))
            #expect(h.resizer.calls.count == 1)
            #expect(h.resizer.calls.first?.requested.width == 640)
            #expect(h.resizer.calls.first?.requested.height == 360)
            #expect(h.firstLine == "[viewfinder] Safari — localhost:3000 | 1280 × 720 px · exact size")
            #expect(h.model.settings.sizeChoice == .size(PixelSize(width: 1280, height: 720)))
        }
    }

    @Test func aSizeTheWindowCantTakeShowsNotExact() async throws {
        try await onMain("aSizeTheWindowCantTakeShowsNotExact") {
            let h = MenuHarness()
            defer { h.cleanUp() }
            h.resizer.rules = ResizeRules(minimumSize: CGSize(width: 643, height: 100))
            await h.perform(.pickWindow)
            await h.perform(.chooseSize(.size(PixelSize(width: 1280, height: 800))))
            #expect(
                h.firstLine == "[viewfinder] Safari — localhost:3000 | 1286 × 800 px · not exact (min width 1286 px)")
            #expect(h.model.context.error == nil)
        }
    }

    @Test func choosingASizeWhileIdleOnlySetsTheNextSize() async throws {
        try await onMain("choosingASizeWhileIdleOnlySetsTheNextSize") {
            let h = MenuHarness()
            defer { h.cleanUp() }
            await h.perform(.chooseSize(.keepCurrent))
            #expect(h.resizer.calls.isEmpty)
            #expect(h.model.settings.sizeChoice == .keepCurrent)
        }
    }

    @Test func customSizeAsksWithTheDisplayScale() async throws {
        try await onMain("customSizeAsksWithTheDisplayScale") {
            let h = MenuHarness()
            defer { h.cleanUp() }
            await h.perform(.pickWindow)
            h.effects.sizeAnswer = PixelSize(width: 1000, height: 600)
            await h.perform(.customSize)
            #expect(h.effects.sizeAsked.first?.0 == PixelSize(width: 1280, height: 800))
            #expect(h.effects.sizeAsked.first?.1 == 2)
            #expect(h.firstLine == "[viewfinder] Safari — localhost:3000 | 1000 × 600 px · exact size")
        }
    }

    @Test func resizeWithoutAccessibilityShowsTheErrorRowUntilTheMenuClosesOnce() async throws {
        try await onMain("resizeWithoutAccessibilityShowsTheErrorRowUntilTheMenuClosesOnce") {
            let h = MenuHarness()
            defer { h.cleanUp() }
            await h.perform(.pickWindow)
            h.permissions.accessibility = .missing
            await h.perform(.chooseSize(.size(PixelSize(width: 1440, height: 900))))
            #expect(h.firstLine.contains("Can't resize windows"))
            #expect(h.model.icon.symbol == "exclamationmark.triangle")

            h.model.menuWillOpen()
            await h.model.menuDidClose()
            #expect(h.model.context.error == nil)
            #expect(h.model.context.displayState == .armed)
        }
    }

    @Test func recordWithoutScreenRecordingShowsItsFix() async throws {
        try await onMain("recordWithoutScreenRecordingShowsItsFix") {
            let h = MenuHarness()
            defer { h.cleanUp() }
            await h.perform(.pickWindow)
            h.permissions.screenRecording = .missing
            await h.perform(.record)
            // Record resized first to the chosen size, then stopped at the permission.
            #expect(h.resizer.calls.count == 1)
            #expect(
                h.model.entries.prefix(2).map(\.line) == [
                    "[exclamationmark.triangle] Screen Recording is off | Allow Skreenrek in System Settings › Privacy & "
                        + "Security, then reopen it.",
                    "Open Privacy Settings…",
                ])
            await h.perform(.openPrivacySettings(.screenRecording))
            #expect(h.effects.opened == [PrivacyPane.url(.screenRecording)])
        }
    }

    @Test func theNextActionClearsTheError() async throws {
        try await onMain("theNextActionClearsTheError") {
            let h = MenuHarness()
            defer { h.cleanUp() }
            h.picker.failure = SkreenrekError.permissionDenied(.screenRecording)
            await h.perform(.pickWindow)
            #expect(h.model.context.displayState == .error)
            h.picker.failure = nil
            await h.perform(.pickWindow)
            #expect(h.model.context.displayState == .armed)
        }
    }

    @Test func recordSkipsTheResizeWhenTheWindowAlreadyHasTheSize() async throws {
        try await onMain("recordSkipsTheResizeWhenTheWindowAlreadyHasTheSize") {
            let h = MenuHarness()
            defer { h.cleanUp() }
            await h.perform(.pickWindow)
            await h.perform(.chooseSize(.size(PixelSize(width: 1280, height: 800))))
            h.permissions.screenRecording = .missing
            await h.perform(.record)
            #expect(h.resizer.calls.count == 1)
        }
    }

    @Test func togglesAndFrameRateFeedTheController() async throws {
        try await onMain("togglesAndFrameRateFeedTheController") {
            let h = MenuHarness()
            defer { h.cleanUp() }
            await h.perform(.toggleCursor)
            await h.perform(.toggleEvents)
            await h.perform(.chooseFrameRate(.fps30))
            let settings = await h.controller.currentSettings
            #expect(!settings.cursor)
            #expect(!settings.events)
            #expect(settings.fps == .fps30)
            #expect(h.model.entries.map(\.line).contains("Show Cursor"))
            #expect(h.model.entries.map(\.line).contains("Frame Rate ▸ 30 fps"))
        }
    }

    @Test func systemActionsGoToTheEffects() async throws {
        try await onMain("systemActionsGoToTheEffects") {
            let h = MenuHarness()
            defer { h.cleanUp() }
            await h.perform(.showInFinder(path: "/a/clip.mp4"))
            await h.perform(.copyFilePath(path: "/a/clip.mp4"))
            await h.perform(.copySnippet("<video>"))
            await h.perform(.copyErrorDetails("error: x"))
            await h.perform(.openSettings)
            await h.perform(.quit)
            #expect(h.effects.revealed == ["/a/clip.mp4"])
            #expect(h.effects.copied == ["/a/clip.mp4", "<video>", "error: x"])
            #expect(h.effects.settingsOpened == 1)
            #expect(h.effects.quitCalls == 1)
        }
    }

    @Test func discardAsksFirst() async throws {
        try await onMain("discardAsksFirst") {
            let h = MenuHarness()
            defer { h.cleanUp() }
            h.effects.discardAnswer = false
            await h.perform(.discard)
            #expect(h.effects.discardAsked == 1)
        }
    }

    @Test func chooseOutputFolderStoresAndPushesIt() async throws {
        try await onMain("chooseOutputFolderStoresAndPushesIt") {
            let h = MenuHarness()
            defer { h.cleanUp() }
            let folder = URL(fileURLWithPath: "/tmp/skreenrek-clips", isDirectory: true)
            h.effects.folderAnswer = folder
            await h.perform(.chooseOutputFolder)
            #expect(h.model.settings.outputFolder == folder)
            #expect(await h.controller.currentSettings.outputFolder == folder)
        }
    }

    @Test func quitDecisions() async throws {
        try await onMain("quitDecisions") {
            let h = MenuHarness()
            defer { h.cleanUp() }
            #expect(h.model.quitDecision == .now)
            h.model.apply(UIFixtures.recording(.mcp))
            #expect(h.model.quitDecision == .askToStop)
            #expect(h.model.wantsStopHotKey)
            var writing = UIFixtures.recording(.mcp)
            writing.state = .writing
            h.model.apply(writing)
            #expect(h.model.quitDecision == .afterWriting)
            #expect(!h.model.wantsStopHotKey)
        }
    }

    @Test func lastClipTitleComesFromTheRecording() async throws {
        try await onMain("lastClipTitleComesFromTheRecording") {
            var tracker = LastClipTracker()
            tracker.observe(UIFixtures.recording(.menu))
            var done = UIFixtures.idle
            done.lastClip = RenderSamples.clip()
            tracker.observe(done)
            #expect(tracker.title == "Safari — localhost:3000")
            // A later snapshot with the same clip keeps the title.
            tracker.observe(done)
            #expect(tracker.title == "Safari — localhost:3000")
        }
    }
}
