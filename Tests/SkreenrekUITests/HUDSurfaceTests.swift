import AppKit
import Foundation
import SkreenrekCore
@testable import SkreenrekUI
import SwiftUI
import Testing

/// Designer's follow-ups on the solid panel: the picker and recording HUDs share its surface, the icon buttons use the
/// row tones, and a disabled Record keeps its tertiary label. Pixels are read as raw bytes from the 2× render.
@MainActor
@Suite struct HUDSurfaceTests {
    typealias Appearance = UIRenderer.Appearance

    // MARK: No glass

    @Test(arguments: Appearance.allCases)
    func theHUDsHaveNoVisualEffectView(_ appearance: Appearance) {
        var views: [NSView] = [
            Self.fitted(PickerLabel(title: "Safari", detail: "1280 × 800 px")),
            Self.fitted(PickerHint()),
            Self.fitted(PickerSizeChip(text: "800 × 600 px")),
            Self.regionCanvas(),
        ]
        views += CaptureRenderSamples.hudStates.map { Self.hud($0.state) }
        for view in views {
            view.appearance = appearance.nsAppearance
            let window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            #expect(Self.visualEffectViews(in: view) == 0, "\(type(of: view))")
            window.contentView = nil
        }
    }

    // MARK: Surface

    @Test(arguments: Appearance.allCases)
    func theHUDsDrawTheAddendumFill(_ appearance: Appearance) throws {
        let fill = Self.bytes(Self.palette(appearance).fill)
        let samples: [(String, NSView, CGFloat)] = [
            ("label", Self.fitted(PickerLabel(title: "Safari", detail: "1280 × 800 px")), 8),
            ("hint", Self.fitted(PickerHint()), 8),
            ("chip", Self.fitted(PickerSizeChip(text: "800 × 600 px")), 2),
            ("recording", Self.hud(.recording(target: "Safari", seconds: 12)), 4),
            ("writing", Self.hud(.writing), 4),
        ]
        for (name, view, x) in samples {
            let rep = try Self.render(view, appearance)
            #expect(Self.pixel(rep, x: Int(x * 2), y: rep.pixelsHigh / 2) == fill + [255], "\(name)")
        }
    }

    @Test(arguments: Appearance.allCases, [false, true])
    func theRecordingHUDHairlineUsesTheToken(_ appearance: Appearance, increaseContrast: Bool) throws {
        let palette = Self.palette(appearance)
        let view = Self.hud(.recording(target: "Safari", seconds: 12), increaseContrast: increaseContrast)
        let rep = try Self.render(view, appearance)
        let expected = Self.blend(palette.hairline(increaseContrast: increaseContrast), over: palette.fill)
        let edge = Self.surfaceEdges(rep).left
        Self.expectClose(Self.pixel(rep, x: edge, y: rep.pixelsHigh / 2), expected, "\(appearance) \(increaseContrast)")
    }

    @Test(arguments: Appearance.allCases)
    func theStopButtonIsTheAddendumCell(_ appearance: Appearance) throws {
        let palette = Self.palette(appearance)
        let rep = try Self.render(Self.hud(.recording(target: "Safari", seconds: 12)), appearance)
        let middle = rep.pixelsHigh / 2
        // The HUD's padding is 12 pt, then the cell's 8 pt padding holds no glyph.
        let end = Self.surfaceEdges(rep).right + 1 - 24
        #expect(Self.pixel(rep, x: end - 6, y: middle) == Self.bytes(palette.cellFill) + [255])
        let edge = palette.cellHairline.map { Self.blend($0, over: palette.cellFill) } ?? Self.bytes(palette.cellFill)
        Self.expectClose(Self.pixel(rep, x: end - 1, y: middle), edge, "\(appearance)")
    }

    // MARK: Size chip

    @Test func theSizeChipPaddingTokensMatchTheDesign() {
        #expect(PickerSizeChip.horizontalPadding == 8)
        #expect(PickerSizeChip.verticalPadding == 4)
    }

    /// Digits of different shapes take the same width, so the chip doesn't jitter while the region is dragged.
    @Test func theSizeChipUsesMonospacedDigits() {
        let narrow = NSHostingView(rootView: PickerSizeChip(text: "111 × 111 px")).fittingSize
        let wide = NSHostingView(rootView: PickerSizeChip(text: "888 × 888 px")).fittingSize
        #expect(narrow.width == wide.width, "\(narrow.width) vs \(wide.width)")
    }

    /// The chip is exactly the 12 pt monospaced-digit text plus 8 pt a side and 4 pt top and bottom.
    @Test func theSizeChipFitsItsTextPlusThePadding() {
        let text = "800 × 600 px"
        let chip = NSHostingView(rootView: PickerSizeChip(text: text)).fittingSize
        let bare = NSHostingView(rootView: Self.chipText(text, background: .clear)).fittingSize
        #expect(chip.width == bare.width + 16, "\(chip.width) vs \(bare.width)")
        #expect(chip.height == bare.height + 8, "\(chip.height) vs \(bare.height)")
    }

    /// Compares where the glyphs land with the same text drawn alone, so the font's side bearings and line spacing
    /// cancel out. The surface is found from its opaque pixels, which leaves out the drawn shadow.
    @Test(arguments: Appearance.allCases)
    func theSizeChipInsetsItsTextOnEverySide(_ appearance: Appearance) throws {
        let text = "800 × 600 px"
        let fill = Self.palette(appearance).fill
        let chip = try Self.render(Self.fitted(PickerSizeChip(text: text)), appearance)
        let bare = try Self.render(Self.fitted(Self.chipText(text, background: fill.color)), appearance)

        let (left, right) = Self.surfaceEdges(chip)
        // Down a column inside the left padding, where no glyph can be.
        let opaque = (0..<chip.pixelsHigh).filter { Self.pixel(chip, x: left + 8, y: $0)[3] == 255 }
        let (top, bottom) = (try #require(opaque.first), try #require(opaque.last))
        // Past the hairline, and past the 4 pt corners along the top and bottom.
        let inked = try #require(Self.ink(chip, fill, x: (left + 8)...(right - 8), y: (top + 2)...(bottom - 2)))
        let alone = try #require(
            Self.ink(bare, fill, x: 0...(bare.pixelsWide - 1), y: 0...(bare.pixelsHigh - 1)))

        let insets = [
            ("left", inked.x.lowerBound - left - alone.x.lowerBound, 16),
            ("right", right - inked.x.upperBound - (bare.pixelsWide - 1 - alone.x.upperBound), 16),
            ("top", inked.y.lowerBound - top - alone.y.lowerBound, 8),
            ("bottom", bottom - inked.y.upperBound - (bare.pixelsHigh - 1 - alone.y.upperBound), 8),
        ]
        // 1 pt of slack: the fitted window rounds the text's fractional width up.
        for (side, actual, wanted) in insets {
            #expect(abs(actual - wanted) <= 2, "\(appearance) \(side): \(actual) px, wanted \(wanted)")
        }
    }

    // MARK: One shadow

    @Test func theShadowTokensMatchTheAddendum() {
        #expect(PanelPalette(.dark).dropShadow == PanelShadow(opacity: 0.35, blur: 24, y: 8))
        #expect(PanelPalette(.light).dropShadow == PanelShadow(opacity: 0.15, blur: 20, y: 6))
        #expect(PanelPalette(.dark).dropShadow.radius == 12)
        #expect(PanelPalette(.light).dropShadow.radius == 10)
    }

    @Test func theRecordingHUDWindowCarriesTheShadowAndThePickerPanelDoesNot() throws {
        let name = "skreenrek.hud-surface.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let hud = RecordingHUD(defaults: defaults)
        #expect(hud.panel.hasShadow)
        #expect(!hud.panel.isOpaque)
        #expect(hud.panel.backgroundColor == .clear)
        #expect(!CapturePanel(frame: .zero).hasShadow)
    }

    /// With the window server drawing the shadow, nothing may be drawn outside the rounded shape.
    @Test(arguments: Appearance.allCases)
    func theRecordingHUDDrawsNoShadowOfItsOwn(_ appearance: Appearance) throws {
        for sample in CaptureRenderSamples.hudStates {
            let rep = try Self.render(Self.hud(sample.state), appearance)
            let (left, right) = Self.surfaceEdges(rep)
            let bottom = rep.pixelsHigh - 1
            for (x, y) in [(left, 0), (right, 0), (left, bottom), (right, bottom)] {
                #expect(Self.pixel(rep, x: x, y: y)[3] == 0, "\(sample.name) corner \(x), \(y)")
            }
        }
    }

    /// The hint sits at y 540–584 of the canvas, whose window has no shadow, so the soft edge below it is SwiftUI's.
    @Test(arguments: Appearance.allCases)
    func thePickerHUDDrawsItsShadowInsideTheCanvas(_ appearance: Appearance) throws {
        let rep = try Self.render(Self.canvas { _ in }, appearance)
        #expect(Self.pixel(rep, x: 800, y: 1180)[3] > 8)
        #expect(Self.pixel(rep, x: 40, y: 40)[3] == 0)
    }

    @Test func aResizeRefreshesTheHUDShadowAndAMoveDoesNot() {
        let panel = ShadowCountingCapturePanel(frame: NSRect(x: 0, y: 0, width: 171, height: 36), carriesShadow: true)
        panel.invalidations = 0
        panel.setFrame(NSRect(x: 40, y: 40, width: 171, height: 36), display: false)
        #expect(panel.invalidations == 0)
        panel.setFrame(NSRect(x: 40, y: 40, width: 179, height: 36), display: false)
        #expect(panel.invalidations == 1)
    }

    @Test func aPanelWithoutAShadowNeverRefreshesIt() {
        let panel = ShadowCountingCapturePanel(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        panel.invalidations = 0
        panel.setFrame(NSRect(x: 0, y: 0, width: 900, height: 600), display: false)
        panel.refreshShadow()
        #expect(panel.invalidations == 0)
    }

    /// The material used to be what the pointer hit, so the HUD must still drag by its background without it.
    @Test func theRecordingHUDStillDragsByItsBackground() throws {
        let view = Self.hud(.recording(target: "Safari", seconds: 12))
        let panel = CapturePanel(frame: view.bounds, carriesShadow: true)
        panel.contentView = view
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let hit = try #require(view.hitTest(NSPoint(x: 4, y: 18)))
        #expect(hit.mouseDownCanMoveWindow)
        panel.contentView = nil
    }

    // MARK: Icon buttons

    @Test(arguments: Appearance.allCases, [PanelInteraction.hover, .pressed])
    func clearUsesTheRowToneAtTheControlRadius(_ appearance: Appearance, state: PanelInteraction) throws {
        let content = Self.pickedContent
        let rep = try Self.render(
            UIRenderer.panel(content, preview: nil, clip: nil, clearState: state), appearance)
        let top = Self.top(of: content) { if case .caption = $0 { true } else { false } }
        let origin = (x: PanelMetrics.clearHitX, y: top + (PanelMetrics.titleLineHeight - PanelMetrics.iconButton) / 2)
        try Self.expectIconTile(rep, origin: origin, appearance: appearance, state: state)
    }

    @Test(arguments: Appearance.allCases, [PanelInteraction.hover, .pressed])
    func lastClipUsesTheRowToneOnlyOnTheForcedButton(_ appearance: Appearance, state: PanelInteraction) throws {
        let content = Self.pickedContent
        let rep = try Self.render(
            UIRenderer.panel(content, preview: nil, clip: nil, lastClipState: state), appearance)
        let top = Self.top(of: content) { if case .clip = $0 { true } else { false } }
        let y = top + (PanelMetrics.clipRowHeight - PanelMetrics.iconButton) / 2
        // Three 24 pt buttons ending at x 288.
        let x = PanelMetrics.contentEndX + PanelMetrics.iconButtonOverhang - 3 * PanelMetrics.iconButton
        try Self.expectIconTile(rep, origin: (x, y), appearance: appearance, state: state)
        let next = Self.pixel(rep, x: Int((x + PanelMetrics.iconButton + 1.5) * 2), y: Int((y + 12) * 2))
        #expect(Array(next.prefix(3)) == Self.bytes(Self.palette(appearance).fill))
    }

    @Test(arguments: Appearance.allCases)
    func iconButtonsAreFlatAtRest(_ appearance: Appearance) throws {
        let content = Self.pickedContent
        let rep = try Self.render(UIRenderer.panel(content, preview: nil, clip: nil), appearance)
        let top = Self.top(of: content) { if case .caption = $0 { true } else { false } }
        let x = Int((PanelMetrics.clearHitX + 1.5) * 2)
        let y = Int((top + (PanelMetrics.titleLineHeight - PanelMetrics.iconButton) / 2 + 12) * 2)
        #expect(Array(Self.pixel(rep, x: x, y: y).prefix(3)) == Self.bytes(Self.palette(appearance).fill))
    }

    // MARK: Disabled Record

    @Test func aDisabledHeroLabelIsTertiary() {
        #expect(PanelSurface.heroForeground(enabled: false) == Color(nsColor: .tertiaryLabelColor))
        #expect(PanelSurface.heroForeground(enabled: true) == .white)
    }

    /// The strongest pixel in the button is a fully covered part of the label or mark.
    @Test(arguments: Appearance.allCases)
    func aDisabledRecordDrawsItsLabelInTertiary(_ appearance: Appearance) throws {
        let content = PanelModel.content(
            for: RenderSamples.armed.context, preview: .permissionMissing(.screenRecording))
        let hero = try #require(content.hero)
        #expect(hero.role == .record && !hero.enabled)
        let rep = try Self.render(UIRenderer.panel(content, preview: nil, clip: nil), appearance)
        let well = Self.bytes(Self.palette(appearance).wellFill)
        let top = Self.top(of: content) { if case .hero = $0 { true } else { false } }

        var strongest = well
        var distance = 0
        for y in Int((top + 4) * 2)..<Int((top + PanelMetrics.heroHeight - 4) * 2) {
            for x in Int((PanelMetrics.margin + 8) * 2)..<Int((PanelMetrics.contentEndX - 8) * 2) {
                let pixel = Array(Self.pixel(rep, x: x, y: y).prefix(3))
                let difference = zip(pixel, well).map { abs($0 - $1) }.reduce(0, +)
                if difference > distance { (strongest, distance) = (pixel, difference) }
            }
        }

        var tertiary: NSColor?
        appearance.nsAppearance.performAsCurrentDrawingAppearance {
            tertiary = NSColor.tertiaryLabelColor.usingColorSpace(.sRGB)
        }
        let color = try #require(tertiary)
        let alpha = color.alphaComponent
        let parts: [CGFloat] = [color.redComponent, color.greenComponent, color.blueComponent]
        var expected: [Int] = []
        for (base, part) in zip(well, parts) {
            let value: CGFloat = CGFloat(base) * (1 - alpha) + part * 255 * alpha
            expected.append(Int(value.rounded()))
        }
        Self.expectClose(strongest, expected, "\(appearance)", tolerance: 4)
    }

    // MARK: Helpers

    private static var pickedContent: PanelContent {
        PanelModel.content(
            for: RenderSamples.armed.context,
            preview: .ready(WindowStill(png: Data(), pixelWidth: 320, pixelHeight: 180)))
    }

    private static func palette(_ appearance: Appearance) -> PanelPalette {
        PanelPalette(appearance == .dark ? .dark : .light)
    }

    private static func fitted<V: View>(_ view: V) -> NSView {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        return hosting
    }

    private static func hud(_ state: HUDState, increaseContrast: Bool = false) -> NSView {
        fitted(RecordingHUDView(presentation: HUDPresentation(state: state, increaseContrast: increaseContrast)))
    }

    private static func canvas(_ change: (inout PickerModel) -> Void) -> PickerCanvas {
        let canvas = PickerCanvas(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        canvas.increaseContrast = false
        var display = RenderSamples.display
        display.visibleFrame = PointRect(x: 0, y: 0, width: 800, height: 600)
        canvas.display = display
        var model = PickerModel(windows: [RenderSamples.safari], displays: [display], ownPid: -1)
        change(&model)
        canvas.update(model, pointer: CGPoint(x: 500, y: 400))
        return canvas
    }

    /// A hovered window and a dragged region, so the label, the hint and the size chip are all present.
    private static func regionCanvas() -> PickerCanvas {
        canvas { model in
            model.hover(CGPoint(x: 200, y: 200))
            model.beginDrag(CGPoint(x: 100, y: 100))
            model.drag(to: CGPoint(x: 500, y: 400))
        }
    }

    private static func render(_ view: NSView, _ appearance: Appearance) throws -> NSBitmapImageRep {
        try #require(NSBitmapImageRep(data: try UIRenderer.png(view, appearance: appearance, active: true)))
    }

    private static func pixel(_ rep: NSBitmapImageRep, x: Int, y: Int) -> [Int] {
        var value = [Int](repeating: 0, count: 4)
        rep.getPixel(&value, atX: x, y: y)
        return value
    }

    /// The first and last opaque pixels across the middle: the HUD can sit up to 1 pt inside its fitted window.
    private static func surfaceEdges(_ rep: NSBitmapImageRep) -> (left: Int, right: Int) {
        let opaque = (0..<rep.pixelsWide).filter { pixel(rep, x: $0, y: rep.pixelsHigh / 2)[3] == 255 }
        return (opaque.first ?? 0, opaque.last ?? 0)
    }

    /// The chip's text as the design specifies it, with no padding or surface.
    private static func chipText(_ text: String, background: Color) -> some View {
        Text(text).font(.system(size: 12)).monospacedDigit()
            .foregroundStyle(PanelSurface.primaryText)
            .background(background)
    }

    /// The bounds of the opaque pixels clearly different from `fill`: the glyphs.
    private static func ink(
        _ rep: NSBitmapImageRep, _ fill: PanelTone, x xs: ClosedRange<Int>, y ys: ClosedRange<Int>
    ) -> (x: ClosedRange<Int>, y: ClosedRange<Int>)? {
        let base = bytes(fill)
        var found: (minX: Int, maxX: Int, minY: Int, maxY: Int)?
        for y in ys {
            for x in xs {
                let value = pixel(rep, x: x, y: y)
                guard value[3] == 255, zip(value, base).map({ abs($0 - $1) }).reduce(0, +) > 240 else { continue }
                found = (
                    min(found?.minX ?? x, x), max(found?.maxX ?? x, x),
                    min(found?.minY ?? y, y), max(found?.maxY ?? y, y)
                )
            }
        }
        return found.map { (x: $0.minX...$0.maxX, y: $0.minY...$0.maxY) }
    }

    private static func bytes(_ tone: PanelTone) -> [Int] {
        [Int(tone.red), Int(tone.green), Int(tone.blue)]
    }

    private static func blend(_ tone: PanelTone, over base: PanelTone) -> [Int] {
        var blended: [Int] = []
        for (top, bottom) in zip(bytes(tone), bytes(base)) {
            let value: Double = Double(top) * tone.opacity + Double(bottom) * (1 - tone.opacity)
            blended.append(Int(value.rounded()))
        }
        return blended
    }

    private static func expectClose(
        _ pixel: [Int], _ expected: [Int], _ label: String, tolerance: Int = 2,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        for (actual, wanted) in zip(pixel, expected) {
            #expect(abs(actual - wanted) <= tolerance, "\(label): \(pixel) vs \(expected)", sourceLocation: sourceLocation)
        }
    }

    /// The tile fills the 24 pt square's edge and interior, and its corner is cut by the 6 pt radius.
    private static func expectIconTile(
        _ rep: NSBitmapImageRep, origin: (x: CGFloat, y: CGFloat), appearance: Appearance, state: PanelInteraction,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let palette = palette(appearance)
        let tone = try #require(palette.rowFill(state), sourceLocation: sourceLocation)
        let tile = blend(tone, over: palette.fill)
        let (x, y) = (Int(origin.x * 2), Int(origin.y * 2))
        let label = "\(appearance) \(state)"
        expectClose(pixel(rep, x: x + 3, y: y + 24), tile, label, sourceLocation: sourceLocation)
        expectClose(pixel(rep, x: x + 6, y: y + 6), tile, label, sourceLocation: sourceLocation)
        expectClose(pixel(rep, x: x + 2, y: y + 2), bytes(palette.fill), label, tolerance: 3, sourceLocation: sourceLocation)
    }

    private static func top(of content: PanelContent, where matches: (PanelBlock) -> Bool) -> CGFloat {
        var y: CGFloat = 0
        for block in PanelMetrics.blocks(for: content) {
            if matches(block) { return y }
            y += PanelMetrics.height(of: block)
        }
        Issue.record("The block is not in this panel")
        return 0
    }

    private static func visualEffectViews(in view: NSView) -> Int {
        view.subviews.reduce(view is NSVisualEffectView ? 1 : 0) { $0 + visualEffectViews(in: $1) }
    }
}

private final class ShadowCountingCapturePanel: CapturePanel {
    var invalidations = 0

    override func invalidateShadow() {
        invalidations += 1
        super.invalidateShadow()
    }
}
