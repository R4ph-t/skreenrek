import CoreGraphics
import Foundation

/// A size in output pixels. Encodes as `{ "width", "height", "unit": "px" }`.
public struct PixelSize: Sendable, Hashable, Codable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// `1280 × 800 px`, the UI and message form.
    public var description: String { "\(width) × \(height) px" }

    /// `1280x800`, the CLI flag form.
    public var flagValue: String { "\(width)x\(height)" }

    private enum CodingKeys: String, CodingKey { case width, height, unit }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try Unit.check(c, key: .unit, expected: "px")
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encode("px", forKey: .unit)
    }
}

/// A rectangle in points, top-left global origin: the coordinate space ScreenCaptureKit and Accessibility use.
/// Encodes as `{ "x", "y", "width", "height", "unit": "pt" }`.
public struct PointRect: Sendable, Hashable, Codable {
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

    /// The size in pixels at a display scale: `round(pt × scale)`.
    public func pixelSize(scale: Double) -> PixelSize {
        PixelSize(width: Int((width * scale).rounded()), height: Int((height * scale).rounded()))
    }

    private enum CodingKeys: String, CodingKey { case x, y, width, height, unit }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try Unit.check(c, key: .unit, expected: "pt")
        x = try c.decode(Double.self, forKey: .x)
        y = try c.decode(Double.self, forKey: .y)
        width = try c.decode(Double.self, forKey: .width)
        height = try c.decode(Double.self, forKey: .height)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encode("pt", forKey: .unit)
    }
}

/// A rectangle in pixels on one display, top-left origin. Encodes as `{ "x", "y", "width", "height", "unit": "px" }`.
public struct PixelRect: Sendable, Hashable, Codable {
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

    private enum CodingKeys: String, CodingKey { case x, y, width, height, unit }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try Unit.check(c, key: .unit, expected: "px")
        x = try c.decode(Int.self, forKey: .x)
        y = try c.decode(Int.self, forKey: .y)
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encode("px", forKey: .unit)
    }
}

enum Unit {
    /// A missing `unit` is accepted; a different one is a decoding error.
    static func check<K: CodingKey>(_ c: KeyedDecodingContainer<K>, key: K, expected: String) throws {
        guard let unit = try c.decodeIfPresent(String.self, forKey: key) else { return }
        guard unit == expected else {
            throw DecodingError.dataCorruptedError(
                forKey: key, in: c, debugDescription: "Expected unit \"\(expected)\", got \"\(unit)\"")
        }
    }
}
