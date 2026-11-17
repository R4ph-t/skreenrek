import Foundation
import SkreenrekCore

/// The Custom Size panel's logic: two px fields, the points equivalent in 12 pt secondary text, and the size when
/// the display can take it. Pure.
public struct CustomSizeModel: Sendable, Hashable {
    public var widthText: String
    public var heightText: String
    public var scale: Double

    public init(widthText: String = "", heightText: String = "", scale: Double) {
        self.widthText = widthText
        self.heightText = heightText
        self.scale = scale
    }

    public init(current: PixelSize?, scale: Double) {
        self.init(
            widthText: current.map { String($0.width) } ?? "", heightText: current.map { String($0.height) } ?? "",
            scale: scale)
    }

    /// The size when both fields hold whole px values this display can take; nil otherwise.
    public var size: PixelSize? {
        guard let size = parsed, (try? SizeRequest(size).points(scale: scale)) != nil else { return nil }
        return size
    }

    /// `640 × 400 pt at 2×`, the reason the size can't be used, or the prompt when a field is empty.
    public var caption: String {
        guard let size = parsed else { return UIStrings.CustomSize.enterSize }
        do {
            let points = try SizeRequest(size).points(scale: scale)
            return UIStrings.CustomSize.points(
                width: Double(points.width), height: Double(points.height), scale: scale)
        } catch {
            return error.message
        }
    }

    public var isValid: Bool { size != nil }

    private var parsed: PixelSize? {
        guard let w = Int(widthText.trimmingCharacters(in: .whitespaces)),
            let h = Int(heightText.trimmingCharacters(in: .whitespaces))
        else { return nil }
        return PixelSize(width: w, height: h)
    }
}
