import AppKit
import Foundation
@testable import SkreenrekUI
import SwiftUI
import Testing

/// Addendum 3: one neutral surface for the panel, the control bar, the HUDs and Settings.
@Suite struct SkreenrekSurfaceTests {
    @Test func theTokensAreTheAddendums() {
        let dark = SkreenrekSurface.dark
        let light = SkreenrekSurface.light
        #expect(dark.base == PanelTone(red: 0x1E, green: 0x1E, blue: 0x1E))
        #expect(light.base == PanelTone(red: 0xF5, green: 0xF5, blue: 0xF5))
        #expect(dark.cell == PanelTone(red: 0x2A, green: 0x2A, blue: 0x2A))
        #expect(light.cell == PanelTone(red: 0xFF, green: 0xFF, blue: 0xFF))
        #expect(dark.well == dark.cell)
        #expect(light.well == PanelTone(red: 0xEB, green: 0xEB, blue: 0xEB))
        #expect(dark.hairline(increaseContrast: false) == .white(0.10))
        #expect(light.hairline(increaseContrast: false) == .black(0.10))
        #expect(dark.hairline(increaseContrast: true) == .white(0.25))
        #expect(light.hairline(increaseContrast: true) == .black(0.25))
        #expect(dark.cellEdge == nil)
        #expect(light.cellEdge == .black(0.08))
        #expect(dark.separator == .white(0.08))
        #expect(light.separator == .black(0.08))
        #expect(SkreenrekSurface.separatorInset == 12)
        #expect(dark.hover == .white(0.08))
        #expect(dark.pressed == .white(0.12))
        #expect(light.hover == .black(0.05))
        #expect(light.pressed == .black(0.09))
        // No blue tint: every opaque tone is neutral.
        for tone in [dark.base, dark.cell, light.base, light.cell, light.well] {
            #expect(tone.red == tone.green && tone.green == tone.blue, "\(tone)")
        }
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func thePanelAndSettingsReadTheSameTones(scheme: ColorScheme) {
        let surface = SkreenrekSurface(scheme)
        let panel = PanelPalette(scheme)
        #expect(panel.fill == surface.base)
        #expect(panel.cellFill == surface.cell)
        #expect(panel.wellFill == surface.well)
        #expect(panel.separator == surface.separator)
        #expect(panel.cellHairline == surface.cellEdge)
        #expect(panel.rowFill(.hover) == surface.hover)
        #expect(panel.rowFill(.pressed) == surface.pressed)
        #expect(panel.rowFill(.rest) == nil)
    }

    @Test(arguments: [true, false])
    @MainActor
    func theSettingsWindowColourFollowsTheAppearance(dark: Bool) throws {
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = SkreenrekSurface.baseColor.usingColorSpace(.sRGB)
        }
        let color = try #require(resolved)
        let tone = SkreenrekSurface(isDark: dark).base
        #expect(Int((color.redComponent * 255).rounded()) == Int(tone.red), "\(color)")
        #expect(Int((color.greenComponent * 255).rounded()) == Int(tone.green), "\(color)")
        #expect(Int((color.blueComponent * 255).rounded()) == Int(tone.blue), "\(color)")
    }

    /// No colour literal in a view: the values live in `SkreenrekSurface.swift`. The V1 kit's embedded SVG and its
    /// parser are exempt.
    @Test func noHexColourLiteralsOutsideTheTokens() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SkreenrekUI")
        let exempt: Set<String> = ["SkreenrekSurface.swift", "BrandKit.swift", "BrandGlyphs.swift"]
        let pattern = try NSRegularExpression(pattern: "(0x|[#])[0-9A-Fa-f]{6}\\b")
        let files = try FileManager.default.contentsOfDirectory(atPath: sources.path)
            .filter { $0.hasSuffix(".swift") && !exempt.contains($0) }
        #expect(files.count > 10)
        for file in files {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            let hits = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
            #expect(hits.isEmpty, "\(file): \(hits)")
        }
    }
}
