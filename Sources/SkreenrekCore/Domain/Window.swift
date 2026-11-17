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
    /// The window server layer. Normal app windows are on layer 0.
    public var layer: Int

    public init(
        id: WindowID, app: String, bundleId: String?, title: String, pid: Int32, frame: PointRect,
        displayId: DisplayID, onScreen: Bool, layer: Int = 0
    ) {
        self.id = id
        self.app = app
        self.bundleId = bundleId
        self.title = title
        self.pid = pid
        self.frame = frame
        self.displayId = displayId
        self.onScreen = onScreen
        self.layer = layer
    }

    private enum CodingKeys: String, CodingKey {
        case id, app, bundleId, title, pid, frame, displayId, onScreen, layer
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(WindowID.self, forKey: .id)
        app = try c.decode(String.self, forKey: .app)
        bundleId = try c.decodeIfPresent(String.self, forKey: .bundleId)
        title = try c.decode(String.self, forKey: .title)
        pid = try c.decode(Int32.self, forKey: .pid)
        frame = try c.decode(PointRect.self, forKey: .frame)
        displayId = try c.decode(DisplayID.self, forKey: .displayId)
        onScreen = try c.decode(Bool.self, forKey: .onScreen)
        // Older payloads have no layer; they only ever held normal windows.
        layer = try c.decodeIfPresent(Int.self, forKey: .layer) ?? 0
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
