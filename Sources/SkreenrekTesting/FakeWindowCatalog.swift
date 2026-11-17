import SkreenrekCore
import Synchronization

/// A window catalog backed by lists the test sets.
public final class FakeWindowCatalog: WindowCatalog {
    private struct State {
        var windows: [WindowInfo]
        var displays: [DisplayInfo]
        var failure: (any Error)?
        var windowsCalls = 0
    }

    private let state: Mutex<State>

    public init(windows: [WindowInfo] = [], displays: [DisplayInfo] = []) {
        state = Mutex(State(windows: windows, displays: displays))
    }

    /// Windows, front to back.
    public var windowList: [WindowInfo] {
        get { state.withLock { $0.windows } }
        set { state.withLock { $0.windows = newValue } }
    }

    public var displayList: [DisplayInfo] {
        get { state.withLock { $0.displays } }
        set { state.withLock { $0.displays = newValue } }
    }

    /// When set, both calls throw it (e.g. `SkreenrekError.permissionDenied(.screenRecording)`).
    public var failure: (any Error)? {
        get { state.withLock { $0.failure } }
        set { state.withLock { $0.failure = newValue } }
    }

    public var windowsCalls: Int { state.withLock { $0.windowsCalls } }

    public func windows() async throws -> [WindowInfo] {
        try state.withLock { s in
            s.windowsCalls += 1
            if let failure = s.failure { throw failure }
            return s.windows
        }
    }

    public func displays() async throws -> [DisplayInfo] {
        try state.withLock { s in
            if let failure = s.failure { throw failure }
            return s.displays
        }
    }
}
