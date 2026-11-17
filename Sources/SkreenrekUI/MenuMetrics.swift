import AppKit

/// The dropdown's measurements from the design spec, in points. One place, so the menu and the rendered previews
/// agree.
public enum MenuMetrics {
    public static let width: CGFloat = 300
    public static let rowHeight: CGFloat = 24
    public static let padding: CGFloat = 8
    /// The 16 pt symbol column starts here, aligned with the menu's checkmark column.
    public static let symbolX: CGFloat = 12
    public static let symbolSize: CGFloat = 16
    /// Every text start in a menu without icons (the submenus).
    public static let textX: CGFloat = 32
    /// The main dropdown's text start, after the checkmark column and the leading icon column.
    public static let iconTextX: CGFloat = 52
    /// The leading icons' symbol size.
    public static let iconPointSize: CGFloat = 13
    public static let trailingPadding: CGFloat = 12
    public static let separatorHeight: CGFloat = 12
    /// The menu's own top and bottom inset.
    public static let verticalInset: CGFloat = 4
    public static let cornerRadius: CGFloat = 10
    public static let highlightRadius: CGFloat = 6
    /// The Size submenu's width, and where its right-aligned trailing values end (from the title's start).
    public static let sizeSubmenuWidth: CGFloat = 240
    public static var sizeSubmenuTrailingStop: CGFloat { sizeSubmenuWidth - textX - trailingPadding }

    public static var titleFont: NSFont { NSFont.systemFont(ofSize: 13) }
    public static var detailFont: NSFont { NSFont.systemFont(ofSize: 12) }
    public static var headerFont: NSFont { NSFont.systemFont(ofSize: 12, weight: .semibold) }
    /// The "Started by …" row.
    public static var infoFont: NSFont { NSFont.systemFont(ofSize: 11) }
    /// The elapsed time beside the menu-bar symbol: SF Mono digits, 12 pt.
    public static var elapsedFont: NSFont { NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) }

    /// The SF Symbol at 16 pt.
    public static func symbol(_ name: String, pointSize: CGFloat = 16, color: NSColor? = nil) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        var configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        if let color {
            // Hierarchical keeps the symbol's layers (the ring around the red recording dot).
            configuration = configuration.applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
        }
        return base.withSymbolConfiguration(configuration)
    }
}
