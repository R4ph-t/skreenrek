import Foundation

/// A throwaway `UserDefaults` for tests and offscreen renders that leaves nothing in `~/Library/Preferences`.
///
/// A suite named like `skreenrek.tests.<uuid>` always leaves an empty `<name>.plist` there: removing the persistent
/// domain only empties it, and cfprefsd rewrites the file even after it is deleted. A suite whose name is an absolute
/// path is stored at that path instead, so this one lives in a fresh temporary directory, and `remove()` drops the
/// domain and deletes the directory.
///
/// Use `withScratchDefaults` where the work fits in a closure, or `ScratchDefaults()` with `defer { remove() }`.
/// Never `UserDefaults(suiteName:)` with a made-up name: a source scan in the tests enforces it.
public final class ScratchDefaults {
    /// The temporary directory that holds the suite's plist.
    public let directory: URL
    /// The suite name: an absolute path inside `directory`. Pass it wherever an API wants the domain name.
    public let suiteName: String
    public let defaults: UserDefaults

    public init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("skreenrek-scratch-defaults-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = directory.appendingPathComponent("defaults").path
        // Only `NSGlobalDomain` and the app's own bundle ID make this nil, and a fresh path is neither.
        defaults = UserDefaults(suiteName: suiteName)!
    }

    /// Empties the domain and deletes the temporary directory. Safe to call more than once.
    public func remove() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Runs `body` with a scratch `UserDefaults`, then removes it.
public func withScratchDefaults<T>(_ body: (UserDefaults) throws -> T) rethrows -> T {
    let scratch = ScratchDefaults()
    defer { scratch.remove() }
    return try body(scratch.defaults)
}

/// Runs `body` with a scratch `UserDefaults`, then removes it.
public func withScratchDefaults<T>(
    isolation: isolated (any Actor)? = #isolation, _ body: (UserDefaults) async throws -> T
) async rethrows -> T {
    let scratch = ScratchDefaults()
    defer { scratch.remove() }
    return try await body(scratch.defaults)
}
