/// Sets and reads a window's frame. Real: Accessibility (02). Fake: `FakeWindowResizer`.
public protocol WindowResizer: Sendable {
    /// Asks the window to take this frame (top-left global pt). The app may not obey; read the frame back.
    func setFrame(_ frame: PointRect, of window: WindowInfo) async throws
    /// The window's current frame (top-left global pt).
    func readFrame(of window: WindowInfo) async throws -> PointRect
}
