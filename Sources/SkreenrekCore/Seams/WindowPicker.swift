import Foundation

/// What a human picked in the picker overlay.
public enum PickResult: Sendable, Hashable {
    /// A window, by its ID. The controller resolves it against the window list.
    case window(WindowID)
    /// A dragged region in pixels on one display.
    case region(PixelRect, displayId: DisplayID)
    /// Esc, Cancel, or the timeout ran out.
    case cancelled
}

/// Opens the picker overlay for a human. Real: the overlay (10). Fake: `FakeWindowPicker`.
public protocol WindowPicker: Sendable {
    /// Returns once the human picks, cancels, or `timeout` seconds pass (then `.cancelled`).
    func pick(timeout: TimeInterval) async throws -> PickResult
}
