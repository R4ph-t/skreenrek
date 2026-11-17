import AppKit
import SkreenrekCore
import SwiftUI

/// Renders `AppModel` into the menu-bar status item and its native `NSMenu`. No view logic lives here: it only turns
/// `StatusIcon` and `DropdownModel`'s rows into AppKit objects (the header and the Last Clip row as hosted SwiftUI
/// views, everything else as native items with a leading icon) and hands chosen actions back to the model.
@MainActor
public final class MenuController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let hotKey: StopHotKey
    private let thumbnails = ClipThumbnails()
    private var renderedRows: [DropdownRow] = []
    private var headerView: NSHostingView<DropdownHeaderView>?
    private var clipView: NSHostingView<ClipRowView>?
    private var accessibilityKey: String?
    private var iconKey: String?
    private var timer: Timer?

    public init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        hotKey = StopHotKey()
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.minimumWidth = MenuMetrics.width
        statusItem.menu = menu
        hotKey.onPress = { [weak model] in
            guard let model else { return }
            Task { await model.perform(.stop) }
        }
        thumbnails.onLoad = { [weak self] in self?.refreshClipRow() }
        model.onChange = { [weak self] in self?.render() }
        render()
    }

    // MARK: - Rendering

    public func showDropdown() { statusItem.button?.performClick(nil) }

    private func render() {
        let context = model.context
        renderIcon(model.icon, state: context.displayState)
        if model.menuOpen { renderMenu(DropdownModel.rows(for: context), context: context) }
        updateTimer()
        updateHotKey()
    }

    /// The V1 menu-bar glyph for the state: a template image (mono), or while recording the bichrome glyph with the
    /// red record dot, then the elapsed time.
    private func renderIcon(_ icon: StatusIcon, state: ControllerState) {
        guard let button = statusItem.button else { return }
        let kitState = BrandStatusGlyph.state(for: state)
        let key = "\(kitState.rawValue) \(icon.tinted)"
        if key != iconKey {
            iconKey = key
            button.image = BrandStatusGlyph.statusItemImage(kitState, accent: icon.tinted)
        }
        if let elapsed = icon.elapsed {
            button.imagePosition = .imageLeading
            button.attributedTitle = NSAttributedString(
                string: " " + elapsed, attributes: [.font: MenuMetrics.elapsedFont])
        } else {
            button.imagePosition = .imageOnly
            button.title = ""
        }
        // The tooltip and VoiceOver sentence change on state changes and every 10 s while recording, never every
        // second.
        if icon.accessibilityKey != accessibilityKey {
            accessibilityKey = icon.accessibilityKey
            button.toolTip = icon.sentence
            button.setAccessibilityLabel(icon.sentence)
        }
    }

    private func renderMenu(_ rows: [DropdownRow], context: MenuContext) {
        guard rows != renderedRows else { return }
        if DropdownModel.onlyHeaderDiffers(rows, renderedRows), let headerView {
            // Only the header changed (the elapsed time): update it in place so hover and focus stay.
            for case .header(let header) in rows { headerView.rootView = DropdownHeaderView(header: header) }
            renderedRows = rows
            return
        }
        menu.removeAllItems()
        headerView = nil
        clipView = nil
        for row in rows { menu.addItem(makeItem(row, context: context)) }
        renderedRows = rows
    }

    private func makeItem(_ row: DropdownRow, context: MenuContext) -> NSMenuItem {
        switch row {
        case .header(let header):
            let view = Self.hosted(DropdownHeaderView(header: header))
            headerView = view
            let item = NSMenuItem()
            item.view = view
            return item
        case .clip(let clip):
            let view = Self.hosted(ClipRowView(clip: clip, thumbnail: thumbnails.image(for: clip.path)))
            clipView = view
            let item = NSMenuItem()
            item.view = view
            return item
        case .separator:
            return .separator()
        case .sectionHeader(let title):
            return .sectionHeader(title: title)
        case .info(let text):
            // "Started by …": 11 pt tertiary, no icon, in the text column.
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.attributedTitle = NSAttributedString(
                string: text, attributes: [.font: MenuMetrics.infoFont, .foregroundColor: NSColor.tertiaryLabelColor])
            return item
        case .item(let model):
            let item = makeItem(model)
            item.image = Self.icon(DropdownModel.symbol(for: model.action), DropdownModel.iconTint(for: model, context: context))
            return item
        case .submenu(let submenu):
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            if let detail = submenu.detail { item.attributedTitle = Self.titleWithDetail(submenu.title, detail) }
            item.image = Self.icon(DropdownModel.symbol(forSubmenu: submenu.title), .neutral)
            let child = NSMenu(title: submenu.title)
            child.autoenablesItems = false
            for entry in submenu.entries { child.addItem(makeItem(entry)) }
            item.submenu = child
            return item
        }
    }

    /// A submenu entry (the Size and Frame Rate choices): plain items, no icons.
    private func makeItem(_ entry: MenuEntry) -> NSMenuItem {
        switch entry {
        case .separator: return .separator()
        case .header(let title): return .sectionHeader(title: title)
        case .item(let model): return makeItem(model)
        case .status(let row): return NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
        case .submenu(let submenu):
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            let child = NSMenu(title: submenu.title)
            for entry in submenu.entries { child.addItem(makeItem(entry)) }
            item.submenu = child
            return item
        }
    }

    /// The leading icon: a 13 pt template symbol that follows the menu's highlight, or red (Record Window, Stop
    /// Recording) or the accent (Pick Window… before a window is picked) for the primary item.
    static func icon(_ symbol: String?, _ tint: DropdownModel.IconTint) -> NSImage? {
        guard let symbol, let image = MenuMetrics.symbol(symbol, pointSize: MenuMetrics.iconPointSize, color: tint.nsColor)
        else { return nil }
        image.isTemplate = tint.nsColor == nil
        return image
    }

    static func hosted<V: View>(_ view: V) -> NSHostingView<V> {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        return hosting
    }

    /// The thumbnail finished loading: show it in the open menu's clip row.
    private func refreshClipRow() {
        guard let clipView else { return }
        let clip = clipView.rootView.clip
        clipView.rootView = ClipRowView(clip: clip, thumbnail: thumbnails.image(for: clip.path))
    }

    private func makeItem(_ model: MenuItemModel) -> NSMenuItem {
        let item = NSMenuItem(title: model.title, action: nil, keyEquivalent: "")
        if let action = model.action {
            item.target = self
            item.action = #selector(choose(_:))
            item.representedObject = ActionBox(action)
        }
        item.isEnabled = model.enabled
        item.state = model.checked ? .on : .off
        item.toolTip = model.toolTip
        if let trailing = model.trailing {
            item.attributedTitle = Self.titleWithTrailing(model.title, trailing, enabled: model.enabled)
        }
        if let shortcut = model.shortcut {
            item.keyEquivalent = shortcut.key
            item.keyEquivalentModifierMask = shortcut.control ? [.control, .command] : [.command]
        }
        return item
    }

    /// `Size` with `1280 × 800 px` right-aligned in the quiet colour, before the submenu arrow.
    static func titleWithDetail(_ title: String, _ detail: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: MenuMetrics.width - MenuMetrics.iconTextX - 40)]
        let text = NSMutableAttributedString(
            string: title, attributes: [.font: MenuMetrics.titleFont, .paragraphStyle: paragraph])
        text.append(
            NSAttributedString(
                string: "\t" + detail,
                attributes: [
                    .font: MenuMetrics.titleFont, .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: paragraph,
                ]))
        return text
    }

    /// A Size preset: `1080p` with `1920 × 1080` right-aligned in 12 pt secondary. Disabled rows dim both.
    static func titleWithTrailing(_ title: String, _ trailing: String, enabled: Bool) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: MenuMetrics.sizeSubmenuTrailingStop)]
        let text = NSMutableAttributedString(
            string: title,
            attributes: [
                .font: MenuMetrics.titleFont, .paragraphStyle: paragraph,
                .foregroundColor: enabled ? NSColor.labelColor : NSColor.tertiaryLabelColor,
            ])
        text.append(
            NSAttributedString(
                string: "\t" + trailing,
                attributes: [
                    .font: MenuMetrics.detailFont, .paragraphStyle: paragraph,
                    .foregroundColor: enabled ? NSColor.secondaryLabelColor : NSColor.quaternaryLabelColor,
                ]))
        return text
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? ActionBox else { return }
        let action = box.action
        Task { await model.perform(action) }
    }

    // MARK: - Elapsed timer and hot key

    private func updateTimer() {
        let recording = model.snapshot.state == .recording
        if recording, timer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Task { await self.model.tick() }
                }
            }
            // Common modes, so the time keeps moving while the menu is open.
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !recording, let timer {
            timer.invalidate()
            self.timer = nil
        }
    }

    private func updateHotKey() {
        if model.wantsStopHotKey { hotKey.register() } else { hotKey.unregister() }
    }

    // MARK: - NSMenuDelegate

    public func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        renderedRows = []
        let context = model.context
        renderMenu(DropdownModel.rows(for: context), context: context)
    }

    public func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        model.menuWillOpen()
    }

    public func menuDidClose(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        Task { await model.menuDidClose() }
    }
}

/// Carries a `MenuAction` through `NSMenuItem.representedObject`.
final class ActionBox: NSObject {
    let action: MenuAction

    init(_ action: MenuAction) {
        self.action = action
    }
}
