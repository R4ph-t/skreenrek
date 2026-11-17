import AppKit
import SkreenrekCore
import SwiftUI

/// B: the dropdown as a `MenuBarExtra(.window)` panel in the Control Center style, 320 pt wide. Mockup only.
///
/// It gives up NSMenu's free keyboard navigation, so it brings its own: focus starts on the primary button, Tab and
/// Shift-Tab walk `DirectionModel.focusOrder` (primary button, tiles, toggles, clip buttons), Return triggers the
/// primary button and Esc closes the panel. The key handling is `DirectionModel.command(for:focus:context:)`.
struct DirectionPanelView: View {
    static let width: CGFloat = 320

    let context: MenuContext
    let thumbnail: NSImage?
    /// The renders draw the panel on a solid stand-in for the window material; in a `MenuBarExtra` the window
    /// supplies the material.
    var drawsBackground = true
    var perform: (MenuAction) -> Void = { _ in }
    var close: () -> Void = {}

    @FocusState private var focus: PanelFocus?

    private var header: DirectionHeader { DirectionModel.header(for: context) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            switch context.displayState {
            case .recording:
                timerBlock
                recordingControls
            case .writing:
                savingBlock
            case .idle, .armed, .error:
                statusCard
                tiles
                toggles
                primaryButton
                if let clip = DirectionModel.lastClip(for: context) { lastClipCard(clip) }
            }
        }
        .padding(12)
        .frame(width: Self.width)
        .background {
            if drawsBackground {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DirectionTheme.panelBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 1))
            }
        }
        .defaultFocus($focus, DirectionModel.initialFocus(for: context))
        .onKeyPress(keys: [.return, .escape, .tab]) { press in
            let key: PanelKey =
                switch press.key {
                case .return: .returnKey
                case .escape: .escape
                default: press.modifiers.contains(.shift) ? .backTab : .tab
                }
            switch DirectionModel.command(for: key, focus: focus, context: context) {
            case .perform(let action): perform(action)
            case .close: close()
            case .focus(let next): focus = next
            case nil: return .ignored
            }
            return .handled
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 6) {
            BrandMark(size: 16)
            Text(UIStrings.productName).font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            Button {
                perform(.openSettings)
            } label: {
                Image(systemName: "gearshape").frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help(UIStrings.Directions.settingsHelp)
            .accessibilityLabel(UIStrings.Directions.settingsHelp)
            .panelFocus($focus, .settings)
            Menu {
                Button(UIStrings.Menu.openOutputFolder) { perform(.openOutputFolder) }
                Divider()
                Button(UIStrings.Menu.quit) { perform(.quit) }
            } label: {
                Image(systemName: "ellipsis").frame(width: 24, height: 24)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(UIStrings.Directions.moreHelp)
            .accessibilityLabel(UIStrings.Directions.moreHelp)
            .panelFocus($focus, .more)
        }
        .frame(height: 28)
    }

    // MARK: - Status

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: header.symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(symbolStyle)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(header.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        .truncationMode(.middle)
                    Text(header.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(
                            header.kind == .notExact ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary)
                        )
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(header.accessibilityLabel)
            if !header.fixes.isEmpty {
                // Side by side when they fit, stacked otherwise; never truncated.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { fixButtons }
                    VStack(alignment: .leading, spacing: 6) { fixButtons }
                }
                .padding(.leading, 34)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.fill.quinary))
        .overlay {
            if header.kind == .error {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.orange, lineWidth: 1)
            }
        }
    }

    private var fixButtons: some View {
        ForEach(Array(header.fixes.enumerated()), id: \.offset) { index, fix in
            Button(fix.title) { if let action = fix.action { perform(action) } }
                .buttonStyle(.bordered)
                .fixedSize()
                .panelFocus($focus, .fix(index))
        }
    }

    private var symbolStyle: AnyShapeStyle {
        switch header.kind {
        case .idle: AnyShapeStyle(.secondary)
        case .error: AnyShapeStyle(Color.orange)
        default: AnyShapeStyle(.primary)
        }
    }

    // MARK: - Tiles and toggles

    private var tiles: some View {
        let size = MenuModel.sizeSubmenu(context.sizeChoice)
        let rate = MenuModel.frameRateSubmenu(context.snapshot.fps)
        return HStack(spacing: 8) {
            tile(size, help: UIStrings.Directions.sizeTileHelp(size.detail ?? ""), focus: .sizeTile)
            tile(rate, help: UIStrings.Directions.frameRateTileHelp(rate.detail ?? ""), focus: .frameRateTile)
        }
    }

    private func tile(_ submenu: SubmenuModel, help: String, focus field: PanelFocus) -> some View {
        Menu {
            ForEach(Array(submenu.entries.enumerated()), id: \.offset) { _, entry in
                switch entry {
                case .item(let item):
                    Button {
                        if let action = item.action { perform(action) }
                    } label: {
                        if item.checked { Label(item.title, systemImage: "checkmark") } else { Text(item.title) }
                    }
                case .separator: Divider()
                default: EmptyView()
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(submenu.title).font(.system(size: 11)).foregroundStyle(.secondary)
                Text(submenu.detail ?? "").font(.system(size: 13, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 62, maxHeight: 62, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.fill.quinary))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help(help)
        .accessibilityLabel(help)
        .panelFocus($focus, field)
    }

    private var toggles: some View {
        VStack(spacing: 0) {
            toggleRow(
                UIStrings.Menu.showCursor, symbol: "cursorarrow", isOn: context.cursor, action: .toggleCursor,
                focus: .cursorToggle)
            toggleRow(
                UIStrings.Menu.writeClickEvents, symbol: "cursorarrow.click", isOn: context.events,
                action: .toggleEvents, focus: .eventsToggle)
        }
    }

    private func toggleRow(
        _ title: String, symbol: String, isOn: Bool, action: MenuAction, focus field: PanelFocus
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 18)
                .accessibilityHidden(true)
            Text(title).font(.system(size: 13)).accessibilityHidden(true)
            Spacer(minLength: 8)
            Toggle(isOn: Binding(get: { isOn }, set: { _ in perform(action) })) { EmptyView() }
                .modifier(DirectionSwitch())
                .fixedSize()
                .accessibilityLabel(title)
                .panelFocus($focus, field)
        }
        .padding(.horizontal, 4)
        .frame(height: 28)
    }

    // MARK: - Primary button

    private var primaryButton: some View {
        VStack(spacing: 6) {
            let armed = context.isArmed
            Button {
                perform(armed ? .record : .pickWindow)
            } label: {
                Label(
                    armed ? UIStrings.Menu.recordWindow : UIStrings.Menu.pickWindow,
                    systemImage: armed ? "record.circle" : "viewfinder"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 10))
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .panelFocus($focus, .primary)
            if armed {
                Button(UIStrings.Menu.pickAnotherWindow) { perform(.pickWindow) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .panelFocus($focus, .pickAnother)
            }
        }
    }

    // MARK: - Last Clip

    private func lastClipCard(_ clip: DirectionClip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(UIStrings.Menu.lastClip).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.top, 4)
            ClipThumbnail(image: thumbnail, width: 296, height: 185, radius: 6, showsPlay: false)
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.title).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                Text(clip.detail).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 8) {
                clipButton(
                    UIStrings.Directions.finder, help: UIStrings.Menu.showInFinder, symbol: "folder",
                    action: .showInFinder(path: clip.path), focus: .clipFinder)
                clipButton(
                    UIStrings.Directions.copyPath, help: UIStrings.Menu.copyFilePath, symbol: "doc.on.doc",
                    action: .copyFilePath(path: clip.path), focus: .clipCopyPath)
                clipButton(
                    UIStrings.Directions.snippet, help: UIStrings.Menu.copySnippet,
                    symbol: "chevron.left.forwardslash.chevron.right", action: .copySnippet(clip.snippet),
                    focus: .clipSnippet)
            }
        }
    }

    private func clipButton(
        _ title: String, help: String, symbol: String, action: MenuAction, focus field: PanelFocus
    ) -> some View {
        Button {
            perform(action)
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 20)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .help(help)
        .accessibilityLabel(help)
        .panelFocus($focus, field)
    }

    // MARK: - Recording and saving

    private var timerBlock: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "record.circle.fill").font(.system(size: 12)).foregroundStyle(.red)
                Text(header.title).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(header.elapsed ?? "").font(.system(size: 34, weight: .light)).monospacedDigit()
            Text(DirectionModel.panelRecordingDetail(context))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.fill.quinary))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(header.accessibilityLabel)
    }

    private var savingBlock: some View {
        ProgressView {
            Text(UIStrings.Menu.savingClip).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .controlSize(.small)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.fill.quinary))
    }

    private var recordingControls: some View {
        VStack(spacing: 6) {
            Button {
                perform(.stop)
            } label: {
                Label(UIStrings.Menu.stopRecording, systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 10))
            .controlSize(.large)
            .tint(.red)
            .keyboardShortcut(.defaultAction)
            .help(UIStrings.Directions.stopHelp)
            .panelFocus($focus, .primary)
            Text(UIStrings.Settings.stopShortcutKeys).font(.system(size: 11)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Button(UIStrings.Menu.discardRecording) { perform(.discard) }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .panelFocus($focus, .discard)
        }
    }
}

extension View {
    /// Makes a control keyboard-focusable (whatever the Keyboard navigation setting) and binds it to the panel's
    /// focus state.
    func panelFocus(_ binding: FocusState<PanelFocus?>.Binding, _ value: PanelFocus) -> some View {
        focusable(interactions: .activate).focused(binding, equals: value)
    }
}
