/// The result of a resize, read back from the window. Its JSON is the design spec's "JSON read-back" block:
///
/// ```json
/// {
///   "window": { "id": 4127, "app": "Safari", "bundleId": "com.apple.Safari", "title": "localhost:3000", "pid": 812 },
///   "display": { "id": 1, "name": "Built-in Retina Display", "scale": 2 },
///   "requested": { "width": 1280, "height": 800, "unit": "px" },
///   "actual":    { "width": 1280, "height": 800, "unit": "px" },
///   "frame":     { "x": 120, "y": 80, "width": 640, "height": 400, "unit": "pt" },
///   "exact": true,
///   "attempts": 1
/// }
/// ```
public struct Readback: Sendable, Hashable, Codable {
    public struct Window: Sendable, Hashable, Codable {
        public var id: WindowID
        public var app: String
        public var bundleId: String?
        public var title: String
        public var pid: Int32

        public init(id: WindowID, app: String, bundleId: String?, title: String, pid: Int32) {
            self.id = id
            self.app = app
            self.bundleId = bundleId
            self.title = title
            self.pid = pid
        }

        public init(_ window: WindowInfo) {
            self.init(id: window.id, app: window.app, bundleId: window.bundleId, title: window.title, pid: window.pid)
        }
    }

    public struct Display: Sendable, Hashable, Codable {
        public var id: DisplayID
        public var name: String
        public var scale: Double

        public init(id: DisplayID, name: String, scale: Double) {
            self.id = id
            self.name = name
            self.scale = scale
        }

        public init(_ display: DisplayInfo) {
            self.init(id: display.id, name: display.name, scale: display.scale)
        }
    }

    public var window: Window
    public var display: Display
    public var requested: PixelSize
    public var actual: PixelSize
    /// The frame read back, in pt.
    public var frame: PointRect
    /// Both dimensions are pixel-equal (0 px tolerance).
    public var exact: Bool
    public var attempts: Int

    public init(
        window: Window, display: Display, requested: PixelSize, actual: PixelSize, frame: PointRect, exact: Bool,
        attempts: Int
    ) {
        self.window = window
        self.display = display
        self.requested = requested
        self.actual = actual
        self.frame = frame
        self.exact = exact
        self.attempts = attempts
    }
}

// `bundleId` is always present in the JSON (null when unknown), so the shape never changes.
extension Readback.Window {
    private enum CodingKeys: String, CodingKey { case id, app, bundleId, title, pid }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(app, forKey: .app)
        try c.encode(bundleId, forKey: .bundleId)
        try c.encode(title, forKey: .title)
        try c.encode(pid, forKey: .pid)
    }
}
