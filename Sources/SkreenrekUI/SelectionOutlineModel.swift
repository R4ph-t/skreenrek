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

/// Everything outside the outline that decides whether it shows.
public struct SelectionOutlineInput: Sendable, Hashable {
    public var target: SelectionOutlineTarget?
    public var pickCount: Int
    /// A recording is running or being written.
    public var capturing: Bool
    public var pickerOpen: Bool
    public var panelOpen: Bool
    public var windowClosed: Bool
    public var reduceMotion: Bool
    public var increaseContrast: Bool

    public init(
        target: SelectionOutlineTarget?, pickCount: Int = 0, capturing: Bool = false, pickerOpen: Bool = false,
        panelOpen: Bool = false, windowClosed: Bool = false, reduceMotion: Bool = false,
        increaseContrast: Bool = false
    ) {
        self.target = target
        self.pickCount = pickCount
        self.capturing = capturing
        self.pickerOpen = pickerOpen
        self.panelOpen = panelOpen
        self.windowClosed = windowClosed
        self.reduceMotion = reduceMotion
        self.increaseContrast = increaseContrast
    }

    public init(snapshot: ControllerSnapshot, panelOpen: Bool, windowClosed: Bool, reduceMotion: Bool, increaseContrast: Bool) {
        let capturing = snapshot.state == .recording || snapshot.state == .writing
        self.init(
            target: snapshot.window.map(SelectionOutlineTarget.init(window:)), pickCount: snapshot.pickCount,
            capturing: capturing, pickerOpen: snapshot.picking, panelOpen: panelOpen, windowClosed: windowClosed,
            reduceMotion: reduceMotion, increaseContrast: increaseContrast)
    }
}

/// How the outline is drawn for one window.
public struct SelectionOutlineAppearance: Sendable, Hashable {
    public var windowID: WindowID
    /// The window frame outset by the stroke, top-left global pt. This is the overlay's frame.
    public var frame: PointRect
    public var cornerRadius: CGFloat
    public var strokeWidth: CGFloat
    public var hairlineWidth: CGFloat
    public var hairlineOpacity: CGFloat
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

    private let macOSMajorVersion: Int
    public private(set) var input = SelectionOutlineInput(target: nil)
    private var presence: WindowPresence?
    private var seenPickCount: Int?
    /// While the panel is closed, the outline stays until this time and then fades.
    private var holdUntil: TimeInterval?

    public init(macOSMajorVersion: Int) {
        self.macOSMajorVersion = macOSMajorVersion
    }

    /// Applies new conditions. Returns the target when this update is a new pick, so its name can be announced.
    @discardableResult
    public mutating func update(_ new: SelectionOutlineInput, now: TimeInterval) -> SelectionOutlineTarget? {
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
        } else if old.panelOpen, !new.panelOpen {
            holdUntil = max(holdUntil ?? now, now)
        }
        return picked
    }

    public mutating func update(presence: WindowPresence) {
        self.presence = presence
    }

    private var fadeSeconds: TimeInterval { input.reduceMotion ? 0 : Self.fadeSeconds }

    /// Nothing about the app rules the outline out. The window itself may still be out of sight.
    private var eligible: Bool {
        input.target != nil && !input.capturing && !input.pickerOpen && !input.windowClosed
    }

    /// The window's position matters now, so the tracker should run.
    public func wantsTracking(at now: TimeInterval) -> Bool {
        guard eligible else { return false }
        if input.panelOpen { return true }
        guard let holdUntil else { return false }
        return now < holdUntil + fadeSeconds
    }

    public func display(at now: TimeInterval) -> SelectionOutlineDisplay {
        guard eligible, let target = input.target else { return .hidden }
        let windowFrame: PointRect
        switch presence {
        case .notVisible: return .hidden
        case .onScreen(let frame): windowFrame = frame
        case nil: windowFrame = target.window.frame
        }
        let appearance = SelectionOutlineAppearance(
            windowID: target.window.id, frame: Self.outlineFrame(around: windowFrame),
            cornerRadius: Self.outlineRadius(macOSMajorVersion: macOSMajorVersion), strokeWidth: Self.strokeWidth,
            hairlineWidth: input.increaseContrast ? 1 : 0.5, hairlineOpacity: input.increaseContrast ? 0.6 : 0.3)
        if input.panelOpen { return .shown(appearance) }
        guard let holdUntil else { return .hidden }
        if now < holdUntil { return .shown(appearance) }
        let fadeEnd = holdUntil + fadeSeconds
        return now < fadeEnd ? .fading(appearance, remaining: fadeEnd - now) : .hidden
    }

    /// The next time `display` changes by itself.
    public func nextDeadline(after now: TimeInterval) -> TimeInterval? {
        guard eligible, !input.panelOpen, let holdUntil else { return nil }
        if now < holdUntil { return holdUntil }
        let fadeEnd = holdUntil + fadeSeconds
        return now < fadeEnd ? fadeEnd : nil
    }
}

/// The overlay window, as the outline controller drives it.
@MainActor
public protocol SelectionOutlineSurface: AnyObject {
    func show(_ appearance: SelectionOutlineAppearance)
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
                self.surface.keepAbove(appearance.windowID)
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
            if shown != display { surface.show(appearance) }
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
