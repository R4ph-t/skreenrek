import Foundation
import Observation
import Sparkle

/// What the dropdown and Settings need from the updater. The app passes `SparkleUpdater`; tests and `render-ui` pass a
/// stand-in, so nothing outside the app starts Sparkle.
@MainActor
public protocol AppUpdater: AnyObject {
    /// False while Sparkle is already checking, downloading or showing its window.
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    func checkForUpdates()
}

/// Sparkle 2's standard updater: it finds, downloads, verifies (EdDSA and the Developer ID signature), installs and
/// relaunches, and shows the release notes in its own window. Built only by `MenuBarAppDelegate`, and only when the
/// bundle carries a feed and a public key (`isConfigured`). Ad-hoc bundles, `.build` runs and the CLI never start it.
@MainActor
@Observable
public final class SparkleUpdater: AppUpdater {
    public private(set) var canCheckForUpdates = false

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?

    /// Starts Sparkle when `info` (normally `Bundle.main.infoDictionary`) is configured, otherwise returns nil.
    public init?(info: [String: Any]? = Bundle.main.infoDictionary) {
        guard Self.isConfigured(info) else { return nil }
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        canCheckForUpdates = controller.updater.canCheckForUpdates
        // SPUUpdater lives on the main thread, so its KVO changes arrive there.
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    public var automaticallyChecksForUpdates: Bool {
        get {
            access(keyPath: \.automaticallyChecksForUpdates)
            return controller.updater.automaticallyChecksForUpdates
        }
        set {
            withMutation(keyPath: \.automaticallyChecksForUpdates) {
                controller.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    public func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Sparkle runs only with a non-empty `SUFeedURL` and `SUPublicEDKey`. `make release` ships both; the ad-hoc
    /// bundle (`make app`, the source formula) has them removed, so a dev build never updates into a release.
    public nonisolated static func isConfigured(_ info: [String: Any]?) -> Bool {
        func value(_ key: String) -> String {
            (info?[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        return !value("SUFeedURL").isEmpty && !value("SUPublicEDKey").isEmpty
    }
}
