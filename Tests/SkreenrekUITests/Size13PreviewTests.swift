import Foundation
import SkreenrekControl
import SkreenrekCore
import Testing

@testable import SkreenrekUI

/// Spec 13 v2's Size submenu, main menu row and the size13 render path, on the spec's sample displays.
@Suite struct SizeSubmenuTests {
    struct Row: Equatable {
        var title: String
        var trailing: String?
        var enabled = true
        var checked = false
        var toolTip: String?
    }

    static func rows(_ entries: [MenuEntry]) -> [Row] {
        entries.map { entry in
            switch entry {
            case .item(let item):
                Row(title: item.title, trailing: item.trailing, enabled: item.enabled, checked: item.checked,
                    toolTip: item.toolTip)
            default: Row(title: "—")
            }
        }
    }

    @Test func parsesSize13() {
        let out = URL(fileURLWithPath: "/tmp/x", isDirectory: true)
        #expect(
            RenderUIRequest.parse(["debug", "render-ui", "--direction", "size13", "--out", "/tmp/x"])
                == .size13(out: out))
        #expect(RenderUIRequest.parse(["debug", "render-ui", "--out", "/tmp/x"]) == .shipping(out: out))
    }

    @Test func laptopSubmenuMatchesTheSpec() {
        let rows = Self.rows(Size13Samples.submenu(on: Size13Samples.laptop))
        #expect(rows.map(\.title) == [
            "720p", "1080p", "1440p", "4K", "—", "Square", "Portrait", "—", "Current Size", "Custom…",
        ])
        #expect(rows.map(\.trailing) == [
            "1280 × 720", "1920 × 1080", "2560 × 1440", "3840 × 2160", nil, "1080 × 1080", "1080 × 1920", nil,
            "2560 × 1600", nil,
        ])
        #expect(rows.filter(\.checked).map(\.title) == ["1080p"])
        #expect(rows.filter { !$0.enabled }.map(\.title) == ["4K", "Portrait"])
        #expect(
            rows[3].toolTip == "4K needs room for a 1920 × 1080 pt window. Use a larger display or pick 1440p.")
        #expect(
            rows[6].toolTip
                == "Portrait needs room for a 540 × 960 pt window. Use a larger display or pick Square.")
    }

    @Test func largeOneXSubmenuHasEverythingEnabled() {
        let rows = Self.rows(Size13Samples.submenu(on: Size13Samples.large))
        #expect(rows.allSatisfy { $0.enabled })
        #expect(rows.allSatisfy { $0.toolTip == nil })
        #expect(rows.filter(\.checked).map(\.title) == ["1080p"])
        // A 1280 × 800 pt window on a 1× display.
        #expect(rows[8].trailing == "1280 × 800")
    }

    @Test func withoutAWindowCurrentSizeHasNoValue() {
        let rows = Self.rows(MenuModel.sizeSubmenu(.keepCurrent, display: Size13Samples.laptop).entries)
        #expect(rows[8] == Row(title: "Current Size", trailing: nil, checked: true))
    }

    @Test func mainMenuRowShowsThePresetNameOrTheCustomSize() {
        #expect(MenuModel.sizeSubmenu(.size(SizePreset.p1080.size)).detail == "1080p")
        #expect(MenuModel.sizeSubmenu(.size(PixelSize(width: 1720, height: 1080))).detail == "1720 × 1080")
        #expect(MenuModel.sizeSubmenu(.keepCurrent).detail == "Current Size")
        let custom = Self.rows(MenuModel.sizeSubmenu(.size(PixelSize(width: 1720, height: 1080))).entries)
        #expect(custom.filter(\.checked).map(\.title) == ["Custom…"])
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
        // Main menu row count unchanged.
        #expect(entries.count == MenuModel.entries(for: RenderSamples.armed.context).count)
    }

    @MainActor @Test func fileNamesAreTheSpecNames() {
        #expect(Size13Renderer.fileNames() == [
            "size-submenu-laptop-light@2x.png", "size-submenu-large-light@2x.png", "custom-valid-light@2x.png",
            "custom-toolarge-light@2x.png", "dropdown-armed-1080p-light@2x.png",
            "size-submenu-laptop-dark@2x.png", "size-submenu-large-dark@2x.png", "custom-valid-dark@2x.png",
            "custom-toolarge-dark@2x.png", "dropdown-armed-1080p-dark@2x.png",
        ])
    }
}
