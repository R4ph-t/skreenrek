import CoreGraphics
import Foundation
import SkreenrekCore

// The drag-to-authorize helper (Designer's addendum 4): a small floating panel beside System Settings with Skreenrek's
// icon, a short looping hint of the icon being dragged into the list, and a real drag. Everything here is pure, so the
// tests drive it with plain values; `DragHelperController` is the thin AppKit layer around it.

/// The addendum's sizes and timings.
public enum DragHelperMetrics {
    public static let size = CGSize(width: 320, height: 88)
    public static let radius: CGFloat = 10
    /// Between System Settings and the panel.
    public static let gap: CGFloat = 12
    /// The panel's top sits this far below System Settings' top, about where the list starts.
    public static let topOffset: CGFloat = 96
    /// From the edges of the screen's visible frame, when clamped or docked.
    public static let screenInset: CGFloat = 16
    /// The room a side needs: the gap and the panel.
    public static var neededRoom: CGFloat { gap + size.width }

    public static let iconSize: CGFloat = 56
    public static let iconOrigin = CGPoint(x: 16, y: 16)
    public static let mirroredIconX: CGFloat = 248
    public static let textX: CGFloat = 84
    public static let textTop: CGFloat = 22
    public static let textWidth: CGFloat = 196
    /// Mirrored, the text is right-aligned to this x.
    public static let mirroredTextTrailing: CGFloat = 236
    public static let titleDetailGap: CGFloat = 2
    public static let closeHit: CGFloat = 20
    public static let closeGlyph: CGFloat = 11
    public static let closeOrigin = CGPoint(x: 292, y: 8)
    public static let mirroredCloseX: CGFloat = 8
    public static let badgeSize: CGFloat = 20

    /// System Settings' window is read this often while the panel is up.
    public static let pollInterval: TimeInterval = 0.25
    /// No System Settings window by then: show the panel docked.
    public static let appearTimeout: TimeInterval = 3
    public static let fadeIn: TimeInterval = 0.2
    public static let fadeOut: TimeInterval = 0.2
    public static let crossfade: TimeInterval = 0.2
    /// Granted: the panel stays this long, then fades out.
    public static let grantedHold: TimeInterval = 1.5

    /// The ghost: 60% at the start, 28 pt of travel, 0.9 s slide and fade, 1.5 s rest, starting 0.6 s after the
    /// panel appears, 8 loops at most.
    public static let ghostOpacity: Double = 0.6
    public static let ghostTravel: CGFloat = 28
    public static let loopDelay: TimeInterval = 0.6
    public static let slide: TimeInterval = 0.9
    public static let rest: TimeInterval = 1.5
    public static var loopPeriod: TimeInterval { slide + rest }
    public static let maxLoops = 8
}

/// Which permissions get the helper: the two Privacy & Security lists that take a dropped app. Direct Capture is
/// macOS 15's system capture alert ([Allow] [Open System Settings]) with no list of its own, so it gets none.
public enum DragHelperPane {
    public static func applies(to permission: Permission) -> Bool {
        switch permission {
        case .screenRecording, .accessibility: true
        case .directCapture: false
        }
    }
}

// MARK: - Placement

/// One screen in AppKit's global coordinates (bottom-left origin).
public struct DragHelperScreen: Sendable, Equatable {
    public var frame: CGRect
    public var visibleFrame: CGRect
    public init(frame: CGRect, visibleFrame: CGRect) { self.frame = frame; self.visibleFrame = visibleFrame }
}

public struct DragHelperPlacement: Sendable, Equatable {
    public enum Side: Sendable, Equatable { case right, left, docked }
    public var side: Side
    /// The panel's frame in AppKit's global coordinates.
    public var frame: CGRect
    /// Left of System Settings: icon on the right, text right-aligned, × on the left.
    public var mirrored: Bool { side == .left }
}

public enum DragHelperPlacer {
    /// Converts a CGWindowList rect (top-left origin of the primary display, y down) to AppKit's global coordinates
    /// (bottom-left origin of the primary display, y up). `primaryHeight` is the primary screen's height.
    public static func appKitRect(fromCG rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Where the panel goes. `settings` is System Settings' window in CGWindowList coordinates, nil when it can't be
    /// read. `screens` starts with the primary screen (the one at the origin); `fallback` is the screen to dock on
    /// when there's no window to go by.
    public static func place(
        settings: CGRect?, screens: [DragHelperScreen], fallback: DragHelperScreen? = nil
    ) -> DragHelperPlacement? {
        guard let primary = screens.first else { return nil }
        guard let settings else {
            return docked(on: fallback ?? primary)
        }
        let window = appKitRect(fromCG: settings, primaryHeight: primary.frame.height)
        let screen = screen(for: window, in: screens) ?? fallback ?? primary
        let visible = screen.visibleFrame
        let size = DragHelperMetrics.size
        let inset = DragHelperMetrics.screenInset
        // The panel's top 96 pt below the window's top, clamped inside the visible frame with the 16 pt inset.
        var y = window.maxY - DragHelperMetrics.topOffset - size.height
        y = min(y, visible.maxY - inset - size.height)
        y = max(y, visible.minY + inset)
        if visible.maxX - window.maxX >= DragHelperMetrics.neededRoom {
            let frame = CGRect(x: window.maxX + DragHelperMetrics.gap, y: y, width: size.width, height: size.height)
            return DragHelperPlacement(side: .right, frame: frame)
        }
        if window.minX - visible.minX >= DragHelperMetrics.neededRoom {
            let frame = CGRect(
                x: window.minX - DragHelperMetrics.gap - size.width, y: y, width: size.width, height: size.height)
            return DragHelperPlacement(side: .left, frame: frame)
        }
        return docked(on: screen)
    }

    /// Bottom-right of the visible frame, 16 pt in.
    static func docked(on screen: DragHelperScreen) -> DragHelperPlacement {
        let size = DragHelperMetrics.size
        let inset = DragHelperMetrics.screenInset
        let visible = screen.visibleFrame
        return DragHelperPlacement(
            side: .docked,
            frame: CGRect(
                x: visible.maxX - inset - size.width, y: visible.minY + inset, width: size.width, height: size.height))
    }

    /// The screen showing most of the window.
    static func screen(for window: CGRect, in screens: [DragHelperScreen]) -> DragHelperScreen? {
        var best: (screen: DragHelperScreen, area: CGFloat)?
        for screen in screens {
            let overlap = screen.frame.intersection(window)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > 0, area > (best?.area ?? 0) { best = (screen, area) }
        }
        return best?.screen
    }
}

// MARK: - System Settings' window

/// What CGWindowList says about System Settings.
public enum SystemSettingsWindow: Sendable, Equatable {
    case notRunning
    /// Running with no window on screen: minimised, hidden, or still launching.
    case hidden
    /// Its main window, in CGWindowList coordinates.
    case visible(CGRect)
    /// The window list couldn't be read.
    case unreadable
}

// MARK: - State

/// Why the helper closed.
public enum DragHelperCloseReason: Sendable, Equatable {
    case closeButton
    case settingsQuit
    /// The onboarding step or Settings window it came from went away.
    case sourceDismissed
    case appQuit
    /// Granted, held 1.5 s, then faded out.
    case granted
}

/// The ghost's frame of the loop: how far it has slid toward System Settings and how opaque it is.
public struct DragHelperGhost: Sendable, Equatable {
    public var offset: CGFloat
    public var opacity: Double
}

/// The helper's state over time: waiting for System Settings, shown (looping), granted, closed. Every input carries
/// `now`, so the tests drive it like a manual clock.
public struct DragHelperState: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case waiting
        case shown
        case granted(at: TimeInterval)
        case closed(DragHelperCloseReason)
    }

    public private(set) var permission: Permission
    public let reduceMotion: Bool
    public private(set) var phase: Phase = .waiting
    public private(set) var placement: DragHelperPlacement?
    /// Whether the panel is on screen: shown, and System Settings isn't minimised or hidden.
    public private(set) var onScreen = false
    /// When the panel first appeared (the fade-in), nil until then.
    public private(set) var appearedAt: TimeInterval?
    public private(set) var hovering = false
    public private(set) var dragging = false
    private let openedAt: TimeInterval
    private var seenSettings = false
    /// Loop time banked while running, and since when it has been running (nil while paused).
    private var banked: TimeInterval = 0
    private var runningSince: TimeInterval?

    public init(permission: Permission, now: TimeInterval, reduceMotion: Bool) {
        self.permission = permission
        self.reduceMotion = reduceMotion
        openedAt = now
    }

    public var isClosed: Bool { if case .closed = phase { true } else { false } }
    public var isGranted: Bool { if case .granted = phase { true } else { false } }

    /// One poll: System Settings' window, the screens and the live permission check.
    public mutating func update(
        now: TimeInterval, window: SystemSettingsWindow, screens: [DragHelperScreen],
        fallback: DragHelperScreen? = nil, granted: Bool
    ) {
        guard !isClosed else { return }
        if case .granted(let at) = phase, now - at >= DragHelperMetrics.grantedHold {
            return close(.granted, now: now)
        }
        switch window {
        case .visible(let bounds):
            seenSettings = true
            placement = DragHelperPlacer.place(settings: bounds, screens: screens, fallback: fallback)
            setOnScreen(true, now: now)
        case .hidden where seenSettings:
            setOnScreen(false, now: now)
        case .notRunning where seenSettings:
            return close(.settingsQuit, now: now)
        case .hidden, .notRunning, .unreadable:
            // Not seen yet (or never readable): docked once 3 s have gone by.
            if appearedAt != nil || now - openedAt >= DragHelperMetrics.appearTimeout {
                placement = DragHelperPlacer.place(settings: nil, screens: screens, fallback: fallback)
                setOnScreen(true, now: now)
            }
        }
        if granted, phase == .shown {
            phase = .granted(at: now)
            pause(now: now)
        }
        // After 8 loops the clock stops for good, so nothing keeps animating.
        if runningSince != nil, loopsCompleted(at: now) >= DragHelperMetrics.maxLoops { pause(now: now) }
    }

    /// Another pane's `Open System Settings…` while the helper is up: the copy changes in place.
    public mutating func switchPane(to permission: Permission, now: TimeInterval) {
        guard !isClosed, permission != self.permission else { return }
        self.permission = permission
        if isGranted {
            phase = .shown
            resumeIfRunnable(now: now)
        }
    }

    public mutating func setHovering(_ hovering: Bool, now: TimeInterval) {
        guard hovering != self.hovering else { return }
        self.hovering = hovering
        hovering ? pause(now: now) : resumeIfRunnable(now: now)
    }

    public mutating func setDragging(_ dragging: Bool, now: TimeInterval) {
        guard dragging != self.dragging else { return }
        self.dragging = dragging
        dragging ? pause(now: now) : resumeIfRunnable(now: now)
    }

    public mutating func close(_ reason: DragHelperCloseReason, now: TimeInterval) {
        guard !isClosed else { return }
        pause(now: now)
        phase = .closed(reason)
        onScreen = false
    }

    // MARK: The loop

    /// Loop time, from the first appearance, not counting pauses.
    func loopClock(at now: TimeInterval) -> TimeInterval {
        banked + (runningSince.map { max(0, now - $0) } ?? 0)
    }

    /// Whole loops played.
    public func loopsCompleted(at now: TimeInterval) -> Int {
        let t = loopClock(at: now) - DragHelperMetrics.loopDelay
        guard t > 0 else { return 0 }
        return min(DragHelperMetrics.maxLoops, Int(t / DragHelperMetrics.loopPeriod))
    }

    /// Whether the ghost loop still has frames to draw: not under Reduce Motion, not paused, fewer than 8 loops.
    public func loopRunning(at now: TimeInterval) -> Bool {
        !reduceMotion && runningSince != nil && loopsCompleted(at: now) < DragHelperMetrics.maxLoops
    }

    /// The ghost at `now`, nil when there is none to draw (Reduce Motion, paused, resting, done).
    public func ghost(at now: TimeInterval) -> DragHelperGhost? {
        guard !reduceMotion, runningSince != nil else { return nil }
        let t = loopClock(at: now) - DragHelperMetrics.loopDelay
        guard t >= 0 else { return nil }
        let loop = Int(t / DragHelperMetrics.loopPeriod)
        guard loop < DragHelperMetrics.maxLoops else { return nil }
        let within = t - Double(loop) * DragHelperMetrics.loopPeriod
        guard within < DragHelperMetrics.slide else { return nil }
        let eased = Self.easeInOut(within / DragHelperMetrics.slide)
        return DragHelperGhost(
            offset: DragHelperMetrics.ghostTravel * eased, opacity: DragHelperMetrics.ghostOpacity * (1 - eased))
    }

    /// Ease-in-out: slow at both ends, symmetric, so 50% of the time is 50% of the slide.
    static func easeInOut(_ p: Double) -> Double {
        let p = min(max(p, 0), 1)
        return p * p * (3 - 2 * p)
    }

    private mutating func setOnScreen(_ visible: Bool, now: TimeInterval) {
        guard visible != onScreen else { return }
        onScreen = visible
        if visible {
            if appearedAt == nil {
                appearedAt = now
                phase = isGranted ? phase : .shown
            }
            resumeIfRunnable(now: now)
        } else {
            pause(now: now)
        }
    }

    /// Stops the clock. A slide in progress goes back to its start, so a resumed loop never starts half-faded.
    private mutating func pause(now: TimeInterval) {
        guard let since = runningSince else { return }
        banked += max(0, now - since)
        runningSince = nil
        let t = banked - DragHelperMetrics.loopDelay
        if t > 0 {
            let loop = (t / DragHelperMetrics.loopPeriod).rounded(.down)
            if t - loop * DragHelperMetrics.loopPeriod < DragHelperMetrics.slide {
                banked = DragHelperMetrics.loopDelay + loop * DragHelperMetrics.loopPeriod
            }
        }
    }

    private mutating func resumeIfRunnable(now: TimeInterval) {
        guard runningSince == nil, onScreen, phase == .shown, !hovering, !dragging, !reduceMotion,
            loopsCompleted(at: now) < DragHelperMetrics.maxLoops
        else { return }
        runningSince = now
    }
}

// MARK: - Bundle guard

/// Whether a drop of this copy of Skreenrek would register the right app.
public enum DragHelperEligibility: Sendable, Equatable {
    case eligible
    /// Not a .app bundle (a bare `swift build` executable): there is nothing to drop.
    case notAppBundle
    /// Gatekeeper's App Translocation runs a quarantined app from a random read-only path.
    case translocated
    /// Running from a mounted disk image (a read-only volume).
    case diskImage

    /// `volumeIsReadOnly` is the bundle volume's read-only flag, nil when it can't be read.
    public static func check(bundleURL: URL, volumeIsReadOnly: Bool?) -> DragHelperEligibility {
        let url = bundleURL.standardizedFileURL
        guard url.isFileURL, url.pathExtension == "app" else { return .notAppBundle }
        if url.path.contains("/AppTranslocation/") { return .translocated }
        if volumeIsReadOnly == true { return .diskImage }
        return .eligible
    }

    /// The running app's bundle.
    public static func current(_ bundle: Bundle = .main) -> DragHelperEligibility {
        let url = bundle.bundleURL
        let readOnly = (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly
        return check(bundleURL: url, volumeIsReadOnly: readOnly)
    }
}
