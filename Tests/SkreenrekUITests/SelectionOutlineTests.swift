import AppKit
import CoreGraphics
import Foundation
import SkreenrekControl
import SkreenrekCore
import SkreenrekTesting
@testable import SkreenrekUI
import Testing

/// The on-screen outline: when it shows, where, how it looks, and how its timing runs on the manual clock.
@Suite struct SelectionOutlineModelTests {
    static let frame = PointRect(x: 100, y: 200, width: 640, height: 400)
    static let target: SelectionOutlineTarget = {
        var window = RenderSamples.safari
        window.frame = frame
        return SelectionOutlineTarget(window: window)
    }()

    static func input(
        picks: Int = 0, capture: SelectionOutlineCapture = .none, picker: Bool = false, panel: Bool = false,
        bar: Bool = false, closed: Bool = false, reduceMotion: Bool = false, contrast: Bool = false,
        target: SelectionOutlineTarget? = target
    ) -> SelectionOutlineInput {
        SelectionOutlineInput(
            target: target, pickCount: picks, capture: capture, pickerOpen: picker, panelOpen: panel,
            controlBarVisible: bar, windowClosed: closed, reduceMotion: reduceMotion, increaseContrast: contrast)
    }

    static func model(_ first: SelectionOutlineInput = input(), macOS: Int = 26) -> SelectionOutlineModel {
        var model = SelectionOutlineModel(macOSMajorVersion: macOS)
        model.update(first, now: 0)
        return model
    }

    private func isShown(_ display: SelectionOutlineDisplay) -> Bool {
        if case .shown = display { return true }
        return false
    }

    // MARK: - Shape

    @Test func theFrameIsTheWindowOutsetByTheStroke() {
        #expect(SelectionOutlineModel.strokeWidth == 3)
        #expect(
            SelectionOutlineModel.outlineFrame(around: Self.frame)
                == PointRect(x: 97, y: 197, width: 646, height: 406))
    }

    @Test func theRadiusIsConcentricForEachSystem() {
        #expect(SelectionOutlineModel.windowCornerRadius(macOSMajorVersion: 26) == 16)
        #expect(SelectionOutlineModel.windowCornerRadius(macOSMajorVersion: 15) == 10)
        #expect(SelectionOutlineModel.outlineRadius(macOSMajorVersion: 26) == 19)
        #expect(SelectionOutlineModel.outlineRadius(macOSMajorVersion: 15) == 13)
        let old = Self.model(Self.input(panel: true), macOS: 15)
        #expect(old.display(at: 0).appearance?.cornerRadius == 13)
    }

    @Test func increaseContrastStrengthensTheHairline() throws {
        let normal = try #require(Self.model(Self.input(panel: true)).display(at: 0).appearance)
        #expect(normal.hairlineWidth == 0.5)
        #expect(normal.hairlineOpacity == 0.3)
        let strong = try #require(Self.model(Self.input(panel: true, contrast: true)).display(at: 0).appearance)
        #expect(strong.hairlineWidth == 1)
        #expect(strong.hairlineOpacity == 0.6)
    }

    // MARK: - When it shows

    @Test func itShowsWhileThePanelIsOpen() {
        #expect(isShown(Self.model(Self.input(panel: true)).display(at: 1000)))
        #expect(Self.model(Self.input()).display(at: 0) == .hidden)
    }

    @Test func itStaysWhileTheControlBarIsVisible() {
        var model = Self.model()
        model.update(Self.input(picks: 1, bar: true), now: 0)
        #expect(isShown(model.display(at: 1000)))
        #expect(model.wantsTracking(at: 1000))
        #expect(model.nextDeadline(after: 1000) == nil)
    }

    @Test func aRecordingWithoutTheIndicatorHidesItEvenIfTheBarIsVisible() {
        var model = Self.model()
        model.update(Self.input(picks: 1, capture: .recordingHidden, bar: true), now: 0)
        #expect(model.display(at: 0) == .hidden)
        #expect(!model.wantsTracking(at: 0))
    }

    @Test func closingThePanelWhileTheBarIsVisibleKeepsTheOutline() {
        var model = Self.model(Self.input(panel: true, bar: true))
        model.update(Self.input(picks: 1, panel: true, bar: true), now: 0)
        model.update(Self.input(picks: 1, bar: true), now: 1)
        #expect(isShown(model.display(at: 10)))
        #expect(model.nextDeadline(after: 10) == nil)
    }

    @Test func turningTheBarOffFadesTheOutline() {
        var model = Self.model(Self.input(picks: 1, bar: true))
        model.update(Self.input(picks: 1), now: 10)
        guard case .fading(_, let remaining) = model.display(at: 10) else {
            Issue.record("Expected the fade")
            return
        }
        #expect(abs(remaining - 0.3) < 0.0001)
        #expect(model.display(at: 10.31) == .hidden)
    }

    @Test(arguments: [
        input(capture: .recordingHidden, panel: true), input(capture: .saving(keepsPick: false), panel: true),
        input(picker: true, panel: true), input(panel: true, closed: true),
        input(panel: true, target: nil),
    ])
    func itNeverShowsInTheExcludedStates(_ input: SelectionOutlineInput) {
        let model = Self.model(input)
        #expect(model.display(at: 0) == .hidden)
        #expect(!model.wantsTracking(at: 0))
    }

    @Test func aWindowOutOfSightHidesItButKeepsTracking() {
        var model = Self.model(Self.input(panel: true))
        model.update(presence: .notVisible)
        #expect(model.display(at: 0) == .hidden)
        #expect(model.wantsTracking(at: 0))
        model.update(presence: .onScreen(Self.frame))
        #expect(isShown(model.display(at: 0)))
    }

    @Test func itFollowsTheWindow() {
        var model = Self.model(Self.input(panel: true))
        model.update(presence: .onScreen(PointRect(x: 10, y: 20, width: 300, height: 200)))
        #expect(model.display(at: 0).appearance?.frame == PointRect(x: 7, y: 17, width: 306, height: 206))
    }

    // MARK: - Timing

    @Test func aPickFlashesThenFades() {
        let clock = ManualClock()
        var model = Self.model()
        let picked = model.update(Self.input(picks: 1), now: clock.now())
        #expect(picked == Self.target)
        #expect(isShown(model.display(at: clock.now())))
        #expect(model.nextDeadline(after: clock.now()) == 1.5)
        clock.advance(by: 1.49)
        #expect(isShown(model.display(at: clock.now())))
        clock.advance(to: 1.5)
        guard case .fading(_, let remaining) = model.display(at: clock.now()) else {
            Issue.record("Expected the fade")
            return
        }
        #expect(abs(remaining - 0.3) < 0.0001)
        #expect(model.nextDeadline(after: clock.now()) == 1.8)
        clock.advance(to: 1.8)
        #expect(model.display(at: clock.now()) == .hidden)
        #expect(model.nextDeadline(after: clock.now()) == nil)
        #expect(!model.wantsTracking(at: clock.now()))
    }

    @Test func reduceMotionKeepsTheFlashAndDropsTheFade() {
        var model = Self.model(Self.input(reduceMotion: true))
        model.update(Self.input(picks: 1, reduceMotion: true), now: 0)
        #expect(isShown(model.display(at: 1.49)))
        #expect(model.display(at: 1.5) == .hidden)
    }

    @Test func pickingTheSameWindowAgainFlashesAgain() {
        var model = Self.model(Self.input(picks: 1))
        #expect(model.display(at: 0) == .hidden)
        #expect(model.update(Self.input(picks: 2), now: 5) != nil)
        #expect(isShown(model.display(at: 5)))
    }

    @Test func thePickCountAlreadyThereAtLaunchDoesNotFlash() {
        var model = SelectionOutlineModel(macOSMajorVersion: 26)
        #expect(model.update(Self.input(picks: 4), now: 0) == nil)
        #expect(model.display(at: 0) == .hidden)
    }

    @Test func openingThePanelDuringTheFlashKeepsItAndClosingFades() {
        var model = Self.model()
        model.update(Self.input(picks: 1), now: 0)
        model.update(Self.input(picks: 1, panel: true), now: 1)
        #expect(isShown(model.display(at: 10)))
        #expect(model.nextDeadline(after: 10) == nil)
        model.update(Self.input(picks: 1), now: 10)
        guard case .fading(_, let remaining) = model.display(at: 10) else {
            Issue.record("Expected the fade")
            return
        }
        #expect(abs(remaining - 0.3) < 0.0001)
        #expect(model.display(at: 10.31) == .hidden)
    }

    @Test func closingThePanelDuringTheFlashLetsTheFlashFinish() {
        var model = Self.model(Self.input(panel: true))
        model.update(Self.input(picks: 1, panel: true), now: 0)
        model.update(Self.input(picks: 1), now: 0.5)
        #expect(isShown(model.display(at: 1.4)))
        #expect(model.display(at: 1.8) == .hidden)
    }

    @Test func clearingAndARecordingWithoutTheIndicatorHideItAtOnce() {
        var cleared = Self.model(Self.input(panel: true))
        cleared.update(Self.input(panel: true, target: nil), now: 1)
        #expect(cleared.display(at: 1) == .hidden)
        #expect(cleared.nextDeadline(after: 1) == nil)
        var recording = Self.model()
        recording.update(Self.input(picks: 1), now: 0)
        recording.update(Self.input(picks: 1, capture: .recordingHidden), now: 0.5)
        #expect(recording.display(at: 0.5) == .hidden)
    }

    @Test func theSnapshotDrivesTheInput() {
        var snapshot = RenderSamples.armed.context.snapshot
        snapshot.picking = true
        snapshot.pickCount = 3
        let input = SelectionOutlineInput(
            snapshot: snapshot, panelOpen: true, windowClosed: false, reduceMotion: true, increaseContrast: false)
        #expect(input.target?.title == "Safari — localhost:3000")
        #expect(input.pickerOpen)
        #expect(input.pickCount == 3)
        #expect(input.reduceMotion)
        snapshot.state = .writing
        #expect(
            SelectionOutlineInput(
                snapshot: snapshot, panelOpen: false, windowClosed: false, reduceMotion: false,
                increaseContrast: false
            ).capture == .saving(keepsPick: false))
    }

    // MARK: - The window server's description

    @Test func theWindowServerDescriptionBecomesAPresence() {
        let bounds = CGRect(x: 10, y: 20, width: 300, height: 200).dictionaryRepresentation
        let onScreen: [String: Any] = [
            kCGWindowBounds as String: bounds, kCGWindowIsOnscreen as String: true,
        ]
        #expect(
            WindowServerPresence.presence(from: [onScreen])
                == .onScreen(PointRect(x: 10, y: 20, width: 300, height: 200)))
        #expect(WindowServerPresence.presence(from: [[kCGWindowBounds as String: bounds]]) == .notVisible)
        #expect(WindowServerPresence.presence(from: []) == .notVisible)
    }
}

/// The controller over fakes: what reaches the overlay, on the manual clock.
@Suite struct SelectionOutlineControllerTests {
    @MainActor
    private final class FakeSurface: SelectionOutlineSurface {
        var log: [String] = []
        var onHide: (() -> Void)?
        func show(_ appearance: SelectionOutlineAppearance, crossfade: TimeInterval) {
            let tone = appearance.tone == .record ? " red" : ""
            log.append("show \(appearance.frame.x)\(tone)" + (crossfade > 0 ? " crossfade \(crossfade)" : ""))
        }
        func fadeOut(_ appearance: SelectionOutlineAppearance, duration: TimeInterval) {
            log.append(abs(duration - 0.3) < 0.0001 ? "fade" : "fade \(duration)")
        }
        func hide() {
            log.append("hide")
            onHide?()
        }
        func keepAbove(_ window: WindowID) { log.append("above") }
        func announce(_ text: String) { log.append(text) }
    }

    @MainActor
    private final class FakeTracker: WindowFrameTracking {
        var onChange: (@MainActor (WindowPresence) -> Void)?
        var started: [WindowID] = []
        var stops = 0
        var first = WindowPresence.onScreen(RenderSamples.safari.frame)
        func start(_ window: WindowInfo, onChange: @escaping @MainActor (WindowPresence) -> Void) {
            started.append(window.id)
            self.onChange = onChange
            onChange(first)
        }
        func stop() {
            stops += 1
            onChange = nil
        }
    }

    private static let target = SelectionOutlineTarget(window: RenderSamples.safari)

    @Test func aPickAnnouncesFlashesFadesAndStopsTracking() async throws {
        try await onMain("outline flash") {
            let clock = ManualClock()
            let surface = FakeSurface()
            let tracker = FakeTracker()
            let controller = SelectionOutlineController(
                surface: surface, tracker: tracker, clock: clock, macOSMajorVersion: 26)
            controller.update(SelectionOutlineInput(target: Self.target))
            #expect(surface.log.isEmpty)
            controller.update(SelectionOutlineInput(target: Self.target, pickCount: 1))
            #expect(surface.log == ["Picked Safari — localhost:3000", "show 117.0"])
            #expect(tracker.started == [RenderSamples.safari.id])
            await clock.waitForSleepers()
            #expect(clock.nextDeadline == 1.5)
            clock.advance(to: 1.5)
            await clock.waitForSleepers()
            #expect(surface.log.last == "fade")
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                surface.onHide = { done.resume() }
                clock.advance(to: 1.8)
            }
            #expect(surface.log.last == "hide")
            #expect(tracker.stops == 1)
        }
    }

    @Test func aMinimisedWindowNeverShowsAndAMoveRedraws() async throws {
        try await onMain("outline tracking") {
            let surface = FakeSurface()
            let tracker = FakeTracker()
            tracker.first = .notVisible
            let controller = SelectionOutlineController(
                surface: surface, tracker: tracker, clock: ManualClock(), macOSMajorVersion: 26)
            controller.update(SelectionOutlineInput(target: Self.target, panelOpen: true))
            #expect(surface.log.isEmpty)
            tracker.onChange?(.onScreen(PointRect(x: 200, y: 0, width: 100, height: 100)))
            #expect(surface.log == ["show 197.0"])
            tracker.onChange?(.onScreen(PointRect(x: 200, y: 0, width: 100, height: 100)))
            #expect(surface.log == ["show 197.0", "above"])
            tracker.onChange?(.onScreen(PointRect(x: 300, y: 0, width: 100, height: 100)))
            #expect(surface.log.last == "show 297.0")
            controller.update(SelectionOutlineInput(target: nil, panelOpen: true))
            #expect(surface.log.last == "hide")
            #expect(tracker.stops == 1)
        }
    }
}


/// The overlay window itself: it must stay up after Skreenrek deactivates.
@MainActor
@Suite struct SelectionOutlineWindowTests {
    @Test func thePanelStaysUpWhenTheAppDeactivatesAndStaysOutOfCapture() {
        let panel = SelectionOutlinePanel()
        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.ignoresMouseEvents)
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.hasShadow)
        #expect(panel.sharingType == .none)
        #expect(!panel.collectionBehavior.contains(.transient))
        #expect(panel.collectionBehavior == [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle])
    }
}

/// The red recording outline (control bar addendum 2, §A): colour per state, geometry, crossfades and fades, regions,
/// and the indicator rule.
@Suite struct RecordingOutlineTests {
    private typealias T = SelectionOutlineModelTests
    private static let display = DisplayInfo(
        id: 1, name: "Built-in Retina Display", scale: 2, frame: PointRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: PointRect(x: 0, y: 33, width: 1512, height: 949))

    private func shown(_ display: SelectionOutlineDisplay) -> SelectionOutlineAppearance? {
        if case .shown(let appearance) = display { return appearance }
        return nil
    }

    /// Picked with the bar up, then the recording starts.
    private func recording(reduceMotion: Bool = false, bar: Bool = true) -> SelectionOutlineModel {
        var model = T.model(T.input(bar: bar, reduceMotion: reduceMotion))
        model.update(T.input(capture: .recordingWindow, bar: bar, reduceMotion: reduceMotion), now: 1)
        return model
    }

    @Test func idlePickedIsTheAccent() throws {
        let appearance = try #require(shown(T.model(T.input(bar: true)).display(at: 0)))
        #expect(appearance.tone == .accent)
    }

    @Test func recordingIsRedWithThePickGeometry() throws {
        let model = recording()
        let red = try #require(shown(model.display(at: 1)))
        #expect(red.tone == .record)
        #expect(red.frame == SelectionOutlineModel.outlineFrame(around: T.frame))
        #expect(red.strokeWidth == 3)
        #expect(red.cornerRadius == 19)
        #expect(red.hairlineWidth == 0.5)
        #expect(red.hairlineOpacity == 0.3)
        #expect(red.windowID == T.target.window.id)
        var old = T.model(T.input(), macOS: 15)
        old.update(T.input(capture: .recordingWindow, contrast: true), now: 0)
        let contrast = try #require(shown(old.display(at: 0)))
        #expect(contrast.cornerRadius == 13)
        #expect(contrast.hairlineWidth == 1)
        #expect(contrast.hairlineOpacity == 0.6)
    }

    @Test func theRedFrameShowsWithThePanelAndTheBarDownAndNeverExpires() throws {
        let model = recording(bar: false)
        #expect(shown(model.display(at: 1000))?.tone == .record)
        #expect(model.nextDeadline(after: 1000) == nil)
        #expect(model.wantsTracking(at: 1000))
    }

    @Test(arguments: [(false, 0.2), (true, 0.0)])
    func recordStartCrossfadesTheAccentToRed(reduceMotion: Bool, seconds: Double) {
        var model = T.model(T.input(bar: true, reduceMotion: reduceMotion))
        let before = model.display(at: 0)
        model.update(T.input(capture: .recordingWindow, bar: true, reduceMotion: reduceMotion), now: 1)
        let after = model.display(at: 1)
        #expect(model.crossfade(from: before, to: after) == seconds)
        #expect(model.crossfade(from: after, to: after) == 0)
        #expect(model.crossfade(from: .hidden, to: after) == 0)
    }

    @Test(arguments: [(false, 0.2), (true, 0.0)])
    func savingWithTheBarOnGoesBackToTheAccent(reduceMotion: Bool, seconds: Double) throws {
        var model = recording(reduceMotion: reduceMotion)
        let before = model.display(at: 2)
        model.update(T.input(capture: .saving(keepsPick: true), bar: true, reduceMotion: reduceMotion), now: 2)
        let after = model.display(at: 2)
        let accent = try #require(shown(after))
        #expect(accent.tone == .accent)
        #expect(model.crossfade(from: before, to: after) == seconds)
        #expect(shown(model.display(at: 100))?.tone == .accent)
        model.update(T.input(bar: true, reduceMotion: reduceMotion), now: 3)
        #expect(shown(model.display(at: 3))?.tone == .accent)
    }

    @Test func savingWithThePickDroppedFadesOutOverAThirdOfASecond() {
        var model = recording()
        model.update(T.input(capture: .saving(keepsPick: false)), now: 2)
        guard case .fading(let appearance, let remaining) = model.display(at: 2) else {
            Issue.record("Expected the fade, got \(model.display(at: 2))")
            return
        }
        #expect(appearance.tone == .record)
        #expect(abs(remaining - 0.3) < 0.0001)
        #expect(model.nextDeadline(after: 2) == 2.3)
        #expect(model.display(at: 2.3) == .hidden)
        #expect(!model.wantsTracking(at: 2))
    }

    /// An agent's recording of the user's picked window: the pick goes when the clip is saved, and the fade runs on.
    @Test func anAgentRecordingThatDropsThePickKeepsFadingAfterTheTargetGoes() {
        var model = recording()
        model.update(T.input(capture: .saving(keepsPick: false)), now: 2)
        model.update(T.input(target: nil), now: 2.1)
        guard case .fading(_, let remaining) = model.display(at: 2.1) else {
            Issue.record("Expected the fade to carry on")
            return
        }
        #expect(abs(remaining - 0.2) < 0.0001)
        #expect(model.display(at: 2.31) == .hidden)
    }

    @Test func reduceMotionDropsTheSavingFade() {
        var model = recording(reduceMotion: true)
        model.update(T.input(capture: .saving(keepsPick: false), reduceMotion: true), now: 2)
        #expect(model.display(at: 2) == .hidden)
    }

    @Test func theBarOffWithThePickKeptStillFades() {
        var model = recording(bar: false)
        model.update(T.input(capture: .saving(keepsPick: true)), now: 2)
        guard case .fading(let appearance, _) = model.display(at: 2) else {
            Issue.record("Expected the fade")
            return
        }
        #expect(appearance.tone == .record)
        #expect(model.display(at: 2.3) == .hidden)
    }

    @Test func itFollowsTheWindowWhileRecordingAndAfterTheClip() throws {
        var model = recording()
        let moved = PointRect(x: 300, y: 250, width: 500, height: 300)
        model.update(presence: .onScreen(moved))
        #expect(shown(model.display(at: 1))?.frame == SelectionOutlineModel.outlineFrame(around: moved))
        model.update(T.input(capture: .saving(keepsPick: true), bar: true), now: 2)
        model.update(T.input(bar: true), now: 3)
        let after = try #require(shown(model.display(at: 3)))
        #expect(after.frame == SelectionOutlineModel.outlineFrame(around: moved))
        #expect(after.tone == .accent)
    }

    @Test func aMinimisedWindowHidesTheRedFrameUntilItComesBack() {
        var model = recording()
        model.update(presence: .notVisible)
        #expect(model.display(at: 1) == .hidden)
        #expect(model.wantsTracking(at: 1))
        model.update(presence: .onScreen(T.frame))
        #expect(shown(model.display(at: 1))?.tone == .record)
    }

    // MARK: - From the snapshot

    private func snapshot(
        state: ControllerState = .recording, window: Bool = true, region: PixelRect? = nil, hud: Bool = true,
        keeps: Bool = false
    ) -> ControllerSnapshot {
        var snapshot = ControllerSnapshot(state: state, fps: .fps30, hud: hud, display: Self.display)
        snapshot.window = window ? T.target.window : nil
        snapshot.region = region
        snapshot.keepsWindowPicked = keeps
        return snapshot
    }

    private func capture(_ snapshot: ControllerSnapshot, indicator: Bool = true) -> SelectionOutlineCapture {
        SelectionOutlineInput(
            snapshot: snapshot, panelOpen: false, windowClosed: false, reduceMotion: false, increaseContrast: false,
            recordingIndicator: indicator
        ).capture
    }

    @Test func aWindowRecordingAsksForTheRedFrame() {
        #expect(capture(snapshot()) == .recordingWindow)
    }

    @Test func theIndicatorSettingOrNoHUDHidesIt() {
        let region = PixelRect(x: 200, y: 100, width: 800, height: 600)
        #expect(capture(snapshot(), indicator: false) == .recordingHidden)
        #expect(capture(snapshot(hud: false)) == .recordingHidden)
        #expect(capture(snapshot(window: false, region: region), indicator: false) == .recordingHidden)
        #expect(capture(snapshot(window: false, region: region, hud: false)) == .recordingHidden)
        var model = T.model(T.input(bar: true))
        model.update(T.input(capture: .recordingHidden, bar: true), now: 1)
        #expect(model.display(at: 1) == .hidden)
    }

    @Test func savingCarriesWhetherThePickStays() {
        #expect(capture(snapshot(state: .writing, keeps: true)) == .saving(keepsPick: true))
        #expect(capture(snapshot(state: .writing, keeps: false)) == .saving(keepsPick: false))
        #expect(capture(snapshot(state: .writing, window: false, keeps: true)) == .saving(keepsPick: false))
        #expect(capture(snapshot(state: .armed)) == .none)
    }

    @Test func aRegionGetsASquareRedFrameJustOutsideIt() throws {
        let region = PixelRect(x: 200, y: 100, width: 800, height: 600)
        let rect = PointRect(x: 100, y: 50, width: 400, height: 300)
        #expect(SelectionOutlineModel.regionFrame(region, on: Self.display) == rect)
        #expect(capture(snapshot(window: false, region: region)) == .recordingRegion(rect))
        var model = SelectionOutlineModel(macOSMajorVersion: 26)
        model.update(SelectionOutlineInput(target: nil, capture: .recordingRegion(rect)), now: 0)
        let frame = try #require(shown(model.display(at: 0)))
        #expect(frame.frame == PointRect(x: 97, y: 47, width: 406, height: 306))
        #expect(frame.cornerRadius == 0)
        #expect(frame.tone == .record)
        #expect(frame.windowID == nil)
        #expect(!model.wantsTracking(at: 0))
        model.update(SelectionOutlineInput(target: nil, capture: .saving(keepsPick: false)), now: 5)
        guard case .fading(let fading, _) = model.display(at: 5) else {
            Issue.record("Expected the region frame to fade")
            return
        }
        #expect(fading.frame == frame.frame)
        #expect(model.display(at: 5.3) == .hidden)
    }

    @Test func aFullScreenRecordingGetsNoFrame() {
        let whole = PixelRect(x: 0, y: 0, width: 3024, height: 1964)
        #expect(capture(snapshot(window: false, region: whole)) == .recordingHidden)
        #expect(SelectionOutlineModel.coversScreen(PointRect(x: 0, y: 0, width: 1512, height: 982), display: Self.display))
    }

    @Test func theTokenIsTheSystemRed() {
        #expect(BrandTheme.recordRed == NSColor.systemRed)
        #expect(SelectionOutlineView.color(.record) == NSColor.systemRed)
        #expect(SelectionOutlineView.color(.accent) == NSColor.controlAccentColor)
    }
}

/// The controller drives the crossfades and fades on the overlay.
@Suite struct RecordingOutlineControllerTests {
    @MainActor
    private final class Surface: SelectionOutlineSurface {
        var log: [String] = []
        func show(_ appearance: SelectionOutlineAppearance, crossfade: TimeInterval) {
            log.append("show \(appearance.tone == .record ? "red" : "accent") \(crossfade)")
        }
        func fadeOut(_ appearance: SelectionOutlineAppearance, duration: TimeInterval) {
            log.append("fade \(appearance.tone == .record ? "red" : "accent") \((duration * 10).rounded() / 10)")
        }
        func hide() { log.append("hide") }
        func keepAbove(_ window: WindowID) {}
        func announce(_ text: String) {}
    }

    @MainActor
    private final class Tracker: WindowFrameTracking {
        var onChange: (@MainActor (WindowPresence) -> Void)?
        func start(_ window: WindowInfo, onChange: @escaping @MainActor (WindowPresence) -> Void) {
            self.onChange = onChange
            onChange(.onScreen(window.frame))
        }
        func stop() { onChange = nil }
    }

    private static let target = SelectionOutlineTarget(window: RenderSamples.safari)

    @Test(arguments: [false, true])
    func barOnTurnsRedAndBack(reduceMotion: Bool) async throws {
        try await onMain("red and back") {
            let surface = Surface()
            let controller = SelectionOutlineController(
                surface: surface, tracker: Tracker(), clock: ManualClock(), macOSMajorVersion: 26)
            let fade = reduceMotion ? 0.0 : 0.2
            func input(_ capture: SelectionOutlineCapture) -> SelectionOutlineInput {
                SelectionOutlineInput(
                    target: Self.target, capture: capture, controlBarVisible: true, reduceMotion: reduceMotion)
            }
            controller.update(input(.none))
            controller.update(input(.recordingWindow))
            controller.update(input(.saving(keepsPick: true)))
            #expect(surface.log == ["show accent 0.0", "show red \(fade)", "show accent \(fade)"])
        }
    }

    @Test func barOffFadesTheRedOut() async throws {
        try await onMain("red fade") {
            let surface = Surface()
            let tracker = Tracker()
            let controller = SelectionOutlineController(
                surface: surface, tracker: tracker, clock: ManualClock(), macOSMajorVersion: 26)
            controller.update(SelectionOutlineInput(target: Self.target, capture: .recordingWindow))
            #expect(surface.log == ["show red 0.0"])
            let moved = PointRect(x: 40, y: 50, width: 300, height: 200)
            tracker.onChange?(.onScreen(moved))
            #expect(surface.log.last == "show red 0.0")
            controller.update(SelectionOutlineInput(target: Self.target, capture: .saving(keepsPick: false)))
            #expect(surface.log.last == "fade red 0.3")
        }
    }
}
