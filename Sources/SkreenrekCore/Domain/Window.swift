/// A window ID (wraps the `CGWindowID` value). Encodes as a bare number.
public struct WindowID: Sendable, Hashable, Codable, Comparable, CustomStringConvertible {
    public var rawValue: UInt32

    public init(_ rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UInt32.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    public var description: String { String(rawValue) }

    public static func < (lhs: WindowID, rhs: WindowID) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One window that can be recorded.
public struct WindowInfo: Sendable, Hashable, Codable {
    public var id: WindowID
    /// The owning app's name, e.g. `Safari`.
    public var app: String
    public var bundleId: String?
    public var title: String
    public var pid: Int32
    /// The whole window frame (title bar included, shadow excluded), top-left global pt.
    public var frame: PointRect
    public var displayId: DisplayID
    public var onScreen: Bool

    public init(
        id: WindowID, app: String, bundleId: String?, title: String, pid: Int32, frame: PointRect,
        displayId: DisplayID, onScreen: Bool
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

    /// The window's size in output pixels on a display: `round(pt × scale)`.
    public func pixelSize(on display: DisplayInfo) -> PixelSize {
        frame.pixelSize(scale: display.scale)
    }
}

/// How a command names a window: a window ID, or an app name (or bundle ID) with an optional title substring.
public enum WindowQuery: Sendable, Hashable {
    case id(WindowID)
    case app(name: String, title: String?)
}

/// What a recording captures.
public enum CaptureTarget: Sendable, Hashable {
    case window(WindowInfo)
    /// A region in pixels on one display.
    case region(PixelRect, displayId: DisplayID)
}
