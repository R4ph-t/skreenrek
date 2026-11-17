import Foundation
import SkreenrekControl
import SkreenrekCore

public enum HUDState: Sendable, Equatable {
    case hidden
    case recording(target: String, seconds: Int)
    case writing
    case saved(duration: Double, path: String)
    case error(reason: String)
}

/// Value-only state and deadlines. The UI supplies monotonic time and hover events.
public struct HUDModel: Sendable {
    public private(set) var state: HUDState = .hidden
    public private(set) var savedAt: TimeInterval?
    public var hovered = false
    private var lastClipID: String?
    private var observed = false
    private var wasCapturing = false
    private var enabled = true
    private var activeError: SkreenrekError?
    private var dismissedError: SkreenrekError?

    public init() {}

    public mutating func observe(_ snapshot: ControllerSnapshot, now: TimeInterval, indicatorEnabled: Bool = true) {
        if !observed { lastClipID = snapshot.lastClip?.recording.id; observed = true }
        if snapshot.state == .recording || snapshot.state == .writing {
            activeError = nil; dismissedError = nil
            enabled = indicatorEnabled && snapshot.hud
            wasCapturing = true
            savedAt = nil
            if snapshot.state == .writing { state = .writing }
            else {
                state = .recording(target: snapshot.window?.app ?? UIStrings.Icon.regionTarget,
                                   seconds: max(0, Int(snapshot.elapsed ?? 0)))
            }
        } else if let error = snapshot.error {
            activeError = error
            state = error == dismissedError ? .hidden : .error(reason: UIStrings.Icon.reason(error))
            savedAt = nil
            wasCapturing = false
        } else if let clip = snapshot.lastClip, clip.recording.id != lastClipID, wasCapturing {
            state = .saved(duration: clip.recording.duration, path: clip.files.clip)
            savedAt = now
            wasCapturing = false
        } else if wasCapturing || { if case .error = state { return true }; return false }() {
            dismiss()
            wasCapturing = false
        }
        lastClipID = snapshot.lastClip?.recording.id
        if !enabled || !indicatorEnabled { state = .hidden }
        tick(now: now)
    }

    public mutating func tick(now: TimeInterval) {
        if let savedAt, now >= savedAt + (hovered ? 8 : 4) { dismiss() }
    }

    public mutating func dismiss() { dismissedError = activeError; state = .hidden; savedAt = nil }
}

/// Placement in top-left global points; dragged positions are remembered independently for each display.
public struct HUDPlacement: Sendable {
    public private(set) var remembered: [DisplayID: PointRect]
    public init(remembered: [DisplayID: PointRect] = [:]) { self.remembered = remembered }
    public mutating func remember(_ frame: PointRect, display: DisplayID) { remembered[display] = frame }

    public func frame(target: PointRect, display: DisplayInfo, width: Double) -> PointRect {
        let screen = display.visibleFrame.cgRect
        let saved = remembered[display.id]
        let x = saved?.x ?? target.cgRect.midX - width / 2
        let below = target.y + target.height + 16
        let y = saved?.y ?? (below + 36 <= screen.maxY ? below : screen.maxY - 36 - 16)
        return PointRect(x: max(screen.minX, min(x, screen.maxX - width)),
                         y: max(screen.minY, min(y, screen.maxY - 36)), width: width, height: 36)
    }
}
