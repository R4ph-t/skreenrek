import Foundation

/// The result of an exact resize, read back from the window: the JSON read-back block.
///
/// Sizes carry `"unit": "px"` and the frame carries `"unit": "pt"` so a reader never has to guess.
public struct Readback: Sendable, Codable, Hashable {
    public struct Window: Sendable, Codable, Hashable {
        public var id: WindowID
        public var app: String
        public var title: String

        public init(id: WindowID, app: String, title: String) {
            self.id = id
            self.app = app
            self.title = title
        }

        public init(_ window: WindowInfo) {
            self.init(id: window.id, app: window.app, title: window.title)
        }
    }

    public struct Display: Sendable, Codable, Hashable {
        public var id: UInt32
        public var scale: Double

        public init(id: UInt32, scale: Double) {
            self.id = id
            self.scale = scale
        }
    }

    /// A pixel size with its unit.
    public struct Size: Sendable, Codable, Hashable {
        public var width: Int
        public var height: Int
        public var unit: String

        public init(_ size: PixelSize) {
            width = size.width
            height = size.height
            unit = "px"
        }

        public var pixelSize: PixelSize { PixelSize(width: width, height: height) }
    }

    /// A point frame with its unit.
    public struct Frame: Sendable, Codable, Hashable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double
        public var unit: String

        public init(_ rect: PointRect) {
            x = rect.x
            y = rect.y
            width = rect.width
            height = rect.height
            unit = "pt"
        }

        public var pointRect: PointRect { PointRect(x: x, y: y, width: width, height: height) }
    }

    public var window: Window
    public var display: Display
    public var requested: Size
    public var actual: Size
    public var frame: Frame
    public var exact: Bool
    public var attempts: Int

    public init(
        window: Window, display: Display, requested: PixelSize, actual: PixelSize, frame: PointRect,
        attempts: Int
    ) {
        self.window = window
        self.display = display
        self.requested = Size(requested)
        self.actual = Size(actual)
        self.frame = Frame(frame)
        self.exact = requested == actual
        self.attempts = attempts
    }
}
