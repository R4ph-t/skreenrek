import Foundation
import SkreenrekControl
import SkreenrekCore

/// The picked window, as the on-screen outline needs it.
public struct SelectionOutlineTarget: Sendable, Hashable {
    public var window: WindowInfo
    public var title: String

    public init(window: WindowInfo) {
        self.window = window
        title = UIStrings.Menu.windowTitle(app: window.app, title: window.title)
    }
}

/// Where the picked window is right now.
public enum WindowPresence: Sendable, Hashable {
    case onScreen(PointRect)
    /// Minimised, hidden, on another Space, or closed.
    case notVisible
}

/// What a recording asks of the outline (control bar addendum 2, §A).
public enum SelectionOutlineCapture: Sendable, Hashable {
    /// No recording: the pick rules.
    case none
    /// A window recording with the indicator on: the red frame around the target.
    case recordingWindow
    /// A region recording with the indicator on: a square red frame around this rect, top-left global points.
    case recordingRegion(PointRect)
    /// A recording with no frame: the indicator is off, `--no-hud`, or the region is the whole screen.
    case recordingHidden
    /// The clip is being written. `keepsPick`: the window stays picked (bar on), so the pick rules apply again.
    case saving(keepsPick: Bool)

    var isRecording: Bool {
        switch self {
        case .recordingWindow, .recordingRegion, .recordingHidden: true
        case .none, .saving: false
        }
    }
}

/// Everything outside the outline that decides whether it shows.
public struct SelectionOutlineInput: Sendable, Hashable {
    public var target: SelectionOutlineTarget?
    public var pickCount: Int
    public var capture: SelectionOutlineCapture
    public var pickerOpen: Bool
    public var panelOpen: Bool
    /// The control bar is up around this window. The outline stays with it.
    public var controlBarVisible: Bool
    public var windowClosed: Bool
    public var reduceMotion: Bool
    public var increaseContrast: Bool

    public init(
        target: SelectionOutlineTarget?, pickCount: Int = 0, capture: SelectionOutlineCapture = .none,
        pickerOpen: Bool = false, panelOpen: Bool = false, controlBarVisible: Bool = false,
        windowClosed: Bool = false, reduceMotion: Bool = false, increaseContrast: Bool = false
    ) {
        self.target = target
        self.pickCount = pickCount
        self.capture = capture
        self.pickerOpen = pickerOpen
        self.panelOpen = panelOpen
        self.controlBarVisible = controlBarVisible
        self.windowClosed = windowClosed
        self.reduceMotion = reduceMotion
        self.increaseContrast = increaseContrast
    }

    /// `recordingIndicator` is the Show recording indicator setting. With `snapshot.hud` it is the bar's and the
    /// HUD's rule: the red frame is a recording indicator.
    public init(
        snapshot: ControllerSnapshot, panelOpen: Bool, windowClosed: Bool, reduceMotion: Bool,
        increaseContrast: Bool, controlBarVisible: Bool = false, recordingIndicator: Bool = true
    ) {
        self.init(
            target: snapshot.window.map(SelectionOutlineTarget.init(window:)), pickCount: snapshot.pickCount,
            capture: Self.capture(snapshot, recordingIndicator: recordingIndicator), pickerOpen: snapshot.picking,
            panelOpen: panelOpen, controlBarVisible: controlBarVisible, windowClosed: windowClosed,
            reduceMotion: reduceMotion, increaseContrast: increaseContrast)
    }

    static func capture(_ snapshot: ControllerSnapshot, recordingIndicator: Bool) -> SelectionOutlineCapture {
        switch snapshot.state {
        case .recording:
            guard recordingIndicator, snapshot.hud else { return .recordingHidden }
            if snapshot.window != nil { return .recordingWindow }
            guard let region = snapshot.region, let display = snapshot.display else { return .recordingHidden }
            let rect = SelectionOutlineModel.regionFrame(region, on: display)
            return SelectionOutlineModel.coversScreen(rect, display: display) ? .recordingHidden : .recordingRegion(rect)
        case .writing:
            return .saving(keepsPick: snapshot.keepsWindowPicked && snapshot.window != nil)
        default:
            return .none
        }
    }
}

/// The outline's colour. `record` is the `record-red` token (`NSColor.systemRed`), the Stop button's red.
public enum SelectionOutlineTone: Sendable, Hashable {
    case accent
    case record
}

/// How the outline is drawn for one window or region.
public struct SelectionOutlineAppearance: Sendable, Hashable {
    /// The window the overlay sits directly above. Nil for a region, which has no window.
    public var windowID: WindowID?
    /// The window frame outset by the stroke, top-left global pt. This is the overlay's frame.
    public var frame: PointRect
    public var cornerRadius: CGFloat
    public var strokeWidth: CGFloat
    public var hairlineWidth: CGFloat
    public var hairlineOpacity: CGFloat
    public var tone: SelectionOutlineTone = .accent
}

public enum SelectionOutlineDisplay: Sendable, Hashable {
    case hidden
    case shown(SelectionOutlineAppearance)
    /// Fading to nothing, with `remaining` seconds left.
    case fading(SelectionOutlineAppearance, remaining: TimeInterval)

    public var appearance: SelectionOutlineAppearance? {
        switch self {
        case .hidden: nil
        case .shown(let appearance), .fading(let appearance, _): appearance
        }
    }
}

/// When the on-screen outline shows, where, and how. Pure: time and the window's position are passed in.
public struct SelectionOutlineModel: Sendable {
    public static let strokeWidth: CGFloat = 3
    public static let flashSeconds: TimeInterval = 1.5
    public static let fadeSeconds: TimeInterval = 0.3
    /// Accent to red when a recording starts, and back when it is saved with the window still picked.
    public static let crossfadeSeconds: TimeInterval = 0.2
    public static let trackingInterval: TimeInterval = 0.1

    /// There's no public API for another app's window radius, so this follows the system's standard window.
    public static func windowCornerRadius(macOSMajorVersion: Int) -> CGFloat {
        macOSMajorVersion >= 26 ? 16 : 10
    }

    /// Concentric with the window: its radius plus the stroke.
    public static func outlineRadius(macOSMajorVersion: Int) -> CGFloat {
        windowCornerRadius(macOSMajorVersion: macOSMajorVersion) + strokeWidth
    }

    public static func outlineFrame(around window: PointRect) -> PointRect {
        PointRect(
            x: window.x - strokeWidth, y: window.y - strokeWidth, width: window.width + strokeWidth * 2,
            height: window.height + strokeWidth * 2)
    }

    /// A region in its display's pixels, as top-left global points.
    public static func regionFrame(_ region: PixelRect, on display: DisplayInfo) -> PointRect {
        let scale = max(display.scale, 1)
        return PointRect(
            x: display.frame.x + Double(region.x) / scale, y: display.frame.y + Double(region.y) / scale,
            width: Double(region.width) / scale, height: Double(region.height) / scale)
    }

    /// A region that is the whole display is a full-screen recording, which gets no frame.
    public static func coversScreen(_ rect: PointRect, display: DisplayInfo) -> Bool {
        let screen = display.frame.cgRect.insetBy(dx: 0.5, dy: 0.5)
        return rect.cgRect.contains(screen)
    }

    private let macOSMajorVersion: Int
    public private(set) var input = SelectionOutlineInput(target: nil)
    private var presence: WindowPresence?
    private var seenPickCount: Int?
    /// While the panel and the control bar are both down, the outline stays until this time and then fades.
    private var holdUntil: TimeInterval?
    /// The red frame a recording left behind, fading out because nothing keeps the pick on screen.
    private var exitFade: (appearance: SelectionOutlineAppearance, end: TimeInterval)?

    public init(macOSMajorVersion: Int) {
        self.macOSMajorVersion = macOSMajorVersion
    }

    /// Applies new conditions. Returns the target when this update is a new pick, so its name can be announced.
    @discardableResult
    public mutating func update(_ new: SelectionOutlineInput, now: TimeInterval) -> SelectionOutlineTarget? {
        let before = display(at: now)
        let old = input
        input = new
        if old.target?.window.id != new.target?.window.id { presence = nil }
        var picked: SelectionOutlineTarget?
        if let seen = seenPickCount, new.pickCount != seen, let target = new.target {
            holdUntil = now + Self.flashSeconds
            picked = target
        }
        seenPickCount = new.pickCount
        if new.target == nil {
            holdUntil = nil
        } else if Self.keptVisible(old), !Self.keptVisible(new) {
            holdUntil = max(holdUntil ?? now, now)
        }
        if new.capture.isRecording || baseDisplay(at: now) != .hidden {
            exitFade = nil
        } else if case .shown(let shown) = before, shown.tone == .record {
            // The recording is over, so the red goes at once. With the pick still on screen it turns back to the
            // accent (a crossfade); with nothing keeping it, it fades out.
            exitFade = (shown, now + fadeSeconds)
        }
        return picked
    }

    public mutating func update(presence: WindowPresence) {
        self.presence = presence
    }

    private var fadeSeconds: TimeInterval { input.reduceMotion ? 0 : Self.fadeSeconds }

    /// How long a change from `old` to `new` crossfades: only a colour change on a frame that stays up.
    public func crossfade(from old: SelectionOutlineDisplay, to new: SelectionOutlineDisplay) -> TimeInterval {
        guard case .shown(let before) = old, case .shown(let after) = new, before.tone != after.tone else { return 0 }
        return input.reduceMotion ? 0 : Self.crossfadeSeconds
    }

    /// Nothing about the app rules the pick outline out. The window itself may still be out of sight.
    private var eligible: Bool {
        guard input.target != nil, !input.pickerOpen, !input.windowClosed else { return false }
        switch input.capture {
        case .none, .saving(keepsPick: true): return true
        case .recordingWindow, .recordingRegion, .recordingHidden, .saving(keepsPick: false): return false
        }
    }

    /// The outline stays up for as long as the panel or the control bar is showing this window.
    private static func keptVisible(_ input: SelectionOutlineInput) -> Bool {
        input.panelOpen || input.controlBarVisible
    }

    /// The window's position matters now, so the tracker should run.
    public func wantsTracking(at now: TimeInterval) -> Bool {
        if input.capture == .recordingWindow { return input.target != nil && !input.windowClosed }
        guard eligible else { return false }
        if Self.keptVisible(input) { return true }
        guard let holdUntil else { return false }
        return now < holdUntil + fadeSeconds
    }

    private var windowFrame: PointRect? {
        guard let target = input.target else { return nil }
        switch presence {
        case .notVisible: return nil
        case .onScreen(let frame): return frame
        case nil: return target.window.frame
        }
    }

    private func appearance(frame: PointRect, windowID: WindowID?, radius: CGFloat, tone: SelectionOutlineTone)
        -> SelectionOutlineAppearance
    {
        SelectionOutlineAppearance(
            windowID: windowID, frame: frame, cornerRadius: radius, strokeWidth: Self.strokeWidth,
            hairlineWidth: input.increaseContrast ? 1 : 0.5, hairlineOpacity: input.increaseContrast ? 0.6 : 0.3,
            tone: tone)
    }

    public func display(at now: TimeInterval) -> SelectionOutlineDisplay {
        let display = baseDisplay(at: now)
        guard display == .hidden, let exitFade, now < exitFade.end else { return display }
        return .fading(exitFade.appearance, remaining: exitFade.end - now)
    }

    private func baseDisplay(at now: TimeInterval) -> SelectionOutlineDisplay {
        let radius = Self.outlineRadius(macOSMajorVersion: macOSMajorVersion)
        switch input.capture {
        case .recordingWindow:
            guard !input.windowClosed, let target = input.target, let frame = windowFrame else { return .hidden }
            return .shown(
                appearance(
                    frame: Self.outlineFrame(around: frame), windowID: target.window.id, radius: radius, tone: .record))
        case .recordingRegion(let rect):
            // A region has no window corners.
            return .shown(appearance(frame: Self.outlineFrame(around: rect), windowID: nil, radius: 0, tone: .record))
        case .recordingHidden, .saving(keepsPick: false):
            return .hidden
        case .none, .saving(keepsPick: true):
            break
        }
        guard eligible, let target = input.target, let frame = windowFrame else { return .hidden }
        let appearance = appearance(
            frame: Self.outlineFrame(around: frame), windowID: target.window.id, radius: radius, tone: .accent)
        if Self.keptVisible(input) { return .shown(appearance) }
        guard let holdUntil else { return .hidden }
        if now < holdUntil { return .shown(appearance) }
        let fadeEnd = holdUntil + fadeSeconds
        return now < fadeEnd ? .fading(appearance, remaining: fadeEnd - now) : .hidden
    }

    /// The next time `display` changes by itself.
    public func nextDeadline(after now: TimeInterval) -> TimeInterval? {
        var deadlines: [TimeInterval] = []
        if let exitFade, now < exitFade.end { deadlines.append(exitFade.end) }
        if eligible, !Self.keptVisible(input), let holdUntil {
            if now < holdUntil {
                deadlines.append(holdUntil)
            } else if now < holdUntil + fadeSeconds {
                deadlines.append(holdUntil + fadeSeconds)
            }
        }
        return deadlines.min()
    }
}

/// The overlay window, as the outline controller drives it.
@MainActor
public protocol SelectionOutlineSurface: AnyObject {
    /// `crossfade` is how long a change of colour takes. 0 swaps it in one frame.
    func show(_ appearance: SelectionOutlineAppearance, crossfade: TimeInterval)
    func fadeOut(_ appearance: SelectionOutlineAppearance, duration: TimeInterval)
    func hide()
    /// Puts the overlay back directly above the window, which may have come forward.
    func keepAbove(_ window: WindowID)
    func announce(_ text: String)
}

/// Reports where a window is, once right away and then on every check, changed or not.
@MainActor
public protocol WindowFrameTracking: AnyObject {
    func start(_ window: WindowInfo, onChange: @escaping @MainActor (WindowPresence) -> Void)
    func stop()
}

/// Connects the model to the overlay, the window tracker and the clock. It holds no rules of its own.
@MainActor
public final class SelectionOutlineController {
    private let surface: any SelectionOutlineSurface
    private let tracker: any WindowFrameTracking
    private let clock: any HostClock
    private var model: SelectionOutlineModel
    private var tracked: WindowID?
    private var shown = SelectionOutlineDisplay.hidden
    private var timer: Task<Void, Never>?

    public init(
        surface: any SelectionOutlineSurface, tracker: any WindowFrameTracking, clock: any HostClock,
        macOSMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    ) {
        self.surface = surface
        self.tracker = tracker
        self.clock = clock
        model = SelectionOutlineModel(macOSMajorVersion: macOSMajorVersion)
    }

    public func update(_ input: SelectionOutlineInput) {
        guard input != model.input else { return }
        if let picked = model.update(input, now: clock.now()) {
            surface.announce(UIStrings.Panel.picked(picked.title))
        }
        refresh()
    }

    private func refresh() {
        let now = clock.now()
        updateTracking(now: now)
        apply(model.display(at: now))
        schedule(after: now)
    }

    private func updateTracking(now: TimeInterval) {
        guard model.wantsTracking(at: now), let window = model.input.target?.window else {
            if tracked != nil { tracker.stop() }
            tracked = nil
            return
        }
        guard tracked != window.id else { return }
        if tracked != nil { tracker.stop() }
        tracked = window.id
        tracker.start(window) { [weak self] presence in
            guard let self else { return }
            self.model.update(presence: presence)
            let display = self.model.display(at: self.clock.now())
            if display == self.shown, let appearance = display.appearance {
                if let windowID = appearance.windowID { self.surface.keepAbove(windowID) }
            } else {
                self.apply(display)
            }
        }
    }

    private func apply(_ display: SelectionOutlineDisplay) {
        switch (shown, display) {
        case (.hidden, .hidden):
            break
        case (.fading(let old, _), .fading(let new, _)) where old == new:
            return
        case (_, .hidden):
            surface.hide()
        case (_, .shown(let appearance)):
            if shown != display { surface.show(appearance, crossfade: model.crossfade(from: shown, to: display)) }
        case (_, .fading(let appearance, let remaining)):
            surface.fadeOut(appearance, duration: remaining)
        }
        shown = display
    }

    private func schedule(after now: TimeInterval) {
        timer?.cancel()
        timer = nil
        guard let deadline = model.nextDeadline(after: now) else { return }
        let clock = clock
        timer = Task { [weak self] in
            do { try await clock.sleep(until: deadline) } catch { return }
            self?.refresh()
        }
    }
}
