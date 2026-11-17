import Foundation
import SkreenrekControl
import SkreenrekCore

/// The size the next recording (or the armed window) gets: the window's own size, or exact pixels.
public enum SizeChoice: Sendable, Hashable {
    case keepCurrent
    case size(PixelSize)

    /// The design spec's default for the next recording.
    public static let `default` = SizeChoice.size(PixelSize(width: 1280, height: 800))

    /// `keep` or `1280x800`, the form `SettingsStore` keeps.
    public var storageValue: String {
        switch self {
        case .keepCurrent: "keep"
        case .size(let size): size.flagValue
        }
    }

    public init?(storageValue: String) {
        if storageValue == "keep" {
            self = .keepCurrent
            return
        }
        let parts = storageValue.split(separator: "x")
        guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]), w > 0, h > 0 else { return nil }
        self = .size(PixelSize(width: w, height: h))
    }

    public var pixelSize: PixelSize? {
        if case .size(let size) = self { return size }
        return nil
    }
}

/// The Size submenu's presets, in the design spec's order, with their quiet suffix.
public enum SizePresets {
    public struct Preset: Sendable, Hashable {
        public var size: PixelSize
        public var note: String?
    }

    public static let all: [Preset] = [
        Preset(size: PixelSize(width: 1280, height: 720)),
        Preset(size: PixelSize(width: 1280, height: 800)),
        Preset(size: PixelSize(width: 1440, height: 900)),
        Preset(size: PixelSize(width: 1920, height: 1080)),
        Preset(size: PixelSize(width: 1080, height: 1920), note: UIStrings.Menu.portrait),
        Preset(size: PixelSize(width: 1080, height: 1080), note: UIStrings.Menu.square),
    ]

    /// `1080 × 1920 px · portrait`.
    public static func title(_ preset: Preset) -> String {
        [preset.size.description, preset.note].compactMap { $0 }.joined(separator: UIStrings.Menu.separator)
    }
}

/// Everything the menu-bar icon and the dropdown are built from: the controller's latest snapshot plus what only the
/// UI knows.
public struct MenuContext: Sendable, Hashable {
    public var snapshot: ControllerSnapshot
    /// A failure from an action the menu started (start, resize, pick); the controller only holds recording failures.
    public var actionError: SkreenrekError?
    /// `Safari — localhost:3000` for the last clip, remembered from its recording.
    public var lastClipTitle: String?
    public var sizeChoice: SizeChoice
    public var cursor: Bool
    public var events: Bool
    /// Screen Recording or Accessibility is missing: the dropdown offers "Permissions needed…".
    public var permissionsMissing: Bool
    /// For the Last Clip row's start time.
    public var timeZone: TimeZone
    public var locale: Locale

    public init(
        snapshot: ControllerSnapshot, actionError: SkreenrekError? = nil, lastClipTitle: String? = nil,
        sizeChoice: SizeChoice = .default, cursor: Bool = true, events: Bool = true, permissionsMissing: Bool = false,
        timeZone: TimeZone = .current, locale: Locale = .current
    ) {
        self.permissionsMissing = permissionsMissing
        self.snapshot = snapshot
        self.actionError = actionError
        self.lastClipTitle = lastClipTitle
        self.sizeChoice = sizeChoice
        self.cursor = cursor
        self.events = events
        self.timeZone = timeZone
        self.locale = locale
    }

    /// The error the menu shows: the newest action error, else the controller's.
    public var error: SkreenrekError? {
        switch snapshot.state {
        case .recording, .writing: nil
        default: actionError ?? snapshot.error
        }
    }

    /// The five display states. An error wins over idle and armed; recording and writing win over an error.
    public var displayState: ControllerState {
        switch snapshot.state {
        case .recording, .writing: return snapshot.state
        default:
            if error != nil { return .error }
            return isArmed ? .armed : .idle
        }
    }

    /// A window or region is picked (the controller may report `error` while still armed).
    public var isArmed: Bool {
        switch snapshot.state {
        case .armed: true
        case .error, .idle: snapshot.window != nil || snapshot.region != nil
        case .recording, .writing: false
        }
    }

    /// `Safari — localhost:3000`, or `Screen region`.
    public var targetTitle: String? {
        if let window = snapshot.window { return UIStrings.Menu.windowTitle(app: window.app, title: window.title) }
        if snapshot.region != nil { return UIStrings.Menu.region }
        return nil
    }

    /// The short name the icon sentences use: the app, or `a screen region`.
    public var spokenTarget: String {
        if let window = snapshot.window { return window.app }
        return UIStrings.Icon.regionTarget
    }

    /// Whole seconds recorded so far.
    public var elapsedSeconds: Int {
        guard let elapsed = snapshot.elapsed, elapsed.isFinite else { return 0 }
        return max(0, Int(elapsed.rounded(.down)))
    }
}
