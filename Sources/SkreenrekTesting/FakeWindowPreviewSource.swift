import Foundation
import SkreenrekCore
import Synchronization

/// A window-preview source the tests script. It records whether the capture ran on the main thread, and it can hold
/// the capture open so a test can see the panel already showing `.loading`.
public final class FakeWindowPreviewSource: WindowPreviewSource, @unchecked Sendable {
    public struct Call: Sendable, Equatable {
        public var windowID: WindowID
        /// The preview box, in pixels, the panel asked the still to fit inside.
        public var fitting: PixelSize
        /// True when `captureStill` began on the main thread. The panel must call it off the main thread.
        public var onMainThread: Bool
    }

    private struct State {
        var result: Result<WindowStill, WindowPreviewError> = .failure(.failed("No result set"))
        var calls: [Call] = []
        var hold = false
        var released = false
        var callWaiter: CheckedContinuation<Call, Never>?
        var releaseWaiter: CheckedContinuation<Void, Never>?
    }

    private let state = Mutex(State())

    public init() {}

    public func setResult(_ result: Result<WindowStill, WindowPreviewError>) {
        state.withLock { $0.result = result }
    }

    public func calls() -> [Call] { state.withLock { $0.calls } }

    /// The next captures wait inside `captureStill` until `release()`.
    public func holdNext() {
        state.withLock {
            $0.hold = true
            $0.released = false
        }
    }

    /// Resumes when `captureStill` has been entered (the call is recorded, and a held capture has not returned).
    public func waitForCall() async -> Call {
        await withCheckedContinuation { continuation in
            let existing = state.withLock { s -> Call? in
                if let call = s.calls.last {
                    return call
                }
                s.callWaiter = continuation
                return nil
            }
            if let existing { continuation.resume(returning: existing) }
        }
    }

    /// Lets a held capture return its result.
    public func release() {
        let waiter = state.withLock { s -> CheckedContinuation<Void, Never>? in
            s.released = true
            let waiter = s.releaseWaiter
            s.releaseWaiter = nil
            return waiter
        }
        waiter?.resume()
    }

    public func captureStill(of window: WindowInfo, fitting maxPixels: PixelSize) async throws -> WindowStill {
        let call = Call(windowID: window.id, fitting: maxPixels, onMainThread: Self.isOnMainThread())
        let waiter = state.withLock { s -> CheckedContinuation<Call, Never>? in
            s.calls.append(call)
            let waiter = s.callWaiter
            s.callWaiter = nil
            return waiter
        }
        waiter?.resume(returning: call)

        let shouldHold = state.withLock { $0.hold && !$0.released }
        if shouldHold {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let alreadyReleased = state.withLock { s -> Bool in
                    if s.released { return true }
                    s.releaseWaiter = continuation
                    return false
                }
                if alreadyReleased { continuation.resume() }
            }
        }
        return try state.withLock { try $0.result.get() }
    }

    /// Synchronous because `Thread.isMainThread` is unavailable from async code. It reports the caller's thread.
    private static func isOnMainThread() -> Bool { Thread.isMainThread }
}
