import Foundation
import Synchronization

/// A hard watchdog for tests: even an uncancellable framework continuation cannot hang the test runner.
public func withTestDeadline<T: Sendable>(seconds: Double = 30,
    _ body: @escaping @Sendable () async throws -> T
) async throws -> T {
    let gate = DeadlineGate<T>()
    return try await withCheckedThrowingContinuation { continuation in
        gate.continuation.withLock { $0 = continuation }
        let task = Task {
            do { gate.finish(.success(try await body())) }
            catch { gate.finish(.failure(error)) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            if gate.finish(.failure(TestDeadlineExceeded())) { task.cancel() }
        }
    }
}

private struct TestDeadlineExceeded: Error {}
private final class DeadlineGate<T: Sendable>: Sendable {
    let continuation = Mutex<CheckedContinuation<T, any Error>?>(nil)
    @discardableResult func finish(_ result: Result<T, any Error>) -> Bool {
        let pending = continuation.withLock { $0.take() }
        pending?.resume(with: result)
        return pending != nil
    }
}
