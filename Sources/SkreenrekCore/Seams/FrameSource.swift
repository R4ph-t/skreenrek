import CoreVideo
import Foundation

/// One frame from the capture source.
///
/// `pixelBuffer` is the source's own IOSurface-backed `420v` buffer, never a copy. `CVPixelBuffer` isn't `Sendable`;
/// a delivered buffer is treated as immutable, which is what makes the `@unchecked` safe.
public struct CapturedFrame: @unchecked Sendable {
    public let pixelBuffer: CVPixelBuffer
    /// Host time in seconds (the `HostClock` time base).
    public let hostTime: TimeInterval

    public init(pixelBuffer: CVPixelBuffer, hostTime: TimeInterval) {
        self.pixelBuffer = pixelBuffer
        self.hostTime = hostTime
    }
}

/// Delivers frames of a target. Real: ScreenCaptureKit (03). Fake: `SyntheticFrameSource`.
public protocol FrameSource: Sendable {
    /// Starts capturing `target` at `size` output pixels. The stream ends when `stop()` is called, and ends with an
    /// error when the source fails (e.g. the window closed).
    func start(target: CaptureTarget, size: PixelSize, fps: FrameRate, showsCursor: Bool) async throws
        -> AsyncThrowingStream<CapturedFrame, any Error>
    func stop() async
    /// Frames dropped since the last `start` because the consumer lagged (the stream keeps only the newest one).
    /// The recorder counts them in `sourceFramesSkipped`, so a lossy recording is never reported clean.
    var droppedFrameCount: Int { get }
}

extension FrameSource {
    /// Sources whose stream never drops (the test fakes) report 0.
    public var droppedFrameCount: Int { 0 }
}
