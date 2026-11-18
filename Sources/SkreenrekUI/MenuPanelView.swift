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
    var showsMaterial: Bool
    var onAction: (MenuAction) -> Void
    var onClose: () -> Void = {}

    @Environment(\.colorSchemeContrast) private var contrast

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
        .background { background }
        .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.radiusPanel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PanelMetrics.radiusPanel, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: contrast == .increased ? 1 : PanelMetrics.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(UIStrings.productName)
        .onExitCommand(perform: onClose)
    }

    private var stack: some View {
        VStack(spacing: 0) {
            ForEach(Array(PanelMetrics.blocks(for: content).enumerated()), id: \.offset) { _, block in
                blockView(block)
                    .frame(width: PanelMetrics.width, height: PanelMetrics.height(of: block), alignment: .leading)
            }
        }
    }

    private var background: some View {
        Group {
            if showsMaterial {
                MenuPanelMaterial()
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: PanelBlock) -> some View {
        switch block {
        case .space:
            Color.clear
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
            PanelRowButton(button: button, onAction: onAction).padding(.leading, PanelMetrics.margin)
        case .toggle(let toggle):
            PanelToggleRow(toggle: toggle, onAction: onAction).padding(.leading, PanelMetrics.margin)
        case .clip:
            if let clip = content.lastClip {
                PanelClipRow(clip: clip, image: clipImage, onAction: onAction).padding(.leading, PanelMetrics.margin)
            }
        case .separator:
            separator
        }
    }

    // MARK: - Preview

    private var previewBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PanelMetrics.radiusControl, style: .continuous)
                .fill(Color(nsColor: .quaternarySystemFill))
            previewContent
            RoundedRectangle(cornerRadius: PanelMetrics.radiusControl, style: .continuous)
                .strokeBorder(
                    content.preview.framed ? Color(nsColor: .systemRed) : Color(nsColor: .separatorColor),
                    lineWidth: content.preview.framed
                        ? PanelMetrics.recordingStroke
                        : (contrast == .increased ? 1 : PanelMetrics.hairline))
        }
        .frame(width: PanelMetrics.blockWidth, height: PanelMetrics.previewHeight)
        .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.radiusControl, style: .continuous))
        .accessibilityElement(children: previewDecorative ? .ignore : .contain)
        .accessibilityHidden(previewDecorative)
    }

    private var previewDecorative: Bool {
        switch content.preview.phase {
        case .failed, .permissionMissing: false
        default: true
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch content.preview.phase {
        case .ready:
            if let previewImage {
                still(previewImage, dimmed: false)
            }
        case .windowClosed:
            ZStack {
                if let previewImage {
                    still(previewImage, dimmed: true)
                    Color(nsColor: .windowBackgroundColor).opacity(0.70)
                }
                Image(systemName: "xmark.rectangle")
                    .font(.system(size: 24))
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)
            }
        case .loading:
            if content.preview.showsSpinner {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            }
        case .failed:
            placeholder(
                symbol: "rectangle.slash", symbolSize: 20, message: content.preview.message,
                help: content.preview.messageHelp, settings: nil)
        case .permissionMissing:
            placeholder(
                symbol: "lock", symbolSize: 20, message: content.preview.message, help: content.preview.messageHelp,
                settings: content.preview.settings)
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
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                if let message {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
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

    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(content.caption.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Text(content.caption.detail)
                .font(.system(size: 12, weight: content.caption.detail == UIStrings.Panel.windowClosed ? .semibold : .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: PanelMetrics.blockWidth, height: PanelMetrics.captionHeight, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.caption.accessibilityLabel)
        .modifier(PanelHelp(text: content.caption.help))
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
                menuEntry(entry)
            }
        } label: {
            HStack(spacing: 0) {
                Text(submenu.title)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 4)
                Text(value)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
                    .accessibilityHidden(true)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .frame(width: width, height: PanelMetrics.cellHeight)
            .background(
                Color(nsColor: .tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: PanelMetrics.radiusControl, style: .continuous))
        }
        // `.borderlessButton` reduces a custom label to its first text, which loses the value and the fill.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(width: width, height: PanelMetrics.cellHeight)
        .accessibilityLabel(UIStrings.Panel.popupLabel(title: submenu.title, value: value))
    }

    @ViewBuilder
    private func menuEntry(_ entry: MenuEntry) -> some View {
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

    @ViewBuilder
    private var hero: some View {
        if let hero = content.hero {
            HStack(spacing: PanelMetrics.heroGap) {
                ForEach(Array(hero.buttons.enumerated()), id: \.offset) { index, button in
                    heroButton(button)
                        .frame(
                            width: hero.buttons.count > 1 && index == hero.buttons.count - 1
                                ? hero.trailingWidth : nil
                        )
                        .frame(maxWidth: index == 0 ? .infinity : nil)
                }
            }
            .frame(width: PanelMetrics.blockWidth, height: PanelMetrics.heroHeight, alignment: .leading)
        }
    }

    private func heroButton(_ button: PanelButton) -> some View {
        Button {
            onAction(button.action)
        } label: {
            HStack(spacing: 6) {
                heroMark(button)
                Text(button.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if let trailing = button.trailing {
                    Spacer(minLength: 4)
                    Text(trailing)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .foregroundStyle(heroForeground(button))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: PanelMetrics.heroHeight, maxHeight: PanelMetrics.heroHeight)
            .background(heroFill(button), in: RoundedRectangle(cornerRadius: PanelMetrics.radiusControl, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!button.enabled)
        .accessibilityLabel(button.accessibilityLabel)
        .modifier(PanelHelp(text: button.help))
        .modifier(PanelHint(text: button.help))
        .modifier(PanelShortcut(button: button))
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
        guard button.enabled else { return Color(nsColor: .quaternarySystemFill) }
        switch button.role {
        case .stop: return Color(nsColor: .systemRed)
        case .record, .pick: return Color.accentColor
        default: return Color(nsColor: .quaternarySystemFill)
        }
    }

    private func heroForeground(_ button: PanelButton) -> Color {
        button.enabled ? .white : Color(nsColor: .tertiaryLabelColor)
    }

    /// The V1 mark in `color`: white on Record in both appearances, tertiary when Record is disabled.
    private func mark(pointSize: CGFloat, color: Color) -> some View {
        Image(nsImage: BrandStatusGlyph.templateLayer(.idle, style: .mono))
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(color)
            .frame(width: pointSize, height: pointSize)
            .accessibilityHidden(true)
    }

    private var origin: some View {
        Text(content.origin ?? "")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(width: PanelMetrics.blockWidth, height: PanelMetrics.originHeight)
            .accessibilityLabel(content.origin ?? "")
    }

    private var separator: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: PanelMetrics.blockWidth - PanelMetrics.separatorInset * 2, height: PanelMetrics.separatorLine)
            .padding(.leading, PanelMetrics.margin + PanelMetrics.separatorInset)
            .frame(maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Rows

/// A 28 pt row. The icon sits 8 pt into the 268 pt row (x = 24), and the title 16 pt after that (x = 48).
private struct PanelRowButton: View {
    var button: PanelButton
    var onAction: (MenuAction) -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button {
            onAction(button.action)
        } label: {
            HStack(spacing: PanelMetrics.iconGap) {
                if let symbol = button.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13))
                        .frame(width: PanelMetrics.iconColumn, height: PanelMetrics.iconColumn)
                        .foregroundStyle(button.tint == .accent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                        .accessibilityHidden(true)
                } else {
                    Color.clear.frame(width: PanelMetrics.iconColumn, height: PanelMetrics.iconColumn)
                }
                Text(button.title)
                    .font(.system(size: 13))
                    .foregroundStyle(button.enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let trailing = button.trailing {
                    Text(trailing)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, PanelMetrics.rowPadding)
            .frame(width: PanelMetrics.blockWidth, height: PanelMetrics.rowHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: PanelMetrics.radiusControl, style: .continuous)
                    .fill(hovering && button.enabled ? rowHover(scheme) : .clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(!button.enabled)
        .onHover { hovering = button.enabled && $0 }
        .accessibilityLabel(button.accessibilityLabel)
        .modifier(PanelHelp(text: button.help))
        .modifier(PanelHint(text: button.help))
        .modifier(PanelShortcut(button: button))
    }
}

private struct PanelToggleRow: View {
    var toggle: PanelToggle
    var onAction: (MenuAction) -> Void

    var body: some View {
        Toggle(
            isOn: Binding(
                get: { toggle.isOn },
                set: { _ in onAction(toggle.action) }
            )
        ) {
            HStack(spacing: PanelMetrics.iconGap) {
                Image(systemName: toggle.symbol)
                    .font(.system(size: 13))
                    .frame(width: PanelMetrics.iconColumn, height: PanelMetrics.iconColumn)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(toggle.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
            }
        }
        .modifier(SettingsSwitch())
        .padding(.horizontal, PanelMetrics.rowPadding)
        .frame(width: PanelMetrics.blockWidth, height: PanelMetrics.rowHeight, alignment: .leading)
        .accessibilityLabel(toggle.accessibilityLabel)
    }
}

/// The Last Clip row. The main area opens the clip. The icon buttons never do.
private struct PanelClipRow: View {
    var clip: PanelLastClip
    var image: NSImage?
    var onAction: (MenuAction) -> Void

    var body: some View {
        HStack(spacing: 0) {
            if clip.canOpen {
                Button {
                    onAction(clip.open)
                } label: {
                    mainLabel
                }
                .buttonStyle(ClipMainButtonStyle())
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
        .padding(.horizontal, PanelMetrics.rowPadding)
        .frame(width: PanelMetrics.blockWidth, height: PanelMetrics.clipRowHeight, alignment: .leading)
    }

    private var mainLabel: some View {
        HStack(spacing: PanelMetrics.iconGap) {
            thumbnail
            VStack(alignment: .leading, spacing: 1) {
                Text(clip.title)
                    .font(.system(size: 13))
                    .foregroundStyle(clip.dimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                Text(clip.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PanelMetrics.radiusChip, style: .continuous)
                .fill(Color(nsColor: .quaternarySystemFill))
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
                    .foregroundStyle(.tertiary)
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

private struct ClipMainButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        ClipMainBody(configuration: configuration, scheme: scheme)
    }
}

private struct ClipMainBody: View {
    let configuration: ButtonStyle.Configuration
    let scheme: ColorScheme
    @State private var hovering = false

    var body: some View {
        configuration.label
            .environment(\.clipHighlighted, hovering || configuration.isPressed)
            .background(
                RoundedRectangle(cornerRadius: PanelMetrics.radiusControl, style: .continuous)
                    .fill(configuration.isPressed ? rowPressed(scheme) : (hovering ? rowHover(scheme) : .clear))
            )
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
                .frame(width: PanelMetrics.iconButton, height: PanelMetrics.iconButton)
                .foregroundStyle(button.enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .background(
                    RoundedRectangle(cornerRadius: PanelMetrics.radiusChip, style: .continuous)
                        .fill(hovering && button.enabled ? rowHover(scheme) : .clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(!button.enabled)
        .onHover { hovering = button.enabled && $0 }
        .accessibilityLabel(button.accessibilityLabel)
        .modifier(PanelHelp(text: button.title))
    }
}

// MARK: - Chrome

private struct MenuPanelMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct PanelHelp: ViewModifier {
    var text: String?

    func body(content: Content) -> some View {
        if let text, !text.isEmpty {
            content.help(text)
        } else {
            content
        }
    }
}

private struct PanelHint: ViewModifier {
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

private func rowHover(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
}

private func rowPressed(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.11)
}
