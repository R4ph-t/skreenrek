import Foundation
import SkreenrekCore
import Synchronization

/// A window picker that answers with what the test set, or waits until the test calls `answer(_:)`.
public final class FakeWindowPicker: WindowPicker {
    private struct State {
        var result: PickResult?
        var failure: (any Error)?
        var timeouts: [TimeInterval] = []
        var waiting: [CheckedContinuation<PickResult, Never>] = []
    }

    private let state: Mutex<State>

    /// - Parameter result: the answer to every `pick`; nil makes `pick` wait for `answer(_:)`.
    public init(result: PickResult? = .cancelled) {
        state = Mutex(State(result: result))
    }

    /// When set, `pick` throws it.
    public var failure: (any Error)? {
        get { state.withLock { $0.failure } }
        set { state.withLock { $0.failure = newValue } }
    }

    /// The timeout of every `pick` call, in order.
    public var timeouts: [TimeInterval] { state.withLock { $0.timeouts } }

    /// How many `pick` calls are waiting for `answer(_:)`.
    public var waitingCount: Int { state.withLock { $0.waiting.count } }

    /// Answers every waiting `pick`.
    public func answer(_ result: PickResult) {
        let waiting = state.withLock { s in
            defer { s.waiting = [] }
            return s.waiting
        }
        for continuation in waiting { continuation.resume(returning: result) }
    }

    public func pick(timeout: TimeInterval) async throws -> PickResult {
        let preset = try state.withLock { s -> PickResult? in
            s.timeouts.append(timeout)
            if let failure = s.failure { throw failure }
            return s.result
        }
        if let preset { return preset }
        return await withCheckedContinuation { continuation in
            state.withLock { $0.waiting.append(continuation) }
        }
    }
}
