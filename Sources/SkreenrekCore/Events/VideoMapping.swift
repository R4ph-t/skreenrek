import CoreGraphics
import Foundation

/// Maps top-left global points to video pixels for one capture target.
///
/// Windows: `x = (gx − frame.x) × scale`. Regions: the point in display pixels minus the region origin. Results are
/// rounded to whole pixels; points outside the video keep their real (possibly negative or oversized) values.
public struct VideoMapping: Sendable, Hashable {
    /// The global point (top-left pt) that maps to display pixel (0, 0) before `offset` is taken off.
    public var origin: CGPoint
    public var scale: Double
    /// Pixels subtracted after scaling (the region origin on its display; zero for windows).
    public var offset: CGPoint

    public init(origin: CGPoint, scale: Double, offset: CGPoint = .zero) {
        self.origin = origin
        self.scale = scale
        self.offset = offset
    }

    /// A window target maps from its frame; a region maps from its display's frame and its own pixel origin.
    public init(target: CaptureTarget, display: DisplayInfo) {
        switch target {
        case .window(let window):
            self.init(origin: CGPoint(x: window.frame.x, y: window.frame.y), scale: display.scale)
        case .region(let rect, _):
            self.init(
                origin: CGPoint(x: display.frame.x, y: display.frame.y), scale: display.scale,
                offset: CGPoint(x: rect.x, y: rect.y))
        }
    }

    /// The video pixel for a global top-left point.
    public func pixel(_ point: CGPoint) -> (x: Int, y: Int) {
        let x = (point.x - origin.x) * scale - offset.x
        let y = (point.y - origin.y) * scale - offset.y
        return (Self.whole(x), Self.whole(y))
    }

    private static func whole(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(value.rounded())
    }
}

/// AppKit's bottom-left screen space ↔ top-left global points, for a single point (the cursor).
public enum CursorGeometry {
    /// Flips an AppKit point (origin at the primary display's bottom-left) to top-left global pt.
    public static func topLeft(fromAppKit point: CGPoint, primaryDisplayHeight: Double) -> CGPoint {
        CGPoint(x: point.x, y: primaryDisplayHeight - point.y)
    }
}
