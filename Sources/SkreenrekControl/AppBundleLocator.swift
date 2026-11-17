import Foundation

/// Finds the `.app` bundle a client executable lives in, so a launch opens exactly that copy by URL. Never by bundle
/// ID: LaunchServices can have several Skreenrek.app copies registered (build folders, a deleted Cellar copy, /tmp)
/// and would pick any of them.
///
/// Pure: symlinks are read through `readLink`, and relative paths are taken from `currentDirectory`.
public struct AppBundleLocator: Sendable {
    /// The target of the symlink at an absolute path, as stored (relative or absolute); nil when it isn't a symlink.
    public var readLink: @Sendable (String) -> String?
    /// Where a relative executable path starts.
    public var currentDirectory: String

    /// More symlink hops than this means a loop.
    static let maxSymlinkHops = 40

    public init(readLink: @escaping @Sendable (String) -> String?, currentDirectory: String) {
        self.readLink = readLink
        self.currentDirectory = currentDirectory
    }

    /// The real file system.
    public static var live: AppBundleLocator {
        AppBundleLocator(
            readLink: { try? FileManager.default.destinationOfSymbolicLink(atPath: $0) },
            currentDirectory: FileManager.default.currentDirectoryPath)
    }

    /// `path` made absolute with every symlink in it followed (in any component, relative or absolute targets), and
    /// `.`/`..` applied. A symlink loop stops resolving where it was.
    public func resolve(_ path: String) -> String {
        let absolute = path.hasPrefix("/") ? path : currentDirectory + "/" + path
        var pending = Self.components(absolute)
        var resolved: [String] = []
        var hops = 0
        while !pending.isEmpty {
            let component = pending.removeFirst()
            if component == "." { continue }
            if component == ".." {
                _ = resolved.popLast()
                continue
            }
            let candidate = "/" + (resolved + [component]).joined(separator: "/")
            guard hops < Self.maxSymlinkHops, let target = readLink(candidate) else {
                resolved.append(component)
                continue
            }
            hops += 1
            if target.hasPrefix("/") { resolved = [] }
            pending = Self.components(target) + pending
        }
        return "/" + resolved.joined(separator: "/")
    }

    /// The bundle enclosing `executablePath` after resolving it (`…/X.app/Contents/MacOS/<executable>` → `…/X.app`),
    /// or nil outside one.
    public func appBundle(executablePath: String) -> URL? {
        Self.enclosingBundle(ofResolved: resolve(executablePath))
    }

    /// The `.app` for an already resolved executable path, or nil.
    static func enclosingBundle(ofResolved path: String) -> URL? {
        let parts = components(path)
        guard parts.count >= 4,
            parts[parts.count - 2] == "MacOS",
            parts[parts.count - 3] == "Contents"
        else { return nil }
        let app = parts[parts.count - 4]
        guard app.count > 4, app.lowercased().hasSuffix(".app") else { return nil }
        return URL(fileURLWithPath: "/" + parts[..<(parts.count - 3)].joined(separator: "/"), isDirectory: true)
    }

    private static func components(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }
}
