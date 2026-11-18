import AppKit
import SkreenrekCore
@testable import SkreenrekUI
import SwiftUI
import Testing

/// The solid panel (addendum of 2026-11-18): the token values, no material in the view tree, and one shadow.
@MainActor
@Suite struct PanelSurfaceTests {
    private let dark = PanelPalette(.dark)
    private let light = PanelPalette(.light)

    @Test func theSurfaceFillsAreOpaqueAndMatchTheAddendum() {
        #expect(dark.fill == PanelTone(red: 0x1E, green: 0x1E, blue: 0x20))
        #expect(light.fill == PanelTone(red: 0xF6, green: 0xF6, blue: 0xF8))
        #expect(dark.cellFill == PanelTone(red: 0x2C, green: 0x2C, blue: 0x2F))
        #expect(light.cellFill == PanelTone(red: 0xFF, green: 0xFF, blue: 0xFF))
        #expect(dark.wellFill == PanelTone(red: 0x2C, green: 0x2C, blue: 0x2F))
        #expect(light.wellFill == PanelTone(red: 0xE9, green: 0xE9, blue: 0xEE))
        for palette in [dark, light] {
            for tone in [palette.fill, palette.cellFill, palette.wellFill] {
                #expect(tone.opacity == 1, "\(tone)")
            }
        }
    }

    @Test func hairlinesAndSeparatorsMatchTheAddendum() {
        #expect(dark.hairline(increaseContrast: false) == .white(0.10))
        #expect(light.hairline(increaseContrast: false) == .black(0.10))
        #expect(dark.hairline(increaseContrast: true) == .white(0.25))
        #expect(light.hairline(increaseContrast: true) == .black(0.25))
        #expect(dark.separator == .white(0.10))
        #expect(light.separator == .black(0.08))
        #expect(dark.cellHairline == nil)
        #expect(light.cellHairline == .black(0.08))
        #expect(PanelSurface.pixel(displayScale: 2) == 0.5)
        #expect(PanelSurface.pixel(displayScale: 1) == 1)
        #expect(PanelSurface.pixel(displayScale: 0) == 1)
    }

    @Test func rowAndHeroInteractionsMatchTheAddendum() {
        #expect(dark.rowFill(.rest) == nil)
        #expect(light.rowFill(.rest) == nil)
        #expect(dark.rowFill(.hover) == .white(0.08))
        #expect(light.rowFill(.hover) == .black(0.05))
        #expect(dark.rowFill(.pressed) == .white(0.12))
        #expect(light.rowFill(.pressed) == .black(0.09))
        #expect(PanelSurface.heroDarkening(.rest) == 0)
        #expect(PanelSurface.heroDarkening(.hover) == 0.06)
        #expect(PanelSurface.heroDarkening(.pressed) == 0.12)
    }

    @Test func pressedWinsOverHoverAndDisabledStaysAtRest() {
        #expect(PanelInteraction(hovering: false, pressed: false) == .rest)
        #expect(PanelInteraction(hovering: true, pressed: false) == .hover)
        #expect(PanelInteraction(hovering: true, pressed: true) == .pressed)
        #expect(PanelInteraction(enabled: false, hovering: true, pressed: true) == .rest)
    }

    @Test func theRadiiAreTenAndSix() {
        #expect(PanelMetrics.radiusPanel == 10)
        #expect(PanelMetrics.radiusControl == 6)
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func thePanelHasNoVisualEffectView(_ appearance: NSAppearance.Name) throws {
        let content = PanelModel.content(for: RenderSamples.armed.context, preview: .noWindow)
        let view = UIRenderer.panel(content, preview: nil, clip: nil)
        view.appearance = NSAppearance(named: appearance)
        let window = NSWindow(
            contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        #expect(!view.subviews.isEmpty)
        #expect(Self.visualEffectViews(in: view) == 0)
        window.contentView = nil
    }

    @Test func theWindowIsClearAndCarriesTheOneShadow() {
        let panel = MenuKeyPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 323))
        panel.isReleasedWhenClosed = false
        #expect(!panel.isOpaque)
        #expect(panel.backgroundColor == .clear)
        #expect(panel.hasShadow)
    }

    @Test func aResizeRefreshesTheShadowAndAMoveDoesNot() {
        let panel = ShadowCountingPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 323))
        panel.isReleasedWhenClosed = false
        panel.invalidations = 0
        panel.setFrame(NSRect(x: 40, y: 40, width: 300, height: 323), display: false)
        #expect(panel.invalidations == 0)
        panel.setFrame(NSRect(x: 40, y: 40, width: 300, height: 530.5), display: false)
        #expect(panel.invalidations == 1)
    }

    private static func visualEffectViews(in view: NSView) -> Int {
        view.subviews.reduce(view is NSVisualEffectView ? 1 : 0) { $0 + visualEffectViews(in: $1) }
    }
}

private final class ShadowCountingPanel: MenuKeyPanel {
    var invalidations = 0

    override func invalidateShadow() {
        invalidations += 1
        super.invalidateShadow()
    }
}
