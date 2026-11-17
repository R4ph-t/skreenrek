import Foundation
import SkreenrekCore

/// A host clock that only moves when a test tells it to. `sleep(until:)` resumes once the clock reaches the deadline.
public final class ManualClock: HostClock, @unchecked Sendable {
    private struct Sleeper {
        let id: UInt64
        let deadline: TimeInterval
        let continuation: CheckedContinuation<Void, Error>
    }

    private struct Watcher {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private struct State {
        var now: TimeInterval
        var nextID: UInt64 = 0
        var sleepers: [Sleeper] = []
        var watchers: [Watcher] = []
    }

    private let state: Locked<State>

    public init(now: TimeInterval = 0) {
        state = Locked(State(now: now))
    }

    public func now() -> TimeInterval {
        state.withLock { $0.now }
    }

    /// How many tasks are suspended in `sleep(until:)`.
    public var sleeperCount: Int {
        state.withLock { $0.sleepers.count }
    }

    /// The earliest pending deadline, if any.
    public var nextDeadline: TimeInterval? {
        state.withLock { $0.sleepers.map(\.deadline).min() }
    }

    public func sleep(until deadline: TimeInterval) async throws {
        try Task.checkCancellation()
        let id = state.withLock { s -> UInt64 in
            s.nextID += 1
            return s.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                enum Outcome { case ready, cancelled, waiting([CheckedContinuation<Void, Never>]) }
                let outcome = state.withLock { s -> Outcome in
                    if s.now >= deadline { return .ready }
                    if Task.isCancelled { return .cancelled }
                    s.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return .waiting(Self.takeSatisfiedWatchers(&s))
                }
                switch outcome {
                case .ready: continuation.resume()
                case .cancelled: continuation.resume(throwing: CancellationError())
                case .waiting(let watchers): watchers.forEach { $0.resume() }
                }
            }
        } onCancel: {
            let sleeper = state.withLock { s -> Sleeper? in
                guard let index = s.sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return s.sleepers.remove(at: index)
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves the clock forward and wakes every sleeper whose deadline has come, earliest first.
    public func advance(by interval: TimeInterval) {
        let target = now() + interval
        advance(to: target)
    }

    /// Moves the clock to `time` (never backwards) and wakes every sleeper whose deadline has come, earliest first.
    public func advance(to time: TimeInterval) {
        let due = state.withLock { s -> [Sleeper] in
            s.now = max(s.now, time)
            let now = s.now
            let due = s.sleepers.filter { $0.deadline <= now }.sorted { $0.deadline < $1.deadline }
            s.sleepers.removeAll { $0.deadline <= now }
            return due
        }
        due.forEach { $0.continuation.resume() }
    }

    /// Suspends until at least `count` tasks are waiting in `sleep(until:)`. Lets a test advance the clock only once
    /// the code under test is parked, without real sleeps.
    public func waitForSleepers(_ count: Int = 1) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let ready = state.withLock { s -> Bool in
                if s.sleepers.count >= count { return true }
                s.watchers.append(Watcher(count: count, continuation: continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }

    private static func takeSatisfiedWatchers(_ s: inout State) -> [CheckedContinuation<Void, Never>] {
        let count = s.sleepers.count
        let ready = s.watchers.filter { $0.count <= count }.map(\.continuation)
        s.watchers.removeAll { $0.count <= count }
        return ready
    }
}
