import Foundation
import SkreenrekControl
import SkreenrekCore

/// The size the next recording (or the armed window) gets: the window's current size, or an exact clip size in
/// pixels (a preset or custom).
public enum SizeChoice: Sendable, Hashable {
    case keepCurrent
    case size(PixelSize)

    /// Spec 13: a picked window keeps its current size until a preset is chosen.
    public static let `default` = SizeChoice.keepCurrent

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

/// The Size submenu's presets in spec 13's groups: the standard video sizes, then the shaped ones.
public enum SizePresets {
    public static let standard: [SizePreset] = [.p720, .p1080, .p1440, .uhd4k]
    public static let shaped: [SizePreset] = [.square, .portrait]
    public static let all = standard + shaped
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
    /// The display the Size presets are checked against: the armed target's, else the main display.
    public var display: DisplayInfo?
    public var cursor: Bool
    public var events: Bool
    /// The Show Control Bar switch.
    public var showControlBar: Bool
    /// The Show Recording Indicator setting.
    public var recordingIndicator: Bool
    /// Screen Recording or Accessibility is missing: the dropdown offers "Permissions needed…".
    public var permissionsMissing: Bool
    /// A newer release's version (`1.0.3`): the footer shows `Update available · 1.0.3`.
    public var updateAvailable: String?
    /// For the Last Clip row's start time.
    public var timeZone: TimeZone
    public var locale: Locale

    public init(
        snapshot: ControllerSnapshot, actionError: SkreenrekError? = nil, lastClipTitle: String? = nil,
        sizeChoice: SizeChoice = .default, display: DisplayInfo? = nil, cursor: Bool = true, events: Bool = true,
        showControlBar: Bool = true, recordingIndicator: Bool = true, permissionsMissing: Bool = false,
        updateAvailable: String? = nil, timeZone: TimeZone = .current, locale: Locale = .current
    ) {
        self.permissionsMissing = permissionsMissing
        self.updateAvailable = updateAvailable
        self.snapshot = snapshot
        self.actionError = actionError
        self.lastClipTitle = lastClipTitle
        self.sizeChoice = sizeChoice
        self.display = display ?? snapshot.display
        self.cursor = cursor
        self.events = events
        self.showControlBar = showControlBar
        self.recordingIndicator = recordingIndicator
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
