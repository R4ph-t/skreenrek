import CoreGraphics

/// A requested window size in output pixels, checked against a display scale before any resize.
public struct SizeRequest: Sendable, Hashable {
    public static let minimumPixels = 2
    public static let maximumPixels = 16384

    public var size: PixelSize

    public init(_ size: PixelSize) {
        self.size = size
    }

    public init(width: Int, height: Int) {
        self.init(PixelSize(width: width, height: height))
    }

    /// The size in points on a display of `scale` (`px ÷ scale`), or a `usage` error (exit 2) when a dimension is out
    /// of range or isn't a whole number of points at that scale.
    public func points(scale: Double) throws(SkreenrekError) -> CGSize {
        try Self.check(size.width, dimension: "Width", noun: "width", scale: scale)
        try Self.check(size.height, dimension: "Height", noun: "height", scale: scale)
        return CGSize(width: Double(size.width) / scale, height: Double(size.height) / scale)
    }

    private static func check(_ px: Int, dimension: String, noun: String, scale: Double) throws(SkreenrekError) {
        guard (minimumPixels...maximumPixels).contains(px) else {
            throw .usage(
                message: "\(dimension) \(px) px is out of range. Sizes go from \(minimumPixels) to "
                    + "\(maximumPixels) px.",
                hint: "Use a \(noun) from \(minimumPixels) to \(maximumPixels) px.")
        }
        guard scale > 0, !fits(px, scale: scale) else { return }
        let (lower, upper) = neighbours(px, scale: scale)
        let label = scaleLabel(scale)
        let message: String
        if scale == 2 {
            message = "\(dimension) \(px) px is odd. On a 2× display sizes must be even."
        } else {
            message = "\(dimension) \(px) px doesn't fit a \(label) display. On a \(label) display sizes must be "
                + "whole points (px ÷ \(scaleNumber(scale)))."
        }
        let options = [lower, upper].filter { (minimumPixels...maximumPixels).contains($0) }.map(String.init)
        throw .usage(message: message, hint: "Use \(options.joined(separator: " or ")) px.")
    }

    /// `px ÷ scale` is a whole number of points.
    static func fits(_ px: Int, scale: Double) -> Bool {
        let pt = Double(px) / scale
        return abs(pt - pt.rounded()) < 1e-9
    }

    /// The nearest valid sizes below and above `px`.
    static func neighbours(_ px: Int, scale: Double) -> (Int, Int) {
        let pt = Double(px) / scale
        let lower = Int((pt.rounded(.down) * scale).rounded())
        let upper = Int((pt.rounded(.up) * scale).rounded())
        return (lower, upper)
    }

    /// `2×`, `1×`, `1.5×`.
    public static func scaleLabel(_ scale: Double) -> String { "\(scaleNumber(scale))×" }

    static func scaleNumber(_ scale: Double) -> String {
        scale == scale.rounded() ? String(Int(scale)) : String(scale)
    }
}
