import Foundation

/// A `MAJOR.MINOR.PATCH` version with an optional pre-release suffix, compared the semver way: numerically per field
/// (`1.0.10` is newer than `1.0.9`), and a pre-release (`1.1.0-beta.1`) older than its release.
public struct SemanticVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var patch: Int
    /// The part after `-`, without build metadata (`+…` is ignored, as semver says).
    public var prerelease: String?

    public init(major: Int, minor: Int, patch: Int, prerelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    /// Parses `1.0.2`, `v1.0.2` or `V1.0.2`, `1.1.0-beta.1`. Missing minor or patch read as 0 (`v2` is `2.0.0`).
    public init?(_ text: String) {
        var rest = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if rest.first == "v" || rest.first == "V" { rest = rest.dropFirst() }
        if let plus = rest.firstIndex(of: "+") { rest = rest[..<plus] }
        var prerelease: String?
        if let dash = rest.firstIndex(of: "-") {
            prerelease = String(rest[rest.index(after: dash)...])
            rest = rest[..<dash]
            if prerelease?.isEmpty == true { return nil }
        }
        let parts = rest.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber), let value = Int(part)
            else { return nil }
            numbers.append(value)
        }
        while numbers.count < 3 { numbers.append(0) }
        self.init(major: numbers[0], minor: numbers[1], patch: numbers[2], prerelease: prerelease)
    }

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.map { "\(core)-\($0)" } ?? core
    }

    public static func < (a: SemanticVersion, b: SemanticVersion) -> Bool {
        if a.major != b.major { return a.major < b.major }
        if a.minor != b.minor { return a.minor < b.minor }
        if a.patch != b.patch { return a.patch < b.patch }
        switch (a.prerelease, b.prerelease) {
        case (nil, nil), (nil, _?): return false
        case (_?, nil): return true
        case (let x?, let y?): return prereleaseLess(x, y)
        }
    }

    /// Dot-separated identifiers: numeric ones compare as numbers and sort before alphanumeric ones; a shorter list
    /// that is a prefix of the other is older.
    private static func prereleaseLess(_ a: String, _ b: String) -> Bool {
        let x = a.split(separator: ".")
        let y = b.split(separator: ".")
        for (p, q) in zip(x, y) where p != q {
            switch (Int(p), Int(q)) {
            case (let m?, let n?): return m < n
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return p < q
            }
        }
        return x.count < y.count
    }
}

/// The newest published release: its version, the page to download it from, and the notes (the release body).
public struct ReleaseInfo: Sendable, Hashable {
    public var version: SemanticVersion
    public var pageURL: URL
    /// GitHub's `body`. Empty when the release has no notes.
    public var notes: String

    public init(version: SemanticVersion, pageURL: URL, notes: String = "") {
        self.version = version
        self.pageURL = pageURL
        self.notes = notes
    }
}

/// Where Skreenrek learns about its newest release. The app passes `GitHubReleaseFeed`; tests pass a fake, so no test
/// touches the network.
public protocol ReleaseFeed: Sendable {
    func latestRelease() async throws -> ReleaseInfo
}

/// The GitHub `releases/latest` endpoint and its JSON.
public enum GitHubReleases {
    public static let latestURL = URL(string: "https://api.github.com/repos/R4ph-t/skreenrek/releases/latest")!
    public static let releasesPage = URL(string: "https://github.com/R4ph-t/skreenrek/releases/latest")!

    public enum ParseError: Error, Equatable {
        case notJSON
        case badTag(String)
    }

    /// Reads `tag_name` (`v1.0.3`), `html_url` and `body` from the endpoint's body. A missing `html_url` falls back to
    /// the releases page. A missing or null `body` is empty notes.
    public static func parse(_ data: Data) throws -> ReleaseInfo {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.notJSON
        }
        let tag = object["tag_name"] as? String ?? ""
        guard let version = SemanticVersion(tag) else { throw ParseError.badTag(tag) }
        let page = (object["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPage
        let notes = object["body"] as? String ?? ""
        return ReleaseInfo(version: version, pageURL: page, notes: notes)
    }
}

/// How the Update button installs a newer release.
public enum UpdateMethod: Sendable, Hashable {
    /// `brew upgrade --cask r4ph-t/skreenrek/skreenrek`, in the background.
    case homebrew
    /// Opens the release page in the browser.
    case releasePage

    public static let brewPath = "/opt/homebrew/bin/brew"
    public static let caskArguments = ["upgrade", "--cask", "r4ph-t/skreenrek/skreenrek"]

    /// Homebrew only when the app runs from `/Applications` (where the cask installs it) and Homebrew is at its Apple
    /// silicon path. Anything else (a dev build, a copy elsewhere) opens the release page.
    public static func decide(bundlePath: String, brewExists: Bool) -> UpdateMethod {
        let path = (bundlePath as NSString).standardizingPath
        guard brewExists, path.hasPrefix("/Applications/"), path.hasSuffix(".app") else { return .releasePage }
        return .homebrew
    }
}

/// Runs the Homebrew upgrade. The app passes `HomebrewUpgrader`; tests pass a fake.
public protocol UpdateInstaller: Sendable {
    /// Runs the upgrade to the end, handing each output line to `progress`. Throws when it fails.
    func upgrade(progress: @escaping @Sendable (String) -> Void) async throws
}

/// The 24 h throttle for automatic checks. The Check for Updates button ignores it.
public enum UpdateSchedule {
    public static let interval: TimeInterval = 24 * 60 * 60

    /// Due when there was never a check, the last one is 24 h old, or the clock went backwards.
    public static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        let age = now.timeIntervalSince(lastCheck)
        return age >= interval || age < 0
    }
}
