import Foundation
import SkreenrekControl
import SkreenrekCore

/// The three v2 polish directions from Designer's directions doc. Mockups only: `skreenrek debug render-ui
/// --direction a|b|c` draws them; the app, `MenuModel` and the live dropdown don't use them.
public enum UIDirection: String, CaseIterable, Sendable {
    /// Refined native: the NSMenu with a header, an icon column and a thumbnail row.
    case a
    /// Panel: a `MenuBarExtra(.window)` panel in the Control Center style.
    case b
    /// Branded native: A plus the placeholder mark and the brand accent.
    case c
}

/// The dropdown's header (A and C) or status card (B) for one moment. Pure.
public struct DirectionHeader: Sendable, Hashable {
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
    public var symbol: String
    /// The window title while recording (A and C show the state through the red tile and the time; B prefixes
    /// "Recording").
    public var title: String
    /// The detail line. While recording it's the size and frame rate only; the time is `elapsed`.
    public var detail: String
    /// `0:12` while recording or saving.
    public var elapsed: String?
    /// The error's fix items (the same ones the shipping dropdown shows).
    public var fixes: [MenuItemModel]
    /// What VoiceOver reads when it differs from the visible text (recording).
    public var spokenLabel: String? = nil

    public var accessibilityLabel: String {
        if let spokenLabel { return spokenLabel }
        return [title, elapsed, detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ". ")
    }
}

/// What the Last Clip row, or B's Last Clip card, shows.
public struct DirectionClip: Sendable, Hashable {
    public var title: String
    /// One line, as the shipping menu shows it (B).
    public var detail: String
    /// A's and C's second line: `0:42 · 1280 × 800 px · 60 fps`.
    public var summary: String
    /// A's and C's third line: the start time (`10:24`) for H.264 MP4, otherwise the format (`ProRes MOV`).
    public var note: String?
    public var path: String
    public var snippet: String
}

/// Where keyboard focus can sit in B's panel.
public enum PanelFocus: Sendable, Hashable {
    case primary
    case pickAnother
    case fix(Int)
    case discard
    case sizeTile
    case frameRateTile
    case cursorToggle
    case eventsToggle
    case clipFinder
    case clipCopyPath
    case clipSnippet
    case settings
    case more
}

/// A key B's panel handles itself, since it gives up NSMenu's keyboard navigation.
public enum PanelKey: Sendable, Hashable {
    case returnKey
    case escape
    case tab
    case backTab
}

public enum PanelCommand: Sendable, Hashable {
    case perform(MenuAction)
    case close
    case focus(PanelFocus)
}

/// Maps the same `MenuContext` the shipping dropdown uses to the directions' pieces. Pure, so tests cover it.
public enum DirectionModel {
    // MARK: - Header

    public static func header(for context: MenuContext) -> DirectionHeader {
        switch context.displayState {
        case .recording:
            let target = context.targetTitle ?? UIStrings.Menu.region
            return DirectionHeader(
                kind: .recording, symbol: StatusIconModel.Symbol.recording, title: target,
                detail: sizeAndRate(context), elapsed: TimeFormat.minutesSeconds(Double(context.elapsedSeconds)),
                fixes: [],
                spokenLabel: UIStrings.Directions.recordingLabel(target: target, seconds: context.elapsedSeconds))
        case .writing:
            return DirectionHeader(
                kind: .saving, symbol: StatusIconModel.Symbol.writing, title: UIStrings.Menu.savingClip,
                detail: MenuModel.recordingDetail(context), elapsed: nil, fixes: [])
        case .error:
            let presentation = ErrorPresentation(
                context.error ?? .internal(message: ""), lastClip: context.snapshot.lastClip)
            return DirectionHeader(
                kind: .error, symbol: "exclamationmark.triangle.fill", title: presentation.row.title,
                detail: presentation.row.detail, elapsed: nil, fixes: presentation.fixes)
        case .armed:
            let row = MenuModel.armedRow(context)
            let exact = context.snapshot.readback?.exact ?? true
            return DirectionHeader(
                kind: exact ? .armed : .notExact, symbol: StatusIconModel.Symbol.armed, title: row.title,
                detail: row.detail, elapsed: nil, fixes: [])
        case .idle:
            let row = MenuModel.idleRow
            return DirectionHeader(
                kind: .idle, symbol: row.symbol, title: row.title, detail: row.detail, elapsed: nil, fixes: [])
        }
    }

    /// `1280 × 800 px · 60 fps`.
    public static func sizeAndRate(_ context: MenuContext) -> String {
        var parts: [String] = []
        if let size = context.snapshot.size { parts.append(size.description) }
        parts.append(UIStrings.Menu.fps(context.snapshot.fps))
        return parts.joined(separator: UIStrings.Menu.separator)
    }

    /// B's recording line: `1280 × 800 px · 60 fps · started by Claude Code`.
    public static func panelRecordingDetail(_ context: MenuContext) -> String {
        var parts = [sizeAndRate(context)]
        if let origin = originFragment(context.snapshot) { parts.append(origin) }
        return parts.joined(separator: UIStrings.Menu.separator)
    }

    static func originFragment(_ snapshot: ControllerSnapshot) -> String? {
        switch snapshot.startedBy {
        case .mcp:
            if let client = snapshot.client?.trimmingCharacters(in: .whitespacesAndNewlines), !client.isEmpty {
                return UIStrings.Directions.startedBy(client: client)
            }
            return UIStrings.Directions.startedOverMCP
        case .menu: return UIStrings.Directions.startedFromMenu
        case .cli: return UIStrings.Directions.startedFromCommandLine
        case nil: return nil
        }
    }

    // MARK: - Menu icons (A and C)

    /// The 16 pt leading symbol for a dropdown item, or nil (Quit, info rows and fix items have none).
    public static func symbol(for action: MenuAction?) -> String? {
        switch action {
        case .pickWindow: "macwindow"
        case .toggleCursor: "cursorarrow"
        case .toggleEvents: "cursorarrow.click"
        case .record: "record.circle"
        case .openOutputFolder: "folder"
        case .openSettings: "gearshape"
        case .stop: "stop.fill"
        case .discard: "trash"
        case .showInFinder: "folder"
        case .copyFilePath: "doc.on.doc"
        case .copySnippet: "chevron.left.forwardslash.chevron.right"
        case .copyErrorDetails: "doc.on.clipboard"
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

    // MARK: - Last Clip

    public static func lastClip(for context: MenuContext) -> DirectionClip? {
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
        return DirectionClip(
            title: context.lastClipTitle ?? fallback ?? clip.recording.id,
            detail: MenuModel.lastClipDetail(clip, timeZone: context.timeZone, locale: context.locale),
            summary: summary, note: note, path: clip.files.clip, snippet: clip.snippet)
    }

    // MARK: - Panel (B)

    /// The primary button's action: Pick Window… when nothing is picked, Record Window when armed, Stop Recording
    /// while recording, none while saving.
    public static func primaryAction(for context: MenuContext) -> MenuAction? {
        switch context.displayState {
        case .recording: .stop
        case .writing: nil
        case .idle, .armed, .error: context.isArmed ? .record : .pickWindow
        }
    }

    /// Tab order: the primary button, then the tiles, the toggles and the clip buttons, as the directions doc
    /// specifies. Pick Another Window… and an error's fix buttons follow the primary button; the two header buttons
    /// come last so Settings and Quit stay reachable from the keyboard.
    public static func focusOrder(for context: MenuContext) -> [PanelFocus] {
        switch context.displayState {
        case .recording: return [.primary, .discard, .settings, .more]
        case .writing: return [.settings, .more]
        case .idle, .armed, .error:
            var order: [PanelFocus] = [.primary]
            if context.isArmed { order.append(.pickAnother) }
            order += header(for: context).fixes.indices.map { .fix($0) }
            order += [.sizeTile, .frameRateTile, .cursorToggle, .eventsToggle]
            if context.snapshot.lastClip != nil { order += [.clipFinder, .clipCopyPath, .clipSnippet] }
            order += [.settings, .more]
            return order
        }
    }

    /// Where focus starts when the panel opens.
    public static func initialFocus(for context: MenuContext) -> PanelFocus? {
        focusOrder(for: context).first
    }

    /// Return triggers the primary button wherever focus is, Esc closes the panel, Tab and Shift-Tab walk the order
    /// (wrapping).
    public static func command(for key: PanelKey, focus: PanelFocus?, context: MenuContext) -> PanelCommand? {
        switch key {
        case .returnKey:
            return primaryAction(for: context).map { .perform($0) }
        case .escape:
            return .close
        case .tab, .backTab:
            let order = focusOrder(for: context)
            guard !order.isEmpty else { return nil }
            guard let focus, let index = order.firstIndex(of: focus) else {
                return .focus(key == .tab ? order[0] : order[order.count - 1])
            }
            let step = key == .tab ? 1 : order.count - 1
            return .focus(order[(index + step) % order.count])
        }
    }
}
