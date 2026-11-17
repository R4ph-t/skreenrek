import CoreGraphics

/// A requested clip size in pixels: the file's exact width and height. Skreenrek picks the window's on-screen size
/// for it (`WindowFit`).
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

    /// A `usage` error (exit 2) when a dimension is out of range or odd. Clips are H.264-friendly even sizes.
    public func validate() throws(SkreenrekError) {
        try Self.check(size.width, dimension: "Width", noun: "width")
        try Self.check(size.height, dimension: "Height", noun: "height")
    }

    private static func check(_ px: Int, dimension: String, noun: String) throws(SkreenrekError) {
        guard (minimumPixels...maximumPixels).contains(px) else {
            throw .usage(
                message: "\(dimension) \(px) px is out of range. Sizes go from \(minimumPixels) to "
                    + "\(maximumPixels) px.",
                hint: "Use a \(noun) from \(minimumPixels) to \(maximumPixels) px.")
        }
        guard px % 2 != 0 else { return }
        let options = [px - 1, px + 1].filter { (minimumPixels...maximumPixels).contains($0) }.map(String.init)
        throw .usage(
            message: "\(dimension) \(px) px is odd. Sizes must be even.",
            hint: "Use \(options.joined(separator: " or ")) px.")
    }

    /// `2×`, `1×`, `1.5×`.
    public static func scaleLabel(_ scale: Double) -> String { "\(scaleNumber(scale))×" }

    static func scaleNumber(_ scale: Double) -> String {
        scale == scale.rounded() ? String(Int(scale)) : String(scale)
    }
}
