import SkreenrekCore
import Synchronization

/// Interrupts the test sends with `interrupt()`, to every live stream.
public final class FakeInterruptSource: InterruptSource {
    private struct State {
        var continuations: [Int: AsyncStream<Void>.Continuation] = [:]
        var nextID = 0
        var subscribed = 0
        var watchers: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    }

    private let state = Mutex(State())

    public init() {}

    /// Streams handed out so far.
    public var subscriptionCount: Int { state.withLock { $0.subscribed } }

    public func interrupts() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let ready = state.withLock { s -> [CheckedContinuation<Void, Never>] in
            let id = s.nextID
            s.nextID += 1
            s.continuations[id] = continuation
            s.subscribed += 1
            let count = s.subscribed
            defer { s.watchers.removeAll { $0.count <= count } }
            return s.watchers.filter { $0.count <= count }.map(\.continuation)
        }
        for watcher in ready { watcher.resume() }
        return stream
    }

    /// Sends one interrupt (Ctrl-C) to every live stream.
    public func interrupt() {
        let live = state.withLock { Array($0.continuations.values) }
        for continuation in live { continuation.yield() }
    }

    /// Returns once at least `count` streams were handed out (no polling).
    public func waitForSubscriptions(_ count: Int = 1) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let ready = state.withLock { s -> Bool in
                if s.subscribed >= count { return true }
                s.watchers.append((count, continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }
}
