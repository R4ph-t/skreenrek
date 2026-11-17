import Darwin
import Foundation
import SkreenrekCore

/// Where the control socket lives.
public enum ControlPaths {
    /// Overrides the socket path (tests and development only).
    public static let environmentKey = "SKREENREK_SOCKET"
    public static let socketName = "control.sock"

    /// `~/Library/Application Support/skreenrek/`.
    public static func supportFolder(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("skreenrek", isDirectory: true)
    }

    /// `SKREENREK_SOCKET` when set, else `~/Library/Application Support/skreenrek/control.sock`.
    public static func socketURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let override = environment[environmentKey], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return supportFolder(home: home).appendingPathComponent(socketName)
    }
}

/// A controller plus its control server, built from injected seams. The app runs it with the real seams (and the UI
/// on top from 08); tests run it with the fakes over a real socket.
public final class HeadlessHost: Sendable {
    public let controller: SkreenrekController
    public let server: ControlServer
    public let socketPath: URL

    public init(
        seams: ControllerSeams, settings: ControllerSettings = ControllerSettings(),
        socketPath: URL = ControlPaths.socketURL(), allowedUID: uid_t = geteuid()
    ) {
        let controller = SkreenrekController(seams: seams, settings: settings, socketPath: socketPath.path)
        let router = ControlRouter(controller: controller, hello: HelloBody(pid: getpid()))
        self.controller = controller
        self.socketPath = socketPath
        self.server = ControlServer(path: socketPath, allowedUID: allowedUID) { line in
            await router.respond(to: line)
        }
    }

    /// Starts serving. Throws `ControlServer.StartError.alreadyRunning` when another instance answers.
    public func start() throws {
        try server.start()
    }

    public func stop() {
        server.stop()
    }
}
