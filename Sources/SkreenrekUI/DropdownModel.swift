import Foundation
import SkreenrekControl
import SkreenrekCore

/// The dropdown's branded header for one moment: the brand tile, the title and the detail, on a tinted band.
public struct DropdownHeader: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case idle
        case armed
        /// Armed, but the read-back disagrees with the requested size.
        case notExact
        case recording
        case saving
        case error
    }

    public var kind: Kind
    /// The SF Symbol the tile falls back to (idle and armed show the brand mark).
    public var symbol: String
    /// `Ready`, the window title, `Recording Safari — localhost:3000`, `Saving clip…` or the error's title.
    public var title: String
    /// The detail line. While recording it's the size and frame rate only; the time is `elapsed`.
    public var detail: String
    /// `0:12` while recording.
    public var elapsed: String?
    /// The error's fix items. The dropdown shows them as menu items right under the header.
    public var fixes: [MenuItemModel]
    /// What VoiceOver reads when it differs from the visible text (recording, not exact).
    public var spokenLabel: String? = nil
    /// The header's tooltip (not exact): the reason the size isn't exact.
    public var help: String? = nil
    /// The compact pill at the header's trailing edge: Record once a window is picked, Stop with the time while
    /// recording. The same actions stay in the menu below, with their shortcuts.
    public var control: HeaderControl? = nil

    public var accessibilityLabel: String {
        if let spokenLabel { return spokenLabel }
        return [title, elapsed, detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ". ")
    }
}

/// The header's compact pill: a small red dot and `Record`, or a red square, `Stop` and the elapsed time.
public struct HeaderControl: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case record
        case stop
    }

    public var kind: Kind
    public var title: String
    /// `0:12` on the Stop pill.
    public var elapsed: String?
    public var action: MenuAction
    /// Record is dimmed until a window is picked, like the Record Window item.
    public var enabled: Bool
    public var accessibilityLabel: String

    public static func record(enabled: Bool) -> HeaderControl {
        HeaderControl(
            kind: .record, title: UIStrings.Brand.record, elapsed: nil, action: .record, enabled: enabled,
            accessibilityLabel: UIStrings.Menu.recordWindow)
    }

    public static func stop(seconds: Int) -> HeaderControl {
        HeaderControl(
            kind: .stop, title: UIStrings.Brand.stop, elapsed: TimeFormat.minutesSeconds(Double(seconds)),
            action: .stop, enabled: true, accessibilityLabel: UIStrings.Brand.stopLabel(seconds: seconds))
    }
}

/// What the Last Clip row shows: a thumbnail of the first frame, the title and a two-line detail.
public struct DropdownClip: Sendable, Hashable {
    public var title: String
    /// The shipping one-line detail (`0:42 · 1280 × 800 px · 60 fps · 10:24`), for VoiceOver.
    public var detail: String
    /// The first detail line: `0:42 · 1280 × 800 px · 60 fps`.
    public var summary: String
    /// The second detail line: the start time (`10:24`) for H.264 MP4, otherwise the format (`ProRes MOV`).
    public var note: String?
    /// The clip file, for the thumbnail.
    public var path: String
    /// The newest clip from this session: the thumbnail gets the accent stroke.
    public var isNewest: Bool

    public var accessibilityLabel: String {
        "\(title). \(detail)"
    }
}

/// One row of the dropdown: `MenuModel`'s entries with the state row swapped for the header and the Last Clip status
/// row swapped for the thumbnail row. Everything else is the same menu.
public enum DropdownRow: Sendable, Hashable {
    case header(DropdownHeader)
    case item(MenuItemModel)
    /// The disabled "Started by …" row: 11 pt tertiary, no icon, indented to the text column.
    case info(String)
    case submenu(SubmenuModel)
    case sectionHeader(String)
    case clip(DropdownClip)
    case separator
}

/// Maps the same `MenuContext` and `MenuModel` entries the behaviour tests cover to the dropdown's rows. Pure, so
/// tests cover it.
public enum DropdownModel {
    // MARK: - Rows

    public static func rows(for context: MenuContext) -> [DropdownRow] {
        var rows: [DropdownRow] = []
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

    /// True when `a` and `b` differ only in their header (the elapsed time), so the open menu can update the header
    /// in place and keep hover and focus.
    public static func onlyHeaderDiffers(_ a: [DropdownRow], _ b: [DropdownRow]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { ($0.isHeader && $1.isHeader) || $0 == $1 }
    }

    // MARK: - Header

    public static func header(for context: MenuContext) -> DropdownHeader {
        switch context.displayState {
        case .recording:
            let target = context.targetTitle ?? UIStrings.Menu.region
            return DropdownHeader(
                kind: .recording, symbol: StatusIconModel.Symbol.recording, title: UIStrings.Menu.recording(target),
                detail: sizeAndRate(context), elapsed: TimeFormat.minutesSeconds(Double(context.elapsedSeconds)),
                fixes: [],
                spokenLabel: UIStrings.Brand.recordingLabel(target: target, seconds: context.elapsedSeconds),
                control: .stop(seconds: context.elapsedSeconds))
        case .writing:
            return DropdownHeader(
                kind: .saving, symbol: StatusIconModel.Symbol.writing, title: UIStrings.Menu.savingClip,
                detail: MenuModel.recordingDetail(context), elapsed: nil, fixes: [])
        case .error:
            let presentation = ErrorPresentation(
                context.error ?? .internal(message: ""), lastClip: context.snapshot.lastClip)
            return DropdownHeader(
                kind: .error, symbol: "exclamationmark.triangle.fill", title: presentation.row.title,
                detail: presentation.row.detail, elapsed: nil, fixes: presentation.fixes)
        case .armed:
            let row = MenuModel.armedRow(context)
            guard let readback = context.snapshot.readback, context.snapshot.window != nil, !readback.exact else {
                return DropdownHeader(
                    kind: .armed, symbol: StatusIconModel.Symbol.armed, title: row.title, detail: row.detail,
                    elapsed: nil, fixes: [], control: .record(enabled: true))
            }
            // One line: `1286 × 800 px · not exact`; the reason moves to the tooltip and VoiceOver.
            let reason = ExactResizer.reason(requested: readback.requested, actuals: [readback.actual])
            let sentence = UIStrings.Brand.notExactReason(
                app: readback.window.app, reason: reason, requested: readback.requested, actual: readback.actual)
            return DropdownHeader(
                kind: .notExact, symbol: StatusIconModel.Symbol.armed, title: row.title, detail: row.detail,
                elapsed: nil, fixes: [], spokenLabel: "\(row.title). \(sentence)", help: sentence, control: .record(enabled: true))
        case .idle:
            let row = MenuModel.idleRow
            return DropdownHeader(
                kind: .idle, symbol: row.symbol, title: row.title, detail: row.detail, elapsed: nil, fixes: [],
                control: .record(enabled: false))
        }
    }

    /// `1280 × 800 px · 60 fps`.
    public static func sizeAndRate(_ context: MenuContext) -> String {
        var parts: [String] = []
        if let size = context.snapshot.size { parts.append(size.description) }
        parts.append(UIStrings.Menu.fps(context.snapshot.fps))
        return parts.joined(separator: UIStrings.Menu.separator)
    }

    // MARK: - Menu icons

    /// The 16 pt leading symbol for a dropdown item, or nil (Quit, info rows and fix items have none).
    public static func symbol(for action: MenuAction?) -> String? {
        switch action {
        case .pickWindow: "macwindow"
        case .toggleCursor: "cursorarrow"
        case .toggleEvents: "cursorarrow.click"
        case .toggleControlBar: PanelSymbol.controlBar
        case .record: "record.circle"
        case .openOutputFolder: "folder"
        case .openSettings: "gearshape"
        case .stop: "stop.fill"
        case .discard: "trash"
        case .showInFinder: "folder"
        case .copyFilePath: "doc.on.doc"
        case .copySnippet: "chevron.left.forwardslash.chevron.right"
        case .copyErrorDetails: "doc.on.clipboard"
        case .showPermissions: "hand.raised"
        case .checkForUpdates: "arrow.triangle.2.circlepath"
        default: nil
        }
    }

    /// Size uses `aspectratio`, Frame Rate `speedometer`.
    public static func symbol(forSubmenu title: String) -> String? {
        switch title {
        case UIStrings.Menu.size: "aspectratio"
        case UIStrings.Menu.frameRate: "speedometer"
        default: nil
        }
    }

    /// How a leading icon is coloured.
    public enum IconTint: Sendable, Hashable {
        /// `.secondary`, the default.
        case neutral
        /// The primary item: Pick Window… before a window is picked.
        case accent
        /// Record Window once armed, and Stop Recording.
        case red
    }

    public static func iconTint(for item: MenuItemModel, context: MenuContext) -> IconTint {
        if item.action == .stop { return .red }
        guard isPrimary(item, context: context) else { return .neutral }
        return item.action == .record ? .red : .accent
    }

    /// The primary item: Record Window once a window is picked, otherwise Pick Window…. Stop is red on its own.
    static func isPrimary(_ item: MenuItemModel, context: MenuContext) -> Bool {
        guard item.enabled else { return false }
        switch context.displayState {
        case .recording, .writing: return false
        case .idle, .armed, .error: return item.action == (context.isArmed ? .record : .pickWindow)
        }
    }

    // MARK: - Last Clip

    public static func lastClip(for context: MenuContext) -> DropdownClip? {
        guard let clip = context.snapshot.lastClip else { return nil }
        let fallback = clip.readback.map { UIStrings.Menu.windowTitle(app: $0.window.app, title: $0.window.title) }
        let r = clip.recording
        let summary = [
            TimeFormat.minutesSeconds(r.duration), PixelSize(width: r.width, height: r.height).description,
            "\(r.fps) fps",
        ].joined(separator: UIStrings.Menu.separator)
        let note =
            ClipFormatLabel.suffix(codec: r.codec.rawValue, clipPath: clip.files.clip)
            ?? MenuModel.startTime(r.startedAt, timeZone: context.timeZone, locale: context.locale)
        return DropdownClip(
            title: context.lastClipTitle ?? fallback ?? clip.recording.id,
            detail: MenuModel.lastClipDetail(clip, timeZone: context.timeZone, locale: context.locale),
            summary: summary, note: note, path: clip.files.clip, isNewest: context.lastClipTitle != nil)
    }
}

extension DropdownRow {
    var isHeader: Bool {
        if case .header = self { return true }
        return false
    }
}
