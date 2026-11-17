import AppKit
import Foundation
import SkreenrekCore
import Testing

@testable import SkreenrekUI

/// The V1 logo kit embedded for direction C: the literals match the kit files in docs/brand/final-V1 byte for
/// byte, and the glyphs parse into the layers the kit's README describes.
@MainActor
@Suite struct BrandKitTests {
    static let kit = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/brand/final-V1")

    @Test func embeddedSVGsMatchTheKit() throws {
        #expect(BrandKit.svgFiles.count == 12)
        for (path, text) in BrandKit.svgFiles {
            let file = try String(contentsOf: Self.kit.appendingPathComponent(path), encoding: .utf8)
            #expect(text == file, "\(path)")
        }
    }

    @Test func embeddedPNGsMatchTheKit() throws {
        #expect(BrandKit.pngFiles.count == 5)
        for (path, base64) in BrandKit.pngFiles {
            let file = try Data(contentsOf: Self.kit.appendingPathComponent(path))
            #expect(Data(base64Encoded: base64) == file, "\(path)")
        }
    }

    @Test func monoGlyphsAreAllInk() {
        for state in BrandKit.MenuBarState.allCases {
            let drawing = KitSVG.parse(BrandKit.monoSVG(state))
            #expect(drawing.viewBox == CGRect(x: 0, y: 0, width: 24, height: 24))
            #expect(drawing.shapes.allSatisfy { $0.paint == .ink }, "\(state)")
            // Two stems and two arms, then the state's own part (dot, ring, arrow or "!").
            #expect(drawing.shapes.count >= 5, "\(state)")
        }
    }

    @Test func statesDifferInShape() {
        let center = CGPoint(x: 12, y: 12)
        #expect(
            KitSVG.parse(BrandKit.monoSVG(.idle)).shapes.last?.geometry == .ring(center: center, radius: 1.75, width: 2))
        #expect(KitSVG.parse(BrandKit.monoSVG(.recording)).shapes.last?.geometry == .disc(center: center, radius: 2.5))
        let geometries = BrandKit.MenuBarState.allCases.map { KitSVG.parse(BrandKit.monoSVG($0)).shapes.map(\.geometry) }
        #expect(Set(geometries.map { "\($0)" }).count == 5)
    }

    @Test func bichromeAccentIsOnlyTheRecordingDotAndTheErrorMark() {
        func accents(_ state: BrandKit.MenuBarState) -> Int {
            KitSVG.parse(BrandKit.bichromeSVG(state)).shapes.filter { $0.paint == .accent }.count
        }
        #expect(accents(.recording) == 1)
        #expect(accents(.error) == 2)
        #expect(accents(.idle) == 0)
        #expect(accents(.armed) == 0)
        #expect(accents(.saving) == 0)
    }

    @Test func layersAreTemplateAndAccent() throws {
        #expect(BrandStatusGlyph.templateLayer(.recording, style: .mono).isTemplate)
        #expect(BrandStatusGlyph.templateLayer(.recording, style: .bichrome).isTemplate)
        let accent = try #require(BrandStatusGlyph.accentLayer(.recording))
        #expect(!accent.isTemplate)
        #expect(BrandStatusGlyph.accentLayer(.error) != nil)
        #expect(BrandStatusGlyph.accentLayer(.idle) == nil)
        #expect(accent.size == NSSize(width: 18, height: 18))
    }

    @Test func controllerStatesMapToKitStates() {
        #expect(BrandStatusGlyph.state(for: .idle) == .idle)
        #expect(BrandStatusGlyph.state(for: .armed) == .armed)
        #expect(BrandStatusGlyph.state(for: .recording) == .recording)
        #expect(BrandStatusGlyph.state(for: .writing) == .saving)
        #expect(BrandStatusGlyph.state(for: .error) == .error)
    }

    @Test func iconMarkSkipsTheBody() {
        // icon-dark: four ink parts (stems and arms) and the gradient record dot. The body, sheen and edge parse as
        // `.other`, which the tile never draws (it asks for ink and the record gradient only).
        let shapes = KitSVG.parse(BrandKit.iconDarkSVG).shapes
        #expect(shapes.filter { $0.paint == .ink }.count == 4)
        #expect(shapes.filter { $0.paint == .recordGradient }.count == 1)
        #expect(shapes.filter { $0.paint != .other }.count == 5)
    }

    @Test func appIconCarriesEveryKitSize() {
        let icon = BrandIcon.appIcon(size: 56)
        #expect(icon.representations.map(\.pixelsWide).sorted() == [16, 32, 64, 128, 256])
    }
}
