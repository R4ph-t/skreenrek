import CoreGraphics
import CoreVideo
import Foundation

/// One captured frame: the source's own IOSurface-backed `420v` buffer (never a copy) and its host time.
public struct CapturedFrame: @unchecked Sendable {
    /// Handed through to the writer untouched. `CVPixelBuffer` isn't `Sendable`; ownership moves with the frame,
    /// and nobody mutates the pixels after capture.
    public let pixelBuffer: CVPixelBuffer
    /// Host time in seconds.
    public let hostTime: TimeInterval

    public init(pixelBuffer: CVPixelBuffer, hostTime: TimeInterval) {
        self.pixelBuffer = pixelBuffer
        self.hostTime = hostTime
    }
}

/// Delivers frames of a capture target. Real implementation: ScreenCaptureKit (03).
public protocol FrameSource: Sendable {
    func start(target: CaptureTarget, size: PixelSize, fps: FrameRate, showsCursor: Bool) async throws
        -> AsyncThrowingStream<CapturedFrame, Error>
    func stop() async
}

/// A mouse button event in top-left global points.
public struct MouseEvent: Sendable, Codable, Equatable {
    public enum Kind: String, Sendable, Codable, Hashable {
        case down
        case up
    }

    public var type: Kind
    /// 0 left, 1 right, 2 and up other buttons.
    public var button: Int
    public var clickCount: Int
    public var location: CGPoint
    /// Host time in seconds.
    public var hostTime: TimeInterval

    public init(type: Kind, button: Int, clickCount: Int, location: CGPoint, hostTime: TimeInterval) {
        self.type = type
        self.button = button
        self.clickCount = clickCount
        self.location = location
        self.hostTime = hostTime
    }
}

/// Global mouse buttons and cursor position. Real implementation: event monitors (04).
public protocol MouseEventSource: Sendable {
    /// Starts delivering events until `stop()`.
    func start() async -> AsyncStream<MouseEvent>
    func stop() async
    /// Current cursor location, top-left global points.
    func cursorLocation() -> CGPoint
}
