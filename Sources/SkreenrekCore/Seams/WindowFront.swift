/// Brings a picked window to the front. Real: `SystemWindowFront`. Tests: `FakeWindowFront`.
public protocol WindowFront: Sendable {
    /// Activates the window's app, and raises that window when Accessibility is allowed. Best effort: a failure
    /// must not fail the pick.
    func bringToFront(_ window: WindowInfo) async
}

/// The default until the app wires the real one: a pick leaves the window where it is.
public struct NoOpWindowFront: WindowFront {
    public init() {}

    public func bringToFront(_ window: WindowInfo) async {}
}
