import CoreGraphics
import Foundation

public enum MouseEventType: String, Sendable, Hashable, Codable {
    case down
    case up
}

/// One mouse button event. No keystrokes, no scroll.
public struct MouseEvent: Sendable, Hashable {
    public var type: MouseEventType
    /// The button index: 0 left, 1 right, 2 middle, 3+ other.
    public var button: Int
    public var clickCount: Int
    /// Global location in top-left pt (the `PointRect` space).
    public var location: CGPoint
    /// Host time in seconds.
    public var hostTime: TimeInterval

    public init(type: MouseEventType, button: Int, clickCount: Int, location: CGPoint, hostTime: TimeInterval) {
        self.type = type
        self.button = button
        self.clickCount = clickCount
        self.location = location
        self.hostTime = hostTime
    }
}

/// Mouse button events and the cursor position. Real: global event monitors (04). Fake: `FakeMouseEventSource`.
public protocol MouseEventSource: Sendable {
    /// Starts delivering events. The stream finishes when `stop()` is called.
    func start() async throws -> AsyncStream<MouseEvent>
    func stop() async
    /// The cursor's current global location, top-left pt.
    func cursorLocation() -> CGPoint
}
