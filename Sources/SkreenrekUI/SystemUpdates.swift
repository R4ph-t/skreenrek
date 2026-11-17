import Foundation
import SkreenrekCore

/// The real `ReleaseFeed`: one unauthenticated GET of GitHub's `releases/latest` for the public repository. Thin: the
/// parsing and the comparison live in `GitHubReleases` and `UpdateChecker`.
public struct GitHubReleaseFeed: ReleaseFeed {
    public struct HTTPError: Error {
        public var status: Int
    }

    public init() {}

    public func latestRelease() async throws -> ReleaseInfo {
        var request = URLRequest(url: GitHubReleases.latestURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Skreenrek/\(SkreenrekVersion.current)", forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw HTTPError(status: status) }
        return try GitHubReleases.parse(data)
    }
}

/// The real `UpdateInstaller`: runs `brew upgrade --cask r4ph-t/skreenrek/skreenrek` and streams its output lines.
public struct HomebrewUpgrader: UpdateInstaller {
    public struct Failed: Error {
        public var status: Int32
    }

    public init() {}

    /// Homebrew installs Skreenrek only when the app runs from `/Applications` and `brew` is at its usual path.
    public static func method(bundle: URL = Bundle.main.bundleURL) -> UpdateMethod {
        UpdateMethod.decide(
            bundlePath: bundle.path, brewExists: FileManager.default.isExecutableFile(atPath: UpdateMethod.brewPath))
    }

    public func upgrade(progress: @escaping @Sendable (String) -> Void) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: UpdateMethod.brewPath)
        process.arguments = UpdateMethod.caskArguments
        var environment = ProcessInfo.processInfo.environment
        // A menu-bar app starts with a minimal PATH; brew needs its own bin and the system tools.
        environment["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        environment["HOMEBREW_NO_COLOR"] = "1"
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let lines = LineSplitter(progress)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                lines.append(data)
            }
        }
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        guard status == 0 else { throw Failed(status: status) }
    }
}

/// Splits a byte stream into lines for the progress callback.
private final class LineSplitter: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let emit: @Sendable (String) -> Void

    init(_ emit: @escaping @Sendable (String) -> Void) {
        self.emit = emit
    }

    func append(_ data: Data) {
        let lines: [String] = lock.withLock {
            buffer.append(data)
            var out: [String] = []
            while let newline = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                out.append(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            return out
        }
        for line in lines { emit(line) }
    }
}
