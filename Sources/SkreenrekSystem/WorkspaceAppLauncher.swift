import AppKit
import SkreenrekCore

/// Opens the app bundle with `NSWorkspace`, hidden and without activating it.
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
