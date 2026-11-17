import AppKit
import SkreenrekCore

/// Renders `AppModel` into the menu-bar status item and its native `NSMenu`. No view logic lives here: it only turns
/// `StatusIcon` and `[MenuEntry]` into AppKit objects and hands chosen actions back to the model.
@MainActor
public final class MenuController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let hotKey: StopHotKey
    private var renderedEntries: [MenuEntry] = []
    private var statusViews: [Int: StatusRowView] = [:]
    private var accessibilityKey: String?
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
        model.onChange = { [weak self] in self?.render() }
        render()
    }

    // MARK: - Rendering

    private func render() {
        renderIcon(model.icon)
        if model.menuOpen { renderMenu(model.entries) }
        updateTimer()
        updateHotKey()
    }

    private func renderIcon(_ icon: StatusIcon) {
        guard let button = statusItem.button else { return }
        let image = MenuMetrics.symbol(icon.symbol, color: icon.tinted ? .systemRed : nil)
        image?.isTemplate = !icon.tinted
        button.image = image
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

    private func renderMenu(_ entries: [MenuEntry]) {
        guard entries != renderedEntries else { return }
        if Self.onlyStatusRowsDiffer(entries, renderedEntries) {
            // Only status text changed (the elapsed time): update those rows in place so hover and focus stay.
            for (index, entry) in entries.enumerated() {
                if case .status(let row) = entry { statusViews[index]?.update(row) }
            }
            renderedEntries = entries
            return
        }
        menu.removeAllItems()
        statusViews = [:]
        for (index, entry) in entries.enumerated() {
            let item = makeItem(entry)
            if case .status = entry, let view = item.view as? StatusRowView { statusViews[index] = view }
            menu.addItem(item)
        }
        renderedEntries = entries
    }

    private func makeItem(_ entry: MenuEntry) -> NSMenuItem {
        switch entry {
        case .status(let row):
            let item = NSMenuItem()
            item.view = StatusRowView(row)
            return item
        case .separator:
            return .separator()
        case .header(let title):
            return .sectionHeader(title: title)
        case .item(let model):
            return makeItem(model)
        case .submenu(let submenu):
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            if let detail = submenu.detail { item.attributedTitle = Self.titleWithDetail(submenu.title, detail) }
            let child = NSMenu(title: submenu.title)
            child.autoenablesItems = false
            for entry in submenu.entries { child.addItem(makeItem(entry)) }
            item.submenu = child
            return item
        }
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
        if let shortcut = model.shortcut {
            item.keyEquivalent = shortcut.key
            item.keyEquivalentModifierMask = shortcut.control ? [.control, .command] : [.command]
        }
        return item
    }

    /// `Size` with `1280 × 800 px` right-aligned in the quiet colour, before the submenu arrow.
    static func titleWithDetail(_ title: String, _ detail: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: MenuMetrics.width - MenuMetrics.textX - 40)]
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

    static func onlyStatusRowsDiffer(_ a: [MenuEntry], _ b: [MenuEntry]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { ($0.isStatus && $1.isStatus) || $0 == $1 }
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
        renderedEntries = []
        renderMenu(model.entries)
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

extension MenuEntry {
    var isStatus: Bool {
        if case .status = self { return true }
        return false
    }
}
