import AppKit
import SkreenrekControl
import SkreenrekCore
import SwiftUI

// Render-only mockups of Designer's spec 13 v2 (picking a size). `skreenrek debug render-ui --direction size13`
// draws them; the app, `MenuModel`, the live Size submenu and the Custom Size panel don't use anything here. The
// enabled/disabled states are the spec's worked examples, written down as sample data, not computed.

/// Spec 13 v2 copy, verbatim.
enum Size13Strings {
    static let size = "Size"
    static let currentSize = "Current Size"
    static let custom = "Custom…"
    static let fourKTooltip =
        "4K needs a display at least 1920 × 1080 points wide. Use a larger display or pick 1440p."
    static let customTitle = "Custom Size"
    static let width = "Width"
    static let height = "Height"
    static let px = "px"
    static let times = "×"
    static let cancel = "Cancel"
    static let setSize = "Set Size"
    static let tooLarge = "Too large for this display."

    /// `Window on screen: 1440 × 810`.
    static func windowOnScreen(width: Int, height: Int) -> String { "Window on screen: \(width) × \(height)" }

    /// `1920 × 1080` (no unit: the submenu's trailing values).
    static func dimensions(_ size: PixelSize) -> String { "\(size.width) × \(size.height)" }
}

/// The spec's Size submenu as sample data for one display.
struct Size13Submenu: Sendable, Hashable {
    struct Row: Sendable, Hashable {
        var title: String
        var trailing: String?
        var enabled = true
        var checked = false
    }

    enum Entry: Sendable, Hashable {
        case row(Row)
        case separator
    }

    var entries: [Entry]
    /// The disabled row whose tooltip is showing, if any.
    var tooltipRow: String?
    var tooltip: String?

    struct Preset: Sendable, Hashable {
        var title: String
        var size: PixelSize
    }

    static let standard: [Preset] = [
        Preset(title: "720p", size: PixelSize(width: 1280, height: 720)),
        Preset(title: "1080p", size: PixelSize(width: 1920, height: 1080)),
        Preset(title: "1440p", size: PixelSize(width: 2560, height: 1440)),
        Preset(title: "4K", size: PixelSize(width: 3840, height: 2160)),
    ]
    static let shaped: [Preset] = [
        Preset(title: "Square", size: PixelSize(width: 1080, height: 1080)),
        Preset(title: "Portrait", size: PixelSize(width: 1080, height: 1920)),
    ]

    /// The submenu with `checked` ticked, `disabled` greyed out, and Current Size showing `current`.
    static func make(checked: String, disabled: Set<String>, current: PixelSize, tooltipRow: String? = nil,
                     tooltip: String? = nil) -> Size13Submenu {
        func rows(_ presets: [Preset]) -> [Entry] {
            presets.map {
                .row(Row(title: $0.title, trailing: Size13Strings.dimensions($0.size),
                         enabled: !disabled.contains($0.title), checked: $0.title == checked))
            }
        }
        let entries: [Entry] = rows(standard) + [.separator] + rows(shaped) + [.separator]
            + [.row(Row(title: Size13Strings.currentSize, trailing: Size13Strings.dimensions(current))),
               .row(Row(title: Size13Strings.custom))]
        return Size13Submenu(entries: entries, tooltipRow: tooltipRow, tooltip: tooltip)
    }
}

/// The spec 13 sample states: Retina MacBook Pro 14" (usable ~1448 × 870 pt) and a large display.
enum Size13Samples {
    /// The sample Safari window's current clip: 640 × 400 pt at 2×.
    static let currentClip = PixelSize(width: 1280, height: 800)

    /// 4K needs a 1920 × 1080 pt window and Portrait ~960 pt tall: neither fits ~1448 × 870 pt.
    static let laptop = Size13Submenu.make(
        checked: "1080p", disabled: ["4K", "Portrait"], current: currentClip, tooltipRow: "4K",
        tooltip: Size13Strings.fourKTooltip)
    static let large = Size13Submenu.make(checked: "1080p", disabled: [], current: currentClip)

    static let preset1080p = PixelSize(width: 1920, height: 1080)

    /// The main menu armed with 1080p: Size row trailing `1080p`, status line 2 `1920 × 1080 px · 60 fps`.
    static func armedEntries() -> [MenuEntry] {
        let context = RenderSamples.context(
            ControllerSnapshot(
                state: .armed, window: RenderSamples.safari, displayId: 1, size: preset1080p,
                readback: Readback(
                    window: Readback.Window(RenderSamples.safari), display: Readback.Display(RenderSamples.display),
                    requested: preset1080p, actual: preset1080p,
                    frame: PointRect(x: 120, y: 80, width: 1440, height: 810), exact: true, attempts: 1),
                fps: .fps60, lastClip: RenderSamples.clip()),
            title: RenderSamples.clipTitle)
        return MenuModel.entries(for: context).map { entry in
            switch entry {
            case .status(var row) where row.symbol == StatusIconModel.Symbol.armed:
                row.detail = [preset1080p.description, UIStrings.Menu.fps(context.snapshot.fps)]
                    .joined(separator: UIStrings.Menu.separator)
                return .status(row)
            case .submenu(var submenu) where submenu.title == UIStrings.Menu.size:
                submenu.title = Size13Strings.size
                submenu.detail = "1080p"
                return .submenu(submenu)
            default:
                return entry
            }
        }
    }
}

// MARK: - Rendering

@MainActor
enum Size13Renderer {
    /// Every file the size13 previews write, in order.
    static func fileNames() -> [String] {
        UIRenderer.Appearance.allCases.flatMap { appearance in
            names.map { "\($0)-\(appearance.rawValue)@2x.png" }
        }
    }

    static let names = [
        "size-submenu-laptop", "size-submenu-large", "custom-valid", "custom-toolarge", "dropdown-armed-1080p",
    ]

    static func render(to folder: URL) throws -> [UIRenderer.Rendered] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var written: [UIRenderer.Rendered] = []
        for appearance in UIRenderer.Appearance.allCases {
            func save(_ view: NSView, _ name: String) throws {
                let url = folder.appendingPathComponent("\(name)-\(appearance.rawValue)@2x.png")
                written.append(try UIRenderer.write(view, appearance: appearance, to: url))
            }
            try save(Size13SubmenuPreview(Size13Samples.laptop), "size-submenu-laptop")
            try save(Size13SubmenuPreview(Size13Samples.large), "size-submenu-large")
            try save(customSheet(.valid), "custom-valid")
            try save(customSheet(.tooLarge), "custom-toolarge")
            try save(DropdownPreview(Size13Samples.armedEntries()), "dropdown-armed-1080p")
        }
        return written
    }

    static func customSheet(_ state: Size13CustomSheet.State) -> NSView {
        let hosting = NSHostingView(rootView: Size13CustomSheet(state: state))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        return hosting
    }
}

/// The Size submenu on the menu material, with the disabled row's tooltip below it when one is showing. The
/// canvas around the menu is transparent.
final class Size13SubmenuPreview: NSView {
    static let menuWidth: CGFloat = 240
    static let tooltipMaxWidth: CGFloat = 300
    static let tooltipFont = NSFont.toolTipsFont(ofSize: 11)
    static let tooltipPadding = NSSize(width: 8, height: 4)
    /// Where the tooltip starts: under the pointer resting at the row's trailing end, just past the menu's text,
    /// so it hides no other row.
    static let tooltipX: CGFloat = menuWidth - 6

    init(_ submenu: Size13Submenu) {
        let rows = submenu.entries.map(Self.view)
        let menuHeight = rows.reduce(MenuMetrics.verticalInset * 2) { $0 + $1.frame.height }
        let menu = Size13MenuBackground(frame: NSRect(x: 0, y: 0, width: Self.menuWidth, height: menuHeight))
        var y = MenuMetrics.verticalInset
        var anchor: CGFloat?
        for (entry, row) in zip(submenu.entries, rows) {
            row.frame.origin = NSPoint(x: 0, y: y)
            menu.addSubview(row)
            if case .row(let model) = entry, model.title == submenu.tooltipRow { anchor = y + row.frame.height }
            y += row.frame.height
        }
        var size = NSSize(width: Self.menuWidth, height: menuHeight)
        var tooltipRect: NSRect?
        if let text = submenu.tooltip, let anchor {
            let bounds = (text as NSString).boundingRect(
                with: NSSize(width: Self.tooltipMaxWidth - Self.tooltipPadding.width * 2, height: 1000),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: Self.tooltipFont])
            let rect = NSRect(
                x: Self.tooltipX, y: anchor + 2, width: ceil(bounds.width) + Self.tooltipPadding.width * 2,
                height: ceil(bounds.height) + Self.tooltipPadding.height * 2)
            tooltipRect = rect
            size.width = max(size.width, rect.maxX + 1)
            size.height = max(size.height, rect.maxY + 1)
        }
        super.init(frame: NSRect(origin: .zero, size: size))
        addSubview(menu)
        // Added last, so the tooltip sits over the menu.
        if let tooltipRect, let tooltip = submenu.tooltip { addSubview(Size13TooltipView(frame: tooltipRect, text: tooltip)) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    static func view(_ entry: Size13Submenu.Entry) -> NSView {
        switch entry {
        case .separator:
            let separator = SeparatorPreview()
            separator.frame.size.width = menuWidth
            return separator
        case .row(let row): return Size13RowView(row, width: menuWidth)
        }
    }
}

/// The menu material with the dropdown's radius and hairline.
final class Size13MenuBackground: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: MenuMetrics.cornerRadius,
            yRadius: MenuMetrics.cornerRadius)
        DropdownPreview.menuBackground.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// One 24 pt submenu row: checkmark column, 13 pt title at 32 pt, 12 pt secondary trailing value.
final class Size13RowView: NSView {
    private let row: Size13Submenu.Row

    init(_ row: Size13Submenu.Row, width: CGFloat) {
        self.row = row
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: MenuMetrics.rowHeight))
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel([row.title, row.trailing].compactMap { $0 }.joined(separator: ", "))
        setAccessibilityEnabled(row.enabled)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let titleColor: NSColor = row.enabled ? .labelColor : .tertiaryLabelColor
        let attributes: [NSAttributedString.Key: Any] = [.font: MenuMetrics.titleFont, .foregroundColor: titleColor]
        let size = (row.title as NSString).size(withAttributes: attributes)
        let y = (bounds.height - size.height) / 2
        if row.checked {
            let rect = NSRect(x: MenuMetrics.symbolX + 2, y: (bounds.height - 12) / 2, width: 12, height: 12)
            MenuMetrics.symbol("checkmark", pointSize: 12, color: titleColor)?.draw(in: rect)
        }
        (row.title as NSString).draw(at: NSPoint(x: MenuMetrics.textX, y: y), withAttributes: attributes)
        if let trailing = row.trailing {
            let trailingAttributes: [NSAttributedString.Key: Any] = [
                .font: MenuMetrics.detailFont,
                .foregroundColor: row.enabled ? NSColor.secondaryLabelColor : NSColor.quaternaryLabelColor,
            ]
            let trailingSize = (trailing as NSString).size(withAttributes: trailingAttributes)
            (trailing as NSString).draw(
                at: NSPoint(
                    x: bounds.width - MenuMetrics.trailingPadding - trailingSize.width,
                    y: (bounds.height - trailingSize.height) / 2),
                withAttributes: trailingAttributes)
        }
    }
}

/// A system-style help tag: 11 pt, wrapped, on the tooltip material.
final class Size13TooltipView: NSView {
    private let text: String

    init(frame: NSRect, text: String) {
        self.text = text
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(text)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    static let background = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.22, green: 0.22, blue: 0.23, alpha: 1)
            : NSColor(srgbRed: 0.99, green: 0.99, blue: 0.99, alpha: 1)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        Self.background.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
        let padding = Size13SubmenuPreview.tooltipPadding
        (text as NSString).draw(
            with: bounds.insetBy(dx: padding.width, dy: padding.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: Size13SubmenuPreview.tooltipFont, .foregroundColor: NSColor.labelColor])
    }
}

/// The spec's Custom… panel: radius 10, 320 pt, W × H in clip px, a quiet live line or the reason in 12 pt red,
/// Cancel and Set Size (default).
struct Size13CustomSheet: View {
    enum State: Sendable {
        /// 1920 × 1080 on the laptop: a 1440 × 810 window.
        case valid
        /// 3840 × 2160 on the laptop.
        case tooLarge
    }

    let state: State

    private var widthText: String { state == .valid ? "1920" : "3840" }
    private var heightText: String { state == .valid ? "1080" : "2160" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Size13Strings.customTitle).font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                field(Size13Strings.width, value: widthText)
                Text(Size13Strings.times).foregroundStyle(.secondary)
                field(Size13Strings.height, value: heightText)
                Text(Size13Strings.px).foregroundStyle(.secondary)
            }
            Group {
                switch state {
                case .valid:
                    Text(Size13Strings.windowOnScreen(width: 1440, height: 810)).foregroundStyle(.secondary)
                case .tooLarge:
                    Text(Size13Strings.tooLarge).foregroundStyle(Color(nsColor: .systemRed))
                }
            }
            .font(.system(size: 12))
            HStack(spacing: 8) {
                Spacer()
                Button(Size13Strings.cancel) {}
                    .keyboardShortcut(.cancelAction)
                Button(Size13Strings.setSize) {}
                    .keyboardShortcut(.defaultAction)
                    .disabled(state == .tooLarge)
            }
        }
        .padding(20)
        .frame(width: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
        // An offscreen window is never key; draw the panel as the key window so Set Size shows as the default.
        .environment(\.controlActiveState, .key)
    }

    private func field(_ label: String, value: String) -> some View {
        TextField(label, text: .constant(value))
            .textFieldStyle(.roundedBorder)
            .frame(width: 96)
            .multilineTextAlignment(.trailing)
            .accessibilityLabel("\(label), \(Size13Strings.px)")
    }
}
