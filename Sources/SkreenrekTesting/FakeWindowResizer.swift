import CoreGraphics
import SkreenrekCore
import Synchronization

/// How a fake window reacts to `setFrame`, in points.
public struct ResizeRules: Sendable, Hashable {
    /// The window won't go smaller than this.
    public var minimumSize: CGSize?
    /// The window won't go larger than this.
    public var maximumSize: CGSize?
    /// The window only takes sizes `base + n × step` (rounding down), like Terminal's character cells. The base is
    /// `minimumSize`, or zero.
    public var sizeStep: CGSize?
    /// `setFrame` calls (1-based, per window) that the window ignores.
    public var ignoredAttempts: Set<Int>

    public init(
        minimumSize: CGSize? = nil, maximumSize: CGSize? = nil, sizeStep: CGSize? = nil,
        ignoredAttempts: Set<Int> = []
    ) {
        self.minimumSize = minimumSize
        self.maximumSize = maximumSize
        self.sizeStep = sizeStep
        self.ignoredAttempts = ignoredAttempts
    }

    /// The frame a window ends up with when asked for `requested`.
    public func apply(to requested: PointRect) -> PointRect {
        var width = requested.width
        var height = requested.height
        if let step = sizeStep {
            let base = minimumSize ?? .zero
            if step.width > 0 { width = base.width + ((width - base.width) / step.width).rounded(.down) * step.width }
            if step.height > 0 {
                height = base.height + ((height - base.height) / step.height).rounded(.down) * step.height
            }
        }
        if let min = minimumSize {
            width = max(width, min.width)
            height = max(height, min.height)
        }
        if let max = maximumSize {
            width = Swift.min(width, max.width)
            height = Swift.min(height, max.height)
        }
        return PointRect(x: requested.x, y: requested.y, width: width, height: height)
    }
}

/// A window resizer that keeps frames in memory and obeys programmable `ResizeRules`.
public final class FakeWindowResizer: WindowResizer {
    public struct Call: Sendable, Hashable {
        public var window: WindowID
        public var requested: PointRect
    }

    private struct State {
        var rules: ResizeRules
        var rulesByWindow: [WindowID: ResizeRules] = [:]
        var frames: [WindowID: PointRect] = [:]
        var attempts: [WindowID: Int] = [:]
        var calls: [Call] = []
        var readCount = 0
        var failure: (any Error)?
    }

    private let state: Mutex<State>

    public init(rules: ResizeRules = ResizeRules()) {
        state = Mutex(State(rules: rules))
    }

    /// Rules for every window without its own.
    public var rules: ResizeRules {
        get { state.withLock { $0.rules } }
        set { state.withLock { $0.rules = newValue } }
    }

    public func setRules(_ rules: ResizeRules, for window: WindowID) {
        state.withLock { $0.rulesByWindow[window] = rules }
    }

    /// When set, both calls throw it (e.g. `SkreenrekError.permissionDenied(.accessibility)`).
    public var failure: (any Error)? {
        get { state.withLock { $0.failure } }
        set { state.withLock { $0.failure = newValue } }
    }

    /// Every `setFrame` call, in order.
    public var calls: [Call] { state.withLock { $0.calls } }

    public var readCount: Int { state.withLock { $0.readCount } }

    /// The frame a window has now (its `WindowInfo.frame` until the first obeyed `setFrame`).
    public func currentFrame(of window: WindowInfo) -> PointRect {
        state.withLock { $0.frames[window.id] ?? window.frame }
    }

    public func setFrame(_ frame: PointRect, of window: WindowInfo) async throws {
        try state.withLock { s in
            if let failure = s.failure { throw failure }
            s.calls.append(Call(window: window.id, requested: frame))
            let attempt = (s.attempts[window.id] ?? 0) + 1
            s.attempts[window.id] = attempt
            let rules = s.rulesByWindow[window.id] ?? s.rules
            guard !rules.ignoredAttempts.contains(attempt) else { return }
            s.frames[window.id] = rules.apply(to: frame)
        }
    }

    public func readFrame(of window: WindowInfo) async throws -> PointRect {
        try state.withLock { s in
            if let failure = s.failure { throw failure }
            s.readCount += 1
            return s.frames[window.id] ?? window.frame
        }
    }
}
