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
    private static let frame = PointRect(x: 100, y: 200, width: 640, height: 400)
    private static let target: SelectionOutlineTarget = {
        var window = RenderSamples.safari
        window.frame = frame
        return SelectionOutlineTarget(window: window)
    }()

    private static func input(
        picks: Int = 0, capturing: Bool = false, picker: Bool = false, panel: Bool = false, bar: Bool = false,
        closed: Bool = false, reduceMotion: Bool = false, contrast: Bool = false,
        target: SelectionOutlineTarget? = target
    ) -> SelectionOutlineInput {
        SelectionOutlineInput(
            target: target, pickCount: picks, capturing: capturing, pickerOpen: picker, panelOpen: panel,
            controlBarVisible: bar, windowClosed: closed, reduceMotion: reduceMotion, increaseContrast: contrast)
    }

    private static func model(_ first: SelectionOutlineInput = input(), macOS: Int = 26) -> SelectionOutlineModel {
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

    @Test func itStillHidesWhileRecordingEvenIfTheBarIsVisible() {
        var model = Self.model()
        model.update(Self.input(picks: 1, capturing: true, bar: true), now: 0)
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
        input(capturing: true, panel: true), input(picker: true, panel: true), input(panel: true, closed: true),
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

    @Test func clearingAndRecordingHideItAtOnce() {
        var cleared = Self.model(Self.input(panel: true))
        cleared.update(Self.input(panel: true, target: nil), now: 1)
        #expect(cleared.display(at: 1) == .hidden)
        #expect(cleared.nextDeadline(after: 1) == nil)
        var recording = Self.model()
        recording.update(Self.input(picks: 1), now: 0)
        recording.update(Self.input(picks: 1, capturing: true), now: 0.5)
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
            ).capturing)
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
        func show(_ appearance: SelectionOutlineAppearance) { log.append("show \(appearance.frame.x)") }
        func fadeOut(_ appearance: SelectionOutlineAppearance, duration: TimeInterval) { log.append("fade") }
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
