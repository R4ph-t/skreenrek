import AppKit
import SkreenrekCore
import SwiftUI

/// The dropdown's header: a 40 pt tile, then the title and the detail, on a 64 pt band (taller when an error's detail
/// wraps or while recording) inset 6 pt from the menu's edges. The live menu hosts it in an `NSMenuItem.view`; the renders draw the
/// same view.
struct DropdownHeaderView: View {
    /// The band is 64 pt; it sits 2 pt in from the row's top and bottom (and 6 pt from the menu's sides).
    static let bandHeight: CGFloat = 64
    static let bandInset: CGFloat = 2
    static var minHeight: CGFloat { bandHeight + bandInset * 2 }

    let header: DropdownHeader
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            tile
            VStack(alignment: .leading, spacing: 2) {
                Text(header.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    // `Recording Safari — localhost:3000` fits by shrinking a little; longer titles lose their middle.
                    .minimumScaleFactor(0.9)
                    .truncationMode(header.kind == .recording ? .middle : .tail)
                detail
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .frame(width: MenuMetrics.width)
        .frame(minHeight: Self.minHeight)
        .background(band)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isHeader)
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
        }
    }

    @ViewBuilder
    private var tile: some View {
        switch header.kind {
        case .recording:
            // The shape and the fill both change, so colour isn't the only cue.
            Circle()
                .fill(Color.red)
                .overlay(Image(systemName: "record.circle.fill").font(.system(size: 20)).foregroundStyle(.white))
                .frame(width: 40, height: 40)
        case .saving:
            plainTile {
                if reduceMotion {
                    Image(systemName: header.symbol).font(.system(size: 20)).foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        case .error:
            plainTile {
                Image(systemName: header.symbol).font(.system(size: 20)).foregroundStyle(.orange)
            }
        case .idle, .armed, .notExact:
            KitMarkTile(size: 40)
        }
    }

    private func plainTile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(contrast == .increased ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.fill.quaternary))
            .overlay(content())
            .frame(width: 40, height: 40)
    }

    private var band: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(BrandTheme.band(header.kind, increaseContrast: contrast == .increased))
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(BrandTheme.bandStroke(header.kind), lineWidth: 1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, Self.bandInset)
    }
}

/// The Last Clip row, 64 pt: a 72 × 45 thumbnail, then the title (one line, truncating in the middle) over the
/// two-line detail: the summary in `.secondary` and the start time or format in `.tertiary`.
struct ClipRowView: View {
    static let height: CGFloat = 64

    let clip: DropdownClip
    let thumbnail: NSImage?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ClipThumbnail(image: thumbnail, width: 72, height: 45, radius: 4, accentStroke: clip.isNewest)
            VStack(alignment: .leading, spacing: 1) {
                Text(clip.title).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
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
        .frame(width: MenuMetrics.width, height: Self.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(clip.accessibilityLabel)
    }
}

/// The whole dropdown composed for the renders, with the menu's metrics and the macOS 26 leading icon column (an
/// offscreen `NSMenu` can't be drawn). The header and the clip row are the same views the live menu hosts; the
/// other rows draw what `MenuController` gives the native items.
struct DropdownPreviewView: View {
    /// The checkmark column, then the 16 pt icon column, then the text.
    static let checkX: CGFloat = 10
    static let iconX: CGFloat = 28
    static let textX: CGFloat = 52

    let context: MenuContext
    let thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(DropdownModel.rows(for: context).enumerated()), id: \.offset) { _, row in
                rowView(row)
            }
        }
        .padding(.vertical, 5)
        .frame(width: MenuMetrics.width)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(BrandTheme.menuBackground))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator, lineWidth: 1))
    }

    @ViewBuilder
    private func rowView(_ row: DropdownRow) -> some View {
        switch row {
        case .header(let header):
            DropdownHeaderView(header: header)
        case .item(let item):
            PreviewMenuRow(
                title: item.title, symbol: DropdownModel.symbol(for: item.action), enabled: item.enabled,
                checked: item.checked, trailing: item.shortcut?.display,
                tint: DropdownModel.iconTint(for: item, context: context))
        case .info(let text):
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.leading, Self.textX)
                .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
        case .submenu(let submenu):
            PreviewMenuRow(
                title: submenu.title, symbol: DropdownModel.symbol(forSubmenu: submenu.title), enabled: true,
                checked: false, trailing: submenu.detail, chevron: true, tint: .neutral)
        case .sectionHeader(let title):
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        case .clip(let clip):
            ClipRowView(clip: clip, thumbnail: thumbnail)
        case .separator:
            Rectangle()
                .fill(.separator)
                .frame(height: 1)
                .padding(.horizontal, 12)
                .frame(height: 11)
        }
    }
}

extension DropdownModel.IconTint {
    var color: Color {
        switch self {
        case .neutral: .secondary
        case .accent: .accentColor
        case .red: .red
        }
    }

    var nsColor: NSColor? {
        switch self {
        case .neutral: nil
        case .accent: .controlAccentColor
        case .red: .systemRed
        }
    }
}

/// One 24 pt menu row for the renders: checkmark column, 16 pt icon column, 13 pt title, then a shortcut, a value or
/// a submenu chevron.
private struct PreviewMenuRow: View {
    let title: String
    let symbol: String?
    let enabled: Bool
    let checked: Bool
    let trailing: String?
    var chevron = false
    let tint: DropdownModel.IconTint

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                if checked {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                }
            }
            .frame(width: 14)
            .padding(.leading, DropdownPreviewView.checkX)
            ZStack {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(enabled ? tint.color : Color.secondary.opacity(0.5))
                        .frame(width: 16, height: 16)
                }
            }
            .frame(width: 16)
            .padding(.leading, DropdownPreviewView.iconX - DropdownPreviewView.checkX - 14)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(enabled ? .primary : .tertiary)
                .lineLimit(1)
                .padding(.leading, DropdownPreviewView.textX - DropdownPreviewView.iconX - 16)
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
        .accessibilityElement(children: .combine)
    }
}
