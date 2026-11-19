import AppKit
import Foundation
import SkreenrekCore
import SkreenrekTesting
@testable import SkreenrekUI
import Testing

/// The drag-to-authorize helper (addendum 4): placement, the loop and its states, the bundle guard and the copy.
@Suite struct DragHelperPlacementTests {
    /// A 1440 × 900 primary screen with a 25 pt menu bar, and a 1920 × 1080 screen to its right.
    static let primary = DragHelperScreen(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))
    static let second = DragHelperScreen(
        frame: CGRect(x: 1440, y: -180, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1440, y: -180, width: 1920, height: 1055))

    private func place(_ settings: CGRect?, screens: [DragHelperScreen] = [primary]) throws -> DragHelperPlacement {
        try #require(DragHelperPlacer.place(settings: settings, screens: screens))
    }

    @Test func goesRightOfSystemSettingsFirst() throws {
        // CG: top 120 pt below the primary's top. AppKit: the window's top is at 900 − 120 = 780.
        let placement = try place(CGRect(x: 100, y: 120, width: 680, height: 560))
        #expect(placement.side == .right)
        #expect(!placement.mirrored)
        #expect(placement.frame == CGRect(x: 792, y: 780 - 96 - 88, width: 320, height: 88))
    }

    @Test func mirrorsToTheLeftWhenTheRightHasNoRoom() throws {
        let placement = try place(CGRect(x: 740, y: 120, width: 680, height: 560))
        #expect(placement.side == .left)
        #expect(placement.mirrored)
        #expect(placement.frame == CGRect(x: 740 - 12 - 320, y: 596, width: 320, height: 88))
    }

    @Test func needs332PointsOnASide() throws {
        // Exactly 332 pt free on the right.
        #expect(try place(CGRect(x: 400, y: 120, width: 708, height: 400)).side == .right)
        // 331 on the right, 400 on the left.
        #expect(try place(CGRect(x: 400, y: 120, width: 709, height: 400)).side == .left)
        // 331 on both sides.
        #expect(try place(CGRect(x: 331, y: 120, width: 778, height: 400)).side == .docked)
    }

    @Test func docksBottomRightWithNoRoomOrNoBounds() throws {
        let docked = CGRect(x: 1440 - 16 - 320, y: 16, width: 320, height: 88)
        let wide = try place(CGRect(x: 40, y: 60, width: 1360, height: 700))
        #expect(wide.side == .docked)
        #expect(!wide.mirrored)
        #expect(wide.frame == docked)
        let unreadable = try place(nil)
        #expect(unreadable.side == .docked)
        #expect(unreadable.frame == docked)
    }

    @Test func clampsTheTopInsideTheVisibleFrame() throws {
        // A window whose top is above the visible frame: the panel stops 16 pt under the menu bar.
        let high = try place(CGRect(x: 100, y: -200, width: 600, height: 400))
        #expect(abs(high.frame.maxY - (875 - 16)) < 0.001)
        // A window near the bottom: the panel stays 16 pt above the visible frame's bottom.
        let low = try place(CGRect(x: 100, y: 850, width: 600, height: 400))
        #expect(low.frame.minY == 16)
    }

    @Test func followsTheScreenTheWindowIsOn() throws {
        // On the second screen (CG y is measured from the primary's top), with room on its right.
        let placement = try place(CGRect(x: 1600, y: 100, width: 800, height: 600), screens: [Self.primary, Self.second])
        #expect(placement.side == .right)
        #expect(placement.frame.minX == 2412)
        #expect(abs(placement.frame.maxY - (900 - 100 - 96)) < 0.001)
        // No room either side there: docked on that screen, not the primary.
        let docked = try place(CGRect(x: 1500, y: 0, width: 1800, height: 600), screens: [Self.primary, Self.second])
        #expect(docked.side == .docked)
        #expect(docked.frame == CGRect(x: 3360 - 16 - 320, y: -180 + 16, width: 320, height: 88))
    }

    @Test func flipsCGWindowCoordinatesToAppKit() {
        let rect = DragHelperPlacer.appKitRect(fromCG: CGRect(x: 10, y: 20, width: 100, height: 50), primaryHeight: 900)
        #expect(rect == CGRect(x: 10, y: 830, width: 100, height: 50))
    }
}

@Suite struct DragHelperStateTests {
    static let screens = [DragHelperPlacementTests.primary]
    static let window = CGRect(x: 100, y: 120, width: 680, height: 560)
    typealias M = DragHelperMetrics

    /// Shown at `t` (System Settings seen at once).
    static func shown(at t: TimeInterval = 0, reduceMotion: Bool = false) -> DragHelperState {
        var state = DragHelperState(permission: .screenRecording, now: t, reduceMotion: reduceMotion)
        state.update(now: t, window: .visible(window), screens: screens, granted: false)
        return state
    }

    @Test func waitsForSystemSettingsThenShowsBesideIt() {
        var state = DragHelperState(permission: .screenRecording, now: 0, reduceMotion: false)
        state.update(now: 0.25, window: .notRunning, screens: Self.screens, granted: false)
        state.update(now: 0.5, window: .hidden, screens: Self.screens, granted: false)
        #expect(state.phase == .waiting)
        #expect(!state.onScreen)
        state.update(now: 0.75, window: .visible(Self.window), screens: Self.screens, granted: false)
        #expect(state.phase == .shown)
        #expect(state.onScreen)
        #expect(state.appearedAt == 0.75)
        #expect(state.placement?.side == .right)
    }

    @Test func docksAfterThreeSecondsWithoutSystemSettings() {
        var state = DragHelperState(permission: .accessibility, now: 0, reduceMotion: false)
        state.update(now: 2.75, window: .notRunning, screens: Self.screens, granted: false)
        #expect(!state.onScreen)
        state.update(now: 3, window: .notRunning, screens: Self.screens, granted: false)
        #expect(state.onScreen)
        #expect(state.placement?.side == .docked)
        // Unreadable bounds dock the same way, and it moves beside System Settings once it shows up.
        var unreadable = DragHelperState(permission: .accessibility, now: 0, reduceMotion: false)
        unreadable.update(now: 3, window: .unreadable, screens: Self.screens, granted: false)
        #expect(unreadable.placement?.side == .docked)
        unreadable.update(now: 3.25, window: .visible(Self.window), screens: Self.screens, granted: false)
        #expect(unreadable.placement?.side == .right)
    }

    @Test func followsTheWindowAndHidesWhileItIsMinimised() {
        var state = Self.shown()
        let before = state.placement?.frame
        state.update(now: 0.25, window: .visible(Self.window.offsetBy(dx: 40, dy: 30)), screens: Self.screens,
                     granted: false)
        #expect(state.placement?.frame == before?.offsetBy(dx: 40, dy: -30))
        state.update(now: 0.5, window: .hidden, screens: Self.screens, granted: false)
        #expect(!state.onScreen)
        #expect(state.phase == .shown)
        state.update(now: 0.75, window: .visible(Self.window), screens: Self.screens, granted: false)
        #expect(state.onScreen)
        #expect(state.appearedAt == 0)
    }

    @Test func closesWhenSystemSettingsQuits() {
        var state = Self.shown()
        state.update(now: 1, window: .notRunning, screens: Self.screens, granted: false)
        #expect(state.phase == .closed(.settingsQuit))
        #expect(!state.onScreen)
        // Nothing brings a closed helper back.
        state.update(now: 2, window: .visible(Self.window), screens: Self.screens, granted: false)
        #expect(state.isClosed)
    }

    @Test func grantedHoldsOneAndAHalfSecondsThenCloses() {
        var state = Self.shown()
        state.update(now: 2, window: .visible(Self.window), screens: Self.screens, granted: true)
        #expect(state.phase == .granted(at: 2))
        #expect(state.ghost(at: 2.5) == nil)
        state.update(now: 3.25, window: .visible(Self.window), screens: Self.screens, granted: true)
        #expect(state.isGranted)
        state.update(now: 3.5, window: .visible(Self.window), screens: Self.screens, granted: true)
        #expect(state.phase == .closed(.granted))
    }

    @Test func screenRecordingThatReadsMissingKeepsThePanelUntilClosed() {
        var state = Self.shown()
        for tick in 1...200 {
            state.update(now: Double(tick) * 0.25, window: .visible(Self.window), screens: Self.screens, granted: false)
        }
        #expect(state.phase == .shown)
        state.close(.closeButton, now: 51)
        #expect(state.phase == .closed(.closeButton))
    }

    @Test func anotherPaneSwapsTheCopyInPlace() {
        var state = Self.shown()
        let placement = state.placement
        state.switchPane(to: .accessibility, now: 1)
        #expect(state.permission == .accessibility)
        #expect(state.placement == placement)
        #expect(state.onScreen)
        #expect(state.appearedAt == 0)
    }

    // MARK: The loop

    @Test func loopTimings() throws {
        let state = Self.shown()
        // Starts 0.6 s after it appears.
        #expect(state.ghost(at: 0.59) == nil)
        #expect(state.ghost(at: 0.6) == DragHelperGhost(offset: 0, opacity: 0.6))
        // Half the 0.9 s slide: half the 28 pt and half the 60%, ease-in-out.
        let mid = try #require(state.ghost(at: 0.6 + 0.45))
        #expect(abs(mid.offset - 14) < 0.001)
        #expect(abs(mid.opacity - 0.3) < 0.001)
        // Eased: slower than linear at the start.
        #expect((state.ghost(at: 0.6 + 0.09)?.offset ?? 99) < 2.8)
        // Then 1.5 s of rest, and the 2.4 s loop again.
        #expect(state.ghost(at: 0.6 + 0.9) == nil)
        #expect(state.ghost(at: 0.6 + 2.39) == nil)
        let again = try #require(state.ghost(at: 0.6 + 2.4 + 0.45))
        #expect(abs(again.offset - mid.offset) < 0.001)
        #expect(abs(again.opacity - mid.opacity) < 0.001)
        #expect(M.loopPeriod == 2.4)
    }

    @Test func stopsAfterEightLoops() {
        var state = Self.shown()
        let end = 0.6 + 8 * 2.4
        #expect(state.ghost(at: end - 2.4 + 0.1) != nil)
        #expect(state.loopsCompleted(at: end - 0.01) == 7)
        #expect(state.loopsCompleted(at: end) == 8)
        #expect(state.ghost(at: end + 0.1) == nil)
        #expect(state.ghost(at: end + 2.4 + 0.1) == nil)
        state.update(now: end + 0.25, window: .visible(Self.window), screens: Self.screens, granted: false)
        #expect(!state.loopRunning(at: end + 0.25))
        // Hovering and leaving doesn't start it again.
        state.setHovering(true, now: end + 1)
        state.setHovering(false, now: end + 2)
        #expect(!state.loopRunning(at: end + 3))
        #expect(state.ghost(at: end + 2.6) == nil)
    }

    @Test func pausesWhileHoveringAndResumesFromTheStartOfTheSlide() {
        var state = Self.shown()
        // Mid-slide in the first loop.
        state.setHovering(true, now: 0.9)
        #expect(state.ghost(at: 0.9) == nil)
        #expect(state.ghost(at: 5) == nil)
        #expect(!state.loopRunning(at: 5))
        state.setHovering(false, now: 10)
        // The first slide starts over: full 60%, no travel.
        #expect(state.ghost(at: 10) == DragHelperGhost(offset: 0, opacity: 0.6))
        #expect(state.loopsCompleted(at: 10) == 0)
    }

    @Test func pausesWhileDraggingAndWhileHidden() {
        var state = Self.shown()
        state.setDragging(true, now: 1)
        #expect(state.ghost(at: 1.2) == nil)
        state.setDragging(false, now: 4)
        #expect(state.ghost(at: 4) != nil)
        state.update(now: 4.25, window: .hidden, screens: Self.screens, granted: false)
        #expect(state.ghost(at: 4.3) == nil)
        #expect(!state.loopRunning(at: 4.3))
    }

    @Test func reduceMotionHasNoGhost() {
        let state = Self.shown(reduceMotion: true)
        for t in stride(from: 0.0, through: 25, by: 0.05) {
            #expect(state.ghost(at: t) == nil)
        }
        #expect(!state.loopRunning(at: 1))
        #expect(state.onScreen)
    }
}

@Suite struct DragHelperEligibilityTests {
    @Test func onlyAnInstalledAppBundleGetsTheHelper() {
        #expect(DragHelperEligibility.check(
            bundleURL: URL(fileURLWithPath: "/Applications/Skreenrek.app"), volumeIsReadOnly: false) == .eligible)
        #expect(DragHelperEligibility.check(
            bundleURL: URL(fileURLWithPath: "/Users/you/Applications/Skreenrek.app"), volumeIsReadOnly: nil)
            == .eligible)
        // A bare `swift build` executable's bundle is its folder.
        #expect(DragHelperEligibility.check(
            bundleURL: URL(fileURLWithPath: "/Users/you/skreenrek/.build/debug"), volumeIsReadOnly: false)
            == .notAppBundle)
        #expect(DragHelperEligibility.check(
            bundleURL: URL(fileURLWithPath: "/private/var/folders/xy/T/AppTranslocation/1234-ABCD/d/Skreenrek.app"),
            volumeIsReadOnly: true) == .translocated)
        #expect(DragHelperEligibility.check(
            bundleURL: URL(fileURLWithPath: "/Volumes/Skreenrek/Skreenrek.app"), volumeIsReadOnly: true)
            == .diskImage)
    }

    @Test func theTestRunnerIsNotEligible() {
        // swift test runs from a .xctest bundle, never a .app.
        #expect(DragHelperEligibility.current() != .eligible)
    }

    @Test func directCaptureHasNoListSoNoHelper() {
        #expect(DragHelperPane.applies(to: .screenRecording))
        #expect(DragHelperPane.applies(to: .accessibility))
        #expect(!DragHelperPane.applies(to: .directCapture))
    }
}

@Suite struct DragHelperCopyTests {
    typealias S = UIStrings.DragHelper

    @Test func copyTable() {
        #expect(S.title == "Drag Skreenrek into the list")
        #expect(S.detail(.screenRecording) == "Drop it on Screen Recording to allow it.")
        #expect(S.detail(.accessibility) == "Drop it on Accessibility to allow it.")
        #expect(S.grantedTitle == "Skreenrek is allowed")
        #expect(S.grantedDetail == "You can close System Settings.")
        #expect(S.iconHelp
            == "Drag into the list in System Settings. Or click + under the list and choose Skreenrek in Applications.")
        #expect(S.close == "Close")
    }

    @Test func voiceOver() {
        #expect(S.panelLabel(.screenRecording)
            == "Skreenrek helper. Drag Skreenrek into the Screen Recording list in System Settings.")
        #expect(S.panelLabel(.accessibility)
            == "Skreenrek helper. Drag Skreenrek into the Accessibility list in System Settings.")
        #expect(S.iconLabel == "Skreenrek app, draggable")
        #expect(S.closeLabel == "Close helper")
    }

    @Test func theCopyIsInTheAudit() {
        for text in [S.title, S.detail(.screenRecording), S.detail(.accessibility), S.grantedTitle, S.grantedDetail,
                     S.iconHelp, S.iconLabel, S.close, S.closeLabel, S.panelLabel(.screenRecording),
                     S.panelLabel(.accessibility)] {
            #expect(UIStrings.allFixed.contains(text), "\(text)")
        }
    }

    @Test func titleFitsOneLineInTheTextColumn() {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        for title in [S.title, S.grantedTitle] {
            let width = (title as NSString).size(withAttributes: [.font: font]).width
            #expect(width <= DragHelperMetrics.textWidth, "\(title): \(width)")
        }
    }
}

@Suite struct DragHelperControllerTests {
    @MainActor private final class FakeSettingsWindow: SystemSettingsWindowSource {
        var window = SystemSettingsWindow.notRunning
        func current() -> SystemSettingsWindow { window }
    }

    /// Never shows a window: System Settings stays unseen and the clock stays at 0, so nothing is ordered in.
    @MainActor private static func make(
        eligibility: DragHelperEligibility = .eligible
    ) -> DragHelperController {
        DragHelperController(
            probe: FakePermissionProbe(screenRecording: .missing, accessibility: .missing),
            windows: FakeSettingsWindow(), now: { 0 }, eligibility: { eligibility }, icon: { NSImage() })
    }

    @Test(.timeLimit(.minutes(1))) func showsForTheTwoListsOnly() async throws {
        try await onMain("drag helper panes", seconds: 10) {
            let helper = Self.make()
            helper.show(.directCapture, from: .onboarding)
            #expect(helper.state == nil)
            helper.show(.screenRecording, from: .onboarding)
            #expect(helper.state?.permission == .screenRecording)
            helper.show(.accessibility, from: .settings)
            #expect(helper.state?.permission == .accessibility)
            helper.close(.appQuit)
            #expect(helper.state == nil)
        }
    }

    @Test(.timeLimit(.minutes(1))) func neverShowsForATranslocatedDiskImageOrBareBuild() async throws {
        try await onMain("drag helper guard", seconds: 10) {
            for reason in [DragHelperEligibility.translocated, .diskImage, .notAppBundle] {
                let helper = Self.make(eligibility: reason)
                helper.show(.screenRecording, from: .settings)
                #expect(helper.state == nil)
            }
        }
    }

    @Test(.timeLimit(.minutes(1))) func closesWithItsSourceAndStaysClosedAfterClose() async throws {
        try await onMain("drag helper source", seconds: 10) {
            let helper = Self.make()
            helper.show(.screenRecording, from: .onboarding)
            helper.dismiss(from: .settings)
            #expect(helper.state != nil)
            helper.dismiss(from: .onboarding)
            #expect(helper.state == nil)
            helper.show(.accessibility, from: .settings)
            helper.close(.closeButton)
            #expect(helper.state == nil)
            // Only Open System Settings… brings it back.
            helper.dismiss(from: .settings)
            #expect(helper.state == nil)
            helper.show(.accessibility, from: .settings)
            #expect(helper.state?.phase == .waiting)
            helper.close(.appQuit)
        }
    }
}
