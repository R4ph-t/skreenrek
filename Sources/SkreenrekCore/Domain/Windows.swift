import Foundation

/// A display, in top-left global points.
public struct DisplayInfo: Sendable, Codable, Hashable {
    /// The `CGDirectDisplayID`.
    public var id: UInt32
    public var name: String
    /// Backing scale factor (1 or 2 on current Macs).
    public var scale: Double
    public var frame: PointRect
    public var visibleFrame: PointRect

    public init(id: UInt32, name: String, scale: Double, frame: PointRect, visibleFrame: PointRect) {
        self.id = id
        self.name = name
        self.scale = scale
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

/// A window's `CGWindowID`.
public struct WindowID: Sendable, Codable, Hashable, RawRepresentable, CustomStringConvertible,
    ExpressibleByIntegerLiteral
{
    public var rawValue: UInt32

    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public init(_ rawValue: UInt32) { self.rawValue = rawValue }
    public init(integerLiteral value: UInt32) { self.rawValue = value }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UInt32.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { String(rawValue) }
}

/// One window as the catalog sees it.
public struct WindowInfo: Sendable, Codable, Hashable {
    public var id: WindowID
    public var app: String
    public var bundleId: String?
    public var title: String
    public var pid: Int32
    /// Whole window frame in top-left global points.
    public var frame: PointRect
    public var displayId: UInt32
    public var onScreen: Bool

    public init(
        id: WindowID, app: String, bundleId: String?, title: String, pid: Int32, frame: PointRect,
        displayId: UInt32, onScreen: Bool
    ) {
        self.id = id
        self.app = app
        self.bundleId = bundleId
        self.title = title
        self.pid = pid
        self.frame = frame
        self.displayId = displayId
        self.onScreen = onScreen
    }

    /// The window's size in pixels on `display`: `round(pt × scale)`.
    public func pixelSize(on display: DisplayInfo) -> PixelSize {
        frame.pixelSize(scale: display.scale)
    }
}

/// How a caller names a window.
public enum WindowQuery: Sendable, Hashable {
    case id(WindowID)
    case app(name: String, title: String?)
}

/// What a recording captures.
public enum CaptureTarget: Sendable, Hashable {
    case window(WindowInfo)
    case region(PixelRect, displayId: UInt32)
}
