import CoreGraphics
import SkreenrekCore
import Synchronization

/// A mouse event source the test drives with `send(_:)` and `cursor`.
public final class FakeMouseEventSource: MouseEventSource {
    private struct State {
        var cursor: CGPoint
        var continuation: AsyncStream<MouseEvent>.Continuation?
        var startCount = 0
        var failure: (any Error)?
    }

    private let state: Mutex<State>

    public init(cursor: CGPoint = .zero) {
        state = Mutex(State(cursor: cursor))
    }

    /// What `cursorLocation()` returns.
    public var cursor: CGPoint {
        get { state.withLock { $0.cursor } }
        set { state.withLock { $0.cursor = newValue } }
    }

    /// When set, `start()` throws it.
    public var failure: (any Error)? {
        get { state.withLock { $0.failure } }
        set { state.withLock { $0.failure = newValue } }
    }

    public var isRunning: Bool { state.withLock { $0.continuation != nil } }
    public var startCount: Int { state.withLock { $0.startCount } }

    public func start() async throws -> AsyncStream<MouseEvent> {
        let (stream, continuation) = AsyncStream<MouseEvent>.makeStream()
        let previous = try state.withLock { s -> AsyncStream<MouseEvent>.Continuation? in
            if let failure = s.failure { throw failure }
            s.startCount += 1
            let previous = s.continuation
            s.continuation = continuation
            return previous
        }
        previous?.finish()
        return stream
    }

    /// Delivers an event to the running stream (dropped when not started). Also moves the cursor to its location.
    public func send(_ event: MouseEvent) {
        let continuation = state.withLock { s in
            s.cursor = event.location
            return s.continuation
        }
        continuation?.yield(event)
    }

    public func stop() async {
        state.withLock { s in
            let c = s.continuation
            s.continuation = nil
            return c
        }?.finish()
    }

    public func cursorLocation() -> CGPoint {
        cursor
    }
}
