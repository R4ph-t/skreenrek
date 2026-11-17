import AppKit

/// The dropdown's measurements from the design spec, in points. One place, so the menu and the rendered previews
/// agree.
public enum MenuMetrics {
    public static let width: CGFloat = 300
    public static let rowHeight: CGFloat = 24
    public static let statusRowHeight: CGFloat = 48
    /// A status row whose detail wraps to two lines (the error rows).
    public static let tallStatusRowHeight: CGFloat = 64
    public static let padding: CGFloat = 8
    /// The 16 pt symbol column starts here, aligned with the menu's checkmark column.
    public static let symbolX: CGFloat = 12
    public static let symbolSize: CGFloat = 16
    /// Every text start.
    public static let textX: CGFloat = 32
    public static let trailingPadding: CGFloat = 12
    public static let separatorHeight: CGFloat = 12
    /// The menu's own top and bottom inset.
    public static let verticalInset: CGFloat = 4
    public static let cornerRadius: CGFloat = 10
    public static let highlightRadius: CGFloat = 6

    public static var titleFont: NSFont { NSFont.systemFont(ofSize: 13) }
    public static var emphasizedTitleFont: NSFont { NSFont.systemFont(ofSize: 13, weight: .semibold) }
    public static var detailFont: NSFont { NSFont.systemFont(ofSize: 12) }
    public static var headerFont: NSFont { NSFont.systemFont(ofSize: 12, weight: .semibold) }
    /// The elapsed time beside the menu-bar symbol: SF Mono digits, 12 pt.
    public static var elapsedFont: NSFont { NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) }

    /// Designer: every status row reserves at least 16 pt; long details wrap like error rows.
    public static let statusTrailingPadding: CGFloat = 16
    public static var textWidth: CGFloat { width - textX - statusTrailingPadding }
    /// A label's own inset on each side; fields are widened by it so their text starts exactly at `textX`.
    static let labelInset: CGFloat = 2

    /// 48 pt, or 64 pt when the detail wraps to a second line.
    public static func statusRowHeight(detail: String) -> CGFloat {
        let bounds = (detail as NSString).boundingRect(
            with: NSSize(width: textWidth, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: detailFont])
        let lineHeight = ceil(detailFont.ascender - detailFont.descender + detailFont.leading)
        return bounds.height > lineHeight * 1.5 ? tallStatusRowHeight : statusRowHeight
    }

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

/// A status row as a menu item view: 16 pt symbol column, 13 pt title, 12 pt secondary detail, text at 32 pt.
public final class StatusRowView: NSView {
    private let imageView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(wrappingLabelWithString: "")
    public private(set) var row: StatusRow

    public init(_ row: StatusRow) {
        self.row = row
        super.init(frame: NSRect(x: 0, y: 0, width: MenuMetrics.width, height: MenuMetrics.statusRowHeight))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.textColor = .labelColor
        detailField.font = MenuMetrics.detailFont
        detailField.textColor = .secondaryLabelColor
        detailField.maximumNumberOfLines = 2
        detailField.lineBreakMode = .byWordWrapping
        detailField.isSelectable = false
        for view in [imageView, titleField, detailField] { addSubview(view) }
        update(row)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public override var isFlipped: Bool { true }

    public func update(_ row: StatusRow) {
        self.row = row
        let height = MenuMetrics.statusRowHeight(detail: row.detail)
        setFrameSize(NSSize(width: MenuMetrics.width, height: height))
        imageView.image = MenuMetrics.symbol(row.symbol, color: row.tint == .red ? .systemRed : .labelColor)
        imageView.contentTintColor = row.tint == .red ? .systemRed : .labelColor
        titleField.stringValue = row.title
        titleField.font = row.emphasized ? MenuMetrics.emphasizedTitleFont : MenuMetrics.titleFont
        detailField.stringValue = row.detail
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(row.accessibilityLabel)
        toolTip = row.help
        layoutRow()
    }

    private func layoutRow() {
        let p = MenuMetrics.padding
        let titleHeight: CGFloat = 16
        let inset = MenuMetrics.labelInset
        let textWidth = MenuMetrics.textWidth + inset * 2
        titleField.frame = NSRect(x: MenuMetrics.textX - inset, y: p, width: textWidth, height: titleHeight)
        imageView.frame = NSRect(
            x: MenuMetrics.symbolX, y: p, width: MenuMetrics.symbolSize, height: MenuMetrics.symbolSize)
        detailField.frame = NSRect(
            x: MenuMetrics.textX - inset, y: p + titleHeight + 1, width: textWidth,
            height: bounds.height - p * 2 - titleHeight - 1)
        detailField.preferredMaxLayoutWidth = textWidth
    }
}
