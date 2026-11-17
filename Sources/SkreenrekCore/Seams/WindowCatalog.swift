/// Lists windows and displays. Real: ScreenCaptureKit + AppKit (02). Fake: `FakeWindowCatalog`.
public protocol WindowCatalog: Sendable {
    /// All windows, front to back.
    func windows() async throws -> [WindowInfo]
    func displays() async throws -> [DisplayInfo]
}
