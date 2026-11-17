import Foundation
import SkreenrekControl
import SkreenrekCore

/// Connects the CLI to the running app through `ControlConnector`, launching it hidden when it isn't running and this
/// executable is inside `Skreenrek.app`. The CLI never captures or resizes itself: everything goes through this
/// connection.
public struct AppConnector: Sendable {
    /// How long a launched app has to answer `hello`.
    public static let launchTimeout = ControlConnector.launchTimeout

    let environment: CLIEnvironment
    let client = ClientInfo(kind: .cli)

    /// A connection that has answered `hello` with this protocol version.
    func connect() async throws -> ControlClient {
        do {
            return try await environment.connector.connect(as: client)
        } catch let error as ControlConnectError {
            throw CLIError(body: error.body)
        }
    }

    /// The `Skreenrek.app` bundle this executable lives in, through symlinks; nil outside a bundle.
    public static func appBundle(executablePath: String) -> URL? {
        ControlConnector.appBundle(executablePath: executablePath)
    }
}

extension CLIEnvironment {
    /// The app connection this environment describes.
    public var connector: ControlConnector {
        ControlConnector(
            socketPath: socketPath, executablePath: executablePath, launcher: launcher, clock: clock,
            launchTimeout: launchTimeout)
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
        case let error as ControlConnectError:
            return error.body
        case let error as ControlClientError:
            return error.body
        default:
            return SkreenrekError.internal(message: "Something went wrong: \(error.localizedDescription)").body
        }
    }
}
