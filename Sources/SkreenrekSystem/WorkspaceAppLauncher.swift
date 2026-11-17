import AppKit
import SkreenrekCore

/// Opens the app bundle at the given URL with `NSWorkspace`, hidden and without activating it. Always by URL, never
/// by bundle ID, so LaunchServices can't pick another registered copy.
public struct WorkspaceAppLauncher: AppLauncher {
    public init() {}

    public func launchHidden(appAt bundle: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        configuration.addsToRecentItems = false
        _ = try await NSWorkspace.shared.openApplication(at: bundle, configuration: configuration)
    }
}
