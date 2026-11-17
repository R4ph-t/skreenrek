/// A display ID (the `CGDirectDisplayID` value).
public typealias DisplayID = UInt32

/// One display, in top-left global points.
public struct DisplayInfo: Sendable, Hashable, Codable {
    public var id: DisplayID
    public var name: String
    /// Backing scale factor: 2 on Retina, 1 on most external displays.
    public var scale: Double
    public var frame: PointRect
    /// The frame minus the menu bar and the Dock.
    public var visibleFrame: PointRect

    public init(id: DisplayID, name: String, scale: Double, frame: PointRect, visibleFrame: PointRect) {
        self.id = id
        self.name = name
        self.scale = scale
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}
