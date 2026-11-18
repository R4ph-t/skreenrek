import AppKit
import SkreenrekControl
import SkreenrekCore
import SkreenrekTesting
import SwiftUI
import Testing

@testable import SkreenrekUI

/// The panel's Size and Frame Rate popups, checked on the native menu items SwiftUI builds from them.
@MainActor
@Suite struct SizeMenuTests {
    private static let custom = PixelSize(width: 1000, height: 600)
    private static let presets = SizePresets.standard + SizePresets.shaped

    /// Every Size choice, with the title of the one row that should be checked.
    private static let sizeChoices: [(choice: SizeChoice, checked: String)] =
        [(.keepCurrent, UIStrings.Menu.currentSize), (.size(custom), UIStrings.Menu.customSize)]
        + presets.map { (.size($0.size), $0.title) }

    private static func items(_ submenu: SubmenuModel) -> [MenuItemModel] {
        submenu.entries.compactMap {
            if case .item(let item) = $0 { item } else { nil }
        }
    }

    private static func menu(_ submenu: SubmenuModel) -> NSMenu {
        NSHostingMenu(rootView: PanelPopupEntries(entries: submenu.entries, onAction: { _ in }))
    }

    private static func rows(_ menu: NSMenu) -> [NSMenuItem] { menu.items.filter { !$0.isSeparatorItem } }

    /// The native rows showing a check mark by either route: the item's state or an image in its label.
    private static func marked(_ menu: NSMenu) -> [NSMenuItem] {
        rows(menu).filter { $0.state == .on || $0.image != nil }
    }

    @Test func exactlyTheSelectedSizeIsChecked() {
        for (choice, checked) in Self.sizeChoices {
            let submenu = MenuModel.sizeSubmenu(choice)
            #expect(Self.items(submenu).filter(\.checked).map(\.title) == [checked])
            let marked = Self.marked(Self.menu(submenu))
            #expect(marked.count == 1)
            #expect(marked.first?.title.hasPrefix(checked) == true)
            #expect(marked.first?.state == .on)
            #expect(marked.first?.image == nil)
        }
    }

    @Test func exactlyTheSelectedFrameRateIsChecked() {
        for rate in FrameRate.allCases {
            let submenu = MenuModel.frameRateSubmenu(rate)
            #expect(Self.items(submenu).filter(\.checked).map(\.title) == [UIStrings.Menu.fps(rate)])
            let marked = Self.marked(Self.menu(submenu))
            #expect(marked.map(\.title) == [UIStrings.Menu.fps(rate)])
            #expect(marked.first?.state == .on)
        }
    }

    @Test func presetsKeepTheirDimensions() {
        let rows = Self.rows(Self.menu(MenuModel.sizeSubmenu(.keepCurrent)))
        #expect(rows.first?.title == "720p  1280 × 720")
        #expect(rows.last?.title == UIStrings.Menu.customSize)
    }

    @Test func aPresetThatDoesNotFitIsDisabledAndSaysWhy() throws {
        let small = DisplayInfo(
            id: 1, name: "Small", scale: 1, frame: PointRect(x: 0, y: 0, width: 1280, height: 800),
            visibleFrame: PointRect(x: 0, y: 0, width: 1280, height: 800))
        let submenu = MenuModel.sizeSubmenu(.keepCurrent, display: small)
        let blocked = try #require(Self.items(submenu).first { $0.toolTip != nil })
        let rows = Self.rows(Self.menu(submenu))
        let row = try #require(rows.first { $0.title.hasPrefix(blocked.title) })
        #expect(!row.isEnabled)
        #expect(row.toolTip == blocked.toolTip)
    }

    @Test func customSendsItsActionWhetherOrNotItIsChecked() throws {
        for choice in [SizeChoice.keepCurrent, .size(Self.custom)] {
            let item = try #require(Self.items(MenuModel.sizeSubmenu(choice)).last)
            var actions: [MenuAction] = []
            let selection = PanelPopupEntries.selection(item) { actions.append($0) }
            let checked = selection.wrappedValue
            #expect(checked == (choice != .keepCurrent))
            selection.wrappedValue = !checked
            #expect(actions == [.customSize])
            // The check follows the model, so a cancelled panel leaves it where it was.
            #expect(selection.wrappedValue == checked)
        }
    }

    @Test func aPresetSendsItsChoice() throws {
        let item = try #require(Self.items(MenuModel.sizeSubmenu(.keepCurrent)).first)
        var actions: [MenuAction] = []
        PanelPopupEntries.selection(item) { actions.append($0) }.wrappedValue = true
        #expect(actions == [.chooseSize(.size(SizePreset.p720.size))])
    }

    @Test func theCustomSizePanelSurvivesDeactivationAndTakesTheKeyboard() {
        let panel = KeyPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        #expect(!panel.hidesOnDeactivate)
        #expect(panel.canBecomeKey)
        #expect(panel.level == .floating)
    }

    @Test func customSizeClosesTheMenuPanelFirst() {
        #expect(!PanelModel.keepsPanelOpen(.customSize))
    }

    @Test func aCustomSizeIsAskedForAndApplied() async {
        let h = MenuHarness()
        defer { h.cleanUp() }
        await h.perform(.pickWindow)
        await h.perform(.chooseSize(.size(SizePreset.p1080.size)))
        h.effects.sizeAnswer = Self.custom
        await h.perform(.customSize)
        #expect(h.effects.sizeAsked.count == 1)
        #expect(h.effects.sizeAsked.first?.0 == SizePreset.p1080.size)
        #expect(h.model.settings.sizeChoice == .size(Self.custom))
    }

    @Test func cancellingCustomSizeKeepsTheCurrentChoice() async {
        let h = MenuHarness()
        defer { h.cleanUp() }
        await h.perform(.pickWindow)
        await h.perform(.chooseSize(.size(SizePreset.p1080.size)))
        let resizes = h.resizer.calls.count
        h.effects.sizeAnswer = nil
        await h.perform(.customSize)
        #expect(h.effects.sizeAsked.count == 1)
        #expect(h.model.settings.sizeChoice == .size(SizePreset.p1080.size))
        #expect(h.resizer.calls.count == resizes)
    }
}
