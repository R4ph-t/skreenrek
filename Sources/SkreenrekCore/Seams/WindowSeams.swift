import Foundation

/// Lists windows and displays. Real implementation: ScreenCaptureKit (02).
public protocol WindowCatalog: Sendable {
    /// Windows, front to back.
    func windows() async throws -> [WindowInfo]
    func displays() async throws -> [DisplayInfo]
}

/// Moves and resizes a window, and reads its frame back. Real implementation: Accessibility (02).
public protocol WindowResizer: Sendable {
    func setFrame(_ frame: PointRect, of window: WindowInfo) async throws
    func readFrame(of window: WindowInfo) async throws -> PointRect
}
