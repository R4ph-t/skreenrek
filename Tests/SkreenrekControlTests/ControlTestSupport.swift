import CoreGraphics
import Foundation
import SkreenrekControl
import SkreenrekCore
import SkreenrekTesting
import Testing

enum ControlFixtures {
    static let retina = DisplayInfo(
        id: 1, name: "Built-in Retina Display", scale: 2,
        frame: PointRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: PointRect(x: 0, y: 33, width: 1512, height: 949))

    /// 640 × 400 pt on the 2× display: 1280 × 800 px.
    static let safari = WindowInfo(
        id: WindowID(4127), app: "Safari", bundleId: "com.apple.Safari", title: "localhost:3000", pid: 812,
        frame: PointRect(x: 120, y: 80, width: 640, height: 400), displayId: 1, onScreen: true)

    /// 320 × 200 pt: 640 × 400 px.
    static let terminal = WindowInfo(
        id: WindowID(5001), app: "Terminal", bundleId: "com.apple.Terminal", title: "zsh", pid: 900,
        frame: PointRect(x: 200, y: 300, width: 320, height: 200), displayId: 1, onScreen: true)
}

/// A short folder for a test's socket and clips (Unix socket paths hold at most 104 bytes).
struct ShortTemp {
    let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skr-\(UUID().uuidString.prefix(8))", isDirectory: true)
    }

    /// Inside a folder that doesn't exist yet, so the server creates it.
    var socket: URL { root.appendingPathComponent("s", isDirectory: true).appendingPathComponent("c.sock") }
    var output: URL { root.appendingPathComponent("out", isDirectory: true) }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// A `HeadlessHost` with fakes, serving a real socket, writing real clips with the software encoder.
final class Harness: Sendable {
    let temp = ShortTemp()
    let catalog: FakeWindowCatalog
    let resizer = FakeWindowResizer()
    let source: SyntheticFrameSource
    let mouse = FakeMouseEventSource()
    let clock: any HostClock
    let permissions = FakePermissionProbe()
    let disk = FakeDiskSpaceProbe()
    let picker: FakeWindowPicker
    let sinks = SinkLog()
    let host: HeadlessHost

    /// - Parameters:
    ///   - source: default 31 frames at 30 fps from host time 0, delivered at once.
    ///   - realTime: true for the perf suites (real clock, real-time writer).
    init(
        source: SyntheticFrameSource = SyntheticFrameSource(count: 31, fps: 30), clock: any HostClock = ManualClock(),
        picker: FakeWindowPicker = FakeWindowPicker(), realTime: Bool = false,
        windows: [WindowInfo] = [ControlFixtures.safari, ControlFixtures.terminal]
    ) {
        self.source = source
        self.clock = clock
        self.picker = picker
        self.catalog = FakeWindowCatalog(windows: windows, displays: [ControlFixtures.retina])
        let seams = ControllerSeams(
            catalog: catalog, resizer: resizer, frameSource: source, mouse: mouse, clock: clock,
            permissions: permissions, disk: disk, picker: picker, ownPid: 99, encoder: .software,
            realTimeWriter: realTime, makeSink: sinks.factory(clock: clock))
        host = HeadlessHost(
            seams: seams, settings: ControllerSettings(outputFolder: temp.output, fps: .fps30), socketPath: temp.socket)
    }

    var controller: SkreenrekController { host.controller }

    func start() throws -> Harness {
        try host.start()
        return self
    }

    func client(_ kind: StartedBy = .cli, name: String? = nil) async throws -> ControlClient {
        try await ControlClient.connect(path: temp.socket, client: ClientInfo(kind: kind, name: name))
    }

    /// Waits (without sleeping or polling) until the current recording has appended `count` slots. Call it after
    /// `record.start` answered, so the clip writer exists.
    func waitForSlots(_ count: Int) async {
        guard let sink = sinks.latest else {
            Issue.record("No recording has started.")
            return
        }
        await sink.waitForAppends(count)
    }

    /// Waits until the controller's state is `state`, from its snapshot stream (no polling).
    func waitForState(_ state: ControllerState) async {
        for await snapshot in await controller.snapshots() where snapshot.state == state { return }
    }

    func stop() {
        host.stop()
        temp.cleanUp()
    }
}

extension ControlClient {
    /// The app's error for a call that must fail.
    func expectError(
        _ method: ControlProtocol.Method, params: some Encodable & Sendable = NoParams(),
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> ErrorBody {
        let reply = try await send(method, params: params)
        do {
            _ = try reply.decode(NoParams.self)
        } catch let error as ControlRemoteError {
            return error.body
        }
        Issue.record("\(method.rawValue) succeeded: \(String(decoding: reply.line, as: UTF8.self))", sourceLocation: sourceLocation)
        return ErrorBody(code: "", message: "", hint: "", exit: 0)
    }
}

/// Decodes a JSON line into a dictionary, to check key sets.
func jsonObject(_ data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}
