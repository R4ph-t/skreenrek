import Foundation
import SkreenrekControl
import SkreenrekCore

/// What a dropdown item does. The menu controller hands it to `AppModel.perform(_:)`.
public enum MenuAction: Sendable, Hashable {
    case pickWindow
    case record
    case stop
    case discard
    case openOutputFolder
    case openSettings
    case quit
    case toggleCursor
    case toggleEvents
    case chooseSize(SizeChoice)
    case customSize
    case chooseFrameRate(FrameRate)
    case showInFinder(path: String)
    case copyFilePath(path: String)
    case copySnippet(String)
    case copyErrorDetails(String)
    case openPrivacySettings(Permission)
    case chooseOutputFolder
    /// Opens onboarding step 1, where each missing permission can be allowed.
    case showPermissions
}

/// A key equivalent shown in the dropdown. No numeric shortcuts.
public enum MenuShortcut: Sendable, Hashable {
    /// ⌘,
    case settings
    /// ⌘Q
    case quit
    /// ⌃⌘⎋, also the global stop hot key while recording.
    case stop

    /// The key equivalent string `NSMenuItem` takes.
    public var key: String {
        switch self {
        case .settings: ","
        case .quit: "q"
        case .stop: "\u{1b}"
        }
    }

    public var control: Bool { self == .stop }

    /// `⌘,`, `⌘Q`, `⌃⌘⎋`, as the dropdown prints them.
    public var display: String {
        switch self {
        case .settings: "⌘,"
        case .quit: "⌘Q"
        case .stop: "⌃⌘⎋"
        }
    }
}

/// A 48 pt row with a symbol, a title line and a quieter detail line.
public struct StatusRow: Sendable, Hashable {
    public enum Tint: Sendable, Hashable {
        case none
        case red
    }

    public var symbol: String
    public var tint: Tint
    public var title: String
    /// The state rows (Ready, Recording…, errors) set their title in semibold; the Last Clip row doesn't.
    public var emphasized: Bool
    public var detail: String
    /// A longer explanation for the tooltip and VoiceOver, kept out of the one-line detail (the not-exact reason).
    public var toolTip: String?
    /// The accessibility sentence for the row: title, detail and the explanation when there is one.
    public var accessibilityLabel: String {
        ["\(title). \(detail)", toolTip].compactMap { $0 }.joined(separator: ". ")
    }

    public init(
        symbol: String, tint: Tint = .none, title: String, emphasized: Bool = true, detail: String,
        toolTip: String? = nil
    ) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.emphasized = emphasized
        self.detail = detail
        self.toolTip = toolTip
    }
}

public struct MenuItemModel: Sendable, Hashable {
    public var title: String
    /// nil for the disabled info row.
    public var action: MenuAction?
    public var enabled: Bool
    public var checked: Bool
    public var shortcut: MenuShortcut?
    /// A quiet value at the row's end in 12 pt secondary, e.g. a preset's `1920 × 1080`.
    public var trailing: String?
    /// Why a disabled row is disabled.
    public var toolTip: String?
    /// Stop Recording while recording.
    public var isDefault: Bool

    public init(
        _ title: String, action: MenuAction?, enabled: Bool = true, checked: Bool = false,
        shortcut: MenuShortcut? = nil, isDefault: Bool = false, trailing: String? = nil, toolTip: String? = nil
    ) {
        self.title = title
        self.action = action
        self.enabled = enabled && action != nil
        self.checked = checked
        self.shortcut = shortcut
        self.isDefault = isDefault
        self.trailing = trailing
        self.toolTip = toolTip
    }
}

public struct SubmenuModel: Sendable, Hashable {
    public var title: String
    /// The current choice, shown at the end of the row in the quiet colour.
    public var detail: String?
    public var entries: [MenuEntry]
}

public indirect enum MenuEntry: Sendable, Hashable {
    case status(StatusRow)
    case item(MenuItemModel)
    case header(String)
    case separator
    case submenu(SubmenuModel)
}

/// Builds the dropdown for one moment. Pure: the AppKit menu only renders it.
public enum MenuModel {
    public static func entries(for context: MenuContext) -> [MenuEntry] {
        switch context.displayState {
        case .recording: return recordingEntries(context)
        case .writing: return writingEntries(context)
        case .idle, .armed, .error: return idleEntries(context)
        }
    }

    // MARK: - States

    private static func idleEntries(_ context: MenuContext) -> [MenuEntry] {
        var entries: [MenuEntry] = []
        if let error = context.error {
            entries += errorEntries(error, lastClip: context.snapshot.lastClip)
        } else {
            entries.append(.status(context.isArmed ? armedRow(context) : idleRow))
        }
        if context.permissionsMissing {
            entries.append(.item(MenuItemModel(UIStrings.Menu.permissionsNeeded, action: .showPermissions)))
        }
        entries.append(.separator)
        entries.append(
            .item(
                MenuItemModel(
                    context.isArmed ? UIStrings.Menu.pickAnotherWindow : UIStrings.Menu.pickWindow,
                    action: .pickWindow)))
        entries.append(.submenu(sizeSubmenu(context.sizeChoice, display: context.display, window: context.snapshot.window)))
        entries.append(.submenu(frameRateSubmenu(context.snapshot.fps)))
        entries.append(.separator)
        entries.append(.item(MenuItemModel(UIStrings.Menu.showCursor, action: .toggleCursor, checked: context.cursor)))
        entries.append(
            .item(MenuItemModel(UIStrings.Menu.writeClickEvents, action: .toggleEvents, checked: context.events)))
        entries.append(.separator)
        entries.append(.item(MenuItemModel(UIStrings.Menu.recordWindow, action: .record, enabled: context.isArmed)))
        if let clip = context.snapshot.lastClip {
            entries.append(.separator)
            entries += lastClipEntries(clip, title: context.lastClipTitle, context: context)
        }
        entries.append(.separator)
        entries += footer
        return entries
    }

    private static func recordingEntries(_ context: MenuContext) -> [MenuEntry] {
        let title = UIStrings.Menu.recording(context.targetTitle ?? UIStrings.Menu.region)
        var entries: [MenuEntry] = [
            .status(
                StatusRow(
                    symbol: StatusIconModel.Symbol.recording, tint: .red, title: title,
                    detail: recordingDetail(context)))
        ]
        if let origin = originRow(context.snapshot) { entries.append(.item(MenuItemModel(origin, action: nil))) }
        entries.append(.separator)
        entries.append(
            .item(MenuItemModel(UIStrings.Menu.stopRecording, action: .stop, shortcut: .stop, isDefault: true)))
        entries.append(.item(MenuItemModel(UIStrings.Menu.discardRecording, action: .discard)))
        entries.append(.separator)
        entries += footer
        return entries
    }

    private static func writingEntries(_ context: MenuContext) -> [MenuEntry] {
        var entries: [MenuEntry] = [
            .status(
                StatusRow(
                    symbol: StatusIconModel.Symbol.writing, title: UIStrings.Menu.savingClip,
                    detail: recordingDetail(context)))
        ]
        if let origin = originRow(context.snapshot) { entries.append(.item(MenuItemModel(origin, action: nil))) }
        entries.append(.separator)
        entries += footer
        return entries
    }

    private static var footer: [MenuEntry] {
        [
            .item(MenuItemModel(UIStrings.Menu.openOutputFolder, action: .openOutputFolder)),
            .item(MenuItemModel(UIStrings.Menu.settings, action: .openSettings, shortcut: .settings)),
            .item(MenuItemModel(UIStrings.Menu.quit, action: .quit, shortcut: .quit)),
        ]
    }

    // MARK: - Status rows

    static let idleRow = StatusRow(
        symbol: StatusIconModel.Symbol.idle, title: UIStrings.Menu.ready, detail: UIStrings.Menu.noWindowPicked)

    /// `viewfinder` · window title · `1920 × 1080 px · 60 fps`. A size that isn't exact stays one line,
    /// `1286 × 800 px · not exact`, with the full reason in the tooltip and VoiceOver. A window that was picked
    /// but not resized yet shows its size alone.
    static func armedRow(_ context: MenuContext) -> StatusRow {
        let snapshot = context.snapshot
        let size = snapshot.size?.description ?? ""
        var note: String? = size.isEmpty ? nil : UIStrings.Menu.fps(snapshot.fps)
        var toolTip: String?
        if let readback = snapshot.readback, snapshot.window != nil, !readback.exact {
            note = UIStrings.Menu.notExact
            toolTip = UIStrings.Menu.notExactReason(
                app: readback.window.app, requested: readback.requested, actual: readback.actual,
                reason: ExactResizer.reason(requested: readback.requested, actuals: [readback.actual]))
        }
        let detail = [size, note].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: UIStrings.Menu.separator)
        return StatusRow(
            symbol: StatusIconModel.Symbol.armed, title: context.targetTitle ?? UIStrings.Menu.region, detail: detail,
            toolTip: toolTip)
    }

    /// `0:12 · 1280 × 800 px · 60 fps`.
    static func recordingDetail(_ context: MenuContext) -> String {
        var parts = [TimeFormat.minutesSeconds(Double(context.elapsedSeconds))]
        if let size = context.snapshot.size { parts.append(size.description) }
        parts.append(UIStrings.Menu.fps(context.snapshot.fps))
        return parts.joined(separator: UIStrings.Menu.separator)
    }

    /// "Started by Claude Code over MCP", "Started from the menu", "Started from the command line".
    static func originRow(_ snapshot: ControllerSnapshot) -> String? {
        switch snapshot.startedBy {
        case .mcp:
            if let client = snapshot.client?.trimmingCharacters(in: .whitespacesAndNewlines), !client.isEmpty {
                return UIStrings.Menu.startedBy(client: client)
            }
            return UIStrings.Menu.startedOverMCP
        case .menu: return UIStrings.Menu.startedFromMenu
        case .cli: return UIStrings.Menu.startedFromCommandLine
        case nil: return nil
        }
    }

    // MARK: - Errors

    /// The error-copy table: a status row, then its fix items.
    public static func errorEntries(_ error: SkreenrekError, lastClip: StopBody?) -> [MenuEntry] {
        let presentation = ErrorPresentation(error, lastClip: lastClip)
        return [.status(presentation.row)] + presentation.fixes.map { .item($0) }
    }

    // MARK: - Last Clip

    static func lastClipEntries(_ clip: StopBody, title: String?, context: MenuContext) -> [MenuEntry] {
        let fallback = clip.readback.map { UIStrings.Menu.windowTitle(app: $0.window.app, title: $0.window.title) }
        return [
            .header(UIStrings.Menu.lastClip),
            .status(
                StatusRow(
                    symbol: StatusIconModel.Symbol.lastClip, title: title ?? fallback ?? clip.recording.id,
                    emphasized: false,
                    detail: lastClipDetail(clip, timeZone: context.timeZone, locale: context.locale))),
            .item(MenuItemModel(UIStrings.Menu.showInFinder, action: .showInFinder(path: clip.files.clip))),
            .item(MenuItemModel(UIStrings.Menu.copyFilePath, action: .copyFilePath(path: clip.files.clip))),
            .item(MenuItemModel(UIStrings.Menu.copySnippet, action: .copySnippet(clip.snippet))),
        ]
    }

    /// Non-default formats replace the clock time, keeping the detail on one line.
    public static func lastClipDetail(_ clip: StopBody, timeZone: TimeZone = .current, locale: Locale = .current)
        -> String
    {
        let r = clip.recording
        var parts = [
            TimeFormat.minutesSeconds(r.duration), PixelSize(width: r.width, height: r.height).description,
            "\(r.fps) fps",
        ]
        if let format = ClipFormatLabel.suffix(codec: r.codec.rawValue, clipPath: clip.files.clip) {
            parts.append(format)
        } else if let time = startTime(r.startedAt, timeZone: timeZone, locale: locale) { parts.append(time) }
        return parts.joined(separator: UIStrings.Menu.separator)
    }

    /// The local clock time a clip started, e.g. `10:42` (follows the Mac's 12/24-hour setting).
    static func startTime(_ timestamp: String, timeZone: TimeZone, locale: Locale) -> String? {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp) else {
            return nil
        }
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone
        style.locale = locale
        return date.formatted(style)
    }

    // MARK: - Submenus

    /// Spec 13's Size submenu: 720p, 1080p, 1440p, 4K · Square, Portrait · Current Size, Custom…, each preset with
    /// its clip px trailing. A preset that can't fit `display` without scaling up is disabled with a tooltip saying
    /// why. Current Size shows the window's current clip px (window pt × display scale).
    public static func sizeSubmenu(_ choice: SizeChoice, display: DisplayInfo? = nil, window: WindowInfo? = nil)
        -> SubmenuModel
    {
        func rows(_ presets: [SizePreset]) -> [MenuEntry] {
            presets.map { preset in
                var toolTip: String?
                if let display, case .failure(let failure) = WindowFit.plan(clip: preset.size, on: display) {
                    toolTip = failure.tooltip
                }
                return .item(
                    MenuItemModel(
                        preset.title, action: .chooseSize(.size(preset.size)), enabled: toolTip == nil,
                        checked: choice == .size(preset.size), trailing: UIStrings.Menu.dimensions(preset.size),
                        toolTip: toolTip))
            }
        }
        let current = window.flatMap { window in display.map { window.frame.pixelSize(scale: $0.scale) } }
        let preset = choice.pixelSize.flatMap(SizePreset.init(size:))
        var entries = rows(SizePresets.standard) + [.separator] + rows(SizePresets.shaped) + [.separator]
        entries.append(
            .item(
                MenuItemModel(
                    UIStrings.Menu.currentSize, action: .chooseSize(.keepCurrent), checked: choice == .keepCurrent,
                    trailing: current.map(UIStrings.Menu.dimensions))))
        entries.append(
            .item(
                MenuItemModel(
                    UIStrings.Menu.customSize, action: .customSize, checked: preset == nil && choice != .keepCurrent)))
        let detail: String =
            switch choice {
            case .keepCurrent: UIStrings.Menu.currentSize
            case .size(let size): preset?.title ?? UIStrings.Menu.dimensions(size)
            }
        return SubmenuModel(title: UIStrings.Menu.size, detail: detail, entries: entries)
    }

    public static func frameRateSubmenu(_ fps: FrameRate) -> SubmenuModel {
        SubmenuModel(
            title: UIStrings.Menu.frameRate, detail: UIStrings.Menu.fps(fps),
            entries: FrameRate.allCases.map {
                .item(MenuItemModel(UIStrings.Menu.fps($0), action: .chooseFrameRate($0), checked: $0 == fps))
            })
    }
}

/// The format suffix for a clip that isn't H.264 MP4: `ProRes MOV`, `HEVC MP4`, `H.264 MOV`.
public enum ClipFormatLabel {
    /// `codec` is the read-back's codec string; the container comes from the clip's extension (a clip from before
    /// formats existed is `.mp4`). Nil for the default H.264 MP4.
    public static func suffix(codec: String, clipPath: String) -> String? {
        let container = URL(fileURLWithPath: clipPath).pathExtension.lowercased() == "mov" ? "mov" : "mp4"
        guard codec != "h264" || container != "mp4" else { return nil }
        return "\(codecLabel(codec)) \(container.uppercased())"
    }

    public static func codecLabel(_ codec: String) -> String {
        switch codec {
        case "h264": "H.264"
        case "hevc": "HEVC"
        case "prores": "ProRes"
        default: codec.uppercased()
        }
    }
}

/// One row of the design spec's error-copy table: title, detail and fix items.
public struct ErrorPresentation: Sendable, Hashable {
    public var row: StatusRow
    public var fixes: [MenuItemModel]

    public init(_ error: SkreenrekError, lastClip: StopBody?) {
        let title: String
        var detail = error.message
        var fixes: [MenuItemModel] = []
        let showClip = lastClip.map {
            MenuItemModel(UIStrings.Menu.showInFinder, action: .showInFinder(path: $0.files.clip))
        }
        let copyDetails = MenuItemModel(
            UIStrings.Errors.copyErrorDetails, action: .copyErrorDetails(UIStrings.Errors.details(error)))
        switch error {
        case .recordingFailed(.windowClosed):
            title = UIStrings.Errors.recordingStopped
            fixes = [showClip, copyDetails].compactMap { $0 }
        case .recordingFailed(.diskLow):
            title = UIStrings.Errors.recordingStopped
            fixes = [showClip].compactMap { $0 }
        case .recordingFailed(.notWritable):
            title = UIStrings.Errors.couldntSave
            fixes = [MenuItemModel(UIStrings.Errors.chooseOutputFolder, action: .chooseOutputFolder)]
        case .recordingFailed(.other):
            title = UIStrings.Errors.recordingStopped
            fixes = [showClip, copyDetails].compactMap { $0 }
        case .permissionDenied(.screenRecording):
            title = UIStrings.Errors.screenRecordingOff
            detail = UIStrings.Errors.screenRecordingDetail
            fixes = [
                MenuItemModel(UIStrings.Errors.openPrivacySettings, action: .openPrivacySettings(.screenRecording))
            ]
        case .permissionDenied(.directCapture):
            title = UIStrings.Errors.directCaptureOff
            detail = UIStrings.Errors.directCaptureDetail
            fixes = [MenuItemModel(UIStrings.Menu.permissionsNeeded, action: .showPermissions)]
        case .permissionDenied(.accessibility):
            title = UIStrings.Errors.cantResize
            detail = UIStrings.Errors.cantResizeDetail
            fixes = [
                MenuItemModel(UIStrings.Errors.openAccessibilitySettings, action: .openPrivacySettings(.accessibility))
            ]
        case .notExact:
            title = UIStrings.Errors.notExact
            fixes = [MenuItemModel(UIStrings.Errors.pickAnotherSize, action: .customSize)]
        default:
            title = UIStrings.Errors.somethingWentWrong
            detail = error.message.split(separator: "\n").first.map(String.init) ?? error.message
            fixes = [copyDetails]
        }
        row = StatusRow(symbol: StatusIconModel.Symbol.error, title: title, detail: detail)
        self.fixes = fixes
    }
}
