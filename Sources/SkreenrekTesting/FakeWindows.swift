import Foundation
import SkreenrekCore

/// A window catalog with windows and displays the test sets.
public final class FakeWindowCatalog: WindowCatalog, @unchecked Sendable {
    private let state: Locked<(windows: [WindowInfo], displays: [DisplayInfo], error: SkreenrekError?)>

    /// `windows` are front to back.
    public init(windows: [WindowInfo] = [], displays: [DisplayInfo] = []) {
        state = Locked((windows, displays, nil))
    }

    public var windowList: [WindowInfo] {
        get { state.withLock { $0.windows } }
        set { state.withLock { $0.windows = newValue } }
    }

    public var displayList: [DisplayInfo] {
        get { state.withLock { $0.displays } }
        set { state.withLock { $0.displays = newValue } }
    }

    /// When set, both calls throw it (for example `.permissionDenied(.screenRecording)`).
    public var error: SkreenrekError? {
        get { state.withLock { $0.error } }
        set { state.withLock { $0.error = newValue } }
    }

    public func windows() async throws -> [WindowInfo] {
        try state.withLock { s in
            if let error = s.error { throw error }
            return s.windows
        }
    }

    public func displays() async throws -> [DisplayInfo] {
        try state.withLock { s in
            if let error = s.error { throw error }
            return s.displays
        }
    }
}

/// How a fake app reacts to resize requests. Sizes are in points, like the Accessibility API.
public struct ResizeRules: Sendable {
    /// The app won't go smaller than this (per dimension).
    public var minimumSize: (width: Double, height: Double)?
    /// The app won't go larger than this (per dimension).
    public var maximumSize: (width: Double, height: Double)?
    /// The app snaps its size to `base + n × step` (like a terminal's character cell), to the nearest step.
    public var sizeStep: (width: Double, height: Double)?
    public var stepBase: (width: Double, height: Double)
    /// 1-based `setFrame` attempts (per window) the app ignores completely.
    public var ignoredAttempts: Set<Int>

    public init(
        minimumSize: (width: Double, height: Double)? = nil, maximumSize: (width: Double, height: Double)? = nil,
        sizeStep: (width: Double, height: Double)? = nil, stepBase: (width: Double, height: Double) = (0, 0),
        ignoredAttempts: Set<Int> = []
    ) {
        self.minimumSize = minimumSize
        self.maximumSize = maximumSize
        self.sizeStep = sizeStep
        self.stepBase = stepBase
        self.ignoredAttempts = ignoredAttempts
    }

    /// The size the app ends up with when asked for `requested`.
    public func apply(width: Double, height: Double) -> (width: Double, height: Double) {
        var w = width
        var h = height
        if let step = sizeStep {
            if step.width > 0 { w = stepBase.width + ((w - stepBase.width) / step.width).rounded() * step.width }
            if step.height > 0 {
                h = stepBase.height + ((h - stepBase.height) / step.height).rounded() * step.height
            }
        }
        if let minimum = minimumSize {
            w = max(w, minimum.width)
            h = max(h, minimum.height)
        }
        if let maximum = maximumSize {
            w = min(w, maximum.width)
            h = min(h, maximum.height)
        }
        return (w, h)
    }
}

/// A window resizer that keeps frames in memory and follows programmable rules per window.
public final class FakeWindowResizer: WindowResizer, @unchecked Sendable {
    public struct Call: Sendable, Hashable {
        public var window: WindowID
        public var requested: PointRect
    }

    private struct State {
        var frames: [WindowID: PointRect] = [:]
        var rules: [WindowID: ResizeRules] = [:]
        var defaultRules = ResizeRules()
        var attempts: [WindowID: Int] = [:]
        var calls: [Call] = []
        var error: SkreenrekError?
    }

    private let state = Locked(State())

    public init(windows: [WindowInfo] = [], rules: ResizeRules = ResizeRules()) {
        state.withLock { s in
            s.defaultRules = rules
            for window in windows { s.frames[window.id] = window.frame }
        }
    }

    /// Sets rules for one window.
    public func setRules(_ rules: ResizeRules, for window: WindowID) {
        state.withLock { $0.rules[window] = rules }
    }

    /// The window's current frame, if known.
    public func frame(of window: WindowID) -> PointRect? {
        state.withLock { $0.frames[window] }
    }

    /// Every `setFrame` call, in order.
    public var calls: [Call] { state.withLock { $0.calls } }

    /// When set, both calls throw it (for example `.permissionDenied(.accessibility)`).
    public var error: SkreenrekError? {
        get { state.withLock { $0.error } }
        set { state.withLock { $0.error = newValue } }
    }

    public func setFrame(_ frame: PointRect, of window: WindowInfo) async throws {
        try state.withLock { s in
            if let error = s.error { throw error }
            s.calls.append(Call(window: window.id, requested: frame))
            let attempt = (s.attempts[window.id] ?? 0) + 1
            s.attempts[window.id] = attempt
            let rules = s.rules[window.id] ?? s.defaultRules
            if rules.ignoredAttempts.contains(attempt) {
                if s.frames[window.id] == nil { s.frames[window.id] = window.frame }
                return
            }
            let size = rules.apply(width: frame.width, height: frame.height)
            s.frames[window.id] = PointRect(x: frame.x, y: frame.y, width: size.width, height: size.height)
        }
    }

    public func readFrame(of window: WindowInfo) async throws -> PointRect {
        try state.withLock { s in
            if let error = s.error { throw error }
            return s.frames[window.id] ?? window.frame
        }
    }
}
