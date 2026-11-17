import Foundation
import SkreenrekCore
import Synchronization

/// A `ReleaseFeed` with a scripted answer. With `gated`, each call waits until `release()` so a test can look at the
/// checking state; `calls` counts the requests.
public final class FakeReleaseFeed: ReleaseFeed {
    public struct Failure: Error, Equatable {
        public init() {}
    }

    private struct State {
        var result: Result<ReleaseInfo, Failure>
        var calls = 0
        var waiting: [CheckedContinuation<Void, Never>] = []
        var released = 0
    }

    private let state: Mutex<State>
    private let gated: Bool
    private let started: AsyncStream<Void>.Continuation
    /// Yields once per call, as soon as the call starts.
    public let calls: AsyncStream<Void>

    public init(_ result: Result<ReleaseInfo, Failure>, gated: Bool = false) {
        state = Mutex(State(result: result))
        self.gated = gated
        (calls, started) = AsyncStream.makeStream()
    }

    /// `v<version>` at the GitHub releases page.
    public convenience init(latest version: String, gated: Bool = false) {
        self.init(
            .success(
                ReleaseInfo(
                    version: SemanticVersion(version)!,
                    pageURL: URL(string: "https://github.com/R4ph-t/skreenrek/releases/tag/v\(version)")!)),
            gated: gated)
    }

    public var callCount: Int { state.withLock { $0.calls } }

    public func setResult(_ result: Result<ReleaseInfo, Failure>) {
        state.withLock { $0.result = result }
    }

    /// Lets one gated call finish (or the next one, if none is waiting yet).
    public func release() {
        let continuation = state.withLock { state -> CheckedContinuation<Void, Never>? in
            if state.waiting.isEmpty {
                state.released += 1
                return nil
            }
            return state.waiting.removeFirst()
        }
        continuation?.resume()
    }

    public func latestRelease() async throws -> ReleaseInfo {
        state.withLock { $0.calls += 1 }
        started.yield()
        if gated {
            await withCheckedContinuation { continuation in
                let resumeNow = state.withLock { state -> Bool in
                    if state.released > 0 {
                        state.released -= 1
                        return true
                    }
                    state.waiting.append(continuation)
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        }
        return try state.withLock { $0.result }.get()
    }
}

/// An `UpdateInstaller` that prints scripted lines and then succeeds or fails.
public final class FakeUpdateInstaller: UpdateInstaller {
    public struct Failure: Error, Equatable {
        public init() {}
    }

    private let lines: [String]
    private let fails: Bool
    private let count = Mutex(0)

    public init(lines: [String] = [], fails: Bool = false) {
        self.lines = lines
        self.fails = fails
    }

    public var runs: Int { count.withLock { $0 } }

    public func upgrade(progress: @escaping @Sendable (String) -> Void) async throws {
        count.withLock { $0 += 1 }
        for line in lines { progress(line) }
        if fails { throw Failure() }
    }
}
