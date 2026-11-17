import Foundation
import SkreenrekCore
import Synchronization

/// A clock that only moves when the test says so. `sleep(until:)` resumes when the clock reaches the deadline.
public final class ManualClock: HostClock {
    private struct Sleeper {
        var id: UInt64
        var deadline: TimeInterval
        var continuation: CheckedContinuation<Void, any Error>
    }

    private struct Waiter {
        var count: Int
        var continuation: CheckedContinuation<Void, Never>
    }

    private struct State {
        var now: TimeInterval
        var nextID: UInt64 = 0
        var sleepers: [Sleeper] = []
        var cancelled: Set<UInt64> = []
        var waiters: [Waiter] = []
    }

    private let state: Mutex<State>

    public init(now: TimeInterval = 0) {
        state = Mutex(State(now: now))
    }

    public func now() -> TimeInterval {
        state.withLock { $0.now }
    }

    /// How many tasks are waiting in `sleep(until:)`.
    public var sleeperCount: Int { state.withLock { $0.sleepers.count } }

    /// The earliest pending deadline, if any.
    public var nextDeadline: TimeInterval? { state.withLock { $0.sleepers.map(\.deadline).min() } }

    /// Moves the clock forward by `seconds` and wakes every sleeper whose deadline has passed.
    public func advance(by seconds: TimeInterval) {
        advance(to: now() + seconds)
    }

    /// Moves the clock to `time` (never backwards) and wakes every sleeper whose deadline has passed, earliest first.
    public func advance(to time: TimeInterval) {
        let due = state.withLock { s -> [Sleeper] in
            s.now = max(s.now, time)
            let now = s.now
            let due = s.sleepers.filter { $0.deadline <= now }.sorted { ($0.deadline, $0.id) < ($1.deadline, $1.id) }
            s.sleepers.removeAll { $0.deadline <= now }
            return due
        }
        for sleeper in due { sleeper.continuation.resume() }
    }

    /// Suspends until at least `count` tasks are waiting in `sleep(until:)`. Lets a test know a task has reached its
    /// sleep before advancing the clock, without sleeping itself.
    public func waitForSleepers(_ count: Int = 1) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let ready = state.withLock { s -> Bool in
                if s.sleepers.count >= count { return true }
                s.waiters.append(Waiter(count: count, continuation: continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }

    public func sleep(until deadline: TimeInterval) async throws {
        try Task.checkCancellation()
        let id = state.withLock { s -> UInt64 in
            s.nextID += 1
            return s.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                enum Outcome { case resume, cancel, wait([CheckedContinuation<Void, Never>]) }
                let outcome = state.withLock { s -> Outcome in
                    if s.cancelled.remove(id) != nil { return .cancel }
                    if deadline <= s.now { return .resume }
                    s.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    let count = s.sleepers.count
                    let ready = s.waiters.filter { $0.count <= count }.map(\.continuation)
                    s.waiters.removeAll { $0.count <= count }
                    return .wait(ready)
                }
                switch outcome {
                case .resume: continuation.resume()
                case .cancel: continuation.resume(throwing: CancellationError())
                case .wait(let ready): for waiter in ready { waiter.resume() }
                }
            }
        } onCancel: {
            let sleeper = state.withLock { s -> Sleeper? in
                if let index = s.sleepers.firstIndex(where: { $0.id == id }) {
                    return s.sleepers.remove(at: index)
                }
                s.cancelled.insert(id)
                return nil
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }
}
