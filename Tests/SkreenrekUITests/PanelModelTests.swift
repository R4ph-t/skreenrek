import Foundation
import SkreenrekCore
import SkreenrekTesting
@testable import SkreenrekUI
import Synchronization
import Testing

/// The menu panel: one height for each spec state, the letterbox, the preview fake, and the clip opener.
@Suite struct PanelModelTests {
    private static let still = WindowStill(png: Data([0x89]), pixelWidth: 536, pixelHeight: 335)

    // MARK: - Heights

    @Test func aPickedWindowHasEveryHeightTheSpecMeasured() {
        #expect(PanelMetrics.contentHeight(Self.armed(clip: false, update: false)) == 558.5)
        #expect(PanelMetrics.contentHeight(Self.armed(update: false)) == 619.5)
        let content = Self.armed()
        #expect(PanelMetrics.contentHeight(content) == 647.5)
        #expect(PanelMetrics.contentHeight(content) == PanelMetrics.idleHeight)
        #expect(PanelMetrics.contentHeight(content) <= PanelMetrics.idleBudget)
        #expect(!content.isCompact)
        #expect(content.showsCells)
        #expect(content.showsPicker)
        #expect(content.showsToggles)
        #expect(content.showsLastClip)
        #expect(content.hero?.action == .record)
        #expect(content.hero?.enabled == true)
        #expect(content.hero?.tint == .accent)
    }

    @Test func recordingHasBothHeightsAndHidesThePicker() throws {
        #expect(PanelMetrics.contentHeight(try Self.recording(update: false)) == 457.5)
        let content = try Self.recording()
        #expect(PanelMetrics.contentHeight(content) == 485.5)
        #expect(PanelMetrics.contentHeight(content) == PanelMetrics.recordingHeight)
        #expect(PanelMetrics.contentHeight(content) <= PanelMetrics.recordingBudget)
        #expect(!content.showsCells)
        #expect(!content.showsPicker)
        #expect(!content.showsToggles)
        #expect(!content.showsLastClip)
        #expect(content.discard != nil)
        #expect(content.origin != nil)
        #expect(content.hero?.role == .stop)
        #expect(content.hero?.tint == .red)
    }

    @Test(arguments: [(false, false, 351.0), (true, false, 412.0), (false, true, 379.0), (true, true, 440.0)])
    func theCompactPanelHasEveryHeightTheSpecMeasured(clip: Bool, update: Bool, height: CGFloat) {
        #expect(PanelMetrics.contentHeight(Self.noWindow(clip: clip, update: update)) == height)
        #expect(PanelMetrics.contentHeight(Self.windowClosed(clip: clip, update: update)) == height)
    }

    @Test func noWindowHasAHeaderAndPickButNoPreviewOrRecord() {
        let content = Self.noWindow(clip: false, update: false)
        #expect(PanelMetrics.contentHeight(content) == PanelMetrics.compactHeight)
        #expect(content.isCompact)
        #expect(content.preview == nil)
        #expect(content.caption == nil)
        #expect(content.clear == nil)
        #expect(!PanelMetrics.blocks(for: content).contains(.preview))
        #expect(content.header?.icon == .noWindow)
        #expect(content.header?.title == "No window")
        #expect(content.header?.detail == "Pick a window to record")
        #expect(content.header?.accessibilityLabel == "No window picked. Pick a window to record.")
        #expect(content.hero?.title == "Pick Window…")
        #expect(content.hero?.symbol == "viewfinder")
        #expect(content.hero?.tint == .accent)
        #expect(content.hero?.isDefault == true)
        #expect(!content.showsPicker)
        #expect(content.showsCells)
        #expect(content.showsToggles)
    }

    @Test func aClosedWindowUsesTheCompactLayout() {
        let content = Self.windowClosed(clip: false, update: false)
        #expect(content.isCompact)
        #expect(content.preview == nil)
        #expect(content.clear == nil)
        #expect(content.header?.icon == .windowClosed)
        #expect(content.header?.title == UIStrings.Panel.windowClosed)
        #expect(content.header?.detail == "Safari — localhost:3000")
        #expect(content.hero?.title == UIStrings.Menu.pickWindow)
        #expect(!content.showsPicker)
        #expect(content.rows.contains { if case .showInFinder = $0.action { true } else { false } } == false)
    }

    @Test func aRecordingThatLostItsWindowReadsAsWindowClosed() {
        var context = RenderSamples.idle.context
        context.snapshot.error = .recordingFailed(.windowClosed(at: 31))
        let content = PanelModel.content(for: context, preview: .noWindow, closedTitle: "Safari — localhost:3000")
        #expect(content.header?.icon == .windowClosed)
        #expect(content.rows.isEmpty)
    }

    @Test func aMissingPermissionWithNoWindowStaysCompactAndOffersTheRow() {
        var context = RenderSamples.idle.context
        context.permissionsMissing = true
        let content = PanelModel.content(for: context, preview: .permissionMissing(.screenRecording))
        #expect(content.isCompact)
        #expect(content.hero?.action == .pickWindow)
        #expect(content.rows.map(\.action) == [.showPermissions])
    }

    @Test func loadingCaptureFailedAndPermissionKeepTheIdleHeight() throws {
        let loading = Self.armed(phase: .loading)
        let slow = Self.armed(phase: .loading, spinner: true)
        let failed = Self.armed(phase: .failed)
        let missing = Self.armed(phase: .permissionMissing(.screenRecording))
        #expect(PanelMetrics.contentHeight(loading) == PanelMetrics.idleHeight)
        #expect(PanelMetrics.contentHeight(slow) == PanelMetrics.idleHeight)
        #expect(PanelMetrics.contentHeight(failed) == PanelMetrics.idleHeight)
        #expect(PanelMetrics.contentHeight(missing) == PanelMetrics.idleHeight)
        #expect(loading.preview?.showsSpinner == false)
        #expect(slow.preview?.showsSpinner == true)
        #expect(failed.hero?.enabled == true)
        #expect(failed.preview?.message == UIStrings.Panel.previewUnavailable)
        #expect(failed.preview?.messageHelp == UIStrings.Panel.previewFailedHelp)
        #expect(missing.hero?.enabled == false)
        #expect(missing.preview?.message == UIStrings.Errors.screenRecordingOff)
        #expect(missing.preview?.messageHelp == UIStrings.Errors.screenRecordingDetail)
        #expect(missing.preview?.settings?.action == .openPrivacySettings(.screenRecording))
        #expect(missing.preview?.settings?.title == UIStrings.Panel.openSettings)
        #expect(!missing.rows.contains { $0.action == .showPermissions })
    }

    @Test func everySpecStateFitsTheShortScreen() throws {
        let states = [
            Self.armed(), Self.noWindow(), Self.windowClosed(), Self.armed(phase: .loading),
            Self.armed(phase: .loading, spinner: true), Self.armed(phase: .failed),
            Self.armed(phase: .permissionMissing(.screenRecording)), try Self.recording(),
        ]
        for content in states {
            #expect(PanelMetrics.contentHeight(content) <= PanelMetrics.availableHeight())
            #expect(!PanelMetrics.scrolls(content))
        }
        #expect(PanelMetrics.scrolls(Self.armed(), screenHeight: 400))
    }

    // MARK: - Geometry

    @Test func everythingSharesTheContentEdges() {
        #expect(PanelMetrics.margin == 16)
        #expect(PanelMetrics.blockWidth == 268)
        #expect(PanelMetrics.contentEndX == 284)
        #expect(PanelMetrics.iconX == 16)
        #expect(PanelMetrics.iconColumn == 16)
        #expect(PanelMetrics.textX == 40)
        #expect(PanelMetrics.rowHighlightX == 8)
        #expect(PanelMetrics.rowHighlightX + PanelMetrics.rowHighlightWidth == 292)
        #expect(PanelMetrics.rowHighlightX + PanelMetrics.rowHighlightWidth - PanelMetrics.rowPadding == 284)
        #expect(PanelMetrics.top == 16)
        #expect(PanelMetrics.bottom == 8)
        #expect(PanelMetrics.capturePixels(scale: 2) == PixelSize(width: 536, height: 335))
    }

    @Test func iconButtonGlyphsEndOnTheContentEdgeAndTheirHitAreasOverhangIt() {
        #expect(PanelMetrics.iconButton == 24)
        #expect(PanelMetrics.iconGlyph == 16)
        #expect(PanelMetrics.clearHitX == 264)
        #expect(PanelMetrics.clearHitX + PanelMetrics.iconButton == 288)
        #expect(PanelMetrics.clearGlyphEndX == 284)
        #expect(PanelMetrics.clearTitleWidth == 236)
    }

    // MARK: - Clear

    @Test func clearShowsOnlyWhileAPickedWindowCanBeForgotten() throws {
        for phase in [PanelPreviewPhase.ready(Self.still), .loading, .failed, .permissionMissing(.screenRecording)] {
            let clear = try #require(Self.armed(phase: phase).clear, "\(phase)")
            #expect(clear.action == .clearWindow)
            #expect(clear.symbol == "xmark.circle.fill")
            #expect(clear.help == "Clear Window")
            #expect(clear.accessibilityLabel == "Clear picked window")
        }
        #expect(try Self.recording().clear == nil)
        #expect(Self.writing().clear == nil)
        #expect(Self.noWindow().clear == nil)
        #expect(Self.windowClosed().clear == nil)
        #expect(Self.armed(phase: .windowClosed(nil)).clear == nil)
        #expect(Self.armed(phase: .windowClosed(nil)).isCompact)
    }

    @Test func clearKeepsThePanelOpen() {
        #expect(PanelModel.keepsPanelOpen(.clearWindow))
    }

    @Test func pickAnotherStaysBesideClear() {
        #expect(Self.armed().rows.first?.title == UIStrings.Menu.pickAnotherWindow)
    }

    @Test func clearForgetsTheWindowAndKeepsTheSizeAndRate() async throws {
        try await onMain("clear") {
            let harness = MenuHarness()
            defer { harness.cleanUp() }
            harness.model.settings.sizeChoice = .size(SizePreset.p1080.size)
            harness.model.settings.fps = .fps30
            await harness.controller.updateSettings(harness.model.settings.controllerSettings)
            _ = try await harness.controller.pick()
            harness.model.apply(await harness.controller.snapshot())
            #expect(harness.model.snapshot.window != nil)
            let resizes = harness.resizer.calls.count
            await harness.perform(.clearWindow)
            harness.model.apply(await harness.controller.snapshot())
            #expect(harness.model.snapshot.window == nil)
            #expect(harness.model.snapshot.state == .idle)
            #expect(harness.model.settings.sizeChoice == .size(SizePreset.p1080.size))
            #expect(harness.model.settings.fps == .fps30)
            #expect(harness.resizer.calls.count == resizes)
            #expect(PanelModel.content(for: harness.model.context, preview: .noWindow).isCompact)
        }
    }

    // MARK: - Selected stroke

    @Test func thePreviewStrokeFollowsTheState() throws {
        for phase in [PanelPreviewPhase.ready(Self.still), .loading, .failed, .permissionMissing(.screenRecording)] {
            #expect(Self.armed(phase: phase).preview?.stroke == .selected, "\(phase)")
        }
        #expect(try Self.recording().preview?.stroke == .recording)
        #expect(Self.writing().preview?.stroke == .selected)
        var region = RenderSamples.idle.context
        region.snapshot.state = .armed
        region.snapshot.region = PixelRect(x: 0, y: 0, width: 200, height: 100)
        #expect(PanelModel.content(for: region, preview: .region).preview?.stroke == .hairline)
        #expect(PanelModel.content(for: region, preview: .region).clear == nil)
    }

    // MARK: - Hero and transitions

    @Test func stopRecordingCarriesItsTimerBesideTheLabel() throws {
        let hero = try #require(try Self.recording().hero)
        #expect(hero.title == "Stop Recording")
        #expect(hero.trailing == "0:12")
        #expect(PanelMetrics.heroTimerGap == 4)
    }

    @Test func onlyAHeightChangeInAnOpenPanelAnimates() {
        let picked = Self.armed()
        let compact = Self.noWindow()
        #expect(PanelMetrics.transitionSeconds == 0.2)
        #expect(PanelMetrics.animatesChange(from: picked, to: compact, panelOpen: true, reduceMotion: false))
        #expect(!PanelMetrics.animatesChange(from: picked, to: compact, panelOpen: true, reduceMotion: true))
        #expect(!PanelMetrics.animatesChange(from: picked, to: compact, panelOpen: false, reduceMotion: false))
        #expect(!PanelMetrics.animatesChange(from: picked, to: picked, panelOpen: true, reduceMotion: false))
    }

    @Test func blocksKeepTheirIdentityAcrossAStateChange() {
        let picked = Set(PanelMetrics.placedBlocks(for: Self.armed()).map(\.id))
        let compact = Set(PanelMetrics.placedBlocks(for: Self.noWindow()).map(\.id))
        #expect(picked.count == PanelMetrics.blocks(for: Self.armed()).count)
        #expect(picked.contains("preview#0") && !compact.contains("preview#0"))
        #expect(compact.contains("header#0") && !picked.contains("header#0"))
        #expect(picked.contains("hero#0") && compact.contains("hero#0"))
        #expect(picked.contains("toggle:Show Cursor#0") && compact.contains("toggle:Show Cursor#0"))
    }

    // MARK: - Letterbox

    @Test func letterboxFillsSixteenByTenAndBarsTheOthers() {
        let boxWidth = 268.0
        let boxHeight = 167.5
        let wide = Letterbox.fit(imageWidth: 16, imageHeight: 10, boxWidth: boxWidth, boxHeight: boxHeight)
        #expect(wide.x == 0)
        #expect(wide.y == 0)
        #expect(wide.width == boxWidth)
        #expect(wide.height == boxHeight)

        let cinema = Letterbox.fit(imageWidth: 21, imageHeight: 9, boxWidth: boxWidth, boxHeight: boxHeight)
        #expect(cinema.width == boxWidth)
        #expect(cinema.height < boxHeight)
        #expect(cinema.y > 0)
        #expect(cinema.x == 0)
        #expect(abs(cinema.width / cinema.height - 21.0 / 9.0) < 0.001)

        let portrait = Letterbox.fit(imageWidth: 9, imageHeight: 16, boxWidth: boxWidth, boxHeight: boxHeight)
        #expect(portrait.height == boxHeight)
        #expect(portrait.width < boxWidth)
        #expect(portrait.x > 0)
        #expect(portrait.y == 0)
        #expect(abs(portrait.width / portrait.height - 9.0 / 16.0) < 0.001)
    }

    @Test func captureSizeFitsTheWindowInsideThePreviewBox() {
        let box = PanelMetrics.capturePixels(scale: 2)
        #expect(box == PixelSize(width: 536, height: 335))
        let filled = PreviewCaptureSize.pixels(aspectWidth: 1600, aspectHeight: 1000, box: box)
        #expect(abs(filled.width - box.width) <= 1)
        #expect(abs(filled.height - box.height) <= 1)
        let cinema = PreviewCaptureSize.pixels(aspectWidth: 2100, aspectHeight: 900, box: box)
        #expect(cinema.width <= box.width)
        #expect(cinema.height < box.height)
        #expect(abs(cinema.width - box.width) <= 1)
        let portrait = PreviewCaptureSize.pixels(aspectWidth: 1080, aspectHeight: 1920, box: box)
        #expect(portrait.height <= box.height)
        #expect(portrait.width < box.width)
        #expect(abs(portrait.height - box.height) <= 1)
    }

    // MARK: - Size and last clip

    @Test func sizeCellShowsThePresetOrCustom() {
        #expect(PanelModel.sizeName(.size(SizePreset.p720.size)) == "720p")
        #expect(PanelModel.sizeName(.size(SizePreset.p1080.size)) == "1080p")
        #expect(PanelModel.sizeName(.size(SizePreset.uhd4k.size)) == "4K")
        #expect(PanelModel.sizeName(.size(PixelSize(width: 1720, height: 1080))) == UIStrings.Panel.custom)
        #expect(PanelModel.sizeName(.keepCurrent) == UIStrings.Panel.custom)
        let content = Self.armed()
        #expect(content.choices?.sizeValue == "1080p")
        #expect(content.caption?.detail.contains("px") == true)
    }

    @Test func lastClipMainAreaOpensTheClipAndTheIconsDoNot() throws {
        var context = RenderSamples.armed.context
        var body = try #require(context.snapshot.lastClip)
        body.recording.width = 1920
        body.recording.height = 1080
        body.recording.duration = 42
        context.snapshot.lastClip = body
        context.lastClipTitle = "Safari — localhost:3000"
        let clip = try #require(
            PanelModel.content(for: context, preview: .ready(Self.still)).lastClip)
        #expect(clip.title == UIStrings.Menu.lastClip)
        #expect(clip.detail == "0:42 · 1080p · 60 fps")
        #expect(clip.canOpen)
        #expect(clip.help == UIStrings.Panel.openClip)
        #expect(clip.accessibilityLabel == "Open last clip, Safari — localhost:3000, 42 seconds")
        #expect(clip.open == .openClip(path: body.files.clip))
        #expect(clip.actions.map(\.action).contains(.openClip(path: body.files.clip)) == false)
        #expect(clip.actions.map(\.title) == [
            UIStrings.Menu.showInFinder, UIStrings.Menu.copyFilePath, UIStrings.Menu.copySnippet,
        ])
    }

    @Test func aMissingClipIsNotClickableAndFinderIsDisabled() throws {
        let clip = try #require(Self.armed(fileExists: false).lastClip)
        #expect(!clip.canOpen)
        #expect(clip.dimmed)
        #expect(clip.detail == UIStrings.Panel.clipMissing)
        #expect(clip.accessibilityLabel == UIStrings.Panel.clipMissingLabel)
        #expect(clip.help == nil)
        #expect(clip.actions.count == 3)
        #expect(clip.actions.first?.enabled == false)
        #expect(clip.actions.dropFirst().allSatisfy { $0.enabled })
    }

    @Test func rowsUseTheSpecSymbols() throws {
        let content = Self.armed()
        #expect(content.rows.first { $0.action == .pickWindow }?.symbol == "viewfinder")
        #expect(content.footer.first { $0.action == .quit }?.symbol == "power")
        let clip = try #require(content.lastClip)
        #expect(clip.actions.first { $0.title == UIStrings.Menu.copyFilePath }?.symbol == "square.on.square")
        #expect(try Self.recording().footer.first { $0.action == .quit }?.symbol == "power")
    }

    @Test func copyAndSizeKeepThePanelOpen() {
        #expect(PanelModel.keepsPanelOpen(.copyFilePath(path: "a")))
        #expect(PanelModel.keepsPanelOpen(.copySnippet("a")))
        #expect(PanelModel.keepsPanelOpen(.chooseSize(.size(SizePreset.p1080.size))))
        #expect(PanelModel.keepsPanelOpen(.chooseFrameRate(.fps60)))
        #expect(PanelModel.keepsPanelOpen(.toggleCursor))
        #expect(!PanelModel.keepsPanelOpen(.openClip(path: "a")))
        #expect(!PanelModel.keepsPanelOpen(.record))
        #expect(!PanelModel.keepsPanelOpen(.stop))
        #expect(!PanelModel.keepsPanelOpen(.openSettings))
        #expect(!PanelModel.keepsPanelOpen(.showInFinder(path: "a")))
    }

    @Test func lastClipOpensThroughTheInjectedOpener() async throws {
        try await onMain("open clip") {
            let harness = MenuHarness()
            defer { harness.cleanUp() }
            let path = RenderSamples.clip().files.clip
            await harness.perform(.openClip(path: path))
            #expect(harness.effects.openedClips == [URL(fileURLWithPath: path)])
        }
    }

    // MARK: - Preview

    @Test func aFastStillDoesNotSpinAndRunsOffTheMainThread() async throws {
        try await onMain("fast still") {
            let fake = FakeWindowPreviewSource()
            let delay = ManualPreviewDelay()
            let model = WindowPreviewModel(source: fake, permissions: FakePermissionProbe(), delay: delay)
            fake.setResult(.success(Self.still))
            fake.holdNext()
            let window = try #require(RenderSamples.armed.context.snapshot.window)
            model.load(window: window, hasRegion: false, scale: 2)
            #expect(isLoading(model.phase))
            #expect(!model.showSpinner)
            let call = await fake.waitForCall()
            #expect(!call.onMainThread)
            #expect(call.fitting == PanelMetrics.capturePixels(scale: 2))
            #expect(fake.calls().count == 1)
            _ = await delay.waitUntilWaiting()
            let ready = Gate<Void>()
            model.onChange = {
                if case .ready = model.phase { ready.finish(()) }
            }
            fake.release()
            await ready.value()
            #expect(!model.showSpinner)
            delay.fire()
            try await waitForSpinnerTask()
            #expect(!model.showSpinner)
            #expect(fake.calls().count == 1)
            guard case .ready(let got) = model.phase else {
                Issue.record("Expected a still")
                return
            }
            #expect(got == Self.still)
        }
    }

    @Test func aSlowStillShowsTheSpinnerOnlyAfterTheDelay() async throws {
        try await onMain("slow still") {
            let fake = FakeWindowPreviewSource()
            let delay = ManualPreviewDelay()
            let model = WindowPreviewModel(source: fake, permissions: FakePermissionProbe(), delay: delay)
            fake.setResult(.success(Self.still))
            fake.holdNext()
            let window = try #require(RenderSamples.armed.context.snapshot.window)
            model.load(window: window, hasRegion: false, scale: 2)
            _ = await fake.waitForCall()
            _ = await delay.waitUntilWaiting()
            #expect(!model.showSpinner)
            let spinning = Gate<Void>()
            model.onChange = {
                if model.showSpinner { spinning.finish(()) }
            }
            delay.fire()
            await spinning.value()
            #expect(model.showSpinner)
            #expect(isLoading(model.phase))
            let ready = Gate<Void>()
            model.onChange = {
                if case .ready = model.phase { ready.finish(()) }
            }
            fake.release()
            await ready.value()
            #expect(!model.showSpinner)
            #expect(fake.calls().count == 1)
        }
    }

    @Test func aMissingPermissionDoesNotCapture() async throws {
        try await onMain("permission") {
            let fake = FakeWindowPreviewSource()
            let permissions = FakePermissionProbe(screenRecording: .missing)
            let model = WindowPreviewModel(source: fake, permissions: permissions, delay: ManualPreviewDelay())
            let window = try #require(RenderSamples.armed.context.snapshot.window)
            model.load(window: window, hasRegion: false, scale: 2)
            #expect(model.phase == .permissionMissing(.screenRecording))
            #expect(fake.calls().isEmpty)
            model.load(window: nil, hasRegion: false, scale: 2)
            #expect(model.phase == .permissionMissing(.screenRecording))
            #expect(fake.calls().isEmpty)
        }
    }

    @Test func reopeningCapturesAgainAndAClosedWindowKeepsTheLastStill() async throws {
        try await onMain("reopen") {
            let fake = FakeWindowPreviewSource()
            let model = WindowPreviewModel(source: fake, permissions: FakePermissionProbe(), delay: ManualPreviewDelay())
            fake.setResult(.success(Self.still))
            let window = try #require(RenderSamples.armed.context.snapshot.window)
            let first = Gate<Void>()
            model.onChange = {
                if case .ready = model.phase { first.finish(()) }
            }
            model.load(window: window, hasRegion: false, scale: 2)
            await first.value()
            fake.setResult(.failure(.windowClosed))
            let second = Gate<Void>()
            model.onChange = {
                if case .windowClosed = model.phase { second.finish(()) }
            }
            model.load(window: window, hasRegion: false, scale: 2)
            await second.value()
            #expect(fake.calls().count == 2)
            guard case .windowClosed(let kept) = model.phase else {
                Issue.record("Expected the closed window")
                return
            }
            #expect(kept == Self.still)
            #expect(model.lastTitle == "Safari — localhost:3000")
        }
    }

    // MARK: - Fixtures

    /// Armed at 1080p. By default with Check for Updates… and a last clip: the 647.5 pt panel.
    private static func armed(
        phase: PanelPreviewPhase = .ready(still), spinner: Bool = false, fileExists: Bool = true, clip: Bool = true,
        update: Bool = true
    ) -> PanelContent {
        var context = RenderSamples.armed.context
        context.checkForUpdates = update ? .enabled : .hidden
        context.sizeChoice = .size(SizePreset.p1080.size)
        if !clip { context.snapshot.lastClip = nil }
        return PanelModel.content(
            for: context, preview: phase, showSpinner: spinner, clipFileExists: fileExists)
    }

    private static func idle(clip: Bool, update: Bool) -> MenuContext {
        var context = RenderSamples.idle.context
        context.checkForUpdates = update ? .enabled : .hidden
        if clip {
            context.snapshot.lastClip = RenderSamples.clip()
            context.lastClipTitle = "Safari — localhost:3000"
        }
        return context
    }

    private static func noWindow(clip: Bool = true, update: Bool = true) -> PanelContent {
        PanelModel.content(for: idle(clip: clip, update: update), preview: .noWindow)
    }

    private static func windowClosed(clip: Bool = true, update: Bool = true) -> PanelContent {
        PanelModel.content(
            for: idle(clip: clip, update: update), preview: .windowClosed(nil),
            closedTitle: "Safari — localhost:3000")
    }

    private static func recording(update: Bool = true) throws -> PanelContent {
        var context = try #require(RenderSamples.states.first { $0.name == "recording" }).context
        context.checkForUpdates = update ? .enabled : .hidden
        return PanelModel.content(for: context, preview: .ready(still))
    }

    private static func writing() -> PanelContent {
        let context = RenderSamples.states.first { $0.name == "writing" }!.context
        return PanelModel.content(for: context, preview: .ready(still))
    }

    private func isLoading(_ phase: PanelPreviewPhase) -> Bool {
        if case .loading = phase { return true }
        return false
    }

    /// Lets the spinner task, which was already waiting, observe that the still won.
    private func waitForSpinnerTask() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            Task { @MainActor in continuation.resume() }
        }
    }
}

/// A preview delay the test fires. Nothing sleeps.
final class ManualPreviewDelay: PreviewDelay, @unchecked Sendable {
    private struct State {
        var continuation: CheckedContinuation<Void, Never>?
        var entered: CheckedContinuation<Int, Never>?
        var milliseconds: Int?
    }

    private let state = Mutex(State())

    func wait(milliseconds: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let entered = state.withLock { s -> CheckedContinuation<Int, Never>? in
                s.milliseconds = milliseconds
                s.continuation = continuation
                let entered = s.entered
                s.entered = nil
                return entered
            }
            entered?.resume(returning: milliseconds)
        }
    }

    func waitUntilWaiting() async -> Int {
        await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            let existing = state.withLock { s -> Int? in
                if s.continuation != nil { return s.milliseconds }
                s.entered = continuation
                return nil
            }
            if let existing { continuation.resume(returning: existing) }
        }
    }

    func fire() {
        let continuation = state.withLock { s -> CheckedContinuation<Void, Never>? in
            let continuation = s.continuation
            s.continuation = nil
            return continuation
        }
        continuation?.resume()
    }
}

/// Resumes once. `finish` may happen before or after `value`.
private final class Gate<T: Sendable>: @unchecked Sendable {
    private struct State {
        var continuation: CheckedContinuation<T, Never>?
        var value: T?
        var done = false
    }

    private let state = Mutex(State())

    func finish(_ value: T) {
        let continuation = state.withLock { s -> CheckedContinuation<T, Never>? in
            guard !s.done else { return nil }
            s.done = true
            s.value = value
            let continuation = s.continuation
            s.continuation = nil
            return continuation
        }
        continuation?.resume(returning: value)
    }

    func value() async -> T {
        await withCheckedContinuation { continuation in
            let existing = state.withLock { s -> T? in
                if s.done, let value = s.value { return value }
                s.continuation = continuation
                return nil
            }
            if let existing { continuation.resume(returning: existing) }
        }
    }
}
