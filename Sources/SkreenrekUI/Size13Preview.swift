import AppKit
import SkreenrekControl
import SkreenrekCore
import SwiftUI

// `skreenrek debug render-ui --direction size13`: Designer's spec 13 v2 Size states, drawn from the shipping models
// (`MenuModel`, `WindowFit`, `CustomSizeModel`) on the spec's sample displays, so the renders can't drift from the app.

/// The spec 13 sample displays and window.
enum Size13Samples {
    /// Retina MacBook Pro 14": 1512 × 982 pt, usable ~1448 × 870 pt after the menu bar, the Dock and the 32 pt
    /// margins.
    static let laptop = DisplayInfo(
        id: 1, name: "Built-in Retina Display", scale: 2, frame: PointRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: PointRect(x: 0, y: 33, width: 1512, height: 934))
    /// A large 1× display (5120 × 2880 pt): every preset fits, 4K and Portrait included.
    static let large = DisplayInfo(
        id: 2, name: "Large Display", scale: 1, frame: PointRect(x: 0, y: 0, width: 5120, height: 2880),
        visibleFrame: PointRect(x: 0, y: 25, width: 5120, height: 2855))

    /// The Safari sample at 1280 × 800 pt: Current Size is 2560 × 1600 on the laptop and 1280 × 800 on the 1× display.
    static func safari(on display: DisplayInfo) -> WindowInfo {
        var window = RenderSamples.safari
        window.frame = PointRect(x: 120, y: 80, width: 1280, height: 800)
        window.displayId = display.id
        return window
    }

    static let choice = SizeChoice.size(SizePreset.p1080.size)

    static func submenu(on display: DisplayInfo) -> [MenuEntry] {
        MenuModel.sizeSubmenu(choice, display: display, window: safari(on: display)).entries
    }

    /// The main menu armed with 1080p on the laptop: the window is 1440 × 810 pt and records a 1920 × 1080 px clip.
    static func armedEntries() -> [MenuEntry] {
        let clip = SizePreset.p1080.size
        var window = RenderSamples.safari
        window.frame = PointRect(x: 120, y: 80, width: 1440, height: 810)
        let context = RenderSamples.context(
            ControllerSnapshot(
                state: .armed, window: window, displayId: laptop.id, size: clip,
                readback: Readback(
                    window: Readback.Window(window), display: Readback.Display(laptop), requested: clip,
                    actual: clip, frame: window.frame, exact: true, attempts: 1),
                fps: .fps60, lastClip: RenderSamples.clip(), display: laptop),
            title: RenderSamples.clipTitle, sizeChoice: choice)
        return MenuModel.entries(for: context)
    }

    static func customSheet(width: Int, height: Int) -> CustomSizeModel {
        CustomSizeModel(widthText: String(width), heightText: String(height), display: laptop)
    }
}

@MainActor
enum Size13Renderer {
    static let names = [
        "size-submenu-laptop", "size-submenu-large", "custom-valid", "custom-toolarge", "dropdown-armed-1080p",
    ]

    /// Every file the size13 render writes, in order.
    static func fileNames() -> [String] {
        UIRenderer.Appearance.allCases.flatMap { appearance in
            names.map { "\($0)-\(appearance.rawValue)@2x.png" }
        }
    }

    static func render(to folder: URL) throws -> [UIRenderer.Rendered] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var written: [UIRenderer.Rendered] = []
        for appearance in UIRenderer.Appearance.allCases {
            func save(_ view: NSView, _ name: String) throws {
                let url = folder.appendingPathComponent("\(name)-\(appearance.rawValue)@2x.png")
                written.append(try UIRenderer.write(view, appearance: appearance, to: url))
            }
            try save(
                SubmenuWithTooltip(Size13Samples.submenu(on: Size13Samples.laptop), tooltipOn: SizePreset.uhd4k.title),
                "size-submenu-laptop")
            try save(
                SubmenuWithTooltip(Size13Samples.submenu(on: Size13Samples.large), tooltipOn: nil),
                "size-submenu-large")
            try save(customSheet(Size13Samples.customSheet(width: 1920, height: 1080)), "custom-valid")
            try save(customSheet(Size13Samples.customSheet(width: 3840, height: 2160)), "custom-toolarge")
            try save(DropdownPreview(Size13Samples.armedEntries()), "dropdown-armed-1080p")
        }
        return written
    }

    static func customSheet(_ model: CustomSizeModel) -> NSView {
        let hosting = NSHostingView(rootView: CustomSizeView(model: model, finish: { _ in }, drawsAsKey: true))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        return hosting
    }
}

/// The Size submenu as the menu draws it, with one disabled row's tooltip showing just past the menu's right edge
/// (so it hides no other row). The canvas around them is transparent.
final class SubmenuWithTooltip: NSView {
    static let tooltipMaxWidth: CGFloat = 300
    static let tooltipFont = NSFont.toolTipsFont(ofSize: 11)
    static let tooltipPadding = NSSize(width: 8, height: 4)

    init(_ entries: [MenuEntry], tooltipOn title: String?) {
        let menu = DropdownPreview(entries, width: MenuMetrics.sizeSubmenuWidth)
        var size = menu.frame.size
        var tooltip: (rect: NSRect, text: String)?
        for row in menu.rows {
            guard let title, case .item(let item) = row.entry, item.title == title, let text = item.toolTip else {
                continue
            }
            let bounds = (text as NSString).boundingRect(
                with: NSSize(width: Self.tooltipMaxWidth - Self.tooltipPadding.width * 2, height: 1000),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: Self.tooltipFont])
            let rect = NSRect(
                x: menu.frame.width - 6, y: row.view.frame.maxY + 2,
                width: ceil(bounds.width) + Self.tooltipPadding.width * 2,
                height: ceil(bounds.height) + Self.tooltipPadding.height * 2)
            tooltip = (rect, text)
            size.width = max(size.width, rect.maxX + 1)
            size.height = max(size.height, rect.maxY + 1)
        }
        super.init(frame: NSRect(origin: .zero, size: size))
        addSubview(menu)
        // Added last, so the tooltip sits over the menu.
        if let tooltip { addSubview(TooltipPreview(frame: tooltip.rect, text: tooltip.text)) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
}

/// A system-style help tag: 11 pt, wrapped, on the tooltip material.
final class TooltipPreview: NSView {
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
        let padding = SubmenuWithTooltip.tooltipPadding
        (text as NSString).draw(
            with: bounds.insetBy(dx: padding.width, dy: padding.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: SubmenuWithTooltip.tooltipFont, .foregroundColor: NSColor.labelColor])
    }
}
