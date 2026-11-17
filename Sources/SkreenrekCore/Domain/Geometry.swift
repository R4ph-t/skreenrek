import CoreGraphics
import Foundation

/// A size in output pixels.
public struct PixelSize: Sendable, Codable, Hashable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// A rectangle in points, top-left global origin: the coordinate space ScreenCaptureKit and Accessibility use.
public struct PointRect: Sendable, Codable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }

    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    /// Pixel size at a display scale: `round(pt × scale)` per dimension.
    public func pixelSize(scale: Double) -> PixelSize {
        PixelSize(width: Int((width * scale).rounded()), height: Int((height * scale).rounded()))
    }
}

/// A rectangle in pixels of one display, top-left origin.
public struct PixelRect: Sendable, Codable, Hashable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var size: PixelSize { PixelSize(width: width, height: height) }
}
