import Foundation
import SkreenrekControl
import SkreenrekCore
import Testing

@testable import SkreenrekUI

/// The render-only spec 13 v2 previews: the command line, and the sample data the PNGs draw.
@Suite struct Size13PreviewTests {
    @Test func parsesSize13() {
        let out = URL(fileURLWithPath: "/tmp/x", isDirectory: true)
        #expect(RenderUIRequest.parse(["debug", "render-ui", "--direction", "size13", "--out", "/tmp/x"]) == .size13(out: out))
        #expect(RenderUIRequest.parse(["debug", "render-ui", "--out", "/tmp/x"]) == .shipping(out: out))
    }

    @Test func laptopSubmenuMatchesTheSpec() {
        let rows = Self.rows(Size13Samples.laptop)
        #expect(rows.map(\.title) == [
            "720p", "1080p", "1440p", "4K", "—", "Square", "Portrait", "—", "Current Size", "Custom…",
        ])
        #expect(rows.map(\.trailing) == [
            "1280 × 720", "1920 × 1080", "2560 × 1440", "3840 × 2160", nil, "1080 × 1080", "1080 × 1920", nil,
            "1280 × 800", nil,
        ])
        #expect(rows.filter(\.checked).map(\.title) == ["1080p"])
        #expect(rows.filter { !$0.enabled }.map(\.title) == ["4K", "Portrait"])
        #expect(Size13Samples.laptop.tooltipRow == "4K")
        #expect(
            Size13Samples.laptop.tooltip
                == "4K needs a display at least 1920 × 1080 points wide. Use a larger display or pick 1440p.")
    }

    @Test func largeSubmenuHasEverythingEnabled() {
        let rows = Self.rows(Size13Samples.large)
        #expect(rows.allSatisfy { $0.enabled })
        #expect(rows.filter(\.checked).map(\.title) == ["1080p"])
        #expect(Size13Samples.large.tooltip == nil)
    }

    @MainActor @Test func armedMenuShowsThePresetName() throws {
        let entries = Size13Samples.armedEntries()
        guard case .status(let row) = try #require(entries.first) else {
            Issue.record("The armed menu starts with its status row")
            return
        }
        #expect(row.title == "Safari — localhost:3000")
        #expect(row.detail == "1920 × 1080 px · 60 fps")
        let size = entries.compactMap { entry -> SubmenuModel? in
            if case .submenu(let submenu) = entry, submenu.title == "Size" { return submenu }
            return nil
        }
        #expect(size.map(\.detail) == ["1080p"])
        // Same row count as the shipping armed menu.
        #expect(entries.count == MenuModel.entries(for: RenderSamples.armed.context).count)
    }

    @Test func shippingSizeSubmenuIsUnchanged() {
        // The previews don't touch the live menu: it still offers Keep Current Size and Custom Size….
        let titles = MenuModel.sizeSubmenu(.keepCurrent).entries.compactMap { entry -> String? in
            if case .item(let item) = entry { return item.title }
            return nil
        }
        #expect(titles.first == "Keep Current Size")
        #expect(titles.last == "Custom Size…")
    }

    @MainActor @Test func fileNamesAreTheSpecNames() {
        #expect(Size13Renderer.fileNames() == [
            "size-submenu-laptop-light@2x.png", "size-submenu-large-light@2x.png", "custom-valid-light@2x.png",
            "custom-toolarge-light@2x.png", "dropdown-armed-1080p-light@2x.png",
            "size-submenu-laptop-dark@2x.png", "size-submenu-large-dark@2x.png", "custom-valid-dark@2x.png",
            "custom-toolarge-dark@2x.png", "dropdown-armed-1080p-dark@2x.png",
        ])
    }

    static func rows(_ submenu: Size13Submenu) -> [Size13Submenu.Row] {
        submenu.entries.map { entry in
            switch entry {
            case .row(let row): row
            case .separator: Size13Submenu.Row(title: "—")
            }
        }
    }
}
