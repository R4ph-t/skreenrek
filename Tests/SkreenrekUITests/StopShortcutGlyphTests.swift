import AppKit
import CoreText
@testable import SkreenrekUI
import Testing

/// The Stop shortcut row: Control-Command-Escape as AppKit's menus spell it, drawn by the row's own font.
@Suite struct StopShortcutGlyphTests {
    @Test func usesTheStandardKeyboardSymbols() {
        let scalars = UIStrings.Settings.stopShortcutKeys.unicodeScalars.map(\.value)
        // ⌃ UP ARROWHEAD (Control), ⌘ PLACE OF INTEREST SIGN (Command), ⎋ BROKEN CIRCLE WITH NORTHWEST ARROW (Escape):
        // the same three code points AppKit's menu key-equivalent formatter returns for "\u{1b}" with
        // [.control, .command].
        #expect(scalars == [0x2303, 0x2318, 0x238B])
        #expect(UIStrings.Panel.stopHelp.hasSuffix("(\(UIStrings.Settings.stopShortcutKeys))"))
    }

    @Test func theRowFontDrawsEveryKeyItself() {
        // No fallback font substitution: the system font has its own glyph for each symbol, so the row draws ⎋ the
        // way menus (which use the same font) do.
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize) as CTFont
        for scalar in UIStrings.Settings.stopShortcutKeys.unicodeScalars {
            var units = Array(String(scalar).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            #expect(CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count), "U+\(String(scalar.value, radix: 16))")
            #expect(glyphs.allSatisfy { $0 != 0 })
        }
    }
}
