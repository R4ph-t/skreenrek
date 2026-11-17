import Darwin
import Foundation
import SkreenrekControl
import SkreenrekCore
import SkreenrekTesting
import Testing

/// A sandboxed shell (Codex's seatbelt without network access) gets `EPERM`/`EACCES` from `connect()` on the control
/// socket. That is reported as `sandboxed` and the app is never launched: the launch would be blocked too, and macOS
/// would call the app damaged.
@Suite struct SandboxedConnectTests {
    static let hint = "This shell is sandboxed. Use the Skreenrek MCP tools, or allow network access for this command."

    @Test(arguments: [EPERM, EACCES])
    func refusedConnectsAreSandboxed(code: Int32) {
        #expect(ControlClientError.connectFailed(path: "/s", errno: code) == .sandboxed(path: "/s", errno: code))
    }

    @Test(arguments: [ENOENT, ECONNREFUSED, ETIMEDOUT, ENAMETOOLONG])
    func otherFailuresMeanNothingListens(code: Int32) {
        #expect(ControlClientError.connectFailed(path: "/s", errno: code) == .notRunning(path: "/s"))
    }

    @Test(arguments: [EPERM, EACCES])
    func insideABundleASandboxedConnectNeverLaunchesTheApp(code: Int32) async throws {
        let t = try AppBundleLocatorTests.Tree()
        let executable = try t.bundle("Applications/Skreenrek.app")
        let launcher = FakeAppLauncher()
        let socket = URL(fileURLWithPath: t.path("c.sock"))
        let connector = ControlConnector(
            socketPath: socket, executablePath: executable, launcher: launcher, clock: ManualClock(),
            dial: { path, _ in throw ControlClientError.connectFailed(path: path.path, errno: code) })
        let error = await #expect(throws: ControlConnectError.self) {
            _ = try await connector.connect(as: ClientInfo(kind: .mcp))
        }
        #expect(launcher.launches.isEmpty)
        #expect(error?.body == ErrorBody(
            code: "sandboxed", message: "Skreenrek can't reach its app from this shell.", hint: Self.hint, exit: 1))
    }

    @Test func aRealEACCESFromConnectIsSandboxed() async throws {
        // A socket inside a folder this user can't search: connect() fails with EACCES, as under a sandbox.
        let t = try AppBundleLocatorTests.Tree()
        let locked = t.path("locked")
        try FileManager.default.createDirectory(atPath: locked, withIntermediateDirectories: true)
        chmod(locked, 0)
        defer { chmod(locked, 0o700) }
        let socket = URL(fileURLWithPath: locked + "/c.sock")
        await #expect(throws: ControlClientError.sandboxed(path: socket.path, errno: EACCES)) {
            _ = try await ControlClient.connect(path: socket, client: ClientInfo(kind: .cli))
        }
    }
}
