import AppKit
import Observation
import SkreenrekCore
import SwiftUI

/// Updated in place, so a timer tick or a new size keeps the hosting view and any hover.
@MainActor
@Observable
final class ControlBarPresentation {
    var content: ControlBarContent
    /// Draws the Size pop-up as it looks with its menu open, for `render-ui`.
    var showsMenuOpen = false

    init(content: ControlBarContent) {
        self.content = content
    }
}

/// The bar: Size, the readout, Record and Clear, or the timer, the readout, Stop and Clear, or Saved with its file
/// buttons. Every fill and hairline comes from the solid panel's tokens. There is no material here.
struct ControlBarView: View {
    var presentation: ControlBarPresentation
    var onAction: (MenuAction) -> Void
    var onHover: (Bool) -> Void = { _ in }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale

    private var content: ControlBarContent { presentation.content }
    private var palette: PanelPalette { PanelPalette(scheme) }
    private var barShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PanelMetrics.radiusPanel, style: .continuous)
    }

    var body: some View {
        HStack(spacing: ControlBarMetrics.slotGap) {
            leadingArea
            if let files = content.files, files.placement == .action {
                ControlBarFileButtons(files: files, gap: ControlBarMetrics.compactFileButtonGap, onAction: onAction)
                    .frame(width: ControlBarMetrics.actionWidth, height: ControlBarMetrics.controlHeight)
            } else {
                ControlBarActionButton(action: content.action, onAction: onAction)
            }
            ControlBarClearButton(clear: content.clear, onAction: onAction)
        }
        // Saving to Saved and Saved to Idle crossfade in place: nothing moves. Reduce Motion swaps in one frame.
        .animation(content.crossfade > 0 ? .easeInOut(duration: content.crossfade) : nil, value: content.phase)
        .padding(.horizontal, ControlBarMetrics.padding)
        .frame(width: content.width.points, height: ControlBarMetrics.height)
        .background(palette.fill.color)
        .clipShape(barShape)
        .overlay {
            barShape.strokeBorder(
                palette.hairline(increaseContrast: contrast == .increased).color,
                lineWidth: PanelSurface.pixel(displayScale: displayScale))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(content.groupLabel)
        // The window is never key, so the first click has to reach the controls.
        .allowsWindowActivationEvents(true)
        .onHover(perform: onHover)
    }

    /// Everything left of Record.
    @ViewBuilder
    private var leadingArea: some View {
        switch content.leading {
        case .size(let control):
            firstSlot {
                ControlBarSizeButton(
                    control: control, showsMenuOpen: presentation.showsMenuOpen, onAction: onAction)
            }
            readoutSlot
        case .timer(let time):
            firstSlot {
                HStack(spacing: ControlBarMetrics.statusGap) {
                    Circle()
                        .fill(PanelSurface.stop)
                        .frame(width: ControlBarMetrics.statusDot, height: ControlBarMetrics.statusDot)
                    Text(time)
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(PanelSurface.primaryText)
                        .lineLimit(1)
                }
                .padding(.leading, ControlBarMetrics.slotInset)
                .accessibilityHidden(true)
            }
            readoutSlot
        case .saving(let spinner, let text, let showsText):
            HStack(spacing: ControlBarMetrics.labelGap) {
                savingIndicator(spinner: spinner)
                    .frame(width: ControlBarMetrics.markSize, height: ControlBarMetrics.markSize)
                if showsText {
                    Text(text)
                        .font(.system(size: 12))
                        .foregroundStyle(PanelSurface.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(width: content.width.leadingAreaWidth, height: ControlBarMetrics.controlHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .modifier(PanelHelp(text: showsText ? nil : text))
        case .saved(let saved):
            HStack(spacing: 0) {
                savedStatus(saved)
                Spacer(minLength: 0)
                if let files = saved.files {
                    ControlBarFileButtons(files: files, gap: ControlBarMetrics.fileButtonGap, onAction: onAction)
                }
            }
            .frame(width: content.width.leadingAreaWidth, height: ControlBarMetrics.controlHeight)
        }
    }

    /// The green check at bar x 14 and the title at x 36.
    private func savedStatus(_ saved: ControlBarSaved) -> some View {
        HStack(spacing: ControlBarMetrics.labelGap) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: ControlBarMetrics.markSize))
                .foregroundStyle(Color(nsColor: .systemGreen))
                .frame(width: ControlBarMetrics.markSize, height: ControlBarMetrics.markSize)
            // Monospaced digits keep the duration's width steady; the word has none.
            Text(saved.title)
                .monospacedDigit()
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PanelSurface.primaryText)
                .lineLimit(1)
        }
        .padding(.leading, ControlBarMetrics.slotInset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(saved.accessibilityLabel)
        .modifier(PanelHelp(text: saved.help))
    }


    private func firstSlot<Content: View>(@ViewBuilder _ slot: () -> Content) -> some View {
        slot()
            .frame(
                width: ControlBarMetrics.sizeSlotWidth, height: ControlBarMetrics.controlHeight, alignment: .leading)
    }

    @ViewBuilder
    private var readoutSlot: some View {
        if let readout = content.readout {
            readoutView(readout)
                .frame(width: ControlBarMetrics.readoutWidth, height: ControlBarMetrics.readoutHeight)
        }
    }

    @ViewBuilder
    private func savingIndicator(spinner: Bool) -> some View {
        if spinner {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: ControlBarMetrics.markSize))
                .foregroundStyle(PanelSurface.secondaryText)
        }
    }

    private func readoutView(_ readout: ControlBarReadout) -> some View {
        HStack(spacing: ControlBarMetrics.warningGap) {
            if readout.warning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: ControlBarMetrics.warningSize))
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .accessibilityHidden(true)
            }
            Text(readout.text)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(PanelSurface.secondaryText)
                .lineLimit(1)
        }
        .opacity(readout.dimmed ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(readout.accessibilityLabel)
        .modifier(PanelHint(text: readout.warning ? readout.help : nil))
        .modifier(PanelHelp(text: readout.help))
    }
}

/// Puts a tooltip over a disabled control. SwiftUI drops `.help` on the control itself.
private struct ControlBarDisabledHelp: ViewModifier {
    var text: String?

    func body(content: Content) -> some View {
        content.overlay {
            if let text {
                Color.clear
                    .contentShape(Rectangle())
                    .help(text)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// The value-only Size pop-up, on the panel's cell fill.
private struct ControlBarSizeButton: View {
    var control: ControlBarSizeControl
    var showsMenuOpen: Bool
    var onAction: (MenuAction) -> Void

    var body: some View {
        Menu {
            PanelPopupEntries(entries: control.entries, onAction: onAction)
        } label: {
            HStack(spacing: 0) {
                Text(control.value)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(control.enabled ? PanelSurface.primaryText : PanelSurface.tertiaryText)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(control.enabled ? PanelSurface.secondaryText : PanelSurface.tertiaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, ControlBarMetrics.slotInset)
            .frame(width: ControlBarMetrics.sizeSlotWidth, height: ControlBarMetrics.controlHeight)
            .contentShape(Rectangle())
        }
        // `.borderlessButton` reduces a custom label to its first text, as in the panel's cells.
        .menuStyle(.button)
        .buttonStyle(ControlBarCellButtonStyle(forcePressed: showsMenuOpen))
        .menuIndicator(.hidden)
        .disabled(!control.enabled)
        .frame(width: ControlBarMetrics.sizeSlotWidth, height: ControlBarMetrics.controlHeight)
        .accessibilityLabel(control.accessibilityLabel)
        .modifier(PanelHint(text: control.enabled ? nil : control.help))
        .modifier(PanelHelp(text: control.enabled ? control.help : nil))
        .modifier(ControlBarDisabledHelp(text: control.enabled ? nil : control.help))
    }
}

/// Record or Stop. A disabled Record keeps its slot, on the cell fill.
private struct ControlBarActionButton: View {
    var action: ControlBarAction
    var onAction: (MenuAction) -> Void

    private var isStop: Bool { action.style == .stop }
    private var enabled: Bool { action.action != nil }
    private var foreground: Color { enabled ? .white : PanelSurface.tertiaryText }

    var body: some View {
        Button {
            if let menuAction = action.action { onAction(menuAction) }
        } label: {
            HStack(spacing: ControlBarMetrics.labelGap) {
                glyph
                Text(isStop ? UIStrings.Brand.stop : UIStrings.Brand.record)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            .frame(width: ControlBarMetrics.actionWidth, height: ControlBarMetrics.controlHeight)
            .contentShape(Rectangle())
        }
        .modifier(ControlBarActionStyle(style: action.style))
        .disabled(!enabled)
        .accessibilityLabel(action.accessibilityLabel)
        .modifier(PanelHint(text: action.accessibilityHint))
        .modifier(PanelHelp(text: enabled ? action.help : nil))
        .modifier(ControlBarDisabledHelp(text: enabled ? nil : action.help))
    }

    @ViewBuilder
    private var glyph: some View {
        switch action.style {
        case .stop:
            RoundedRectangle(cornerRadius: ControlBarMetrics.stopSquareRadius, style: .continuous)
                .fill(.white)
                .frame(width: ControlBarMetrics.stopSquare, height: ControlBarMetrics.stopSquare)
                .accessibilityHidden(true)
        case .recordBlocked:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: ControlBarMetrics.markSize))
                .foregroundStyle(Color(nsColor: .systemOrange))
                .frame(width: ControlBarMetrics.markSize, height: ControlBarMetrics.markSize)
                .accessibilityHidden(true)
        case .record, .recordBusy:
            PanelBrandMark(pointSize: ControlBarMetrics.markSize, color: foreground)
        }
    }
}

/// Show in Finder and Copy File Path on Saved: 24 pt icon buttons with no fill at rest and the panel's hover and
/// pressed tones.
private struct ControlBarFileButtons: View {
    var files: ControlBarFiles
    var gap: CGFloat
    var onAction: (MenuAction) -> Void

    var body: some View {
        HStack(spacing: gap) {
            button("folder", help: files.revealHelp, label: files.revealLabel, action: .showInFinder(path: files.path))
            button(files.copyGlyph, help: files.copyHelp, label: files.copyLabel, action: .copyFilePath(path: files.path))
        }
    }

    private func button(_ symbol: String, help: String, label: String, action: MenuAction) -> some View {
        Button {
            onAction(action)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: ControlBarMetrics.fileButton, height: ControlBarMetrics.fileButton)
        }
        .buttonStyle(
            PanelIconButtonStyle(rest: PanelSurface.secondaryText, active: PanelSurface.primaryText, forcedState: nil)
        )
        .accessibilityLabel(label)
        .modifier(PanelHelp(text: help))
    }
}

/// Forgets the window. Dimmed while the window can't be forgotten, and hidden while recording and saving. Its slot
/// stays either way, so the bar never reflows.
private struct ControlBarClearButton: View {
    var clear: ControlBarClear
    var onAction: (MenuAction) -> Void

    var body: some View {
        Button {
            if let action = clear.action { onAction(action) }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: ControlBarMetrics.clearGlyph, weight: .semibold))
                .foregroundStyle(clear.enabled ? PanelSurface.secondaryText : PanelSurface.tertiaryText)
                .frame(width: ControlBarMetrics.clearWidth, height: ControlBarMetrics.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(ControlBarCellButtonStyle())
        .disabled(!clear.enabled || !clear.visible)
        .accessibilityLabel(clear.accessibilityLabel)
        .modifier(PanelHelp(text: clear.enabled && clear.visible ? clear.help : nil))
        .modifier(ControlBarDisabledHelp(text: clear.enabled || !clear.visible ? nil : clear.help))
        .opacity(clear.visible ? 1 : 0)
        .allowsHitTesting(clear.visible)
        .accessibilityHidden(!clear.visible)
        .frame(width: ControlBarMetrics.clearWidth, height: ControlBarMetrics.controlHeight)
    }
}

private struct ControlBarActionStyle: ViewModifier {
    var style: ControlBarAction.Style

    func body(content: Content) -> some View {
        switch style {
        case .record: content.buttonStyle(PanelHeroButtonStyle(fill: PanelSurface.accent))
        case .stop: content.buttonStyle(PanelHeroButtonStyle(fill: PanelSurface.stop))
        case .recordBusy, .recordBlocked: content.buttonStyle(ControlBarCellButtonStyle())
        }
    }
}

/// The panel's cell: its fill and light hairline, the row hover on top, and darker while pressed or open.
private struct ControlBarCellButtonStyle: ButtonStyle {
    var forcePressed = false

    func makeBody(configuration: Configuration) -> some View {
        ControlBarCellBody(configuration: configuration, forcePressed: forcePressed)
    }
}

private struct ControlBarCellBody: View {
    let configuration: ButtonStyle.Configuration
    let forcePressed: Bool
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let palette = PanelPalette(scheme)
        let shape = RoundedRectangle(cornerRadius: PanelMetrics.radiusControl, style: .continuous)
        let interaction = PanelInteraction(
            enabled: isEnabled, hovering: hovering, pressed: configuration.isPressed || forcePressed)
        configuration.label
            .background {
                shape.fill(palette.cellFill.color)
                    .overlay {
                        if interaction == .hover {
                            shape.fill(palette.rowColor(.hover))
                        } else if interaction == .pressed {
                            shape.fill(Color.black.opacity(PanelSurface.heroDarkening(.pressed)))
                        }
                    }
            }
            .overlay {
                if let hairline = palette.cellHairline {
                    shape.strokeBorder(hairline.color, lineWidth: PanelSurface.pixel(displayScale: displayScale))
                }
            }
            .contentShape(shape)
            .onHover { hovering = $0 }
    }
}
