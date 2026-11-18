import Foundation
import Observation
import SkreenrekCore

/// Where the update check stands.
public enum UpdateState: Sendable, Hashable {
    /// Never checked on this Mac.
    case idle
    case checking
    case upToDate(current: SemanticVersion)
    case available(ReleaseInfo)
    /// The check failed. Quiet: Settings shows a Retry button, the dropdown shows nothing.
    case failed
    /// Homebrew is upgrading; `line` is its latest output line.
    case installing(ReleaseInfo, line: String?)
    /// Homebrew finished: offer Relaunch.
    case installed(ReleaseInfo)
    /// Homebrew failed: offer the release page.
    case installFailed(ReleaseInfo)
}

/// Checks GitHub for a newer release on launch and at most once every 24 h (plus Check for Updates), and installs it
/// with Homebrew when the app came from the cask. The network call and the upgrade are seams, so tests drive every
/// state with fakes and a fixed clock.
@MainActor
@Observable
public final class UpdateChecker {
    public enum Key {
        public static let lastCheck = "updates.lastCheck"
        public static let latestVersion = "updates.latestVersion"
        public static let latestPage = "updates.latestPage"
        public static let latestNotes = "updates.latestNotes"
    }

    public private(set) var state: UpdateState
    public let current: SemanticVersion
    public let method: UpdateMethod

    /// Called after every state change (the dropdown's footer line follows it).
    @ObservationIgnored public var onChange: (() -> Void)?
    @ObservationIgnored private let feed: any ReleaseFeed
    @ObservationIgnored private let installer: (any UpdateInstaller)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let openURL: (URL) -> Void
    @ObservationIgnored private let relaunchApp: () -> Void

    public init(
        current: String = SkreenrekVersion.current, feed: any ReleaseFeed, installer: (any UpdateInstaller)?,
        method: UpdateMethod, defaults: UserDefaults, now: @escaping () -> Date = Date.init,
        openURL: @escaping (URL) -> Void, relaunch: @escaping () -> Void
    ) {
        let current = SemanticVersion(current) ?? SemanticVersion(major: 0, minor: 0, patch: 0)
        self.current = current
        self.feed = feed
        self.installer = installer
        self.method = installer == nil ? .releasePage : method
        self.defaults = defaults
        self.now = now
        self.openURL = openURL
        self.relaunchApp = relaunch
        state = Self.remembered(defaults: defaults, current: current)
    }

    /// The last check's answer, so an update found yesterday still shows after a relaunch inside the 24 h.
    private static func remembered(defaults: UserDefaults, current: SemanticVersion) -> UpdateState {
        guard let text = defaults.string(forKey: Key.latestVersion), let latest = SemanticVersion(text) else {
            return .idle
        }
        guard latest > current else { return .upToDate(current: current) }
        let page = defaults.string(forKey: Key.latestPage).flatMap(URL.init(string:)) ?? GitHubReleases.releasesPage
        let notes = defaults.string(forKey: Key.latestNotes) ?? ""
        return .available(ReleaseInfo(version: latest, pageURL: page, notes: notes))
    }

    public var lastCheck: Date? {
        let seconds = defaults.double(forKey: Key.lastCheck)
        return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
    }

    /// The newer version, while one is waiting to be installed (the dropdown's footer line).
    public var availableVersion: SemanticVersion? {
        if case .available(let info) = state { return info.version }
        return nil
    }

    /// True while Homebrew runs, so the app doesn't quit under it.
    public var isInstalling: Bool {
        if case .installing = state { return true }
        return false
    }

    // MARK: - Checking

    /// On launch and from the app's hourly timer: checks only when the last check is 24 h old.
    public func checkIfDue() async {
        guard UpdateSchedule.isDue(lastCheck: lastCheck, now: now()) else { return }
        await check()
    }

    /// Check for Updates and Retry: checks now, whatever the throttle says.
    public func checkNow() async {
        await check()
    }

    private func check() async {
        switch state {
        case .checking, .installing, .installed: return
        default: break
        }
        let previous = state
        set(.checking)
        defaults.set(now().timeIntervalSince1970, forKey: Key.lastCheck)
        do {
            let release = try await feed.latestRelease()
            defaults.set(release.version.description, forKey: Key.latestVersion)
            defaults.set(release.pageURL.absoluteString, forKey: Key.latestPage)
            defaults.set(release.notes, forKey: Key.latestNotes)
            set(release.version > current ? .available(release) : .upToDate(current: current))
        } catch {
            // A known update stays on screen; otherwise the row says the check failed.
            if case .available = previous { set(previous) } else { set(.failed) }
        }
    }

    // MARK: - Installing

    /// The Update button: Homebrew in the background when the app came from the cask, otherwise the release page.
    public func update() async {
        let release: ReleaseInfo
        switch state {
        case .available(let info), .installFailed(let info): release = info
        default: return
        }
        guard method == .homebrew, let installer, !isInstallFailed else {
            openURL(release.pageURL)
            return
        }
        set(.installing(release, line: nil))
        do {
            try await installer.upgrade { [weak self] line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                Task { @MainActor in self?.progress(trimmed, release: release) }
            }
            set(.installed(release))
        } catch {
            set(.installFailed(release))
        }
    }

    private var isInstallFailed: Bool {
        if case .installFailed = state { return true }
        return false
    }

    private func progress(_ line: String, release: ReleaseInfo) {
        guard case .installing = state else { return }
        set(.installing(release, line: line))
    }

    public func relaunch() {
        guard case .installed = state else { return }
        relaunchApp()
    }

    /// The Settings row's button.
    public func perform(_ action: UpdateRowModel.Action) async {
        switch action {
        case .check: await checkNow()
        case .update: await update()
        case .relaunch: relaunch()
        case .openReleasePage:
            switch state {
            case .available(let info), .installFailed(let info), .installing(let info, _), .installed(let info):
                openURL(info.pageURL)
            default:
                openURL(GitHubReleases.releasesPage)
            }
        }
    }

    private func set(_ new: UpdateState) {
        guard new != state else { return }
        state = new
        onChange?()
    }
}

/// What the Settings Updates row shows for a state. Pure, so tests cover it.
public struct UpdateRowModel: Sendable, Hashable {
    public enum Action: Sendable, Hashable {
        case check
        case update
        case relaunch
        case openReleasePage
    }

    public struct Button: Sendable, Hashable {
        public var title: String
        public var action: Action
        /// The Update and Relaunch buttons are the row's default (accent) button.
        public var prominent: Bool
        public var enabled: Bool
    }

    public var detail: String
    public var button: Button
    /// A small spinner before the button (checking, installing).
    public var busy: Bool
    /// The detail is the quiet failure line.
    public var quiet: Bool
    /// Release notes for the What's new disclosure. Set only while an update is available and the notes aren't blank.
    public var notes: String?

    public init(state: UpdateState, current: SemanticVersion, method: UpdateMethod) {
        let check = Button(title: UIStrings.Updates.checkForUpdates, action: .check, prominent: false, enabled: true)
        busy = false
        quiet = false
        notes = nil
        switch state {
        case .idle:
            detail = UIStrings.Updates.currentVersion(current.description)
            button = check
        case .checking:
            detail = UIStrings.Updates.checking
            button = Button(title: check.title, action: .check, prominent: false, enabled: false)
            busy = true
        case .upToDate(let version):
            detail = UIStrings.Updates.upToDate(version.description)
            button = check
        case .available(let info):
            detail = UIStrings.Updates.available(info.version.description, current: current.description)
            notes = Self.visibleNotes(info.notes)
            button = Button(
                title: method == .homebrew ? UIStrings.Updates.update : UIStrings.Updates.download, action: .update,
                prominent: true, enabled: true)
        case .failed:
            detail = UIStrings.Updates.failed
            button = Button(title: UIStrings.Updates.retry, action: .check, prominent: false, enabled: true)
            quiet = true
        case .installing(_, let line):
            detail = line ?? UIStrings.Updates.installing
            button = Button(title: UIStrings.Updates.update, action: .update, prominent: true, enabled: false)
            busy = true
        case .installed(let info):
            detail = UIStrings.Updates.installed(info.version.description)
            button = Button(title: UIStrings.Updates.relaunch, action: .relaunch, prominent: true, enabled: true)
        case .installFailed:
            detail = UIStrings.Updates.installFailed
            button = Button(
                title: UIStrings.Updates.openReleasePage, action: .openReleasePage, prominent: false, enabled: true)
            quiet = true
        }
    }

    /// Blank notes stay hidden. Anything else is the markdown the disclosure shows, without surrounding whitespace.
    private static func visibleNotes(_ notes: String) -> String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
