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

public struct PanelPreviewBox: Sendable, Hashable {
    public var phase: PanelPreviewPhase
    /// A 2 pt red inner stroke, only while recording.
    public var framed: Bool
    /// The spinner, and only after the still has already taken 300 ms.
    public var showsSpinner: Bool
    /// The one line in the box: "Preview unavailable", "Screen Recording is off", or nothing.
    public var message: String?
    /// The full sentence, tooltip and VoiceOver. The line in the box stays short.
    public var messageHelp: String?
    /// Open Settings…, inside the box when a capture permission is missing.
    public var settings: PanelButton?
}

/// The hero is one full-width button, or Pick Window… beside a disabled Record.
public struct PanelHero: Sendable, Hashable {
    public var buttons: [PanelButton]
    /// The last button's width when there are two. The first takes the rest, with an 8 pt gap.
    public var trailingWidth: CGFloat?
}

/// The menu panel for one moment: the same actions as the menu, laid out as direction B.
public struct PanelContent: Sendable, Hashable {
    public var caption: PanelCaption
    public var preview: PanelPreviewBox
    public var hero: PanelHero?
    public var origin: String?
    public var choices: PanelChoices?
    public var rows: [PanelButton]
    public var toggles: [PanelToggle]
    public var discard: PanelButton?
    public var lastClip: PanelLastClip?
    public var footer: [PanelButton]

    public var showsCells: Bool { choices != nil }
    public var showsPicker: Bool { rows.contains { $0.action == .pickWindow } }
    public var showsToggles: Bool { !toggles.isEmpty }
    public var showsLastClip: Bool { lastClip != nil }
}

/// A vertical piece of the panel. The view draws these in order, and the height is their sum, so the two can't drift.
public enum PanelBlock: Sendable, Hashable {
    case space(CGFloat)
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

/// Direction B. Idle with a window, an update and a last clip is 619.5 pt (the cap is 620). Recording is 485.5.
/// No window and window-closed are 591.5. All of those fit an 800 pt screen minus the menu bar.
public enum PanelMetrics {
    public static let width: CGFloat = 300
    /// The window block and the rows share this left edge.
    public static let margin: CGFloat = 16
    public static let blockWidth: CGFloat = 268
    public static let top: CGFloat = 16
    public static let bottom: CGFloat = 8
    public static let windowGap: CGFloat = 12
    public static let previewHeight: CGFloat = 167.5
    public static let captionHeight: CGFloat = 33
    public static let cellHeight: CGFloat = 28
    public static let sizeCellWidth: CGFloat = 116
    public static let cellGap: CGFloat = 8
    public static let heroHeight: CGFloat = 40
    public static let heroGap: CGFloat = 8
    /// The disabled Record beside Pick Window….
    public static let recordWidth: CGFloat = 104
    public static let rowHeight: CGFloat = 28
    public static let clipRowHeight: CGFloat = 44
    public static let originHeight: CGFloat = 15
    public static let originGap: CGFloat = 8
    /// 8 pt, the hairline, 8 pt.
    public static let separator: CGFloat = 17
    public static let separatorLine: CGFloat = 1
    /// The hairline is inset this far from the 268 pt block, so the line is 252 pt.
    public static let separatorInset: CGFloat = 8
    public static let rowPadding: CGFloat = 8
    public static let iconColumn: CGFloat = 16
    public static let iconGap: CGFloat = 8
    public static let thumbWidth: CGFloat = 40
    public static let thumbHeight: CGFloat = 25
    public static let iconButton: CGFloat = 24
    public static let radiusPanel: CGFloat = 10
    public static let radiusControl: CGFloat = 6
    public static let radiusChip: CGFloat = 4
    public static let hairline: CGFloat = 0.5
    public static let recordingStroke: CGFloat = 2
    public static let spinnerDelayMilliseconds = 300
    public static let fadeSeconds: Double = 0.12
    public static let menuBarHeight: CGFloat = 24
    public static let shortScreen: CGFloat = 800
    public static let idleBudget: CGFloat = 620
    public static let recordingBudget: CGFloat = 490
    /// Idle with a window, the update row and a last clip.
    public static let idleHeight: CGFloat = 619.5
    public static let recordingHeight: CGFloat = 485.5
    /// No window picked, and the window-closed state. Idle minus the Pick Another row.
    public static let compactHeight: CGFloat = 591.5

    /// The row icon, on the redline: the row starts at x = 16 and pads 8.
    public static var iconX: CGFloat { margin + rowPadding }
    /// The row title.
    public static var textX: CGFloat { iconX + iconColumn + iconGap }
    /// Where the switches and the clip icon buttons end.
    public static var contentEndX: CGFloat { margin + blockWidth - rowPadding }

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
        case .preview: previewHeight
        case .caption: captionHeight
        case .cells: cellHeight
        case .hero: heroHeight
        case .origin: originHeight
        case .row: rowHeight
        case .toggle: rowHeight
        case .clip: clipRowHeight
        case .separator: separator
        }
    }

    /// Idle: top, preview, caption, cells, hero, then pick + toggles, the clip, and the footer, with a separator
    /// before each of those groups. Recording: preview, caption, hero, the origin line, discard, footer.
    public static func blocks(for content: PanelContent) -> [PanelBlock] {
        var blocks: [PanelBlock] = [.space(top), .preview, .space(windowGap), .caption]
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
        case .toggleCursor, .toggleEvents, .chooseSize, .chooseFrameRate, .copyFilePath, .copySnippet,
            .copyErrorDetails:
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
        let caption = caption(for: context, phase: phase, closedTitle: closedTitle)
        let preview = previewBox(phase, showSpinner: showSpinner, framed: recording)
        let hero = hero(for: context, phase: phase, recording: recording, writing: writing)
        let origin = busy ? MenuModel.originRow(context.snapshot) : nil
        let choices = busy ? nil : choices(for: context)
        let rows = busy ? [] : rows(for: context, phase: phase)
        let toggles = busy ? [] : toggles(for: context)
        let discard = recording ? discardButton() : nil
        let lastClip = busy ? nil : lastClip(for: context, fileExists: clipFileExists)
        return PanelContent(
            caption: caption, preview: preview, hero: hero, origin: origin, choices: choices, rows: rows,
            toggles: toggles, discard: discard, lastClip: lastClip, footer: footer(context))
    }

    // MARK: - Caption

    private static func caption(
        for context: MenuContext, phase: PanelPreviewPhase, closedTitle: String?
    ) -> PanelCaption {
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
        if case .windowClosed = phase {
            let title = closedTitle ?? context.lastClipTitle ?? context.targetTitle ?? UIStrings.Menu.ready
            return PanelCaption(
                title: title, detail: UIStrings.Panel.windowClosed,
                accessibilityLabel: "\(title), \(UIStrings.Panel.windowClosed)")
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
        guard context.isArmed || context.snapshot.window != nil else {
            let row = MenuModel.idleRow
            return PanelCaption(
                title: row.title, detail: row.detail, accessibilityLabel: "\(row.title), \(row.detail)")
        }
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

    private static func previewBox(
        _ phase: PanelPreviewPhase, showSpinner: Bool, framed: Bool
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
            phase: phase, framed: framed, showsSpinner: spinning, message: message, messageHelp: help,
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
        for context: MenuContext, phase: PanelPreviewPhase, recording: Bool, writing: Bool
    ) -> PanelHero? {
        if recording { return PanelHero(buttons: [stopButton(context)]) }
        if writing { return nil }
        if case .windowClosed = phase {
            return PanelHero(buttons: [pickButton(another: true, isDefault: true)])
        }
        if case .permissionMissing(let permission) = phase {
            let copy = permissionCopy(permission)
            return PanelHero(buttons: [recordButton(enabled: false, help: copy.help)])
        }
        if context.isArmed, recordAllowed(phase) {
            return PanelHero(buttons: [recordButton(enabled: true, isDefault: true)])
        }
        return PanelHero(
            buttons: [
                pickButton(another: false, isDefault: true),
                recordButton(enabled: false, help: UIStrings.Panel.pickAWindowFirst),
            ],
            trailingWidth: PanelMetrics.recordWidth)
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

    private static func pickButton(another: Bool, isDefault: Bool) -> PanelButton {
        let title = another ? UIStrings.Menu.pickAnotherWindow : UIStrings.Menu.pickWindow
        return PanelButton(
            title: title, action: .pickWindow, role: .pick, symbol: "macwindow",
            accessibilityLabel: title, tint: .accent, isDefault: isDefault)
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

    private static func rows(for context: MenuContext, phase: PanelPreviewPhase) -> [PanelButton] {
        var rows: [PanelButton] = []
        if showsPickRow(context, phase: phase) {
            let another = context.isArmed || context.snapshot.window != nil
            rows.append(
                PanelButton(
                    title: another ? UIStrings.Menu.pickAnotherWindow : UIStrings.Menu.pickWindow,
                    action: .pickWindow, role: .row, symbol: "macwindow"))
        }
        if showsPermissionsRow(context, phase: phase) {
            rows.append(
                PanelButton(
                    title: UIStrings.Menu.permissionsNeeded, action: .showPermissions, role: .row,
                    symbol: "hand.raised"))
        }
        if showsFixes(context, phase: phase), let error = context.error {
            for fix in ErrorPresentation(error, lastClip: context.snapshot.lastClip).fixes {
                guard let action = fix.action else { continue }
                rows.append(
                    PanelButton(
                        title: fix.title, action: action, role: .row, symbol: DropdownModel.symbol(for: action),
                        help: fix.toolTip))
            }
        }
        return rows
    }

    /// The spec's no-window and window-closed screens have no Pick row: Pick is the hero.
    private static func showsPickRow(_ context: MenuContext, phase: PanelPreviewPhase) -> Bool {
        switch phase {
        case .noWindow, .windowClosed: false
        case .region: true
        default: context.isArmed || context.snapshot.window != nil
        }
    }

    /// The preview already has Open Settings… for a missing capture permission. Accessibility still gets the row,
    /// because the still works and the row is how that permission is fixed.
    private static func showsPermissionsRow(_ context: MenuContext, phase: PanelPreviewPhase) -> Bool {
        guard context.permissionsMissing else { return false }
        if case .permissionMissing = phase { return false }
        return true
    }

    /// Window closed and a missing capture permission explain themselves in the preview. Other errors keep their
    /// fix rows.
    private static func showsFixes(_ context: MenuContext, phase: PanelPreviewPhase) -> Bool {
        guard context.displayState == .error else { return false }
        switch phase {
        case .permissionMissing, .windowClosed: false
        default: true
        }
    }

    private static func toggles(for context: MenuContext) -> [PanelToggle] {
        [
            PanelToggle(
                title: UIStrings.Menu.showCursor, symbol: "cursorarrow", isOn: context.cursor, action: .toggleCursor,
                accessibilityLabel: UIStrings.Menu.showCursor),
            PanelToggle(
                title: UIStrings.Menu.writeClickEvents, symbol: "cursorarrow.click", isOn: context.events,
                action: .toggleEvents, accessibilityLabel: UIStrings.Menu.writeClickEvents),
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
                    symbol: "doc.on.doc", accessibilityLabel: UIStrings.Menu.copyFilePath),
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
                title: UIStrings.Menu.quit, action: .quit, role: .footer, trailing: MenuShortcut.quit.display,
                shortcut: .quit))
        return rows
    }
}
