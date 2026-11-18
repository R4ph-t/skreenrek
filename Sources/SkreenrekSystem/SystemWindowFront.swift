import AppKit
import ApplicationServices
import SkreenrekCore

/// Activates the picked window's app and, when Accessibility is allowed, raises that window.
public final class SystemWindowFront: WindowFront, Sendable {
    private let resizer: AXWindowResizer

    public init(resizer: AXWindowResizer) {
        self.resizer = resizer
    }

    public func bringToFront(_ window: WindowInfo) async {
        await MainActor.run {
            _ = NSRunningApplication(processIdentifier: window.pid)?.activate()
        }
        try? await resizer.raise(window)
    }
}
