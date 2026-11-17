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

    public init(
        socketPath: URL, executablePath: String, launcher: any AppLauncher, clock: any HostClock,
        launchTimeout: TimeInterval = ControlConnector.launchTimeout
    ) {
        self.socketPath = socketPath
        self.executablePath = executablePath
        self.launcher = launcher
        self.clock = clock
        self.launchTimeout = launchTimeout
    }

    /// A connection for `client` that has answered `hello` with this protocol version. Fails with
    /// `ControlConnectError`.
    public func connect(as client: ClientInfo) async throws -> ControlClient {
        do {
            return try await attempt(client)
        } catch ControlClientError.notRunning {}
        guard let bundle = Self.appBundle(executablePath: executablePath) else {
            throw ControlConnectError(body: ErrorBody(
                code: "internal", message: Self.notRunningMessage, hint: Self.notRunningHint, exit: 1))
        }
        do {
            try await launcher.launchHidden(appAt: bundle)
        } catch {
            throw ControlConnectError(body: ErrorBody(
                code: "internal", message: "Skreenrek couldn't be opened: \(error.localizedDescription)",
                hint: Self.notRunningHint, exit: 1))
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
        let connection = try await ControlClient.connect(path: socketPath, client: client)
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

    /// The `Skreenrek.app` bundle this executable lives in, through symlinks (`~/.local/bin/skreenrek` →
    /// `…/Skreenrek.app/Contents/MacOS/skreenrek`); nil outside a bundle.
    public static func appBundle(executablePath: String) -> URL? {
        let resolved = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath()
        let components = resolved.pathComponents
        guard components.count >= 4,
            components[components.count - 1] == "skreenrek",
            components[components.count - 2] == "MacOS",
            components[components.count - 3] == "Contents",
            components[components.count - 4] == "Skreenrek.app"
        else { return nil }
        return resolved.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
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
        case .connectionClosed:
            return ErrorBody(
                code: "internal", message: "Skreenrek closed the connection before answering.",
                hint: "Run: skreenrek doctor", exit: 1)
        case .timedOut, .badResponse:
            return ErrorBody(code: "internal", message: description, hint: "Run: skreenrek doctor", exit: 1)
        }
    }
}
