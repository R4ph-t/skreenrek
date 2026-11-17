import AppKit
import SkreenrekControl
import SkreenrekCore
import SwiftUI

/// `skreenrek debug render-ui --out DIR`: the menu-bar icons, status rows, a composed dropdown for each state, the
/// Size and Frame Rate submenus and the Settings window, as PNGs at 2× in light and dark, named
/// `<surface>-<state>-<light|dark>@2x.png`. How screenshots reach Designer without a hand session.
@MainActor
public enum UIRenderer {
    public enum Appearance: String, CaseIterable, Sendable {
        case light
        case dark

        var nsAppearance: NSAppearance {
            NSAppearance(named: self == .light ? .aqua : .darkAqua)!
        }
    }

    public struct Rendered: Sendable, Hashable {
        public var url: URL
        /// Pixel size of the PNG.
        public var pixelWidth: Int
        public var pixelHeight: Int
    }

    public static let scale: CGFloat = 2

    /// Renders every surface into `folder` (created when missing) and returns the files written, in order.
    @discardableResult
    public static func renderAll(to folder: URL) throws -> [Rendered] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var written: [Rendered] = []
        for appearance in Appearance.allCases {
            func save(_ view: NSView, _ surface: String, _ state: String) throws {
                let name = "\(surface)-\(state)-\(appearance.rawValue)@2x.png"
                written.append(try write(view, appearance: appearance, to: folder.appendingPathComponent(name)))
            }
            for sample in RenderSamples.states {
                let context = sample.context
                try save(MenuBarIconPreview(StatusIconModel.icon(for: context)), "menubaricon", sample.name)
                // The Last Clip samples show the Last Clip row; the others their state row.
                let rows = MenuModel.entries(for: context).compactMap(\.statusRow)
                if let row = sample.name.hasPrefix("lastclip") ? rows.last : rows.first {
                    try save(StatusRowPreview(row), "statusrow", sample.name)
                }
                try save(DropdownPreview(MenuModel.entries(for: context)), "dropdown", sample.name)
            }
            let base = RenderSamples.armed.context
            try save(DropdownPreview(MenuModel.sizeSubmenu(base.sizeChoice).entries), "submenu", "size")
            try save(DropdownPreview(MenuModel.frameRateSubmenu(base.snapshot.fps).entries), "submenu", "framerate")
            try save(settingsView(), "settings", "default")
        }
        return written
    }

    /// The Settings window's content with sample values (Accessibility missing, so both permission row forms show).
    static func settingsView() -> NSView {
        let defaults = UserDefaults(suiteName: "skreenrek.render-ui.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults, home: URL(fileURLWithPath: "/Users/you", isDirectory: true))
        store.outputFolder = URL(fileURLWithPath: "/Users/you/Movies/Skreenrek", isDirectory: true)
        let panel = SettingsPanelState(
            permissions: StaticPermissions(screenRecording: .allowed, accessibility: .missing),
            loginItem: StaticLoginItem(),
            agents: AgentsPanelState(installer: AgentInstaller(
                home: FileManager.default.temporaryDirectory.appendingPathComponent("skreenrek-preview-\(UUID().uuidString)"),
                executablePath: "/unused/skreenrek", path: "")))
        let hosting = NSHostingView(
            rootView: SettingsView(store: store, panel: panel, actions: .none, version: SkreenrekVersion.current))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        return hosting
    }

    /// Draws `view` at 2× with the appearance forced and writes a PNG.
    static func write(_ view: NSView, appearance: Appearance, to url: URL) throws -> Rendered {
        let data = try png(view, appearance: appearance)
        try data.write(to: url, options: .atomic)
        let size = view.bounds.size
        return Rendered(url: url, pixelWidth: Int(size.width * scale), pixelHeight: Int(size.height * scale))
    }

    static func png(_ view: NSView, appearance: Appearance) throws -> Data {
        view.appearance = appearance.nsAppearance
        // An offscreen window gives SwiftUI and the text fields a real layout pass and backing.
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: view.bounds.size), styleMask: .borderless, backing: .buffered,
            defer: false)
        window.appearance = appearance.nsAppearance
        window.backgroundColor = .clear
        window.isOpaque = false
        let container = NSView(frame: NSRect(origin: .zero, size: view.bounds.size))
        window.contentView = container
        container.addSubview(view)
        view.frame.origin = .zero
        view.layoutSubtreeIfNeeded()
        if let hosting = view as? NSHostingView<SettingsView> {
            let size = hosting.fittingSize
            hosting.frame = NSRect(origin: .zero, size: size)
            window.setContentSize(size)
            container.frame = NSRect(origin: .zero, size: size)
            hosting.layoutSubtreeIfNeeded()
        }
        view.displayIfNeeded()

        let size = view.bounds.size
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)
        else { throw RenderError.bitmap }
        rep.size = size
        appearance.nsAppearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: rep)
        }
        container.subviews.forEach { $0.removeFromSuperview() }
        window.contentView = nil
        guard let data = rep.representation(using: .png, properties: [:]) else { throw RenderError.png }
        return data
    }

    enum RenderError: Error, CustomStringConvertible {
        case bitmap
        case png

        var description: String {
            switch self {
            case .bitmap: "Couldn't make a bitmap to render into."
            case .png: "Couldn't encode the PNG."
            }
        }
    }
}

extension MenuEntry {
    var statusRow: StatusRow? {
        if case .status(let row) = self { return row }
        return nil
    }
}

// MARK: - Sample states

/// The states `render-ui` draws, with Designer's sample values (Safari, localhost:3000, 1280 × 800 px).
public enum RenderSamples {
    public struct Sample: Sendable {
        public var name: String
        public var context: MenuContext
    }

    static let display = DisplayInfo(
        id: 1, name: "Built-in Retina Display", scale: 2, frame: PointRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: PointRect(x: 0, y: 33, width: 1512, height: 949))
    static let safari = WindowInfo(
        id: WindowID(4127), app: "Safari", bundleId: "com.apple.Safari", title: "localhost:3000", pid: 812,
        frame: PointRect(x: 120, y: 80, width: 640, height: 400), displayId: 1, onScreen: true)
    static let size = PixelSize(width: 1280, height: 800)

    static func readback(actual: PixelSize) -> Readback {
        Readback(
            window: Readback.Window(safari), display: Readback.Display(display), requested: size, actual: actual,
            frame: PointRect(x: 120, y: 80, width: Double(actual.width) / 2, height: Double(actual.height) / 2),
            exact: actual == size, attempts: actual == size ? 1 : 3)
    }

    public static func clip(codec: VideoCodec = .h264, file: String = "clip.mp4") -> StopBody {
        let folder = "/Users/you/Movies/Skreenrek/2026-11-17_104207_safari"
        return StopBody(
            recording: StopBody.Recording(
                id: "2026-11-17_104207_safari", duration: 42.0, fps: 60, width: 1280, height: 800, codec: codec,
                startedAt: "2026-11-17T10:24:07.120+01:00", startedBy: .mcp,
                stats: RecordingStats(slotsWritten: 2520, framesFresh: 2400, encoder: .hardware)),
            files: StopBody.Files(
                clip: "\(folder)/\(file)", events: "\(folder)/events.json", snippet: "\(folder)/hyperframes.html"),
            snippet: "<video class=\"clip\"></video>", readback: readback(actual: size))
    }

    static func context(
        _ snapshot: ControllerSnapshot, actionError: SkreenrekError? = nil, title: String? = nil
    ) -> MenuContext {
        MenuContext(
            snapshot: snapshot, actionError: actionError, lastClipTitle: title,
            timeZone: TimeZone(identifier: "Europe/Paris")!, locale: Locale(identifier: "en_GB"))
    }

    static let clipTitle = "Safari — localhost:3000"

    public static let idle = Sample(name: "idle", context: context(ControllerSnapshot(state: .idle, fps: .fps60)))
    public static let armed = Sample(
        name: "armed",
        context: context(
            ControllerSnapshot(
                state: .armed, window: safari, displayId: 1, size: size, readback: readback(actual: size),
                fps: .fps60, lastClip: clip()),
            title: clipTitle))

    public static let states: [Sample] = [
        idle,
        Sample(
            name: "lastclip",
            context: context(ControllerSnapshot(state: .idle, fps: .fps60, lastClip: clip()), title: clipTitle)),
        Sample(
            name: "lastclipmov",
            context: context(
                ControllerSnapshot(state: .idle, fps: .fps60, lastClip: clip(file: "clip.mov")), title: clipTitle)),
        armed,
        Sample(
            name: "armednotexact",
            context: context(
                ControllerSnapshot(
                    state: .armed, window: safari, displayId: 1, size: PixelSize(width: 1286, height: 800),
                    readback: readback(actual: PixelSize(width: 1286, height: 800)), fps: .fps60))),
        Sample(
            name: "recording",
            context: context(
                ControllerSnapshot(
                    state: .recording, elapsed: 12.4, window: safari, displayId: 1, size: size, fps: .fps60,
                    startedBy: .mcp, client: "Claude Code"))),
        Sample(
            name: "writing",
            context: context(
                ControllerSnapshot(
                    state: .writing, elapsed: 42, window: safari, displayId: 1, size: size, fps: .fps60,
                    startedBy: .menu))),
        Sample(
            name: "errorwindowclosed",
            context: context(
                ControllerSnapshot(
                    state: .error, fps: .fps60, lastClip: clip(),
                    error: .recordingFailed(.windowClosed(at: 31))), title: clipTitle)),
        Sample(
            name: "errorscreenrecording",
            context: context(
                ControllerSnapshot(state: .idle, fps: .fps60), actionError: .permissionDenied(.screenRecording))),
        Sample(
            name: "erroraccessibility",
            context: context(
                ControllerSnapshot(state: .armed, window: safari, displayId: 1, size: size, fps: .fps60),
                actionError: .permissionDenied(.accessibility))),
        Sample(
            name: "errornotexact",
            context: context(
                ControllerSnapshot(state: .armed, window: safari, displayId: 1, size: size, fps: .fps60),
                actionError: .notExact(
                    app: "Safari", requested: size, actual: PixelSize(width: 1286, height: 800),
                    reason: .minWidth(1286)))),
        Sample(
            name: "errordisklow",
            context: context(
                ControllerSnapshot(
                    state: .error, fps: .fps60, lastClip: clip(), error: .recordingFailed(.diskLow(at: 252))),
                title: clipTitle)),
        Sample(
            name: "errorwritefailed",
            context: context(
                ControllerSnapshot(state: .error, fps: .fps60, error: .recordingFailed(.notWritable)))),
    ]
}

/// Fixed permission state for previews.
struct StaticPermissions: PermissionProbe {
    var screenRecording: PermissionStatus
    var accessibility: PermissionStatus
}

/// An Open at login stand-in for previews: off, and never touches the system.
@MainActor
final class StaticLoginItem: LoginItemService {
    var isEnabled = false
    func setEnabled(_ enabled: Bool) throws { isEnabled = enabled }
}

// MARK: - Preview views

/// The menu-bar icon as the status item draws it: 22 pt tall, the symbol plus the elapsed time while recording, on
/// a menu-bar-like backdrop.
final class MenuBarIconPreview: NSView {
    static let height: CGFloat = 24
    private let icon: StatusIcon

    init(_ icon: StatusIcon) {
        self.icon = icon
        let titleWidth =
            icon.elapsed.map {
                ceil((" " + $0 as NSString).size(withAttributes: [.font: MenuMetrics.elapsedFont]).width)
            } ?? 0
        super.init(frame: NSRect(x: 0, y: 0, width: 16 + 16 + titleWidth, height: Self.height))
        setAccessibilityLabel(icon.sentence)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        let symbolRect = NSRect(x: 8, y: (bounds.height - 16) / 2, width: 16, height: 16)
        MenuMetrics.symbol(icon.symbol, color: icon.tinted ? .systemRed : .labelColor)?.draw(in: symbolRect)
        if let elapsed = icon.elapsed {
            let text = " " + elapsed as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: MenuMetrics.elapsedFont, .foregroundColor: NSColor.labelColor,
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: 24, y: (bounds.height - size.height) / 2), withAttributes: attributes)
        }
    }
}

/// A composed dropdown: the same entries the `NSMenu` shows, laid out with the design spec's metrics on the menu
/// material's colours (an offscreen `NSMenu` can't be drawn).
final class DropdownPreview: NSView {
    init(_ entries: [MenuEntry]) {
        let rows = entries.map(Self.view)
        let height = rows.reduce(MenuMetrics.verticalInset * 2) { $0 + $1.frame.height }
        super.init(frame: NSRect(x: 0, y: 0, width: MenuMetrics.width, height: height))
        var y = MenuMetrics.verticalInset
        for row in rows {
            row.frame.origin = NSPoint(x: 0, y: y)
            addSubview(row)
            y += row.frame.height
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: MenuMetrics.cornerRadius,
            yRadius: MenuMetrics.cornerRadius)
        Self.menuBackground.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    /// The menu material's tone in each appearance.
    static let menuBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1)
            : NSColor(srgbRed: 0.96, green: 0.96, blue: 0.96, alpha: 1)
    }

    static func view(_ entry: MenuEntry) -> NSView {
        switch entry {
        case .status(let row): StatusRowView(row)
        case .separator: SeparatorPreview()
        case .header(let title): MenuItemPreview(header: title)
        case .item(let item): MenuItemPreview(item: item)
        case .submenu(let submenu): MenuItemPreview(submenu: submenu)
        }
    }
}

/// One status row on the menu's backdrop.
final class StatusRowPreview: NSView {
    init(_ row: StatusRow) {
        let view = StatusRowView(row)
        super.init(frame: view.frame)
        addSubview(view)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        DropdownPreview.menuBackground.setFill()
        bounds.fill()
    }
}

final class SeparatorPreview: NSView {
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuMetrics.width, height: MenuMetrics.separatorHeight))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(
            x: MenuMetrics.trailingPadding, y: floor(bounds.midY),
            width: bounds.width - MenuMetrics.trailingPadding * 2,
            height: 1
        ).fill()
    }
}

/// One 24 pt row: checkmark column, 13 pt title at 32 pt, then a shortcut, a detail or a submenu chevron.
final class MenuItemPreview: NSView {
    private var title = ""
    private var titleFont = MenuMetrics.titleFont
    private var titleColor = NSColor.labelColor
    private var checked = false
    private var trailing: String?
    private var chevron = false

    init(item: MenuItemModel) {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuMetrics.width, height: MenuMetrics.rowHeight))
        title = item.title
        titleColor = item.enabled ? .labelColor : .tertiaryLabelColor
        checked = item.checked
        trailing = item.shortcut?.display
    }

    init(submenu: SubmenuModel) {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuMetrics.width, height: MenuMetrics.rowHeight))
        title = submenu.title
        trailing = submenu.detail
        chevron = true
    }

    init(header: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuMetrics.width, height: MenuMetrics.rowHeight))
        title = header
        titleFont = MenuMetrics.headerFont
        titleColor = .secondaryLabelColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: titleColor]
        let size = (title as NSString).size(withAttributes: attributes)
        let y = (bounds.height - size.height) / 2
        if checked {
            let rect = NSRect(
                x: MenuMetrics.symbolX + 2, y: (bounds.height - 12) / 2, width: 12, height: 12)
            MenuMetrics.symbol("checkmark", pointSize: 12, color: .labelColor)?.draw(in: rect)
        }
        var right = bounds.width - MenuMetrics.trailingPadding
        if chevron {
            let rect = NSRect(x: right - 8, y: (bounds.height - 12) / 2, width: 8, height: 12)
            MenuMetrics.symbol("chevron.right", pointSize: 11, color: .secondaryLabelColor)?.draw(in: rect)
            right -= 16
        }
        if let trailing {
            let trailingAttributes: [NSAttributedString.Key: Any] = [
                .font: MenuMetrics.titleFont, .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let width = (trailing as NSString).size(withAttributes: trailingAttributes).width
            (trailing as NSString).draw(at: NSPoint(x: right - width, y: y), withAttributes: trailingAttributes)
        }
        (title as NSString).draw(at: NSPoint(x: MenuMetrics.textX, y: y), withAttributes: attributes)
    }
}
