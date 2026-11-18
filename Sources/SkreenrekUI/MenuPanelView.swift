import AppKit
import SwiftUI

/// The menu panel. Blocks come from `PanelMetrics`, so the drawn stack is the stack the height budget measures.
@MainActor
struct MenuPanelView: View {
    var content: PanelContent
    var maxHeight: CGFloat
    var previewImage: NSImage?
    var clipImage: NSImage?
    var reduceMotion: Bool
    /// Bumped after Clear, to move focus to Pick Window….
    var heroFocusRequest = 0
    /// Draws the Clear button hovered, for `render-ui`.
    var showsClearHover = false
    var onAction: (MenuAction) -> Void
    var onClose: () -> Void = {}

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    @FocusState private var heroFocused: Bool
    @AccessibilityFocusState private var heroAccessibilityFocused: Bool

    var body: some View {
        let height = PanelMetrics.contentHeight(content)
        let viewport = min(height, maxHeight)
        Group {
            if height > maxHeight {
                ScrollView(.vertical, showsIndicators: true) { stack }
            } else {
                stack
            }
        }
        .frame(width: PanelMetrics.width, height: viewport, alignment: .top)
        .background(palette.fill.color)
        .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.radiusPanel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PanelMetrics.radiusPanel, style: .continuous)
                .strokeBorder(
                    palette.hairline(increaseContrast: contrast == .increased).color,
                    lineWidth: PanelSurface.pixel(displayScale: displayScale))
        }
        // The top edge stays under the status item while the window's height animates.
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(UIStrings.productName)
        .onExitCommand(perform: onClose)
        .onChange(of: heroFocusRequest) {
            heroFocused = true
            heroAccessibilityFocused = true
        }
    }

    private var stack: some View {
        VStack(spacing: 0) {
            ForEach(PanelMetrics.placedBlocks(for: content)) { placed in
                blockView(placed.block)
                    .frame(
                        width: PanelMetrics.width, height: PanelMetrics.height(of: placed.block), alignment: .leading
                    )
                    .transition(.opacity)
            }
        }
    }

    private var palette: PanelPalette { PanelPalette(scheme) }

    @ViewBuilder
    private func blockView(_ block: PanelBlock) -> some View {
        switch block {
        case .space:
            Color.clear
        case .header:
            header.padding(.leading, PanelMetrics.margin)
        case .preview:
            previewBox.padding(.leading, PanelMetrics.margin)
        case .caption:
            caption.padding(.leading, PanelMetrics.margin)
        case .cells:
            cells.padding(.leading, PanelMetrics.margin)
        case .hero:
            hero.padding(.leading, PanelMetrics.margin)
        case .origin:
            origin.padding(.leading, PanelMetrics.margin)
        case .row(let button):
            PanelRowButton(button: button, onAction: onAction).padding(.leading, PanelMetrics.rowHighlightX)
        case .toggle(let toggle):
            PanelToggleRow(toggle: toggle, onAction: onAction).padding(.leading, PanelMetrics.rowHighlightX)
        case .clip:
            if let clip = content.lastClip {
                PanelClipRow(clip: clip, image: clipImage, onAction: onAction)
                    .padding(.leading, PanelMetrics.rowHighlightX)
            }
        case .separator:
            separator
        }
    }

    // MARK: - Compact header

    @ViewBuilder
    private var header: some View {
        if let header = content.header {
            HStack(spacing: PanelMetrics.iconGap) {
                headerIcon(header.icon)
                    .frame(width: PanelMetrics.iconColumn, height: PanelMetrics.iconColumn)
                    .foregroundStyle(PanelSurface.secondaryText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(header.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .contentTransition(.opacity)
                    Text(header.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(PanelSurface.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .contentTransition(.opacity)
                }
            }
            .frame(width: PanelMetrics.blockWidth, height: PanelMetrics.captionHeight, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(header.accessibilityLabel)
            .modifier(PanelHelp(text: header.help))
        }
    }

    @ViewBuilder
    private func headerIcon(_ icon: PanelHeader.Icon) -> some View {
        switch icon {
        case .noWindow:
            Image(systemName: PanelSymbol.pickWindow).font(.system(size: 16))
        case .windowClosed:
            // SF Symbols has no window-with-× at this weight, so the badge is composed.
            Image(systemName: "macwindow")
                .font(.system(size: 16))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: PanelSymbol.clearWindow)
                        .font(.system(size: 8, weight: .bold))
                        .background(Circle().fill(palette.fill.color))
                        .offset(x: 2, y: 2)
                }
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewBox: some View {
        if let preview = content.preview {
            ZStack {
                RoundedRectangle(cornerRadius: PanelMetrics.radiusControl, style: .continuous)
                    .fill(palette.wellFill.color)
                previewContent(preview)
                RoundedRectangle(cornerRadius: PanelMetrics.radiusControl, style: .continuous)
                    .strokeBorder(strokeColor(preview.stroke), lineWidth: strokeWidth(preview.stroke))
            }
            .frame(width: PanelMetrics.blockWidth, height: PanelMetrics.previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.radiusControl, style: .continuous))
            .accessibilityElement(children: previewDecorative(preview) ? .ignore : .contain)
            .accessibilityHidden(previewDecorative(preview))
        }
    }

    private func strokeColor(_ stroke: PanelPreviewStroke) -> Color {
        switch stroke {
        case .hairline: Color(nsColor: .separatorColor)
        case .selected: Color(nsColor: .controlAccentColor)
        case .recording: Color(nsColor: .systemRed)
        }
    }

    private func strokeWidth(_ stroke: PanelPreviewStroke) -> CGFloat {
        switch stroke {
        case .hairline: contrast == .increased ? 1 : PanelMetrics.hairline
        case .selected, .recording: PanelMetrics.previewStroke
        }
    }

    private func previewDecorative(_ preview: PanelPreviewBox) -> Bool {
        switch preview.phase {
        case .failed, .permissionMissing: false
        default: true
        }
    }

    @ViewBuilder
    private func previewContent(_ preview: PanelPreviewBox) -> some View {
        switch preview.phase {
        case .ready:
            if let previewImage {
                still(previewImage, dimmed: false)
            }
        case .windowClosed:
            ZStack {
                if let previewImage {
                    still(previewImage, dimmed: true)
                    palette.wellFill.color.opacity(0.70)
                }
                Image(systemName: "xmark.rectangle")
                    .font(.system(size: 24))
                    .foregroundStyle(PanelSurface.primaryText)
                    .accessibilityHidden(true)
            }
        case .loading:
            if preview.showsSpinner {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            }
        case .failed:
            placeholder(
                symbol: "rectangle.slash", symbolSize: 20, message: preview.message,
                help: preview.messageHelp, settings: nil)
        case .permissionMissing:
            placeholder(
                symbol: "lock", symbolSize: 20, message: preview.message, help: preview.messageHelp,
                settings: preview.settings)
        case .noWindow, .region:
            mark(pointSize: 32, color: Color.primary.opacity(0.28))
        }
    }

    private func still(_ image: NSImage, dimmed: Bool) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: PanelMetrics.blockWidth, height: PanelMetrics.previewHeight)
            .grayscale(dimmed ? 1 : 0)
            .opacity(dimmed ? 0.22 : 1)
            .accessibilityHidden(true)
            .transition(.opacity)
            .animation(reduceMotion ? nil : .easeOut(duration: PanelMetrics.fadeSeconds), value: previewImage != nil)
    }

    private func placeholder(
        symbol: String, symbolSize: CGFloat, message: String?, help: String?, settings: PanelButton?
    ) -> some View {
        VStack(spacing: 6) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: symbolSize))
                    .foregroundStyle(PanelSurface.secondaryText)
                    .accessibilityHidden(true)
                if let message {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(PanelSurface.secondaryText)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(help ?? message ?? "")
            .modifier(PanelHelp(text: help))
            if let settings {
                Button(settings.title) { onAction(settings.action) }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(
                        Color(nsColor: .tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: PanelMetrics.radiusControl, style: .continuous))
                    .accessibilityLabel(settings.accessibilityLabel)
            }
        }
    }

    // MARK: - Caption, cells, hero

    @ViewBuilder
    private var caption: some View {
        if let caption = content.caption {
            VStack(alignment: .leading, spacing: 2) {
                Text(caption.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentTransition(.opacity)
                    .frame(
                        width: content.clear == nil ? PanelMetrics.blockWidth : PanelMetrics.clearTitleWidth,
                        alignment: .leading)
                Text(caption.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(PanelSurface.secondaryText)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            .frame(width: PanelMetrics.blockWidth, height: PanelMetrics.captionHeight, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(caption.accessibilityLabel)
            .modifier(PanelHelp(text: caption.help))
            .overlay(alignment: .topLeading) {
                if let clear = content.clear {
                    PanelClearButton(button: clear, forcedHover: showsClearHover, onAction: onAction)
                        .offset(
                            x: PanelMetrics.clearHitX - PanelMetrics.margin,
                            y: (PanelMetrics.titleLineHeight - PanelMetrics.iconButton) / 2)
                }
            }
        }
    }

    @ViewBuilder
    private var cells: some View {
        if let choices = content.choices {
            HStack(spacing: PanelMetrics.cellGap) {
                popup(
                    choices.size, value: choices.sizeValue, width: PanelMetrics.sizeCellWidth)
                popup(
                    choices.frameRate, value: choices.frameRateValue, width: PanelMetrics.frameRateCellWidth)
            }
            .frame(width: PanelMetrics.blockWidth, height: PanelMetrics.cellHeight, alignment: .leading)
        }
    }

    private func popup(_ submenu: SubmenuModel, value: String, width: CGFloat) -> some View {
        Menu {
            ForEach(Array(submenu.entries.enumerated()), id: \.offset) { _, entry in
                PanelMenuEntry(entry: entry, onAction: onAction)
            }
        } label: {
            HStack(spacing: 0) {
                Text(submenu.title)
                    .foregroundStyle(PanelSurface.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 4)
                Text(value)
                    .foregroundStyle(PanelSurface.primaryText)
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(PanelSurface.secondaryText)
                    .padding(.leading, 6)
                    .accessibilityHidden(true)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .frame(width: width, height: PanelMetrics.cellHeight)
            .background(
                palette.cellFill.color,
                in: RoundedRectangle(cornerRadius: PanelMetrics.radiusControl, style: .continuous)
            )
            .overlay {
                if let hairline = palette.cellHairline {
                    RoundedRectangle(cornerRadius: PanelMetrics.radiusControl, style: .continuous)
                        .strokeBorder(hairline.color, lineWidth: PanelSurface.pixel(displayScale: displayScale))
                }
            }
        }
        // `.borderlessButton` reduces a custom label to its first text, which loses the value and the fill.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(width: width, height: PanelMetrics.cellHeight)
        .accessibilityLabel(UIStrings.Panel.popupLabel(title: submenu.title, value: value))
    }

    @ViewBuilder
    private var hero: some View {
        if let button = content.hero {
            Button {
                onAction(button.action)
            } label: {
                HStack(spacing: PanelMetrics.heroIconGap) {
                    heroMark(button)
                    HStack(spacing: PanelMetrics.heroTimerGap) {
                        Text(button.title)
                            .lineLimit(1)
                        if let trailing = button.trailing {
                            Text(trailing)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(heroForeground(button))
                .padding(.horizontal, 12)
                .frame(width: PanelMetrics.blockWidth, height: PanelMetrics.heroHeight)
            }
            .buttonStyle(PanelHeroButtonStyle(fill: heroFill(button)))
            .disabled(!button.enabled)
            .focused($heroFocused)
            .accessibilityFocused($heroAccessibilityFocused)
            .accessibilityLabel(button.accessibilityLabel)
            .modifier(PanelHelp(text: button.help))
            .modifier(PanelHint(text: button.help))
            .modifier(PanelShortcut(button: button))
        }
    }

    @ViewBuilder
    private func heroMark(_ button: PanelButton) -> some View {
        switch button.role {
        case .stop:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(.white)
                .frame(width: 11, height: 11)
                .accessibilityHidden(true)
        case .pick:
            Image(systemName: button.symbol ?? PanelSymbol.pickWindow)
                .font(.system(size: 16, weight: .semibold))
                .accessibilityHidden(true)
        default:
            mark(pointSize: 20, color: heroForeground(button))
        }
    }

    private func heroFill(_ button: PanelButton) -> Color {
        guard button.enabled else { return palette.wellFill.color }
        switch button.role {
        case .stop: return PanelSurface.stop
        case .record, .pick: return PanelSurface.accent
        default: return palette.wellFill.color
        }
    }

    private func heroForeground(_ button: PanelButton) -> Color {
        button.enabled ? .white : PanelSurface.tertiaryText
    }

    /// The V1 mark in `color`: white on Record in both appearances, tertiary when Record is disabled.
    private func mark(pointSize: CGFloat, color: Color) -> some View {
        PanelBrandMark(pointSize: pointSize, color: color)
    }

    private var origin: some View {
        Text(content.origin ?? "")
            .font(.system(size: 12))
            .foregroundStyle(PanelSurface.secondaryText)
            .lineLimit(1)
            .frame(width: PanelMetrics.blockWidth, height: PanelMetrics.originHeight)
            .accessibilityLabel(content.origin ?? "")
    }

    private var separator: some View {
        // From the top of the block, so the one-pixel line lands on a pixel instead of straddling two.
        Rectangle()
            .fill(palette.separator.color)
            .frame(width: PanelMetrics.blockWidth, height: PanelSurface.pixel(displayScale: displayScale))
            .padding(.leading, PanelMetrics.margin)
            .padding(.top, (PanelMetrics.separator - PanelMetrics.separatorLine) / 2)
            .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Shared with the control bar

/// One row of a Size or Frame Rate pop-up.
struct PanelMenuEntry: View {
    var entry: MenuEntry
    var onAction: (MenuAction) -> Void

    var body: some View {
        switch entry {
        case .separator:
            Divider()
        case .item(let item):
            Button {
                if let action = item.action { onAction(action) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .opacity(item.checked ? 1 : 0)
                        .accessibilityHidden(true)
                    Text(item.title)
                    if let trailing = item.trailing {
                        Spacer(minLength: 12)
                        Text(trailing)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(!item.enabled)
            .modifier(PanelHelp(text: item.toolTip))
        default:
            EmptyView()
        }
    }
}

/// The Skreenrek mark in one colour.
struct PanelBrandMark: View {
    var pointSize: CGFloat
    var color: Color

    var body: some View {
        Image(nsImage: BrandStatusGlyph.templateLayer(.idle, style: .mono))
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(color)
            .frame(width: pointSize, height: pointSize)
            .accessibilityHidden(true)
    }
}

// MARK: - Rows

/// A 28 pt row. The highlight runs x 8–292, the icon column starts at x 16, and the title at x 40.
private struct PanelRowButton: View {
    var button: PanelButton
    var onAction: (MenuAction) -> Void

    var body: some View {
        Button {
            onAction(button.action)
        } label: {
            HStack(spacing: PanelMetrics.iconGap) {
                if let symbol = button.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13))
                        .frame(width: PanelMetrics.iconColumn, height: PanelMetrics.iconColumn)
                        .foregroundStyle(button.tint == .accent ? PanelSurface.accent : PanelSurface.secondaryText)
                        .accessibilityHidden(true)
                } else {
                    Color.clear.frame(width: PanelMetrics.iconColumn, height: PanelMetrics.iconColumn)
                }
                Text(button.title)
                    .font(.system(size: 13))
                    .foregroundStyle(button.enabled ? PanelSurface.primaryText : PanelSurface.tertiaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let trailing = button.trailing {
                    Text(trailing)
                        .font(.system(size: 13))
                        .foregroundStyle(PanelSurface.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, PanelMetrics.rowPadding)
            .frame(width: PanelMetrics.rowHighlightWidth, height: PanelMetrics.rowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PanelRowButtonStyle())
        .disabled(!button.enabled)
        .accessibilityLabel(button.accessibilityLabel)
        .modifier(PanelHelp(text: button.help))
        .modifier(PanelHint(text: button.help))
        .modifier(PanelShortcut(button: button))
    }
}

/// A row with its switch at the trailing content edge, x 284.
private struct PanelToggleRow: View {
    var toggle: PanelToggle
    var onAction: (MenuAction) -> Void

    var body: some View {
        HStack(spacing: PanelMetrics.iconGap) {
            Image(systemName: toggle.symbol)
                .font(.system(size: 13))
                .frame(width: PanelMetrics.iconColumn, height: PanelMetrics.iconColumn)
                .foregroundStyle(PanelSurface.secondaryText)
                .accessibilityHidden(true)
            Text(toggle.title)
                .font(.system(size: 13))
                .lineLimit(1)
                .accessibilityHidden(true)
            Spacer(minLength: 4)
            TrailingSwitch(
                title: toggle.accessibilityLabel,
                isOn: Binding(get: { toggle.isOn }, set: { _ in onAction(toggle.action) }))
        }
        .padding(.horizontal, PanelMetrics.rowPadding)
        .frame(width: PanelMetrics.rowHighlightWidth, height: PanelMetrics.rowHeight, alignment: .leading)
    }
}

/// The Last Clip row. The main area opens the clip. The icon buttons never do.
private struct PanelClipRow: View {
    var clip: PanelLastClip
    var image: NSImage?
    var onAction: (MenuAction) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            if clip.canOpen {
                Button {
                    onAction(clip.open)
                } label: {
                    mainLabel
                }
                .buttonStyle(PanelRowButtonStyle())
                .accessibilityLabel(clip.accessibilityLabel)
                .modifier(PanelHelp(text: clip.help))
            } else {
                mainLabel
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(clip.accessibilityLabel)
            }
            HStack(spacing: 0) {
                ForEach(Array(clip.actions.enumerated()), id: \.offset) { _, button in
                    PanelIconButton(button: button, onAction: onAction)
                }
            }
        }
        // The last hit area overhangs the content edge, so its glyph ends at x 284.
        .padding(.trailing, PanelMetrics.rowPadding - PanelMetrics.iconButtonOverhang)
        .frame(width: PanelMetrics.rowHighlightWidth, height: PanelMetrics.clipRowHeight, alignment: .leading)
    }

    private var mainLabel: some View {
        HStack(spacing: PanelMetrics.iconGap) {
            thumbnail
            VStack(alignment: .leading, spacing: 1) {
                Text(clip.title)
                    .font(.system(size: 13))
                    .foregroundStyle(clip.dimmed ? PanelSurface.secondaryText : PanelSurface.primaryText)
                    .lineLimit(1)
                Text(clip.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(PanelSurface.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.leading, PanelMetrics.rowPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PanelMetrics.radiusChip, style: .continuous)
                .fill(PanelPalette(scheme).wellFill.color)
            if clip.fileExists, let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: PanelMetrics.thumbWidth, height: PanelMetrics.thumbHeight)
                    .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.radiusChip, style: .continuous))
                ClipThumbOverlay()
            } else if !clip.fileExists {
                Image(systemName: "film")
                    .font(.system(size: 14))
                    .foregroundStyle(PanelSurface.tertiaryText)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: PanelMetrics.thumbWidth, height: PanelMetrics.thumbHeight)
        .overlay(
            RoundedRectangle(cornerRadius: PanelMetrics.radiusChip, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: PanelMetrics.hairline)
        )
        .accessibilityHidden(true)
    }
}

/// Darkens the thumbnail and draws the play glyph while the main area is hovered or pressed.
private struct ClipThumbOverlay: View {
    @Environment(\.clipHighlighted) private var highlighted

    var body: some View {
        ZStack {
            if highlighted {
                Color.black.opacity(0.22)
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.radiusChip, style: .continuous))
        .allowsHitTesting(false)
    }
}

/// The row highlight, x 8–292: hover and pressed tones, and the Last Clip thumbnail's overlay.
private struct PanelRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PanelRowButtonBody(configuration: configuration)
    }
}

private struct PanelRowButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let interaction = PanelInteraction(
            enabled: isEnabled, hovering: hovering, pressed: configuration.isPressed)
        configuration.label
            .environment(\.clipHighlighted, interaction != .rest)
            .background(
                RoundedRectangle(cornerRadius: PanelMetrics.radiusControl, style: .continuous)
                    .fill(PanelPalette(scheme).rowColor(interaction))
            )
            .onHover { hovering = $0 }
    }
}

/// Pick Window…, Record and Stop Recording: a solid fill that darkens on hover and press.
struct PanelHeroButtonStyle: ButtonStyle {
    var fill: Color

    func makeBody(configuration: Configuration) -> some View {
        PanelHeroButtonBody(configuration: configuration, fill: fill)
    }
}

private struct PanelHeroButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let fill: Color
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PanelMetrics.radiusControl, style: .continuous)
        let interaction = PanelInteraction(
            enabled: isEnabled, hovering: hovering, pressed: configuration.isPressed)
        configuration.label
            .background {
                shape.fill(fill)
                    .overlay(shape.fill(Color.black.opacity(PanelSurface.heroDarkening(interaction))))
            }
            .contentShape(shape)
            .onHover { hovering = $0 }
    }
}

private struct PanelIconButton: View {
    var button: PanelButton
    var onAction: (MenuAction) -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button {
            onAction(button.action)
        } label: {
            Image(systemName: button.symbol ?? "circle")
                .font(.system(size: 13))
                .frame(width: PanelMetrics.iconGlyph, height: PanelMetrics.iconGlyph)
                .frame(width: PanelMetrics.iconButton, height: PanelMetrics.iconButton)
                .foregroundStyle(button.enabled ? PanelSurface.primaryText : PanelSurface.tertiaryText)
                .background(
                    RoundedRectangle(cornerRadius: PanelMetrics.radiusChip, style: .continuous)
                        .fill(PanelPalette(scheme).rowColor(hovering && button.enabled ? .hover : .rest))
                )
        }
        .buttonStyle(.plain)
        .disabled(!button.enabled)
        .onHover { hovering = button.enabled && $0 }
        .accessibilityLabel(button.accessibilityLabel)
        .modifier(PanelHelp(text: button.title))
    }
}

/// Clear, at the end of the title line: a 16 pt glyph in a 24 pt hit area.
private struct PanelClearButton: View {
    var button: PanelButton
    var forcedHover: Bool
    var onAction: (MenuAction) -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    private var highlighted: Bool { hovering || forcedHover }

    var body: some View {
        Button {
            onAction(button.action)
        } label: {
            Image(systemName: button.symbol ?? PanelSymbol.clearWindow)
                .font(.system(size: PanelMetrics.iconGlyph))
                .foregroundStyle(highlighted ? PanelSurface.primaryText : PanelSurface.secondaryText)
                .frame(width: PanelMetrics.iconButton, height: PanelMetrics.iconButton)
                .background(
                    RoundedRectangle(cornerRadius: PanelMetrics.radiusChip, style: .continuous)
                        .fill(PanelPalette(scheme).rowColor(highlighted ? .hover : .rest))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(button.accessibilityLabel)
        .modifier(PanelHelp(text: button.help))
    }
}

// MARK: - Chrome

struct PanelHelp: ViewModifier {
    var text: String?

    func body(content: Content) -> some View {
        if let text, !text.isEmpty {
            content.help(text)
        } else {
            content
        }
    }
}

struct PanelHint: ViewModifier {
    var text: String?

    func body(content: Content) -> some View {
        if let text, !text.isEmpty {
            content.accessibilityHint(text)
        } else {
            content
        }
    }
}

private struct PanelShortcut: ViewModifier {
    var button: PanelButton

    func body(content: Content) -> some View {
        if button.isDefault {
            content.keyboardShortcut(.defaultAction)
        } else if let shortcut = button.shortcut, shortcut != .stop {
            content.keyboardShortcut(KeyEquivalent(Character(shortcut.key)), modifiers: .command)
        } else {
            content
        }
    }
}

private struct ClipHighlightKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    fileprivate var clipHighlighted: Bool {
        get { self[ClipHighlightKey.self] }
        set { self[ClipHighlightKey.self] = newValue }
    }
}
