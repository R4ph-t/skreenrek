import AppKit
import SkreenrekControl
import SkreenrekCore
import SkreenrekTesting
@testable import SkreenrekUI
import SwiftUI
import Testing

private enum Bar {
    /// The menu bar takes the top 33 pt and the Dock the bottom 49, so the visible frame ends at y 933.
    static let screen = DisplayInfo(
        id: 1, name: "Built-in Retina Display", scale: 2, frame: PointRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: PointRect(x: 0, y: 33, width: 1512, height: 900))
    static let external = DisplayInfo(
        id: 2, name: "External", scale: 1, frame: PointRect(x: 1512, y: 0, width: 1920, height: 1080),
        visibleFrame: PointRect(x: 1512, y: 25, width: 1920, height: 1055))
    static let window = PointRect(x: 100, y: 100, width: 800, height: 500)
    static let p1080 = SizePreset.p1080.size
    static let p720 = SizePreset.p720.size

    static func target(_ frame: PointRect = window) -> SelectionOutlineTarget {
        var info = RenderSamples.safari
        info.frame = frame
        return SelectionOutlineTarget(window: info)
    }

    static func input(
        frame: PointRect = window, choice: SizeChoice = .size(p1080), activity: ControlBarActivity = .idle,
        readback: Readback? = nil, writable: Bool = true, resize: ControlBarResize = .none,
        reduceMotion: Bool = false
    ) -> ControlBarInput {
        ControlBarInput(
            target: target(frame), activity: activity, sizeChoice: choice, readback: readback, clipSize: p1080,
            outputWritable: writable, resize: resize, reduceMotion: reduceMotion)
    }

    static func model(
        _ input: ControlBarInput = input(), permissions: ControlBarPermissions = ControlBarPermissions(),
        displays: [DisplayInfo] = [screen], presence: WindowPresence? = nil
    ) -> ControlBarModel {
        var model = ControlBarModel()
        model.update(displays: displays)
        model.update(permissions: permissions)
        model.update(input, now: 0)
        if let presence {
            model.update(presence: presence)
        } else if let frame = input.target?.window.frame {
            model.update(presence: .onScreen(frame))
        }
        return model
    }

    static func readback(requested: PixelSize, actual: PixelSize, frame: PointRect = window) -> Readback {
        Readback(
            window: Readback.Window(RenderSamples.safari), display: Readback.Display(screen), requested: requested,
            actual: actual, frame: frame, exact: requested == actual, attempts: 3)
    }

    static func size(_ content: ControlBarContent?) -> ControlBarSizeControl? {
        if case .size(let control)? = content?.leading { return control }
        return nil
    }
}

// MARK: - Placement

@Suite struct ControlBarPlacementTests {
    private func layout(_ window: PointRect, on display: DisplayInfo = Bar.screen) -> ControlBarLayout {
        ControlBarLayout.place(window: window, on: display)
    }

    @Test func itSitsEightPointsBelowTheWindowAndCentred() {
        let result = layout(Bar.window)
        #expect(result.placement == .below)
        #expect(result.width == .regular)
        #expect(result.frame == PointRect(x: 350, y: 608, width: 300, height: 36))
    }

    @Test func belowNeedsRoomForTheBarAndItsMargin() {
        // 889 + 8 + 36 + 8 is exactly the visible frame's end.
        #expect(layout(PointRect(x: 100, y: 100, width: 800, height: 781)).placement == .below)
        #expect(layout(PointRect(x: 100, y: 100, width: 800, height: 782)).placement == .above)
    }

    @Test func itFlipsAboveWhenThereIsNoRoomBelow() {
        let result = layout(PointRect(x: 100, y: 500, width: 800, height: 420))
        #expect(result.placement == .above)
        #expect(result.frame.y == 456)
        #expect(result.frame.y + result.frame.height == 492)
    }

    @Test func aFullHeightWindowDocksInsideItsBottomEdge() {
        let result = layout(PointRect(x: 100, y: 33, width: 800, height: 900))
        #expect(result.placement == .docked)
        #expect(result.frame.y + result.frame.height == 933 - 12)
    }

    @Test func aFullScreenWindowDocksInsideTheScreen() {
        var display = Bar.screen
        display.visibleFrame = display.frame
        let result = layout(display.frame, on: display)
        #expect(result.placement == .docked)
        #expect(result.frame.y + result.frame.height == 982 - 12)
        #expect(result.frame.x == 606)
    }

    @Test func aWindowHangingOffTheScreenKeepsTheBarOnIt() {
        let result = layout(PointRect(x: 100, y: 20, width: 800, height: 1200))
        #expect(result.placement == .docked)
        #expect(result.frame.y + result.frame.height <= 933 - 8)
    }

    @Test func theCentreIsRoundedToWholePoints() {
        #expect(layout(PointRect(x: 100, y: 100, width: 801, height: 500)).frame.x == 351)
    }

    @Test func itIsClampedToBothScreenEdges() {
        #expect(layout(PointRect(x: -400, y: 100, width: 500, height: 400)).frame.x == 8)
        #expect(layout(PointRect(x: 1300, y: 100, width: 500, height: 400)).frame.x == 1204)
    }

    @Test func theDisplayIsTheOneWithTheLargestPartOfTheWindow() throws {
        let screens = [Bar.screen, Bar.external]
        let mostlyRight = PointRect(x: 1400, y: 100, width: 800, height: 500)
        let mostlyLeft = PointRect(x: 1000, y: 100, width: 800, height: 500)
        #expect(ControlBarLayout.display(for: mostlyRight, among: screens)?.id == 2)
        #expect(ControlBarLayout.display(for: mostlyLeft, among: screens)?.id == 1)
        // It never straddles the two: clamped inside the left screen, 8 pt from the seam.
        let display = try #require(ControlBarLayout.display(for: mostlyLeft, among: screens))
        let frame = ControlBarLayout.place(window: mostlyLeft, on: display).frame
        #expect(frame.x + frame.width == 1504)
    }

    @Test func aWindowOnNoScreenUsesTheKnownDisplay() {
        let away = PointRect(x: 9000, y: 9000, width: 400, height: 400)
        #expect(ControlBarLayout.display(for: away, among: [Bar.screen], fallback: Bar.external)?.id == 2)
    }

    @Test func aNarrowWindowGetsTheCompactBar() {
        let result = layout(PointRect(x: 100, y: 100, width: 260, height: 400))
        #expect(result.width == .compact)
        #expect(result.frame == PointRect(x: 134, y: 508, width: 192, height: 36))
        #expect(layout(PointRect(x: 100, y: 100, width: 300, height: 400)).width == .regular)
    }

    @Test func aVeryNarrowWindowKeepsTheCompactBarCentred() {
        let result = layout(PointRect(x: 100, y: 100, width: 120, height: 400))
        #expect(result.frame.width == 192)
        #expect(result.frame.x == 64)
    }

    @Test func theSlotsAddUpToBothWidths() {
        let m = ControlBarMetrics.self
        #expect(m.padding + m.sizeSlotWidth == 90)
        #expect(90 + m.slotGap == 102)
        #expect(102 + m.readoutWidth == 198)
        #expect(198 + m.slotGap == 210)
        #expect(210 + m.actionWidth == 294)
        #expect(294 + m.padding == m.regularWidth)
        #expect(m.padding * 2 + m.sizeSlotWidth + m.slotGap + m.actionWidth == m.compactWidth)
    }
}

// MARK: - When it shows

@Suite struct ControlBarVisibilityTests {
    @Test func aPickedWindowOnScreenShowsTheBar() {
        let model = Bar.model()
        #expect(model.display(at: 0) != nil)
        #expect(model.wantsTracking)
    }

    @Test func nothingPickedOrARegionShowsNothing() {
        // A picked region reaches the bar as no window.
        let model = Bar.model(ControlBarInput(target: nil))
        #expect(model.display(at: 0) == nil)
        #expect(!model.wantsTracking)
    }

    @Test func theSwitchHidesItAndStopsTracking() {
        var input = Bar.input()
        input.enabled = false
        let model = Bar.model(input)
        #expect(model.display(at: 0) == nil)
        #expect(!model.wantsTracking)
    }

    @Test func theHeadlessHostNeverShowsIt() {
        var input = Bar.input()
        input.menuBarApp = false
        #expect(Bar.model(input).display(at: 0) == nil)
        #expect(!Bar.model(input).wantsTracking)
    }

    @Test func thePickerHidesIt() {
        var input = Bar.input()
        input.pickerOpen = true
        #expect(Bar.model(input).display(at: 0) == nil)
    }

    @Test func aClosedWindowRemovesIt() {
        var input = Bar.input()
        input.windowClosed = true
        #expect(Bar.model(input).display(at: 0) == nil)
        #expect(!Bar.model(input).wantsTracking)
    }

    /// Minimised, hidden, on another Space and closed all reach the bar as `notVisible`.
    @Test func aWindowOutOfSightHidesItButKeepsTrackingSoItComesBack() {
        var model = Bar.model(presence: .notVisible)
        #expect(model.display(at: 0) == nil)
        #expect(model.wantsTracking)
        model.update(presence: .onScreen(Bar.window))
        #expect(model.display(at: 0) != nil)
    }

    @Test func itStaysWhileRecordingAndSaving() {
        #expect(Bar.model(Bar.input(activity: .recording(seconds: 3))).display(at: 0) != nil)
        #expect(Bar.model(Bar.input(activity: .saving)).display(at: 0) != nil)
    }

    @Test(arguments: [ControlBarActivity.recording(seconds: 3), .saving])
    func noRecordingChromeHidesItWhileCapturing(activity: ControlBarActivity) {
        var input = Bar.input(activity: activity)
        input.recordingChrome = false
        let model = Bar.model(input)
        #expect(model.display(at: 0) == nil)
        #expect(!model.wantsTracking)
    }

    @Test(arguments: [ControlBarActivity.idle, .starting])
    func noRecordingChromeLeavesThePickedWindowsBarAlone(activity: ControlBarActivity) {
        var input = Bar.input(activity: activity)
        input.recordingChrome = false
        #expect(Bar.model(input).display(at: 0) != nil)
    }

    /// The HUD's rule: the setting and the recording's own option must both allow it.
    @Test(arguments: [(true, true, true), (false, true, false), (true, false, false), (false, false, false)])
    func theChromeFlagFollowsTheHUDsRule(setting: Bool, recordingHUD: Bool, expected: Bool) {
        var snapshot = UIFixtures.recording(.mcp, client: "Claude Code")
        snapshot.hud = recordingHUD
        let context = MenuContext(snapshot: snapshot, recordingIndicator: setting)
        let input = ControlBarInput(
            context: context, windowClosed: false, outputWritable: true, resize: .none, recordStarting: false,
            reduceMotion: false)
        #expect(input.recordingChrome == expected)
        #expect(input.target?.window.id == UIFixtures.safari.id)
        #expect(input.activity == .recording(seconds: 12))
    }

    @Test func aRegionRecordingStillGetsNoBar() {
        var snapshot = UIFixtures.recording(.mcp, client: "Claude Code")
        snapshot.window = nil
        snapshot.region = PixelRect(x: 0, y: 0, width: 640, height: 360)
        let input = ControlBarInput(
            context: MenuContext(snapshot: snapshot), windowClosed: false, outputWritable: true, resize: .none,
            recordStarting: false, reduceMotion: false)
        #expect(Bar.model(input).display(at: 0) == nil)
    }

    @Test func itFollowsTheWindowAndChangesModeAtOnce() throws {
        var model = Bar.model()
        #expect(model.display(at: 0)?.placement == .below)
        model.update(presence: .onScreen(PointRect(x: 100, y: 500, width: 800, height: 420)))
        let moved = try #require(model.display(at: 0))
        #expect(moved.placement == .above)
        #expect(moved.frame.y == 456)
    }

    @Test func theInputComesFromTheAppState() {
        var context = RenderSamples.armed.context
        context.sizeChoice = .size(Bar.p1080)
        context.showControlBar = false
        context.snapshot.picking = true
        let input = ControlBarInput(
            context: context, windowClosed: false, outputWritable: false, resize: .resizing, recordStarting: true,
            reduceMotion: true)
        #expect(!input.enabled)
        #expect(input.menuBarApp)
        #expect(input.pickerOpen)
        #expect(input.target?.window.id == RenderSamples.safari.id)
        #expect(input.activity == .starting)
        #expect(!input.outputWritable)
    }
}

// MARK: - States

@Suite struct ControlBarStateTests {
    private func content(_ model: ControlBarModel, at now: TimeInterval = 0) throws -> ControlBarContent {
        try #require(model.display(at: now)).content
    }

    @Test func idleShowsThePresetThePixelsAndRecord() throws {
        let content = try content(Bar.model())
        let size = try #require(Bar.size(content))
        #expect(size.value == "1080p")
        #expect(size.enabled)
        #expect(size.help == "Clip size. Skreenrek resizes the window to fit.")
        #expect(size.accessibilityLabel == "Size, 1080p")
        let readout = try #require(content.readout)
        #expect(readout.text == "1920 × 1080 px")
        #expect(!readout.warning && !readout.dimmed)
        #expect(readout.accessibilityLabel == "1920 by 1080 pixels")
        #expect(readout.help == "The clip will be 1920 × 1080 px. The window is 800 × 500 pt on screen.")
        #expect(content.action.style == .record)
        #expect(content.action.action == .record)
        #expect(content.action.help == "Record this window.")
        #expect(content.action.accessibilityLabel == "Record")
        #expect(content.action.accessibilityHint == "Records Safari — localhost:3000.")
        #expect(content.groupLabel == "Skreenrek controls for Safari — localhost:3000")
    }

    @Test func aCustomSizeReadsCustomWithTheWindowsPixelsAndNoCheckmark() throws {
        let content = try content(Bar.model(Bar.input(choice: .keepCurrent)))
        let size = try #require(Bar.size(content))
        #expect(size.value == "Custom")
        #expect(content.readout?.text == "1600 × 1000 px")
        #expect(!size.entries.contains { if case .item(let item) = $0 { item.checked } else { false } })
    }

    @Test func resizingShowsTheNewNameAndThePreviousSizeDimmed() throws {
        var model = Bar.model()
        model.update(Bar.input(choice: .size(Bar.p720), resize: .resizing), now: 0)
        model.update(presence: .onScreen(PointRect(x: 100, y: 100, width: 640, height: 360)))
        let content = try content(model)
        #expect(Bar.size(content)?.value == "720p")
        #expect(content.readout?.text == "1920 × 1080 px")
        #expect(content.readout?.dimmed == true)
        #expect(content.action.style == .recordBusy)
        #expect(content.action.action == nil)
    }

    @Test func notExactShowsTheTriangleAndTheActualSizeWithoutPx() throws {
        let actual = PixelSize(width: 1926, height: 1080)
        let model = Bar.model(Bar.input(readback: Bar.readback(requested: Bar.p1080, actual: actual)))
        let content = try content(model)
        let readout = try #require(content.readout)
        #expect(readout.text == "1926 × 1080")
        #expect(readout.warning)
        #expect(readout.help == "Safari won't go narrower than 1926 px, so the clip is 1926 × 1080 instead of 1920 × 1080.")
        #expect(Bar.size(content)?.value == "1080p")
        #expect(content.action.style == .record)
    }

    @Test func aRefusalRevertsAndWarnsForFourSeconds() throws {
        var model = Bar.model()
        model.update(Bar.input(choice: .size(Bar.p720), resize: .resizing), now: 1)
        let announcement = model.update(
            Bar.input(resize: .refused(sequence: 1, reason: "Safari said no.")), now: 2)
        #expect(announcement == "Safari said no.")
        let during = try content(model, at: 5.99)
        #expect(Bar.size(during)?.value == "1080p")
        #expect(during.readout?.text == "1920 × 1080")
        #expect(during.readout?.warning == true)
        #expect(during.readout?.help == "Safari said no.")
        #expect(model.nextDeadline(after: 2) == 6)
        let after = try content(model, at: 6)
        #expect(after.readout?.text == "1920 × 1080 px")
        #expect(after.readout?.warning == false)
        #expect(model.nextDeadline(after: 6) == nil)
    }

    @Test func theSameRefusalIsAnnouncedOnce() {
        var model = Bar.model()
        let input = Bar.input(resize: .refused(sequence: 1, reason: "No."))
        #expect(model.update(input, now: 0) == "No.")
        #expect(model.update(input, now: 1) == nil)
        #expect(model.update(Bar.input(resize: .refused(sequence: 2, reason: "No.")), now: 2) == "No.")
    }

    @Test func disabledRecordKeepsItsSlotAndSizeStaysUsable() throws {
        let model = Bar.model(permissions: ControlBarPermissions(screenRecording: .missing))
        let content = try content(model)
        #expect(content.action.style == .recordBlocked(.screenRecording))
        #expect(content.action.action == nil)
        let sentence = "Screen Recording isn't allowed. Skreenrek can't record until you allow it."
        #expect(content.action.help == sentence)
        #expect(content.action.accessibilityLabel == "Record")
        #expect(content.action.accessibilityHint == sentence)
        #expect(Bar.size(content)?.enabled == true)
        #expect(content.width == .regular)
    }

    @Test func theDisabledReasonsComeInTheSpecsOrder() throws {
        let tooBig = SizeChoice.size(SizePreset.uhd4k.size)
        func block(_ permissions: ControlBarPermissions, _ choice: SizeChoice, writable: Bool) -> ControlBarBlock? {
            ControlBarModel.block(
                permissions: permissions, sizeChoice: choice, display: Bar.screen, outputWritable: writable)
        }
        let both = ControlBarPermissions(screenRecording: .missing, directCapture: .missing)
        #expect(block(both, tooBig, writable: false) == .screenRecording)
        let direct = ControlBarPermissions(directCapture: .missing)
        #expect(block(direct, tooBig, writable: false) == .directCapture)
        #expect(
            ControlBarBlock.directCapture.sentence
                == "Direct capture isn't approved. Finish setup so macOS asks about its private window picker first.")
        let fit = try #require(block(ControlBarPermissions(), tooBig, writable: false))
        #expect(
            fit.sentence == "4K needs room for a 1920 × 1080 pt window. Use a larger display or pick 1440p.")
        let folder = block(ControlBarPermissions(), .size(Bar.p1080), writable: false)
        #expect(folder == .outputFolder)
        #expect(folder?.sentence == "The output folder isn't writable. Choose another folder in Settings.")
        #expect(block(ControlBarPermissions(), .size(Bar.p1080), writable: true) == nil)
    }

    @Test func theOutputFolderBlocksRecordFromTheInput() throws {
        let content = try content(Bar.model(Bar.input(writable: false)))
        #expect(content.action.style == .recordBlocked(.outputFolder))
    }

    private static let noAccessibility = ControlBarPermissions(accessibility: .missing)
    private static let accessibilityOff =
        "Skreenrek can't resize windows without Accessibility. Recording at the current size."

    @Test func withoutAccessibilitySizeIsDisabledAndTheReadoutWarnsAtTheWindowsSize() throws {
        let content = try content(Bar.model(permissions: Self.noAccessibility))
        let size = try #require(Bar.size(content))
        #expect(!size.enabled)
        #expect(size.help == Self.accessibilityOff)
        let readout = try #require(content.readout)
        #expect(readout.text == "1600 × 1000")
        #expect(readout.warning)
        #expect(!readout.dimmed)
        #expect(readout.help == Self.accessibilityOff)
        #expect(readout.accessibilityLabel == "1600 by 1000 pixels")
        #expect(content.action.style == .record)
        #expect(content.action.action == .record)
    }

    /// The preset is never applied here, and Size is disabled, so it must not be able to block Record.
    @Test func withoutAccessibilityAPresetThatDoesNotFitLeavesRecordAvailable() throws {
        let input = Bar.input(choice: .size(SizePreset.uhd4k.size))
        let content = try content(Bar.model(input, permissions: Self.noAccessibility))
        #expect(content.action.style == .record)
        #expect(content.readout?.text == "1600 × 1000")
    }

    @Test func theAccessibilityWarningEndsWhenRecordingStarts() throws {
        let input = Bar.input(activity: .recording(seconds: 3))
        let readout = try #require(try content(Bar.model(input, permissions: Self.noAccessibility)).readout)
        #expect(!readout.warning)
        #expect(readout.text == "1920 × 1080 px")
    }

    @Test func theCompactBarSaysItOnceInTheTooltip() throws {
        let input = Bar.input(frame: Self.narrow, choice: .keepCurrent)
        let content = try content(Bar.model(input, permissions: Self.noAccessibility))
        let size = try #require(Bar.size(content))
        #expect(size.help == Self.accessibilityOff)
        #expect(size.accessibilityLabel == "Size, Custom, 520 by 800 pixels")
    }

    @Test func recordingShowsTheTimerThePixelsAndStop() throws {
        let content = try content(Bar.model(Bar.input(activity: .recording(seconds: 724))))
        #expect(content.leading == .timer("12:04"))
        #expect(content.readout?.text == "1920 × 1080 px")
        #expect(content.action.style == .stop)
        #expect(content.action.action == .stop)
        #expect(content.action.help == "Stop Recording (⌃⌘⎋)")
        #expect(content.action.accessibilityLabel == "Stop Recording, 12 minutes 4 seconds")
    }

    @Test(arguments: [(12, "0:12"), (3599, "59:59"), (3600, "1:00:00"), (3723, "1:02:03")])
    func theTimerGainsHoursAndTheBarKeepsItsWidth(seconds: Int, expected: String) throws {
        let display = try #require(Bar.model(Bar.input(activity: .recording(seconds: seconds))).display(at: 0))
        #expect(display.content.leading == .timer(expected))
        #expect(display.frame.width == 300)
        #expect(display.content.readout?.text == "1920 × 1080 px")
    }

    /// After the inset, the dot and its gap, the widest clock under 100 hours still fits the first slot.
    @Test func theLongestTimerFitsItsSlot() {
        let m = ControlBarMetrics.self
        let room = m.sizeSlotWidth - m.slotInset - m.statusDot - m.statusGap
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        let width = NSAttributedString(string: "88:88:88", attributes: [.font: font]).size().width
        #expect(width <= room, "\(width) in \(room)")
    }

    @Test func savingIsOneGroupOfSpinnerAndTextAndDisablesRecord() throws {
        let content = try content(Bar.model(Bar.input(activity: .saving)))
        #expect(content.leading == .saving(spinner: true, text: "Saving clip…", showsText: true))
        #expect(content.readout == nil)
        #expect(content.action.style == .recordBusy)
    }

    @Test func theSavingGroupHasTheSpaceLeftOfRecord() {
        #expect(ControlBarWidth.regular.leadingAreaWidth == 192)
        #expect(ControlBarWidth.compact.leadingAreaWidth == ControlBarMetrics.sizeSlotWidth)
        #expect(ControlBarMetrics.labelGap == 6)
    }

    @Test func reduceMotionSwapsTheSpinnerAndDropsTheFades() throws {
        let model = Bar.model(Bar.input(activity: .saving, reduceMotion: true))
        #expect(try content(model).leading == .saving(spinner: false, text: "Saving clip…", showsText: true))
        #expect(model.fadeSeconds == 0)
        #expect(Bar.model().fadeSeconds == 0.15)
    }

    @Test func startingDisablesRecordWithoutATriangle() throws {
        #expect(try content(Bar.model(Bar.input(activity: .starting))).action.style == .recordBusy)
    }

    @Test func theWidthNeverChangesBetweenStates() throws {
        let inputs = [
            Bar.input(), Bar.input(choice: .keepCurrent), Bar.input(activity: .recording(seconds: 1)),
            Bar.input(activity: .saving), Bar.input(writable: false), Bar.input(resize: .resizing),
        ]
        for input in inputs {
            let display = try #require(Bar.model(input).display(at: 0))
            #expect(display.frame.width == 300, "\(input.activity)")
        }
    }

    // MARK: Compact

    private static let narrow = PointRect(x: 100, y: 100, width: 260, height: 400)

    @Test func theCompactBarMovesThePixelsToThePopUp() throws {
        let content = try content(Bar.model(Bar.input(frame: Self.narrow, choice: .keepCurrent)))
        #expect(content.width == .compact)
        #expect(content.readout == nil)
        let size = try #require(Bar.size(content))
        #expect(size.accessibilityLabel == "Size, Custom, 520 by 800 pixels")
        #expect(
            size.help == "Clip size. Skreenrek resizes the window to fit. "
                + "The clip will be 520 × 800 px. The window is 260 × 400 pt on screen.")
    }

    /// The text stays off the compact bar. It is still the tooltip and what VoiceOver reads.
    @Test(arguments: [false, true])
    func theCompactBarKeepsSavingInTheTooltip(reduceMotion: Bool) throws {
        let input = Bar.input(frame: Self.narrow, activity: .saving, reduceMotion: reduceMotion)
        let content = try content(Bar.model(input))
        #expect(content.leading == .saving(spinner: !reduceMotion, text: "Saving clip…", showsText: false))
        #expect(content.readout == nil)
    }

    // MARK: Menu

    @Test func theMenuHasTheSixPresetsAndNothingElse() throws {
        let entries = try #require(Bar.size(try content(Bar.model()))).entries
        var titles: [String] = []
        for entry in entries {
            switch entry {
            case .item(let item): titles.append(item.title)
            case .separator: titles.append("-")
            default: Issue.record("Unexpected entry \(entry)")
            }
        }
        #expect(titles == ["720p", "1080p", "1440p", "4K", "-", "Square", "Portrait"])
    }

    @Test func theMenuChecksTheChoiceAndDisablesWhatDoesNotFit() throws {
        let entries = try #require(Bar.size(try content(Bar.model()))).entries
        let items = entries.compactMap { entry -> MenuItemModel? in
            if case .item(let item) = entry { return item }
            return nil
        }
        #expect(items.filter(\.checked).map(\.title) == ["1080p"])
        #expect(items.first?.trailing == "1280 × 720")
        #expect(items.first?.action == .chooseSize(.size(Bar.p720)))
        let k4 = try #require(items.first { $0.title == "4K" })
        #expect(!k4.enabled)
        #expect(k4.toolTip == "4K needs room for a 1920 × 1080 pt window. Use a larger display or pick 1440p.")
        #expect(items.first { $0.title == "1440p" }?.enabled == true)
    }

    @Test func theMenuFollowsTheWindowsDisplay() throws {
        let onExternal = PointRect(x: 1600, y: 100, width: 800, height: 500)
        let model = Bar.model(Bar.input(frame: onExternal), displays: [Bar.screen, Bar.external])
        let entries = try #require(Bar.size(try content(model))).entries
        // At 1× a clip needs its full size in points, so 1440p no longer fits as it does on the 2× laptop.
        let items = entries.compactMap { entry -> MenuItemModel? in
            if case .item(let item) = entry { return item }
            return nil
        }
        #expect(items.first { $0.title == "720p" }?.enabled == true)
        #expect(items.first { $0.title == "1440p" }?.enabled == false)
        #expect(items.first { $0.title == "4K" }?.enabled == false)
    }
}

// MARK: - Controller and shared tracker

@MainActor
private final class FakeBarSurface: ControlBarSurface {
    var log: [String] = []
    var last: ControlBarDisplay?
    var onUpdate: (() -> Void)?

    func show(_ display: ControlBarDisplay, fade: TimeInterval) {
        last = display
        log.append("show \(display.frame.y) fade \(fade)")
    }
    func update(_ display: ControlBarDisplay) {
        last = display
        log.append("update \(display.frame.y)")
        onUpdate?()
    }
    func hide(fade: TimeInterval) { log.append("hide fade \(fade)") }
    func keepAbove(_ window: WindowID) { log.append("above") }
    func announce(_ text: String) { log.append("say \(text)") }
}

@MainActor
private final class FakeOutlineSurface: SelectionOutlineSurface {
    var hidden = 0
    var onHide: (() -> Void)?
    func show(_ appearance: SelectionOutlineAppearance) {}
    func fadeOut(_ appearance: SelectionOutlineAppearance, duration: TimeInterval) {}
    func hide() {
        hidden += 1
        onHide?()
    }
    func keepAbove(_ window: WindowID) {}
    func announce(_ text: String) {}
}

@MainActor
private final class FakeBarTracker: WindowFrameTracking {
    var onChange: (@MainActor (WindowPresence) -> Void)?
    var started: [WindowID] = []
    var stops = 0
    var first = WindowPresence.onScreen(Bar.window)

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

@Suite struct ControlBarControllerTests {
    @MainActor
    private static func make(
        clock: ManualClock = ManualClock(), probe: FakePermissionProbe = FakePermissionProbe()
    ) -> (ControlBarController, FakeBarSurface, FakeBarTracker) {
        let surface = FakeBarSurface()
        let tracker = FakeBarTracker()
        let controller = ControlBarController(
            surface: surface, tracker: tracker, clock: clock, permissions: probe, displays: { [Bar.screen] })
        return (controller, surface, tracker)
    }

    @Test func aPickFadesInAndClearingFadesOut() async throws {
        try await onMain("bar fade") {
            let (controller, surface, tracker) = Self.make()
            var changes = 0
            controller.onVisibilityChange = { changes += 1 }
            controller.update(Bar.input())
            #expect(surface.log.contains("show 608.0 fade 0.15"))
            #expect(controller.isVisible)
            #expect(tracker.started == [RenderSamples.safari.id])
            controller.update(ControlBarInput(target: nil))
            #expect(surface.log.last == "hide fade 0.15")
            #expect(!controller.isVisible)
            #expect(tracker.stops == 1)
            #expect(changes == 2)
        }
    }

    @Test func reduceMotionShowsAndHidesInOneFrame() async throws {
        try await onMain("bar reduce motion") {
            let (controller, surface, _) = Self.make()
            let input = Bar.input(reduceMotion: true)
            controller.update(input)
            #expect(surface.log.contains("show 608.0 fade 0.0"))
            var off = input
            off.enabled = false
            controller.update(off)
            #expect(surface.log.last == "hide fade 0.0")
        }
    }

    @Test func everyTickReordersAndAMoveUpdatesWithoutAFade() async throws {
        try await onMain("bar tracking") {
            let (controller, surface, tracker) = Self.make()
            controller.update(Bar.input())
            surface.log = []
            tracker.onChange?(.onScreen(Bar.window))
            #expect(surface.log == ["above"])
            tracker.onChange?(.onScreen(PointRect(x: 100, y: 200, width: 800, height: 500)))
            #expect(surface.log == ["above", "update 708.0"])
            tracker.onChange?(.notVisible)
            #expect(surface.log.last == "hide fade 0.15")
            #expect(!controller.isVisible)
            tracker.onChange?(.onScreen(Bar.window))
            #expect(surface.log.last == "show 608.0 fade 0.15")
        }
    }

    @Test func aRefusalIsAnnouncedAndClearsItself() async throws {
        try await onMain("bar refusal") {
            let clock = ManualClock()
            let (controller, surface, _) = Self.make(clock: clock)
            controller.update(Bar.input())
            controller.update(Bar.input(resize: .resizing))
            controller.update(Bar.input(resize: .refused(sequence: 1, reason: "No.")))
            #expect(surface.log.contains("say No."))
            #expect(surface.last?.content.readout?.warning == true)
            await clock.waitForSleepers()
            #expect(clock.nextDeadline == 4)
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                surface.onUpdate = { done.resume() }
                clock.advance(to: 4)
            }
            #expect(surface.last?.content.readout?.warning == false)
        }
    }

    @Test func theBarFadesOutWhenAnUnpickedRecordingEnds() async throws {
        try await onMain("bar agent end") {
            let (controller, surface, tracker) = Self.make()
            var input = Bar.input(activity: .recording(seconds: 1))
            controller.update(input)
            #expect(controller.isVisible)
            input.target = nil
            input.activity = .idle
            controller.update(input)
            #expect(!controller.isVisible)
            #expect(surface.log.last == "hide fade 0.15")
            #expect(tracker.stops == 1)
        }
    }

    @Test func aPermissionChangeReachesTheBarOnATick() async throws {
        try await onMain("bar permissions") {
            let clock = ManualClock()
            let probe = FakePermissionProbe()
            let (controller, surface, tracker) = Self.make(clock: clock, probe: probe)
            controller.update(Bar.input())
            probe.accessibility = .missing
            tracker.onChange?(.onScreen(Bar.window))
            #expect(Bar.size(surface.last?.content)?.enabled == true)
            clock.advance(to: 1)
            tracker.onChange?(.onScreen(Bar.window))
            #expect(Bar.size(surface.last?.content)?.enabled == false)
        }
    }

    /// The outline's flash ends and stops its tracking. The bar is still up, so the one tracker keeps running.
    @Test func trackingOutlivesTheOutlineFlashWhileTheBarIsVisible() async throws {
        try await onMain("shared tracking") {
            let clock = ManualClock()
            let source = FakeBarTracker()
            let shared = SharedWindowFrameTracker(source: source)
            let outlineSurface = FakeOutlineSurface()
            let outline = SelectionOutlineController(
                surface: outlineSurface, tracker: shared.makeClient(), clock: clock, macOSMajorVersion: 26)
            let barSurface = FakeBarSurface()
            let bar = ControlBarController(
                surface: barSurface, tracker: shared.makeClient(), clock: clock,
                permissions: FakePermissionProbe(), displays: { [Bar.screen] })
            let target = SelectionOutlineTarget(window: RenderSamples.safari)
            outline.update(SelectionOutlineInput(target: target))
            outline.update(SelectionOutlineInput(target: target, pickCount: 1))
            bar.update(Bar.input())
            #expect(source.started == [RenderSamples.safari.id])
            await clock.waitForSleepers()
            clock.advance(to: 1.5)
            await clock.waitForSleepers()
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                outlineSurface.onHide = { done.resume() }
                clock.advance(to: 1.8)
            }
            #expect(source.stops == 0)
            source.onChange?(.onScreen(PointRect(x: 100, y: 200, width: 800, height: 500)))
            #expect(barSurface.log.last == "update 708.0")
            bar.update(ControlBarInput(target: nil))
            #expect(source.stops == 1)
        }
    }

    @Test func aSecondClientGetsTheLatestPositionRightAway() async throws {
        try await onMain("shared replay") {
            let source = FakeBarTracker()
            let shared = SharedWindowFrameTracker(source: source)
            let first = shared.makeClient()
            let second = shared.makeClient()
            var seen: [WindowPresence] = []
            first.start(RenderSamples.safari) { _ in }
            source.onChange?(.notVisible)
            second.start(RenderSamples.safari) { seen.append($0) }
            #expect(seen == [.notVisible])
            #expect(source.started.count == 1)
            first.stop()
            #expect(source.stops == 0)
            second.stop()
            #expect(source.stops == 1)
        }
    }

    @Test func aNewWindowMovesTheSharedTracker() async throws {
        try await onMain("shared switch") {
            let source = FakeBarTracker()
            let shared = SharedWindowFrameTracker(source: source)
            let client = shared.makeClient()
            var other = RenderSamples.safari
            other.id = WindowID(9)
            client.start(RenderSamples.safari) { _ in }
            client.start(other) { _ in }
            #expect(source.started == [RenderSamples.safari.id, other.id])
            #expect(source.stops == 1)
        }
    }
}

// MARK: - HUD

@Suite struct ControlBarHUDTests {
    @Test func theHUDStandsDownWhileTheBarIsVisible() {
        var model = HUDModel()
        var snapshot = UIFixtures.recording(.menu)
        model.observe(snapshot, now: 0, controlBarVisible: true)
        #expect(model.state == .hidden)
        snapshot.state = .writing
        model.observe(snapshot, now: 1, controlBarVisible: true)
        #expect(model.state == .hidden)
    }

    @Test func savedStillAppearsAfterASuppressedRecording() {
        var model = HUDModel()
        var snapshot = UIFixtures.recording(.menu)
        model.observe(snapshot, now: 0, controlBarVisible: true)
        snapshot.state = .armed
        snapshot.lastClip = RenderSamples.clip()
        model.observe(snapshot, now: 1, controlBarVisible: true)
        #expect(model.state.kind == .saved)
    }

    @Test func theHUDComesBackWhenTheBarGoesAway() {
        var model = HUDModel()
        let snapshot = UIFixtures.recording(.menu)
        model.observe(snapshot, now: 0, controlBarVisible: true)
        model.observe(snapshot, now: 1, controlBarVisible: false)
        #expect(model.state == .recording(target: "Safari", seconds: 12))
    }

    @Test func theIndicatorSettingStillWinsWithoutTheBar() {
        var model = HUDModel()
        model.observe(UIFixtures.recording(.menu), now: 0, indicatorEnabled: false, controlBarVisible: false)
        #expect(model.state == .hidden)
    }
}

// MARK: - App state

@Suite struct ControlBarAppModelTests {
    /// Pick → armed and idle → the bar is on with Record, through the same input MenuController builds.
    @Test func pickingAWindowShowsTheBarIdleWithRecordEnabled() async throws {
        try await onMain("bar on pick") {
            let h = MenuHarness()
            defer { h.cleanUp() }
            let surface = FakeBarSurface()
            let tracker = FakeBarTracker()
            let controller = ControlBarController(
                surface: surface, tracker: tracker, clock: ManualClock(), permissions: h.permissions,
                displays: { [MenuHarness.display] })
            #expect(!controller.isVisible)

            await h.perform(.pickWindow)
            #expect(h.model.snapshot.state == .armed)
            #expect(h.model.context.isArmed)
            #expect(!h.model.snapshot.picking)
            #expect(h.model.snapshot.window?.id == UIFixtures.safari.id)
            #expect(!h.model.recordStarting)

            let context = h.model.context
            #expect(context.snapshot.window != nil && context.isArmed)
            controller.update(
                ControlBarInput(
                    context: context, windowClosed: false, outputWritable: true, resize: .none,
                    recordStarting: h.model.recordStarting, reduceMotion: true))

            #expect(controller.isVisible)
            #expect(tracker.started == [UIFixtures.safari.id])
            #expect(surface.last?.content.action.style == .record)
            #expect(surface.last?.content.action.action == .record)
        }
    }

    @Test func theSwitchDefaultsOnAndIsSharedByThePanelAndSettings() async throws {
        try await onMain("control bar switch") {
            let (defaults, name) = SettingsStoreTests.suite()
            defer { defaults.removePersistentDomain(forName: name) }
            let store = SettingsStore(defaults: defaults)
            #expect(store.showControlBar)
            store.showControlBar = false
            #expect(defaults.object(forKey: "showControlBar") as? Bool == false)
            #expect(!SettingsStore(defaults: defaults).showControlBar)

            let h = MenuHarness()
            defer { h.cleanUp() }
            #expect(h.model.context.showControlBar)
            await h.perform(.toggleControlBar)
            #expect(!h.model.settings.showControlBar)
            #expect(!h.model.context.showControlBar)
            let toggle = PanelModel.content(for: h.model.context, preview: .noWindow).toggles.last
            #expect(toggle?.isOn == false)
        }
    }

    @Test func aPresetFromTheBarUsesTheExactResizeAndClears() async throws {
        try await onMain("bar resize") {
            let h = MenuHarness()
            defer { h.cleanUp() }
            await h.perform(.pickWindow)
            await h.model.chooseBarSize(Bar.p720, currentFrame: UIFixtures.safari.frame)
            #expect(h.resizer.calls.count == 1)
            #expect(h.model.barResize == .none)
            #expect(h.model.settings.sizeChoice == .size(Bar.p720))
            #expect(h.model.snapshot.readback?.actual == Bar.p720)
            #expect(h.model.snapshot.readback?.exact == true)
        }
    }

    @Test func aWindowThatKeepsItsSizeIsARefusalAndRevertsTheChoice() async throws {
        try await onMain("bar refused") {
            let h = MenuHarness()
            defer { h.cleanUp() }
            h.resizer.rules = ResizeRules(ignoredAttempts: [1, 2, 3])
            await h.perform(.pickWindow)
            let before = h.model.settings.sizeChoice
            await h.model.chooseBarSize(Bar.p720, currentFrame: UIFixtures.safari.frame)
            guard case .refused(1, let reason) = h.model.barResize else {
                Issue.record("Expected a refusal, got \(h.model.barResize)")
                return
            }
            #expect(reason.contains("instead of 1280 × 720"))
            #expect(h.model.settings.sizeChoice == before)
            #expect(h.model.actionError == nil)
        }
    }

    @Test func aFailedResizeIsARefusalToo() async throws {
        try await onMain("bar failed") {
            let h = MenuHarness()
            defer { h.cleanUp() }
            await h.perform(.pickWindow)
            h.resizer.failure = SkreenrekError.internal(message: "It broke.\nMore detail.")
            await h.model.chooseBarSize(Bar.p720, currentFrame: UIFixtures.safari.frame)
            #expect(h.model.barResize == .refused(sequence: 1, reason: "It broke."))
            #expect(h.model.settings.sizeChoice == .keepCurrent)
        }
    }

    @Test func aResizeThatLandsElsewhereStaysAndIsNotARefusal() async throws {
        try await onMain("bar not exact") {
            let h = MenuHarness()
            defer { h.cleanUp() }
            h.resizer.rules = ResizeRules(maximumSize: CGSize(width: 1000, height: 700))
            await h.perform(.pickWindow)
            await h.model.chooseBarSize(Bar.p720, currentFrame: UIFixtures.safari.frame)
            #expect(h.model.barResize == .none)
            #expect(h.model.settings.sizeChoice == .size(Bar.p720))
            #expect(h.model.snapshot.readback?.exact == false)
        }
    }

    @Test func recordFromTheBarWithoutAccessibilityRecordsTheWindowAsItIs() async throws {
        try await onMain("bar record without accessibility") {
            let h = MenuHarness(frames: 31)
            defer { h.cleanUp() }
            h.permissions.accessibility = .missing
            await h.perform(.pickWindow)
            h.model.settings.sizeChoice = .size(Bar.p720)
            await h.model.recordFromBar()
            h.model.apply(await h.controller.snapshot())
            #expect(h.model.snapshot.state == .recording)
            #expect(h.model.snapshot.size == UIFixtures.size)
            #expect(h.resizer.calls.isEmpty)
            #expect(h.model.actionError == nil)
            #expect(h.model.snapshot.error == nil)
            await h.perform(.stop)
        }
    }

    @Test func recordFromTheBarWithAccessibilityStillResizesFirst() async throws {
        try await onMain("bar record with accessibility") {
            let h = MenuHarness(frames: 31)
            defer { h.cleanUp() }
            await h.perform(.pickWindow)
            h.model.settings.sizeChoice = .size(Bar.p720)
            await h.model.recordFromBar()
            h.model.apply(await h.controller.snapshot())
            #expect(h.model.snapshot.state == .recording)
            #expect(h.model.snapshot.size == Bar.p720)
            #expect(h.resizer.calls.count == 1)
            await h.perform(.stop)
        }
    }

    @Test func thePanelsRecordStillNeedsAccessibilityForAPreset() async throws {
        try await onMain("panel record without accessibility") {
            let h = MenuHarness(frames: 31)
            defer { h.cleanUp() }
            h.permissions.accessibility = .missing
            await h.perform(.pickWindow)
            h.model.settings.sizeChoice = .size(Bar.p720)
            await h.perform(.record)
            #expect(h.model.snapshot.state != .recording)
            #expect(h.model.actionError == .permissionDenied(.accessibility))
        }
    }

    @Test func aRecordingFromTheMenuKeepsTheWindowPicked() async throws {
        try await onMain("bar keeps window") {
            let h = MenuHarness(frames: 31)
            defer { h.cleanUp() }
            await h.perform(.pickWindow)
            await h.perform(.record)
            #expect(h.model.snapshot.state == .recording)
            #expect(!h.model.recordStarting)
            await h.perform(.stop)
            #expect(h.model.snapshot.state == .armed)
            #expect(h.model.snapshot.window?.id == UIFixtures.safari.id)
            #expect(h.model.snapshot.lastClip != nil)
            #expect(h.model.snapshot.pickCount == 1)
        }
    }

    @Test func withTheBarOffARecordingForgetsTheWindowAsBefore() async throws {
        try await onMain("bar off forgets") {
            let h = MenuHarness(frames: 31)
            defer { h.cleanUp() }
            await h.perform(.toggleControlBar)
            await h.perform(.pickWindow)
            await h.perform(.record)
            await h.perform(.stop)
            #expect(h.model.snapshot.state == .idle)
            #expect(h.model.snapshot.window == nil)
        }
    }

    @Test func aRecordingFromTheBarKeepsTheWindowPicked() async throws {
        try await onMain("bar record keeps window") {
            let h = MenuHarness(frames: 31)
            defer { h.cleanUp() }
            await h.perform(.pickWindow)
            await h.model.recordFromBar()
            h.model.apply(await h.controller.snapshot())
            #expect(h.model.snapshot.state == .recording)
            await h.perform(.stop)
            #expect(h.model.snapshot.state == .armed)
            #expect(h.model.snapshot.window?.id == UIFixtures.safari.id)
            #expect(h.model.snapshot.lastClip != nil)
            #expect(Self.bar(h).display(at: 0)?.content.action.style == .record)
        }
    }

    @MainActor
    private static func input(_ h: MenuHarness) -> ControlBarInput {
        ControlBarInput(
            context: h.model.context, windowClosed: false, outputWritable: true, resize: .none,
            recordStarting: false, reduceMotion: false)
    }

    @MainActor
    private static func bar(_ h: MenuHarness) -> ControlBarModel { Bar.model(input(h)) }

    private static func agentParams(hud: Bool? = nil) -> StartParams {
        StartParams(windowId: UIFixtures.safari.id.rawValue, hud: hud)
    }

    @Test func anAgentsWindowRecordingShowsTheBarsRecordingStateThenHidesIt() async throws {
        try await onMain("agent bar") {
            let h = MenuHarness(frames: 31)
            defer { h.cleanUp() }
            #expect(h.model.snapshot.window == nil)
            _ = try await h.controller.start(Self.agentParams(), startedBy: .mcp, client: "Claude Code")
            h.model.apply(await h.controller.snapshot())
            let content = try #require(Self.bar(h).display(at: 0)).content
            guard case .timer = content.leading else {
                Issue.record("Expected the timer, got \(content.leading)")
                return
            }
            #expect(content.action.style == .stop)
            _ = try await h.controller.stop()
            h.model.apply(await h.controller.snapshot())
            #expect(h.model.snapshot.window == nil)
            #expect(Self.bar(h).display(at: 0) == nil)
        }
    }

    @Test func noHUDHidesTheBarDuringAnAgentsRecording() async throws {
        try await onMain("agent no hud") {
            let h = MenuHarness(frames: 31)
            defer { h.cleanUp() }
            _ = try await h.controller.start(Self.agentParams(hud: false), startedBy: .cli)
            h.model.apply(await h.controller.snapshot())
            #expect(h.model.snapshot.state == .recording)
            #expect(h.model.snapshot.window?.id == UIFixtures.safari.id)
            #expect(Self.bar(h).display(at: 0) == nil)
            _ = try await h.controller.stop()
        }
    }

    @Test func theRecordingIndicatorSettingHidesTheBarUntilTheClipIsDone() async throws {
        try await onMain("indicator off") {
            let h = MenuHarness(frames: 31)
            defer { h.cleanUp() }
            h.model.settings.hud = false
            await h.model.pushSettings()
            await h.perform(.pickWindow)
            #expect(Self.bar(h).display(at: 0) != nil)
            await h.perform(.record)
            #expect(h.model.snapshot.state == .recording)
            #expect(Self.bar(h).display(at: 0) == nil)
            await h.perform(.stop)
            #expect(h.model.snapshot.window?.id == UIFixtures.safari.id)
            #expect(Self.bar(h).display(at: 0)?.content.action.style == .record)
        }
    }

    @Test func aRecordingStartedElsewhereForgetsTheWindowAsBefore() async throws {
        try await onMain("agent recording") {
            let h = MenuHarness(frames: 31)
            defer { h.cleanUp() }
            await h.perform(.pickWindow)
            _ = try await h.controller.start(StartParams(), startedBy: .mcp, client: "Claude Code")
            _ = try await h.controller.stop()
            let snapshot = await h.controller.snapshot()
            #expect(snapshot.state == .idle)
            #expect(snapshot.window == nil)
        }
    }
}

// MARK: - Panel row

@Suite struct ControlBarPanelRowTests {
    private func armed(clip: Bool, update: Bool) -> PanelContent {
        var context = RenderSamples.armed.context
        context.sizeChoice = .size(SizePreset.p1080.size)
        context.updateAvailable = update ? "1.0.4" : nil
        if !clip { context.snapshot.lastClip = nil }
        return PanelModel.content(
            for: context, preview: .ready(WindowStill(png: Data(), pixelWidth: 320, pixelHeight: 180)))
    }

    @Test func theSwitchFollowsWriteClickEvents() throws {
        let toggles = armed(clip: false, update: false).toggles
        #expect(toggles.map(\.title) == ["Show Cursor", "Write Click Events", "Show Control Bar"])
        let row = try #require(toggles.last)
        #expect(row.symbol == "rectangle.bottomthird.inset.filled")
        #expect(row.isOn)
        #expect(row.action == .toggleControlBar)
        #expect(row.accessibilityLabel == "Show Control Bar")
        #expect(NSImage(systemSymbolName: row.symbol, accessibilityDescription: nil) != nil)
        #expect(PanelModel.keepsPanelOpen(.toggleControlBar))
    }

    @Test func thePanelHeightsGrowByOneRow() {
        #expect(PanelMetrics.contentHeight(armed(clip: false, update: false)) == 558.5)
        #expect(PanelMetrics.contentHeight(armed(clip: true, update: false)) == 619.5)
        #expect(PanelMetrics.contentHeight(armed(clip: true, update: true)) == 647.5)
        let none = PanelModel.content(for: RenderSamples.idle.context, preview: .noWindow)
        #expect(PanelMetrics.contentHeight(none) == 351)
        #expect(none.toggles.last?.title == "Show Control Bar")
    }

    @Test func theNewCopyIsInTheAudit() {
        for text in [
            "Show Control Bar", "Show control bar", "Record this window.",
            "Clip size. Skreenrek resizes the window to fit.",
            "The output folder isn't writable. Choose another folder in Settings.",
            "Skreenrek can't resize windows without Accessibility. Recording at the current size.",
        ] {
            #expect(UIStrings.allFixed.contains(text), "\(text)")
        }
    }
}

// MARK: - The view and the window

@MainActor
@Suite struct ControlBarSurfaceTests {
    private func content(_ input: ControlBarInput = Bar.input()) throws -> ControlBarContent {
        try #require(Bar.model(input).display(at: 0)).content
    }

    private func hosted(_ content: ControlBarContent) -> NSView {
        let view = NSHostingView(
            rootView: ControlBarView(presentation: ControlBarPresentation(content: content), onAction: { _ in }))
        view.sizingOptions = []
        view.frame = NSRect(x: 0, y: 0, width: content.width.points, height: ControlBarMetrics.height)
        return view
    }

    private static func visualEffectViews(in view: NSView) -> Int {
        view.subviews.reduce(view is NSVisualEffectView ? 1 : 0) { $0 + visualEffectViews(in: $1) }
    }

    @Test func theBarHasNoGlass() throws {
        let inputs = [Bar.input(), Bar.input(activity: .recording(seconds: 3)), Bar.input(activity: .saving)]
        for input in inputs {
            let view = hosted(try content(input))
            let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            #expect(!view.subviews.isEmpty)
            #expect(Self.visualEffectViews(in: view) == 0)
            window.contentView = nil
        }
    }

    @Test func theShadowTokensMatchTheAddendum() {
        #expect(PanelPalette(.dark).dropShadow == PanelShadow(opacity: 0.35, blur: 24, y: 8))
        #expect(PanelPalette(.light).dropShadow == PanelShadow(opacity: 0.15, blur: 20, y: 6))
    }

    /// Reads the drawn pixels: the surface token, and the slot edges at x 6, 90, 210 and 294.
    @Test(arguments: [UIRenderer.Appearance.light, .dark])
    func theFillAndSlotEdgesAreWhereTheSpecPutsThem(appearance: UIRenderer.Appearance) throws {
        let palette = PanelPalette(appearance == .dark ? .dark : .light)
        let data = try UIRenderer.png(hosted(try content()), appearance: appearance, active: true)
        let image = try #require(NSBitmapImageRep(data: data))
        #expect(image.pixelsWide == 600)
        #expect(image.pixelsHigh == 72)
        // Raw bytes: the PNG is tagged sRGB, and `colorAt` would convert them again.
        func isTone(_ x: Int, _ y: Int, _ tone: PanelTone) -> Bool {
            var pixel = [Int](repeating: 0, count: 4)
            image.getPixel(&pixel, atX: x * 2, y: y * 2)
            return pixel == [Int(tone.red), Int(tone.green), Int(tone.blue), 255]
        }
        #expect(isTone(3, 18, palette.fill), "bar fill")
        #expect(isTone(5, 18, palette.fill), "before the pop-up")
        #expect(isTone(7, 18, palette.cellFill), "pop-up start")
        #expect(isTone(88, 18, palette.cellFill), "pop-up end")
        #expect(isTone(91, 18, palette.fill), "after the pop-up")
        #expect(isTone(209, 18, palette.fill), "before Record")
        #expect(!isTone(211, 18, palette.fill), "Record start")
        #expect(!isTone(292, 18, palette.fill), "Record end")
        #expect(isTone(295, 18, palette.fill), "after Record")
    }

    /// Reads the drawn pixels left of Record: the indicator and the text form one centred group, 6 pt apart.
    @Test(arguments: [false, true], [UIRenderer.Appearance.light, .dark])
    func theSavingGroupIsCentredLeftOfRecord(reduceMotion: Bool, appearance: UIRenderer.Appearance) throws {
        let input = Bar.input(activity: .saving, reduceMotion: reduceMotion)
        let data = try UIRenderer.png(hosted(try content(input)), appearance: appearance, active: true)
        let image = try #require(NSBitmapImageRep(data: data))
        let fill = PanelPalette(appearance == .dark ? .dark : .light).fill
        let background = [Int(fill.red), Int(fill.green), Int(fill.blue), 255]
        // Device pixels, inside the 6...198 pt area and clear of the bar's hairline.
        let inked = (12..<396).filter { x in
            (4..<(image.pixelsHigh - 4)).contains { y in
                var pixel = [Int](repeating: 0, count: 4)
                image.getPixel(&pixel, atX: x, y: y)
                return pixel != background
            }
        }
        let first = try #require(inked.first)
        let last = try #require(inked.last)
        let centre = Double(first + last + 1) / 4
        #expect(abs(centre - 102) <= 1.5, "centre \(centre) pt")
        #expect(Double(first) / 2 > 30, "starts at \(Double(first) / 2) pt")
        // The widest empty run in the group is the gap after the indicator, which ends at most 16 pt from the start.
        let gaps = zip(inked, inked.dropFirst()).filter { $1 - $0 > 1 && $0 - first < 36 }
        let gap = try #require(gaps.max { $0.1 - $0.0 < $1.1 - $1.0 })
        let gapPoints = Double(gap.1 - gap.0 - 1) / 2
        #expect(gapPoints >= 5 && gapPoints <= 8, "gap \(gapPoints) pt")
    }

    /// `.transient` is omitted: it would hide the bar when focus returns to the picked window.
    @Test func thePanelNeverTakesFocusAndStaysOutOfCapture() {
        let panel = ControlBarPanel()
        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.becomesKeyOnlyIfNeeded)
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.hasShadow)
        #expect(!panel.isMovable)
        #expect(!panel.isMovableByWindowBackground)
        #expect(panel.sharingType == .none)
        #expect(!panel.collectionBehavior.contains(.transient))
        #expect(panel.collectionBehavior == [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle])
    }

    /// `sharingType = .none` is what keeps the bar out. Listing it in `exceptingWindows` would put it back.
    @Test func noCaptureFilterAddsWindowsBack() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var filters = 0
        for case let file as URL in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for use in text.components(separatedBy: "exceptingWindows:").dropFirst() {
                filters += 1
                #expect(use.hasPrefix(" []"), "\(file.lastPathComponent)")
            }
        }
        #expect(filters > 0)
    }

    @Test func theFirstClickActs() {
        let view = ControlBarHostingView(rootView: Color.clear)
        #expect(view.acceptsFirstMouse(for: nil))
    }

    @Test func everyRenderCaseIsThere() {
        let names = Set(ControlBarRenderer.samples().map(\.name))
        for name in [
            "below", "above", "docked", "recording", "recording-hour", "disabled", "disabled-size", "narrow", "saving",
            "saving-reducedmotion", "size-menu",
        ] {
            #expect(names.contains(name), "\(name)")
        }
        #expect(UIRenderer.settingsSamples.contains { $0.name == "general-control-bar" })
    }
}
