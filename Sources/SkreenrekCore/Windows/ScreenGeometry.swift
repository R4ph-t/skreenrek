import CoreGraphics

/// Converts between AppKit screen frames (bottom-left origin at the primary display, y up) and top-left global points
/// (origin at the primary display's top-left corner, y down: the space ScreenCaptureKit, Accessibility and
/// `PointRect` use). Pure: the caller passes the primary display's height.
public struct ScreenGeometry: Sendable, Hashable {
    /// The height of the primary display (the screen whose AppKit frame origin is 0, 0), in pt.
    public var primaryHeight: Double

    public init(primaryHeight: Double) {
        self.primaryHeight = primaryHeight
    }

    /// An AppKit frame (bottom-left origin) as top-left global pt.
    public func topLeft(fromAppKit rect: CGRect) -> PointRect {
        PointRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// An AppKit point (bottom-left origin), e.g. the cursor, as a top-left global point.
    public func topLeft(fromAppKit point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// A top-left global rect as an AppKit frame (bottom-left origin).
    public func appKit(fromTopLeft rect: PointRect) -> CGRect {
        CGRect(x: rect.x, y: primaryHeight - (rect.y + rect.height), width: rect.width, height: rect.height)
    }
}
