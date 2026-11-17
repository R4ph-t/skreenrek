import Foundation
import Synchronization

/// The stream a frame source hands the recorder: it keeps only the newest undelivered frame, so a lagging consumer
/// never piles up capture buffers (the capture pool never runs dry), and it counts every frame it drops.
public final class FrameStreamFeed: Sendable {
    public let stream: AsyncThrowingStream<CapturedFrame, any Error>
    private let continuation: AsyncThrowingStream<CapturedFrame, any Error>.Continuation
    private let dropped = Mutex(0)

    public init() {
        (stream, continuation) = AsyncThrowingStream<CapturedFrame, any Error>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
    }

    /// Frames dropped so far: replaced by a newer frame before the consumer took them.
    public var droppedCount: Int { dropped.withLock { $0 } }

    /// Offers a frame without blocking. An older undelivered frame is dropped and counted.
    public func yield(_ frame: CapturedFrame) {
        if case .dropped = continuation.yield(frame) {
            dropped.withLock { $0 += 1 }
        }
    }

    /// Ends the stream, with an error when given.
    public func finish(throwing error: (any Error)? = nil) {
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }

    /// Called once when the consumer stops listening or the stream finishes.
    public func onTermination(_ handler: @escaping @Sendable () -> Void) {
        continuation.onTermination = { _ in handler() }
    }
}
