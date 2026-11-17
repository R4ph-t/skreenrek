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

    /// A window target maps from its frame; a region maps from its display's frame and its own pixel origin. A
    /// window recorded at a `clip` size other than its native pixels maps through the clip's scale and crop
    /// (`WindowFit.sourceRect`).
    public init(target: CaptureTarget, display: DisplayInfo, clip: PixelSize? = nil) {
        switch target {
        case .window(let window):
            let origin = CGPoint(x: window.frame.x, y: window.frame.y)
            let size = CGSize(width: window.frame.width, height: window.frame.height)
            guard let clip, clip != window.frame.pixelSize(scale: display.scale), size.width > 0 else {
                self.init(origin: origin, scale: display.scale)
                return
            }
            let source = WindowFit.sourceRect(window: size, clip: clip) ?? CGRect(origin: .zero, size: size)
            let scale = Double(clip.width) / source.width
            self.init(origin: origin, scale: scale, offset: CGPoint(x: source.minX * scale, y: source.minY * scale))
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
