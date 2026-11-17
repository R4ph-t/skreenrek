import Foundation

/// Host time in seconds. Real: the host clock (03). Fake: `ManualClock`.
public protocol HostClock: Sendable {
    func now() -> TimeInterval
    /// Returns once `now() >= deadline`. Throws `CancellationError` if the task is cancelled first.
    func sleep(until deadline: TimeInterval) async throws
}
