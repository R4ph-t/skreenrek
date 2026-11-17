import CoreGraphics
import Foundation
import SkreenrekCLI
import SkreenrekControl
import SkreenrekCore
import SkreenrekTesting
import Synchronization
import Testing

enum CLIFixtures {
    static let retina = DisplayInfo(
        id: 1, name: "Built-in Retina Display", scale: 2,
        frame: PointRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: PointRect(x: 0, y: 33, width: 1512, height: 949))

    /// 640 × 400 pt on the 2× display: 1280 × 800 px.
    static let safari = WindowInfo(
        id: WindowID(4127), app: "Safari", bundleId: "com.apple.Safari", title: "localhost:3000", pid: 812,
        frame: PointRect(x: 120, y: 80, width: 640, height: 400), displayId: 1, onScreen: true)

    /// 756 × 472.5 pt: 1512 × 945 px.
    static let github = WindowInfo(
        id: WindowID(4133), app: "Safari", bundleId: "com.apple.Safari", title: "GitHub", pid: 812,
        frame: PointRect(x: 300, y: 100, width: 756, height: 472.5), displayId: 1, onScreen: true)

    /// 320 × 200 pt: 640 × 400 px.
    static let terminal = WindowInfo(
        id: WindowID(5001), app: "Terminal", bundleId: "com.apple.Terminal", title: "zsh", pid: 900,
        frame: PointRect(x: 200, y: 300, width: 320, height: 200), displayId: 1, onScreen: true)
}

/// A test wait that took longer than its watchdog.
struct WaitTimedOut: Error, CustomStringConvertible {
    var what: String
    var seconds: Double
    var description: String { "Gave up after \(seconds) s waiting for \(what)." }
}

/// Runs `body`, failing with `WaitTimedOut` after `seconds` of real time instead of hanging. The watchdog only bounds
/// the wait; it never drives the test's timing. A body still stuck is cancelled and left behind.
func within<T: Sendable>(
    _ what: String, seconds: Double = 30, _ body: @escaping @Sendable () async throws -> T
) async throws -> T {
    let gate = ResumeOnce<T>()
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
        gate.set(continuation)
        let task = Task {
            do {
                gate.finish(.success(try await body()))
            } catch {
                gate.finish(.failure(error))
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            if gate.finish(.failure(WaitTimedOut(what: what, seconds: seconds))) { task.cancel() }
        }
    }
}

/// Resumes a continuation once, from whichever side finishes first.
private final class ResumeOnce<T: Sendable>: Sendable {
    private let state = Mutex<(continuation: CheckedContinuation<T, any Error>?, done: Bool)>((nil, false))

    func set(_ continuation: CheckedContinuation<T, any Error>) {
        state.withLock { $0.continuation = continuation }
    }

    @discardableResult
    func finish(_ result: Result<T, any Error>) -> Bool {
        let continuation = state.withLock { s -> CheckedContinuation<T, any Error>? in
            guard !s.done else { return nil }
            s.done = true
            return s.continuation
        }
        continuation?.resume(with: result)
        return continuation != nil
    }
}

/// Collects what the CLI writes to one stream.
final class OutputBuffer: TextOutput {
    private let text = Mutex("")

    func write(_ text: String) {
        self.text.withLock { $0 += text }
    }

    var contents: String { text.withLock { $0 } }
}

/// One CLI run: the exit code and both streams.
struct CLIResult: Sendable, CustomStringConvertible {
    var code: Int32
    var out: String
    var err: String

    var description: String { "exit \(code)\n--- stdout\n\(out)--- stderr\n\(err)" }

    /// The stdout JSON as a dictionary.
    func json() throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
    }

    /// The stderr JSON error envelope's body.
    func jsonError() throws -> [String: Any] {
        let object = try #require(try JSONSerialization.jsonObject(with: Data(err.utf8)) as? [String: Any])
        return try #require(object["error"] as? [String: Any])
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: Data(out.utf8))
    }
}

/// A short folder for a test's socket and clips (Unix socket paths hold at most 104 bytes). It is also the home
/// folder the CLI sees, so clip paths print as `~/out/…`.
struct ShortTemp {
    let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skc-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    var socket: URL { root.appendingPathComponent("s", isDirectory: true).appendingPathComponent("c.sock") }
    var output: URL { root.appendingPathComponent("out", isDirectory: true) }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// A `HeadlessHost` with fakes serving a real socket, plus the CLI environment pointed at it. The host isn't started
/// until `start()`, so app-launch tests can start it from the fake launcher.
final class CLIHarness: Sendable {
    let temp = ShortTemp()
    let catalog: FakeWindowCatalog
    let resizer = FakeWindowResizer()
    let source: SyntheticFrameSource
    let mouse = FakeMouseEventSource()
    let clock: ManualClock
    let permissions = FakePermissionProbe()
    let disk = FakeDiskSpaceProbe()
    let picker: FakeWindowPicker
    let sinks = SinkLog()
    let interrupts = FakeInterruptSource()
    let host: HeadlessHost

    init(
        source: SyntheticFrameSource = SyntheticFrameSource(count: 31, fps: 30), clock: ManualClock = ManualClock(),
        picker: FakeWindowPicker = FakeWindowPicker(), encode: Bool = false,
        windows: [WindowInfo] = [CLIFixtures.safari, CLIFixtures.terminal]
    ) {
        self.source = source
        self.clock = clock
        self.picker = picker
        catalog = FakeWindowCatalog(windows: windows, displays: [CLIFixtures.retina])
        let seams = ControllerSeams(
            catalog: catalog, resizer: resizer, frameSource: source, mouse: mouse, clock: clock,
            permissions: permissions, disk: disk, picker: picker, ownPid: 99, encoder: .software,
            realTimeWriter: false, makeSink: sinks.factory(clock: clock, encode: encode))
        host = HeadlessHost(
            seams: seams, settings: ControllerSettings(outputFolder: temp.output, fps: .fps60), socketPath: temp.socket)
    }

    var controller: SkreenrekController { host.controller }

    @discardableResult
    func start() throws -> CLIHarness {
        try host.start()
        return self
    }

    func stop() {
        host.stop()
        temp.cleanUp()
    }

    /// The CLI environment: not a TTY, no `NO_COLOR`, home is the temp folder, not inside an app bundle.
    func environment(
        stdout: OutputBuffer, stderr: OutputBuffer, tty: Bool = false, variables: [String: String] = [:],
        executablePath: String = "/usr/local/bin/skreenrek", launcher: any AppLauncher = FakeAppLauncher(),
        launchClock: (any HostClock)? = nil, perf: PerfSeams? = nil
    ) -> CLIEnvironment {
        CLIEnvironment(
            stdout: stdout, stderr: stderr, stdoutIsTTY: tty, stderrIsTTY: tty, variables: variables,
            home: temp.root, currentDirectory: temp.root.appendingPathComponent("work", isDirectory: true),
            socketPath: temp.socket, executablePath: executablePath, launcher: launcher, interrupts: interrupts,
            clock: launchClock ?? ManualClock(), perf: perf)
    }

    /// Runs the CLI in process, bounded by a watchdog.
    func run(
        _ arguments: [String], tty: Bool = false, variables: [String: String] = [:],
        executablePath: String = "/usr/local/bin/skreenrek", launcher: any AppLauncher = FakeAppLauncher(),
        launchClock: (any HostClock)? = nil, perf: PerfSeams? = nil
    ) async throws -> CLIResult {
        let out = OutputBuffer()
        let err = OutputBuffer()
        let env = environment(
            stdout: out, stderr: err, tty: tty, variables: variables, executablePath: executablePath,
            launcher: launcher, launchClock: launchClock, perf: perf)
        let code = try await within("skreenrek \(arguments.joined(separator: " "))") {
            await CLI.run(arguments, environment: env)
        }
        return CLIResult(code: code, out: out.contents, err: err.contents)
    }

    /// A direct control connection, for setting up state the CLI then reads.
    func client(_ kind: StartedBy = .cli) async throws -> ControlClient {
        try await ControlClient.connect(path: temp.socket, client: ClientInfo(kind: kind))
    }

    /// Waits until the current recording has appended `count` slots.
    func waitForSlots(_ count: Int) async throws {
        let sink = try #require(sinks.latest, "No recording has started.")
        try await within("\(count) slots") { await sink.waitForAppends(count) }
    }

    /// Waits until the controller's state is `state`.
    func waitForState(_ state: ControllerState) async throws {
        let controller = controller
        try await within("state \(state)") {
            for await snapshot in await controller.snapshots() where snapshot.state == state { return }
        }
    }

    /// Waits until `count` callers wait in `record.wait`.
    func waitForEndWaiters(_ count: Int = 1) async throws {
        let controller = controller
        try await within("\(count) record.wait callers") { await controller.waitForEndWaiters(count) }
    }

    /// The clip folder of a recording, as the CLI prints it.
    func tildeFolder(_ id: String) -> String { "~/out/\(id)" }
}
