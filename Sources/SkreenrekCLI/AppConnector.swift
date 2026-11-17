import Foundation
import SkreenrekControl
import SkreenrekCore

/// Connects to the running app, launching it hidden when it isn't running and this executable is inside
/// `Skreenrek.app`. The CLI never captures or resizes itself: everything goes through this connection.
public struct AppConnector: Sendable {
    /// How long a launched app has to answer `hello`.
    public static let launchTimeout: TimeInterval = 10
    /// How often the socket is tried again while a launched app starts.
    static let retryInterval: TimeInterval = 0.05

    static let notRunning = SkreenrekError.internal(message: "Skreenrek isn't running.")
    static let notRunningHint = "Open Skreenrek.app, or run: skreenrek app"

    let environment: CLIEnvironment
    let client = ClientInfo(kind: .cli)

    /// A connection that has answered `hello` with this protocol version.
    func connect() async throws -> ControlClient {
        do {
            return try await attempt()
        } catch ControlClientError.notRunning {}
        guard let bundle = Self.appBundle(executablePath: environment.executablePath) else {
            throw CLIError(body: ErrorBody(
                code: Self.notRunning.code, message: Self.notRunning.message, hint: Self.notRunningHint, exit: 1))
        }
        do {
            try await environment.launcher.launchHidden(appAt: bundle)
        } catch {
            throw CLIError(body: ErrorBody(
                code: "internal", message: "Skreenrek couldn't be opened: \(error.localizedDescription)",
                hint: Self.notRunningHint, exit: 1))
        }
        let clock = environment.clock
        let deadline = clock.now() + environment.launchTimeout
        while true {
            do {
                return try await attempt()
            } catch ControlClientError.notRunning {}
            let now = clock.now()
            guard now < deadline else {
                let seconds = Int(environment.launchTimeout.rounded())
                throw CLIError(body: ErrorBody(
                    code: "internal", message: "Skreenrek didn't start within \(seconds) seconds.",
                    hint: "Open Skreenrek.app, then run: skreenrek doctor", exit: 1))
            }
            try await clock.sleep(until: min(deadline, now + Self.retryInterval))
        }
    }

    private func attempt() async throws -> ControlClient {
        let connection = try await ControlClient.connect(path: environment.socketPath, client: client)
        let hello = try await connection.call(.hello, as: HelloBody.self)
        guard hello.protocol == ControlProtocol.version else {
            throw CLIError(body: ErrorBody(
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

/// A failure the CLI reports: the design spec's `{code, message, hint, exit}`.
struct CLIError: Error {
    var body: ErrorBody

    init(body: ErrorBody) {
        self.body = body
    }

    /// Any error as the body to print.
    static func body(for error: any Error) -> ErrorBody {
        switch error {
        case let error as CLIError:
            return error.body
        case let error as SkreenrekError:
            return error.body
        case let error as ControlRemoteError:
            return error.body
        case let error as ControlClientError:
            switch error {
            case .notRunning:
                return ErrorBody(
                    code: "internal", message: AppConnector.notRunning.message, hint: AppConnector.notRunningHint,
                    exit: 1)
            case .connectionClosed:
                return ErrorBody(
                    code: "internal", message: "Skreenrek closed the connection before answering.",
                    hint: "Run: skreenrek doctor", exit: 1)
            case .timedOut, .badResponse:
                return ErrorBody(
                    code: "internal", message: error.description, hint: "Run: skreenrek doctor", exit: 1)
            }
        default:
            return SkreenrekError.internal(message: "Something went wrong: \(error.localizedDescription)").body
        }
    }
}
