import Foundation

/// One still of a window, uncropped. PNG so this target never needs a pixel-buffer or image type.
public struct WindowStill: Sendable, Hashable {
    public var png: Data
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(png: Data, pixelWidth: Int, pixelHeight: Int) {
        self.png = png
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// Why a window still could not be taken. Never a prompt: a missing permission is reported.
public enum WindowPreviewError: Error, Sendable, Hashable {
    /// The first capture permission that's missing, in onboarding order.
    case permissionMissing(Permission)
    /// The window is gone.
    case windowClosed
    /// Capture failed for another reason. One sentence, for a log; the panel shows its own copy.
    case failed(String)
}

/// One still of a picked window each time the panel asks. Real capture lives in SkreenrekSystem. Fake:
/// `FakeWindowPreviewSource`. Not a live stream, and it never prompts.
///
/// `fitting` is the preview box in pixels (the box in points times the screen scale). The still is the whole window
/// scaled to fit inside that box, so the panel letterboxes it and nothing is cropped.
public protocol WindowPreviewSource: Sendable {
    func captureStill(of window: WindowInfo, fitting maxPixels: PixelSize) async throws -> WindowStill
}

/// The capture buffer for a window of `aspect` (only the ratio matters), fitted inside `box` so the still is the
/// whole window. A 16:10 window in a 16:10 box fills it. A zero side becomes 1 px rather than an empty buffer.
public enum PreviewCaptureSize {
    public static func pixels(aspectWidth: Double, aspectHeight: Double, box: PixelSize) -> PixelSize {
        let fitted = Letterbox.fit(
            imageWidth: aspectWidth, imageHeight: aspectHeight, boxWidth: Double(box.width),
            boxHeight: Double(box.height))
        return PixelSize(
            width: max(1, Int(fitted.width.rounded())), height: max(1, Int(fitted.height.rounded())))
    }
}

/// Where a still sits inside the preview box. Aspect-fit and centered: the image is never cropped, and the rest of
/// the box is the neutral fill.
public struct Letterbox: Sendable, Hashable {
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

    /// Fits `image` inside `box`. A zero side returns a zero rect rather than dividing by zero.
    public static func fit(imageWidth: Double, imageHeight: Double, boxWidth: Double, boxHeight: Double) -> Letterbox {
        guard imageWidth > 0, imageHeight > 0, boxWidth > 0, boxHeight > 0 else {
            return Letterbox(x: 0, y: 0, width: 0, height: 0)
        }
        let scale = min(boxWidth / imageWidth, boxHeight / imageHeight)
        let width = imageWidth * scale
        let height = imageHeight * scale
        return Letterbox(x: (boxWidth - width) / 2, y: (boxHeight - height) / 2, width: width, height: height)
    }
}
