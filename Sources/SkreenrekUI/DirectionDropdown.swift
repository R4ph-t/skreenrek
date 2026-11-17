import AppKit
import SkreenrekCore
import SwiftUI

/// One row of A's and C's dropdown. The rows are `MenuModel`'s entries with the state row swapped for the header
/// and the Last Clip status row swapped for the thumbnail row; everything else is the same menu.
public enum DirectionRow: Sendable, Hashable {
    case header(DirectionHeader)
    case item(MenuItemModel)
    /// The disabled "Started by …" row: 11 pt tertiary, no icon, indented to the text column.
    case info(String)
    case submenu(SubmenuModel)
    case sectionHeader(String)
    case clip(DirectionClip)
    case separator
}

extension DirectionModel {
    /// A's and C's dropdown for one moment. Pure.
    public static func dropdownRows(for context: MenuContext) -> [DirectionRow] {
        var rows: [DirectionRow] = []
        var sawHeader = false
        var inLastClip = false
        for entry in MenuModel.entries(for: context) {
            switch entry {
            case .status:
                if !sawHeader {
                    sawHeader = true
                    rows.append(.header(header(for: context)))
                } else if inLastClip, let clip = lastClip(for: context) {
                    rows.append(.clip(clip))
                }
            case .header(let title):
                inLastClip = title == UIStrings.Menu.lastClip
                rows.append(.sectionHeader(title))
            case .item(let item):
                rows.append(item.action == nil ? .info(item.title) : .item(item))
            case .submenu(let submenu):
                rows.append(.submenu(submenu))
            case .separator:
                inLastClip = false
                rows.append(.separator)
            }
        }
        return rows
    }

    /// C tints the primary item's icon: Record Window once a window is picked, otherwise Pick Window….
    static func isPrimary(_ item: MenuItemModel, context: MenuContext) -> Bool {
        guard let primary = primaryAction(for: context), primary != .stop else { return false }
        return item.action == primary && item.enabled
    }
}

/// A (`branded: false`) or C (`branded: true`): the native menu with a header, an icon column and a thumbnail row,
/// composed with the menu's metrics the way the shipping preview is (an offscreen `NSMenu` can't be drawn). The
/// header and clip row are the custom views the app would put in `NSMenuItem.view` through `NSHostingView`.
struct DirectionDropdownView: View {
    static let width: CGFloat = 300
    /// The checkmark column, then the 16 pt icon column, then the text.
    static let checkX: CGFloat = 10
    static let iconX: CGFloat = 28
    static let textX: CGFloat = 52

    let context: MenuContext
    let branded: Bool
    let thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(DirectionModel.dropdownRows(for: context).enumerated()), id: \.offset) { _, row in
                rowView(row)
            }
        }
        .padding(.vertical, 5)
        .frame(width: Self.width)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DirectionTheme.menuBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func rowView(_ row: DirectionRow) -> some View {
        switch row {
        case .header(let header):
            DirectionHeaderView(header: header, branded: branded)
        case .item(let item):
            MenuItemRow(
                title: item.title, symbol: DirectionModel.symbol(for: item.action), enabled: item.enabled,
                checked: item.checked, trailing: item.shortcut?.display,
                symbolColor: symbolColor(item))
        case .info(let text):
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.leading, Self.textX)
                .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
        case .submenu(let submenu):
            MenuItemRow(
                title: submenu.title, symbol: DirectionModel.symbol(forSubmenu: submenu.title), enabled: true,
                checked: false, trailing: submenu.detail, chevron: true, symbolColor: .secondary)
        case .sectionHeader(let title):
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        case .clip(let clip):
            DirectionClipRow(clip: clip, thumbnail: thumbnail, branded: branded)
        case .separator:
            Rectangle()
                .fill(.separator)
                .frame(height: 1)
                .padding(.horizontal, 12)
                .frame(height: 11)
        }
    }

    /// Red only for Stop (and C's Record Window); C's other primary item (Pick Window…) takes the system accent.
    private func symbolColor(_ item: MenuItemModel) -> Color {
        if item.action == .stop { return .red }
        if branded, DirectionModel.isPrimary(item, context: context) {
            return item.action == .record ? .red : .accentColor
        }
        return .secondary
    }
}

/// One 24 pt menu row: checkmark column, 16 pt icon in the leading icon column, 13 pt title, then a shortcut, a
/// value or a submenu chevron.
private struct MenuItemRow: View {
    let title: String
    let symbol: String?
    let enabled: Bool
    let checked: Bool
    let trailing: String?
    var chevron = false
    let symbolColor: Color

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                if checked {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                }
            }
            .frame(width: 14)
            .padding(.leading, DirectionDropdownView.checkX)
            ZStack {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(symbolColor)
                        .frame(width: 16, height: 16)
                }
            }
            .frame(width: 16)
            .padding(.leading, DirectionDropdownView.iconX - DirectionDropdownView.checkX - 14)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(enabled ? .primary : .tertiary)
                .padding(.leading, DirectionDropdownView.textX - DirectionDropdownView.iconX - 16)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).font(.system(size: 13)).foregroundStyle(.secondary).monospacedDigit()
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }
        }
        .padding(.trailing, 12)
        .frame(height: 24)
        .opacity(enabled ? 1 : 0.85)
        .accessibilityElement(children: .combine)
    }
}

/// A's header (64 pt): a 40 pt icon tile, then the title and the detail. C adds the tinted band and the brand mark.
struct DirectionHeaderView: View {
    let header: DirectionHeader
    let branded: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            tile
            VStack(alignment: .leading, spacing: 2) {
                Text(header.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                detail
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(minHeight: 64)
        .background(band)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(header.accessibilityLabel)
        .help(header.help ?? "")
    }

    @ViewBuilder
    private var detail: some View {
        if let elapsed = header.elapsed, header.kind == .recording {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(elapsed).font(.system(size: 22, weight: .medium)).monospacedDigit()
                Text(UIStrings.Menu.separator + header.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        } else {
            Text(header.detail)
                .font(.system(size: 12))
                .foregroundStyle(header.kind == .notExact ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                .lineLimit(header.kind == .notExact ? 1 : nil)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 4)  // the detail keeps a 16 pt right inset and wraps
        }
    }

    @ViewBuilder
    private var tile: some View {
        switch header.kind {
        case .recording:
            Circle()
                .fill(Color.red)
                .overlay(Image(systemName: "record.circle.fill").font(.system(size: 20)).foregroundStyle(.white))
                .frame(width: 40, height: 40)
        case .saving:
            plainTile { ProgressView().controlSize(.small) }
        case .error:
            plainTile {
                Image(systemName: header.symbol).font(.system(size: 20)).foregroundStyle(.orange)
            }
        case .idle, .armed, .notExact:
            if branded {
                KitMarkTile(size: 40)
            } else {
                plainTile {
                    Image(systemName: header.symbol)
                        .font(.system(size: 20))
                        .foregroundStyle(header.kind == .idle ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                }
            }
        }
    }

    private func plainTile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.fill.quaternary)
            .overlay(content())
            .frame(width: 40, height: 40)
    }

    @ViewBuilder
    private var band: some View {
        if branded {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(bandColor)
                .padding(.horizontal, 6)
        }
    }

    /// Neutral unless something needs attention: red only while recording, orange only for an error.
    private var bandColor: AnyShapeStyle {
        switch header.kind {
        case .recording: AnyShapeStyle(Color.red.opacity(0.14))
        case .error: AnyShapeStyle(Color.orange.opacity(0.12))
        default: AnyShapeStyle(.fill.quinary)
        }
    }
}

/// A's Last Clip row (64 pt): a 72 × 45 thumbnail centred vertically, then the title (tail-truncated), the summary
/// in `.secondary` and the start time or format in `.tertiary`.
struct DirectionClipRow: View {
    static let height: CGFloat = 64

    let clip: DirectionClip
    let thumbnail: NSImage?
    let branded: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ClipThumbnail(image: thumbnail, width: 72, height: 45, radius: 4, accentStroke: branded)
            VStack(alignment: .leading, spacing: 1) {
                Text(clip.title).font(.system(size: 13)).lineLimit(1).truncationMode(.tail)
                Text(clip.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                if let note = clip.note {
                    Text(note).font(.system(size: 12)).foregroundStyle(.tertiary).monospacedDigit().lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .frame(height: Self.height)
        .accessibilityElement(children: .combine)
    }
}
