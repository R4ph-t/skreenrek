import Foundation
import SkreenrekControl
import SkreenrekCore

/// What the preview box is showing. The still itself comes from `WindowPreviewSource`.
public enum PanelPreviewPhase: Sendable, Hashable {
    case noWindow
    /// A screen region is armed. There is no window to photograph.
    case region
    case loading
    case ready(WindowStill)
    case failed
    case permissionMissing(Permission)
    /// The window left. `still` is the last one taken, dimmed in the box.
    case windowClosed(WindowStill?)

    public var still: WindowStill? {
        switch self {
        case .ready(let still): still
        case .windowClosed(let still): still
        default: nil
        }
    }
}

/// One control in the menu panel.
public struct PanelButton: Sendable, Hashable {
    public enum Role: Sendable, Hashable {
        case record
        case stop
        case pick
        case row
        case icon
        case footer
    }

    public enum Tint: Sendable, Hashable {
        case neutral
        case accent
        case red
    }

    public var title: String
    public var action: MenuAction
    public var enabled: Bool
    public var role: Role
    public var symbol: String?
    /// A quiet trailing value: the elapsed time, or `⌘,`.
    public var trailing: String?
    public var help: String?
    public var accessibilityLabel: String
    public var tint: Tint
    /// Return triggers the hero. Settings and Quit keep their shortcuts.
    public var isDefault: Bool
    public var shortcut: MenuShortcut?

    public init(
        title: String, action: MenuAction, enabled: Bool = true, role: Role, symbol: String? = nil,
        trailing: String? = nil, help: String? = nil, accessibilityLabel: String? = nil, tint: Tint = .neutral,
        isDefault: Bool = false, shortcut: MenuShortcut? = nil
    ) {
        self.title = title
        self.action = action
        self.enabled = enabled
        self.role = role
        self.symbol = symbol
        self.trailing = trailing
        self.help = help
        self.accessibilityLabel = accessibilityLabel ?? title
        self.tint = tint
        self.isDefault = isDefault
        self.shortcut = shortcut
    }
}

public struct PanelToggle: Sendable, Hashable {
    public var title: String
    public var symbol: String
    public var isOn: Bool
    public var action: MenuAction
    public var accessibilityLabel: String
}

/// Size and Frame Rate, one row of pop-up cells. `sizeValue` is the preset name, or Custom.
public struct PanelChoices: Sendable, Hashable {
    public var size: SubmenuModel
    public var sizeValue: String
    public var frameRate: SubmenuModel
    public var frameRateValue: String
}

/// The Last Clip row. The main area opens the clip; `actions` are the icon buttons and never do.
public struct PanelLastClip: Sendable, Hashable {
    public var title: String
    public var detail: String
    /// Secondary title when the file is gone.
    public var dimmed: Bool
    public var path: String
    public var fileExists: Bool
    public var accessibilityLabel: String
    public var help: String?
    public var open: MenuAction
    public var actions: [PanelButton]

    public var canOpen: Bool { fileExists }
    public var fileURL: URL { URL(fileURLWithPath: path) }
}

public struct PanelCaption: Sendable, Hashable {
    public var title: String
    public var detail: String
    public var accessibilityLabel: String
    public var help: String?
}

/// The preview's edge. A picked window gets the selected stroke, a recording the red one, and anything else the
/// quiet hairline.
public enum PanelPreviewStroke: Sendable, Hashable {
    case hairline
    case selected
    case recording
}

public struct PanelPreviewBox: Sendable, Hashable {
    public var phase: PanelPreviewPhase
    public var stroke: PanelPreviewStroke
    /// The spinner, and only after the still has already taken 300 ms.
    public var showsSpinner: Bool
    /// The one line in the box: "Preview unavailable", "Screen Recording is off", or nothing.
    public var message: String?
    /// The full sentence, tooltip and VoiceOver. The line in the box stays short.
    public var messageHelp: String?
    /// Open Settings…, inside the box when a capture permission is missing.
    public var settings: PanelButton?
}

/// The compact header that stands in for the preview and caption when there is no window to show.
public struct PanelHeader: Sendable, Hashable {
    public enum Icon: Sendable, Hashable {
        case noWindow
        case windowClosed
    }

    public var icon: Icon
    public var title: String
    public var detail: String
    public var accessibilityLabel: String
    public var help: String?
}

/// The top of the panel. The compact form has no preview at all, so an empty box can't come back.
public enum PanelWindowBlock: Sendable, Hashable {
    case compact(PanelHeader)
    /// `clear` is the button at the end of the title line, present only while a window can be forgotten.
    case target(preview: PanelPreviewBox, caption: PanelCaption, clear: PanelButton?)
}

/// The menu panel for one moment: the same actions as the menu, laid out as direction B.
public struct PanelContent: Sendable, Hashable {
    public var window: PanelWindowBlock
    public var hero: PanelButton?
    public var origin: String?
    public var choices: PanelChoices?
    public var rows: [PanelButton]
    public var toggles: [PanelToggle]
    public var discard: PanelButton?
    public var lastClip: PanelLastClip?
    public var footer: [PanelButton]

    public var isCompact: Bool { header != nil }
    public var header: PanelHeader? {
        if case .compact(let header) = window { return header }
        return nil
    }
    public var preview: PanelPreviewBox? {
        if case .target(let preview, _, _) = window { return preview }
        return nil
    }
    public var caption: PanelCaption? {
        if case .target(_, let caption, _) = window { return caption }
        return nil
    }
    public var clear: PanelButton? {
        if case .target(_, _, let clear) = window { return clear }
        return nil
    }
    public var showsCells: Bool { choices != nil }
    public var showsPicker: Bool { rows.contains { $0.action == .pickWindow } }
    public var showsToggles: Bool { !toggles.isEmpty }
    public var showsLastClip: Bool { lastClip != nil }
}

/// A vertical piece of the panel. The view draws these in order, and the height is their sum, so the two can't drift.
public enum PanelBlock: Sendable, Hashable {
    case space(CGFloat)
    case header
    case preview
    case caption
    case cells
    case hero
    case origin
    case row(PanelButton)
    case toggle(PanelToggle)
    case clip
    case separator
}

/// A block with an identity that survives a state change, so the blocks that stay slide and the others fade.
public struct PanelPlacedBlock: Sendable, Hashable, Identifiable {
    public var id: String
    public var block: PanelBlock
}

/// The 1.0.5 panel. Every element shares one content edge, x 16–284. Row highlights are inset 8 from the panel edge.
/// Compact is 351 pt, a picked window 558.5, and recording 457.5, before the optional Last Clip and update rows.
public enum PanelMetrics {
    public static let width: CGFloat = 300
    /// The content edge: the preview, caption, cells, hero, separators and row icons start here.
    public static let margin: CGFloat = 16
    public static let blockWidth: CGFloat = 268
    public static let top: CGFloat = 16
    public static let bottom: CGFloat = 8
    public static let windowGap: CGFloat = 12
    public static let previewHeight: CGFloat = 167.5
    /// The caption, and the compact header that replaces it.
    public static let captionHeight: CGFloat = 33
    public static let cellHeight: CGFloat = 28
    public static let sizeCellWidth: CGFloat = 116
    public static let cellGap: CGFloat = 8
    public static let heroHeight: CGFloat = 40
    public static let heroIconGap: CGFloat = 6
    /// Between Stop Recording and its timer.
    public static let heroTimerGap: CGFloat = 4
    public static let rowHeight: CGFloat = 28
    public static let clipRowHeight: CGFloat = 44
    public static let originHeight: CGFloat = 15
    public static let originGap: CGFloat = 8
    /// 8 pt, the hairline, 8 pt.
    public static let separator: CGFloat = 17
    public static let separatorLine: CGFloat = 1
    /// The row highlight runs x 8–292.
    public static let rowHighlightX: CGFloat = 8
    public static let rowHighlightWidth: CGFloat = 284
    /// From the highlight's edge to the row's content.
    public static let rowPadding: CGFloat = 8
    public static let iconColumn: CGFloat = 16
    public static let iconGap: CGFloat = 8
    public static let thumbWidth: CGFloat = 40
    public static let thumbHeight: CGFloat = 25
    /// An icon button's hit area. Its 16 pt glyph is centred, so the area overhangs the content edge by 4.
    public static let iconButton: CGFloat = 24
    public static let iconGlyph: CGFloat = 16
    public static let iconButtonOverhang: CGFloat = 4
    /// The title line stops this far before the content edge when the Clear button is on it.
    public static let clearTitleInset: CGFloat = 32
    public static let titleLineHeight: CGFloat = 16
    public static let radiusPanel: CGFloat = 10
    public static let radiusControl: CGFloat = 6
    public static let radiusChip: CGFloat = 4
    public static let hairline: CGFloat = 0.5
    public static let previewStroke: CGFloat = 2
    public static let spinnerDelayMilliseconds = 300
    public static let fadeSeconds: Double = 0.12
    /// The panel's height change and its cross-fades when the state changes while it's open.
    public static let transitionSeconds: Double = 0.2
    public static let menuBarHeight: CGFloat = 24
    public static let shortScreen: CGFloat = 800
    /// Picked, with Last Clip and the update row. The control bar spec accepts passing the old 620 cap by 27.5.
    public static let idleBudget: CGFloat = 648
    public static let recordingBudget: CGFloat = 490
    /// Idle with a window, the update row and a last clip.
    public static let idleHeight: CGFloat = 647.5
    /// Recording with the update row.
    public static let recordingHeight: CGFloat = 485.5
    /// No window picked, or the window closed, with no clip and no update row.
    public static let compactHeight: CGFloat = 351

    /// The row icon's column.
    public static var iconX: CGFloat { rowHighlightX + rowPadding }
    /// Every row title.
    public static var textX: CGFloat { iconX + iconColumn + iconGap }
    /// Where the switches, shortcuts and icon-button glyphs end.
    public static var contentEndX: CGFloat { margin + blockWidth }
    /// The Clear button's hit area, x 264–288.
    public static var clearHitX: CGFloat { contentEndX + iconButtonOverhang - iconButton }
    public static var clearGlyphEndX: CGFloat { clearHitX + (iconButton + iconGlyph) / 2 }
    public static var clearTitleWidth: CGFloat { blockWidth - clearTitleInset }

    public static var frameRateCellWidth: CGFloat { blockWidth - sizeCellWidth - cellGap }

    /// The preview box in pixels at `scale` (2× is 536 × 335). The capture fits the window inside this.
    public static func capturePixels(scale: CGFloat) -> PixelSize {
        let factor = scale > 0 ? scale : 2
        return PixelSize(
            width: max(1, Int((blockWidth * factor).rounded())),
            height: max(1, Int((previewHeight * factor).rounded())))
    }

    public static func availableHeight(
        screenHeight: CGFloat = shortScreen, menuBar: CGFloat = menuBarHeight
    ) -> CGFloat {
        max(0, screenHeight - menuBar)
    }

    public static func contentHeight(_ content: PanelContent) -> CGFloat {
        blocks(for: content).reduce(0) { $0 + height(of: $1) }
    }

    /// True when the panel is taller than the screen under the menu bar, so the view scrolls.
    public static func scrolls(
        _ content: PanelContent, screenHeight: CGFloat = shortScreen, menuBar: CGFloat = menuBarHeight
    ) -> Bool {
        contentHeight(content) > availableHeight(screenHeight: screenHeight, menuBar: menuBar)
    }

    public static func height(of block: PanelBlock) -> CGFloat {
        switch block {
        case .space(let value): value
        case .header, .caption: captionHeight
        case .preview: previewHeight
        case .cells: cellHeight
        case .hero: heroHeight
        case .origin: originHeight
        case .row: rowHeight
        case .toggle: rowHeight
        case .clip: clipRowHeight
        case .separator: separator
        }
    }

    /// Compact: top, header, cells, hero. With a target: top, preview, caption, then the cells and hero. After those
    /// come the controls, the clip and the footer, with a separator before each group.
    public static func blocks(for content: PanelContent) -> [PanelBlock] {
        var blocks: [PanelBlock] = [.space(top)]
        switch content.window {
        case .compact: blocks.append(.header)
        case .target: blocks += [.preview, .space(windowGap), .caption]
        }
        if content.choices != nil {
            blocks += [.space(windowGap), .cells]
        }
        if content.hero != nil {
            blocks += [.space(windowGap), .hero]
        }
        if content.origin != nil {
            blocks += [.space(originGap), .origin]
        }
        var controls: [PanelBlock] = content.rows.map { .row($0) } + content.toggles.map { .toggle($0) }
        if let discard = content.discard { controls.append(.row(discard)) }
        var groups: [[PanelBlock]] = []
        if !controls.isEmpty { groups.append(controls) }
        if content.lastClip != nil { groups.append([.clip]) }
        if !content.footer.isEmpty { groups.append(content.footer.map { .row($0) }) }
        for group in groups {
            blocks.append(.separator)
            blocks += group
        }
        blocks.append(.space(bottom))
        return blocks
    }

    /// The blocks with stable identities: rows and toggles by title, repeated spacers and separators by position.
    public static func placedBlocks(for content: PanelContent) -> [PanelPlacedBlock] {
        var seen: [String: Int] = [:]
        return blocks(for: content).map { block in
            let name: String
            switch block {
            case .space: name = "space"
            case .header: name = "header"
            case .preview: name = "preview"
            case .caption: name = "caption"
            case .cells: name = "cells"
            case .hero: name = "hero"
            case .origin: name = "origin"
            case .row(let button): name = "row:\(button.title)"
            case .toggle(let toggle): name = "toggle:\(toggle.title)"
            case .clip: name = "clip"
            case .separator: name = "separator"
            }
            let index = seen[name, default: 0]
            seen[name] = index + 1
            return PanelPlacedBlock(id: "\(name)#\(index)", block: block)
        }
    }

    /// A change animates only while the panel is open, only when its height changes, and never under Reduce Motion.
    public static func animatesChange(
        from old: PanelContent, to new: PanelContent, panelOpen: Bool, reduceMotion: Bool
    ) -> Bool {
        panelOpen && !reduceMotion && contentHeight(old) != contentHeight(new)
    }
}

public enum PanelModel {
    /// Preset name, or Custom for Current Size and any size that isn't a preset. The px stays on the caption.
    public static func sizeName(_ choice: SizeChoice) -> String {
        switch choice {
        case .keepCurrent: UIStrings.Panel.custom
        case .size(let size): SizePreset(size: size)?.title ?? UIStrings.Panel.custom
        }
    }

    public static func clipSizeName(_ pixels: PixelSize) -> String {
        SizePreset(size: pixels)?.title ?? UIStrings.Panel.custom
    }

    /// Copy stays open. Size and frame rate stay open so the window can resize while the panel is up.
    /// Everything that leaves (Record, Stop, Settings, opening the clip) closes it.
    public static func keepsPanelOpen(_ action: MenuAction) -> Bool {
        switch action {
        case .toggleCursor, .toggleEvents, .toggleControlBar, .chooseSize, .chooseFrameRate, .copyFilePath, .copySnippet,
            .copyErrorDetails, .clearWindow:
            true
        default:
            false
        }
    }

    /// The phase `render-ui` draws for a sample that has no live capture.
    public static func illustratedPhase(for context: MenuContext) -> PanelPreviewPhase {
        if let error = context.error {
            switch error {
            case .permissionDenied(let permission) where permission != .accessibility:
                return .permissionMissing(permission)
            case .recordingFailed(.windowClosed):
                return .windowClosed(nil)
            default:
                break
            }
        }
        if context.snapshot.window == nil {
            return context.snapshot.region == nil ? .noWindow : .region
        }
        return .ready(WindowStill(png: Data(), pixelWidth: 16, pixelHeight: 10))
    }

    public static func content(
        for context: MenuContext, preview phase: PanelPreviewPhase, showSpinner: Bool = false,
        clipFileExists: Bool = true, closedTitle: String? = nil
    ) -> PanelContent {
        let recording = context.displayState == .recording
        let writing = context.displayState == .writing
        let busy = recording || writing
        let closed = !busy && windowClosed(context, phase: phase)
        let hasTarget = context.snapshot.window != nil || context.snapshot.region != nil
        let compact = !busy && (closed || !hasTarget)
        // A missing permission has no box to explain itself in here, so the compact layout uses its rows instead.
        let phase = compact && !closed ? PanelPreviewPhase.noWindow : phase
        let window: PanelWindowBlock
        if compact {
            window = .compact(header(for: context, closed: closed, closedTitle: closedTitle))
        } else {
            window = .target(
                preview: previewBox(phase, showSpinner: showSpinner, stroke: stroke(context, recording: recording)),
                caption: caption(for: context, phase: phase),
                clear: !busy && context.snapshot.window != nil ? clearButton() : nil)
        }
        return PanelContent(
            window: window,
            hero: hero(for: context, phase: phase, compact: compact, recording: recording, writing: writing),
            origin: busy ? MenuModel.originRow(context.snapshot) : nil,
            choices: busy ? nil : choices(for: context),
            rows: busy ? [] : rows(for: context, phase: phase, compact: compact, closed: closed),
            toggles: busy ? [] : toggles(for: context),
            discard: recording ? discardButton() : nil,
            lastClip: busy ? nil : lastClip(for: context, fileExists: clipFileExists),
            footer: footer(context))
    }

    private static func windowClosed(_ context: MenuContext, phase: PanelPreviewPhase) -> Bool {
        if case .windowClosed = phase { return true }
        if case .recordingFailed(.windowClosed) = context.error { return true }
        return false
    }

    // MARK: - Compact header

    private static func header(for context: MenuContext, closed: Bool, closedTitle: String?) -> PanelHeader {
        if closed {
            let title = closedTitle ?? context.lastClipTitle ?? context.targetTitle
            return PanelHeader(
                icon: .windowClosed, title: UIStrings.Panel.windowClosed,
                detail: title ?? UIStrings.Panel.pickWindowToRecord,
                accessibilityLabel: [UIStrings.Panel.windowClosed, title].compactMap { $0 }.joined(separator: ", "))
        }
        if context.displayState == .error, let error = context.error {
            let caption = errorCaption(error)
            return PanelHeader(
                icon: .noWindow, title: caption.title, detail: caption.detail,
                accessibilityLabel: caption.accessibilityLabel, help: caption.help)
        }
        return PanelHeader(
            icon: .noWindow, title: UIStrings.Panel.noWindow, detail: UIStrings.Panel.pickWindowToRecord,
            accessibilityLabel: UIStrings.Panel.noWindowLabel)
    }

    private static func clearButton() -> PanelButton {
        PanelButton(
            title: UIStrings.Panel.clearWindow, action: .clearWindow, role: .icon, symbol: PanelSymbol.clearWindow,
            help: UIStrings.Panel.clearWindow, accessibilityLabel: UIStrings.Panel.clearPickedWindow)
    }

    // MARK: - Caption

    private static func caption(for context: MenuContext, phase: PanelPreviewPhase) -> PanelCaption {
        switch context.displayState {
        case .recording:
            let target = context.targetTitle ?? UIStrings.Menu.region
            let bucket = context.elapsedSeconds / StatusIconModel.spokenInterval * StatusIconModel.spokenInterval
            return PanelCaption(
                title: UIStrings.Menu.recording(target), detail: DropdownModel.sizeAndRate(context),
                accessibilityLabel: UIStrings.Brand.recordingLabel(target: target, seconds: bucket))
        case .writing:
            return PanelCaption(
                title: UIStrings.Menu.savingClip, detail: MenuModel.recordingDetail(context),
                accessibilityLabel: UIStrings.Icon.writing)
        default:
            break
        }
        switch phase {
        case .permissionMissing, .failed:
            return normalCaption(context)
        default:
            if context.displayState == .error, let error = context.error {
                return errorCaption(error)
            }
            return normalCaption(context)
        }
    }

    private static func normalCaption(_ context: MenuContext) -> PanelCaption {
        let row = MenuModel.armedRow(context)
        let spoken: String
        if let help = row.toolTip {
            spoken = "\(row.title). \(help)"
        } else if let size = context.snapshot.size {
            spoken = UIStrings.Panel.spokenCaption(title: row.title, size: size, fps: context.snapshot.fps)
        } else {
            spoken = "\(row.title), \(row.detail)"
        }
        return PanelCaption(title: row.title, detail: row.detail, accessibilityLabel: spoken, help: row.toolTip)
    }

    private static func errorCaption(_ error: SkreenrekError) -> PanelCaption {
        let presentation = ErrorPresentation(error, lastClip: nil)
        return PanelCaption(
            title: presentation.row.title, detail: presentation.row.detail,
            accessibilityLabel: "\(presentation.row.title). \(presentation.row.detail)",
            help: presentation.row.detail)
    }

    // MARK: - Preview

    private static func stroke(_ context: MenuContext, recording: Bool) -> PanelPreviewStroke {
        if recording { return .recording }
        return context.snapshot.window != nil ? .selected : .hairline
    }

    private static func previewBox(
        _ phase: PanelPreviewPhase, showSpinner: Bool, stroke: PanelPreviewStroke
    ) -> PanelPreviewBox {
        var message: String?
        var help: String?
        var settings: PanelButton?
        if case .failed = phase {
            message = UIStrings.Panel.previewUnavailable
            help = UIStrings.Panel.previewFailedHelp
        }
        if case .permissionMissing(let permission) = phase {
            let copy = permissionCopy(permission)
            message = copy.line
            help = copy.help
            settings = PanelButton(
                title: UIStrings.Panel.openSettings, action: .openPrivacySettings(permission), role: .row,
                accessibilityLabel: UIStrings.Panel.openSettings)
        }
        let spinning = showSpinner && phaseIsLoading(phase)
        return PanelPreviewBox(
            phase: phase, stroke: stroke, showsSpinner: spinning, message: message, messageHelp: help,
            settings: settings)
    }

    private static func phaseIsLoading(_ phase: PanelPreviewPhase) -> Bool {
        if case .loading = phase { return true }
        return false
    }

    private static func permissionCopy(_ permission: Permission) -> (line: String, help: String) {
        switch permission {
        case .screenRecording:
            (UIStrings.Errors.screenRecordingOff, UIStrings.Errors.screenRecordingDetail)
        case .directCapture:
            (UIStrings.Errors.directCaptureOff, UIStrings.Errors.directCaptureDetail)
        case .accessibility:
            (UIStrings.Errors.cantResize, UIStrings.Errors.cantResizeDetail)
        }
    }

    // MARK: - Hero

    private static func hero(
        for context: MenuContext, phase: PanelPreviewPhase, compact: Bool, recording: Bool, writing: Bool
    ) -> PanelButton? {
        if recording { return stopButton(context) }
        if writing { return nil }
        if compact { return pickButton() }
        if case .permissionMissing(let permission) = phase {
            return recordButton(enabled: false, help: permissionCopy(permission).help)
        }
        if context.isArmed, recordAllowed(phase) { return recordButton(enabled: true, isDefault: true) }
        return pickButton()
    }

    /// Failed and loading still record. No window, a closed window, and a missing permission don't.
    private static func recordAllowed(_ phase: PanelPreviewPhase) -> Bool {
        switch phase {
        case .noWindow, .windowClosed, .permissionMissing: false
        case .region, .loading, .ready, .failed: true
        }
    }

    private static func recordButton(enabled: Bool, help: String? = nil, isDefault: Bool = false) -> PanelButton {
        PanelButton(
            title: UIStrings.Brand.record, action: .record, enabled: enabled, role: .record,
            help: help, accessibilityLabel: UIStrings.Menu.recordWindow, tint: enabled ? .accent : .neutral,
            isDefault: isDefault && enabled)
    }

    private static func stopButton(_ context: MenuContext) -> PanelButton {
        PanelButton(
            title: UIStrings.Menu.stopRecording, action: .stop, role: .stop,
            trailing: TimeFormat.minutesSeconds(Double(context.elapsedSeconds)), help: UIStrings.Panel.stopHelp,
            accessibilityLabel: UIStrings.Brand.stopLabel(seconds: context.elapsedSeconds), tint: .red,
            isDefault: true)
    }

    private static func pickButton() -> PanelButton {
        PanelButton(
            title: UIStrings.Menu.pickWindow, action: .pickWindow, role: .pick, symbol: PanelSymbol.pickWindow,
            tint: .accent, isDefault: true)
    }

    // MARK: - Rows

    private static func choices(for context: MenuContext) -> PanelChoices {
        PanelChoices(
            size: MenuModel.sizeSubmenu(
                context.sizeChoice, display: context.display, window: context.snapshot.window),
            sizeValue: sizeName(context.sizeChoice),
            frameRate: MenuModel.frameRateSubmenu(context.snapshot.fps),
            frameRateValue: UIStrings.Menu.fps(context.snapshot.fps))
    }

    private static func rows(
        for context: MenuContext, phase: PanelPreviewPhase, compact: Bool, closed: Bool
    ) -> [PanelButton] {
        var rows: [PanelButton] = []
        // In the compact layout Pick is the hero.
        if !compact {
            rows.append(
                PanelButton(
                    title: UIStrings.Menu.pickAnotherWindow, action: .pickWindow, role: .row,
                    symbol: PanelSymbol.pickWindow))
        }
        if showsPermissionsRow(context, phase: phase) {
            rows.append(
                PanelButton(
                    title: UIStrings.Menu.permissionsNeeded, action: .showPermissions, role: .row,
                    symbol: "hand.raised"))
        }
        if showsFixes(context, phase: phase, closed: closed), let error = context.error {
            for fix in ErrorPresentation(error, lastClip: context.snapshot.lastClip).fixes {
                guard let action = fix.action else { continue }
                rows.append(
                    PanelButton(
                        title: fix.title, action: action, role: .row, symbol: PanelSymbol.symbol(for: action),
                        help: fix.toolTip))
            }
        }
        return rows
    }

    /// The preview already has Open Settings… for a missing capture permission. Accessibility still gets the row,
    /// because the still works and the row is how that permission is fixed.
    private static func showsPermissionsRow(_ context: MenuContext, phase: PanelPreviewPhase) -> Bool {
        guard context.permissionsMissing else { return false }
        if case .permissionMissing = phase { return false }
        return true
    }

    /// A closed window and a missing capture permission explain themselves above. Other errors keep their fix rows.
    private static func showsFixes(_ context: MenuContext, phase: PanelPreviewPhase, closed: Bool) -> Bool {
        guard context.displayState == .error, !closed else { return false }
        if case .permissionMissing = phase { return false }
        return true
    }

    private static func toggles(for context: MenuContext) -> [PanelToggle] {
        [
            PanelToggle(
                title: UIStrings.Menu.showCursor, symbol: "cursorarrow", isOn: context.cursor, action: .toggleCursor,
                accessibilityLabel: UIStrings.Menu.showCursor),
            PanelToggle(
                title: UIStrings.Menu.writeClickEvents, symbol: "cursorarrow.click", isOn: context.events,
                action: .toggleEvents, accessibilityLabel: UIStrings.Menu.writeClickEvents),
            PanelToggle(
                title: UIStrings.Menu.showControlBar, symbol: PanelSymbol.controlBar, isOn: context.showControlBar,
                action: .toggleControlBar, accessibilityLabel: UIStrings.Menu.showControlBar),
        ]
    }

    private static func discardButton() -> PanelButton {
        PanelButton(
            title: UIStrings.Menu.discardRecording, action: .discard, role: .row, symbol: "trash")
    }

    private static func lastClip(for context: MenuContext, fileExists: Bool) -> PanelLastClip? {
        guard let clip = context.snapshot.lastClip else { return nil }
        let recording = clip.recording
        let pixels = PixelSize(width: recording.width, height: recording.height)
        let present = [
            TimeFormat.minutesSeconds(recording.duration), clipSizeName(pixels), "\(recording.fps) fps",
        ].joined(separator: UIStrings.Menu.separator)
        let windowTitle = context.lastClipTitle
            ?? clip.readback.map { UIStrings.Menu.windowTitle(app: $0.window.app, title: $0.window.title) }
            ?? recording.id
        let seconds = max(0, Int(recording.duration.rounded()))
        let path = clip.files.clip
        return PanelLastClip(
            title: UIStrings.Menu.lastClip,
            detail: fileExists ? present : UIStrings.Panel.clipMissing,
            dimmed: !fileExists, path: path, fileExists: fileExists,
            accessibilityLabel: fileExists
                ? UIStrings.Panel.openLastClip(title: windowTitle, seconds: seconds)
                : UIStrings.Panel.clipMissingLabel,
            help: fileExists ? UIStrings.Panel.openClip : nil,
            open: .openClip(path: path),
            actions: [
                PanelButton(
                    title: UIStrings.Menu.showInFinder, action: .showInFinder(path: path), enabled: fileExists,
                    role: .icon, symbol: "folder", accessibilityLabel: UIStrings.Menu.showInFinder),
                PanelButton(
                    title: UIStrings.Menu.copyFilePath, action: .copyFilePath(path: path), role: .icon,
                    symbol: PanelSymbol.copyFilePath, accessibilityLabel: UIStrings.Menu.copyFilePath),
                PanelButton(
                    title: UIStrings.Menu.copySnippet, action: .copySnippet(clip.snippet), role: .icon,
                    symbol: "chevron.left.forwardslash.chevron.right",
                    accessibilityLabel: UIStrings.Menu.copySnippet),
            ])
    }

    private static func footer(_ context: MenuContext) -> [PanelButton] {
        var rows: [PanelButton] = []
        if let version = context.updateAvailable {
            rows.append(
                PanelButton(
                    title: UIStrings.Updates.menuAvailable + UIStrings.Menu.separator + version, action: .showUpdate,
                    role: .footer, symbol: "arrow.down.circle", tint: .accent))
        }
        rows.append(
            PanelButton(
                title: UIStrings.Menu.openOutputFolder, action: .openOutputFolder, role: .footer, symbol: "folder"))
        rows.append(
            PanelButton(
                title: UIStrings.Menu.settings, action: .openSettings, role: .footer, symbol: "gearshape",
                trailing: MenuShortcut.settings.display, shortcut: .settings))
        rows.append(
            PanelButton(
                title: UIStrings.Menu.quit, action: .quit, role: .footer, symbol: PanelSymbol.quit,
                trailing: MenuShortcut.quit.display, shortcut: .quit))
        return rows
    }
}

/// The SF Symbols where the panel's design differs from the older dropdown's.
enum PanelSymbol {
    static let pickWindow = "viewfinder"
    static let clearWindow = "xmark.circle.fill"
    static let copyFilePath = "square.on.square"
    static let quit = "power"
    static let controlBar = "rectangle.bottomthird.inset.filled"

    static func symbol(for action: MenuAction) -> String? {
        switch action {
        case .pickWindow: pickWindow
        case .copyFilePath: copyFilePath
        case .quit: quit
        default: DropdownModel.symbol(for: action)
        }
    }
}
