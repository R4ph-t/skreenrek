import CoreGraphics
import Foundation
import SkreenrekCore

/// A mouse source the test drives: `send(_:)` delivers an event, `cursor` sets the cursor location.
public final class FakeMouseEventSource: MouseEventSource, @unchecked Sendable {
    private let state: Locked<(cursor: CGPoint, continuation: AsyncStream<MouseEvent>.Continuation?)>

    public init(cursor: CGPoint = .zero) {
        state = Locked((cursor, nil))
    }

    public var cursor: CGPoint {
        get { state.withLock { $0.cursor } }
        set { state.withLock { $0.cursor = newValue } }
    }

    public var isRunning: Bool { state.withLock { $0.continuation != nil } }

    public func start() async -> AsyncStream<MouseEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: MouseEvent.self)
        let previous = state.withLock { s -> AsyncStream<MouseEvent>.Continuation? in
            let previous = s.continuation
            s.continuation = continuation
            return previous
        }
        previous?.finish()
        return stream
    }

    public func stop() async {
        let continuation = state.withLock { s -> AsyncStream<MouseEvent>.Continuation? in
            defer { s.continuation = nil }
            return s.continuation
        }
        continuation?.finish()
    }

    /// Delivers an event when started; dropped otherwise, like a stopped monitor.
    public func send(_ event: MouseEvent) {
        _ = state.withLock { $0.continuation }?.yield(event)
    }

    public func cursorLocation() -> CGPoint {
        cursor
    }
}
