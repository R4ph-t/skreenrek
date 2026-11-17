import Foundation
import SkreenrekCore

/// Connects a client (the CLI or the MCP server) to the running app, launching it hidden when it isn't running and
/// the executable is inside `Skreenrek.app`. Clients never capture or resize themselves: everything goes through the
/// connection this returns.
public struct ControlConnector: Sendable {
    /// How long a launched app has to answer `hello`.
    public static let launchTimeout: TimeInterval = 10
    /// How often the socket is tried again while a launched app starts.
    static let retryInterval: TimeInterval = 0.05

    static let notRunningMessage = "Skreenrek isn't running."
    static let notRunningHint = "Open Skreenrek.app, or run: skreenrek app"

    public var socketPath: URL
    /// The running executable's path, as exec'd (symlinks are resolved here).
    public var executablePath: String
    public var launcher: any AppLauncher
    /// Times the wait for a launched app; nothing else.
    public var clock: any HostClock
    public var launchTimeout: TimeInterval
    /// Resolves `executablePath` to the bundle to launch.
    public var locator: AppBundleLocator
    /// Opens the socket. Real: `ControlClient.connect`; tests throw `ControlClientError.connectFailed(path:errno:)`
    /// to stand in for a sandbox's `EPERM`/`EACCES`.
    public var dial: Dial

    public typealias Dial = @Sendable (_ path: URL, _ client: ClientInfo) async throws -> ControlClient

    public static let socketDial: Dial = { path, client in try await ControlClient.connect(path: path, client: client) }

    public init(
        socketPath: URL, executablePath: String, launcher: any AppLauncher, clock: any HostClock,
        launchTimeout: TimeInterval = ControlConnector.launchTimeout, locator: AppBundleLocator = .live,
        dial: @escaping Dial = ControlConnector.socketDial
    ) {
        self.socketPath = socketPath
        self.executablePath = executablePath
        self.launcher = launcher
        self.clock = clock
        self.launchTimeout = launchTimeout
        self.locator = locator
        self.dial = dial
    }

    /// A connection for `client` that has answered `hello` with this protocol version. Fails with
    /// `ControlConnectError`. A sandboxed process (connecting refused with `EPERM`/`EACCES`) never launches the
    /// app: the launch would be blocked too, and macOS would call the app damaged.
    public func connect(as client: ClientInfo) async throws -> ControlClient {
        do {
            return try await attempt(client)
        } catch ControlClientError.notRunning {}
        let resolved = locator.resolve(executablePath)
        guard let bundle = AppBundleLocator.enclosingBundle(ofResolved: resolved) else {
            throw ControlConnectError(body: Self.notInBundleBody(executablePath: executablePath, resolved: resolved))
        }
        do {
            try await launcher.launchHidden(appAt: bundle)
        } catch {
            throw ControlConnectError(body: Self.launchFailedBody(bundle: bundle, error: error))
        }
        let deadline = clock.now() + launchTimeout
        while true {
            do {
                return try await attempt(client)
            } catch ControlClientError.notRunning {}
            let now = clock.now()
            guard now < deadline else {
                let seconds = Int(launchTimeout.rounded())
                throw ControlConnectError(body: ErrorBody(
                    code: "internal", message: "Skreenrek didn't start within \(seconds) seconds.",
                    hint: "Open Skreenrek.app, then run: skreenrek doctor", exit: 1))
            }
            try await clock.sleep(until: min(deadline, now + Self.retryInterval))
        }
    }

    private func attempt(_ client: ClientInfo) async throws -> ControlClient {
        let connection: ControlClient
        do {
            connection = try await dial(socketPath, client)
        } catch let error as ControlClientError {
            if case .sandboxed = error { throw ControlConnectError(body: error.body) }
            throw error
        }
        let hello = try await connection.call(.hello, as: HelloBody.self)
        guard hello.protocol == ControlProtocol.version else {
            connection.close()
            throw ControlConnectError(body: ErrorBody(
                code: "internal",
                message: "This command speaks control protocol \(ControlProtocol.version), but the running Skreenrek "
                    + "app speaks \(hello.protocol).",
                hint: ControlProtocol.mismatchHint, exit: 1))
        }
        return connection
    }

    /// The `.app` bundle this executable lives in, through symlinks (`~/.local/bin/skreenrek` →
    /// `…/Skreenrek.app/Contents/MacOS/skreenrek`); nil outside a bundle.
    public static func appBundle(executablePath: String) -> URL? {
        AppBundleLocator.live.appBundle(executablePath: executablePath)
    }

    /// The app isn't running and this executable has no bundle to open: names the path that was tried.
    static func notInBundleBody(executablePath: String, resolved: String) -> ErrorBody {
        let tried = resolved == executablePath ? resolved : "\(executablePath) (resolved to \(resolved))"
        return ErrorBody(
            code: "internal",
            message: "Skreenrek isn't running, and \(tried) isn't inside an app bundle, so it can't be opened.",
            hint: notRunningHint, exit: 1)
    }

    /// macOS refused to open `bundle`: names the bundle and the macOS error (description, domain and code).
    static func launchFailedBody(bundle: URL, error: any Error) -> ErrorBody {
        let ns = error as NSError
        return ErrorBody(
            code: "internal",
            message: "Skreenrek couldn't be opened at \(bundle.path): \(ns.localizedDescription) "
                + "(\(ns.domain) error \(ns.code))",
            hint: "Reinstall Skreenrek, or open \(bundle.path) by hand, then run: skreenrek doctor", exit: 1)
    }
}

/// The app couldn't be reached or launched: the design spec's `{code, message, hint, exit}`.
public struct ControlConnectError: Error, Hashable {
    public var body: ErrorBody

    public init(body: ErrorBody) {
        self.body = body
    }
}

extension ControlClientError {
    /// How a client reports a call the app didn't answer.
    public var body: ErrorBody {
        switch self {
        case .notRunning:
            return ErrorBody(
                code: "internal", message: ControlConnector.notRunningMessage, hint: ControlConnector.notRunningHint,
                exit: 1)
        case .sandboxed:
            // Exit 1, like every other way of not reaching the app; the `sandboxed` code tells agents why.
            return ErrorBody(
                code: "sandboxed", message: "Skreenrek can't reach its app from this shell.",
                hint: "This shell is sandboxed. Use the Skreenrek MCP tools, or allow network access for this "
                    + "command.", exit: 1)
        case .connectionClosed:
            return ErrorBody(
                code: "internal", message: "Skreenrek closed the connection before answering.",
                hint: "Run: skreenrek doctor", exit: 1)
        case .timedOut, .badResponse:
            return ErrorBody(code: "internal", message: description, hint: "Run: skreenrek doctor", exit: 1)
        }
    }
}
