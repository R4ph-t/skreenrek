import Foundation

/// Opens the Skreenrek app bundle hidden (menu bar only, no activation) when a CLI or MCP call finds it isn't
/// running. Real: `WorkspaceAppLauncher`. Fake: `FakeAppLauncher`.
public protocol AppLauncher: Sendable {
    /// Returns once the launch request is handed off; the app's socket may answer later.
    func launchHidden(appAt bundle: URL) async throws
}
