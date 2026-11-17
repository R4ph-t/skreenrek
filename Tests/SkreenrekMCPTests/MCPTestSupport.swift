import CoreGraphics
import Foundation
import SkreenrekControl
import SkreenrekCore
@testable import SkreenrekMCP
import SkreenrekTesting
import Synchronization
import Testing

enum MCPFixtures {
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

/// A test wait that took longer than its watchdog.
struct WaitTimedOut: Error, CustomStringConvertible {
    var what: String
    var seconds: Double
    var description: String { "Gave up after \(seconds) s waiting for \(what)." }
}

/// Runs `body`, failing with `WaitTimedOut` after `seconds` of real time instead of hanging. The watchdog only bounds
/// the wait; it never drives the test's timing.
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

/// Everything the server writes on stdout, line by line, with waits for a given response.
final class StdoutCollector: Sendable {
    private struct State {
        var raw = Data()
        var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    }
    private let state = Mutex(State())

    func write(_ data: Data) {
        let ready = state.withLock { s -> [CheckedContinuation<Void, Never>] in
            s.raw.append(data)
            let lines = s.raw.filter { $0 == 0x0A }.count
            let ready = s.waiters.filter { $0.count <= lines }.map(\.continuation)
            s.waiters.removeAll { $0.count <= lines }
            return ready
        }
        for continuation in ready { continuation.resume() }
    }

    /// Everything written, as text.
    var text: String { state.withLock { String(decoding: $0.raw, as: UTF8.self) } }

    /// Every complete line, parsed.
    func messages() throws -> [JSONValue] {
        try text.split(separator: "\n", omittingEmptySubsequences: false).dropLast().map {
            try JSONValue.parse(Data($0.utf8))
        }
    }

    /// Returns once `count` lines are written.
    func waitForLines(_ count: Int) async {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { s -> Bool in
                if s.raw.filter({ $0 == 0x0A }).count >= count { return true }
                s.waiters.append((count, continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }
}

/// What the server logs on stderr.
final class LogBuffer: Sendable {
    private let lines = Mutex("")

    func append(_ line: String) {
        lines.withLock { $0 += line + "\n" }
    }

    var text: String { lines.withLock { $0 } }
}

/// A short folder for a test's socket and clips (Unix socket paths hold at most 104 bytes).
struct ShortTemp {
    let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skm-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    var socket: URL { root.appendingPathComponent("s", isDirectory: true).appendingPathComponent("c.sock") }
    var output: URL { root.appendingPathComponent("out", isDirectory: true) }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// A `HeadlessHost` with fakes on a real socket, and the MCP server driven through an in-memory stdin pipe, as
/// `skreenrek mcp` runs it.
final class MCPHarness: Sendable {
    let temp = ShortTemp()
    let catalog: FakeWindowCatalog
    let resizer = FakeWindowResizer()
    let source: SyntheticFrameSource
    let mouse = FakeMouseEventSource()
    let clock = ManualClock()
    let permissions = FakePermissionProbe()
    let disk = FakeDiskSpaceProbe()
    let picker: FakeWindowPicker
    let sinks = SinkLog()
    let host: HeadlessHost
    let server: MCPServer
    let launcher: FakeAppLauncher
    let stdout = StdoutCollector()
    let stderr = LogBuffer()
    private let stdin = Pipe()
    private let nextID = Mutex(1)
    private let serving = Mutex<Task<Void, Never>?>(nil)

    init(
        encode: Bool = false, picker: FakeWindowPicker = FakeWindowPicker(),
        executablePath: String = "/usr/local/bin/skreenrek", launcher: FakeAppLauncher = FakeAppLauncher()
    ) {
        source = SyntheticFrameSource(count: 31, fps: 30)
        self.picker = picker
        self.launcher = launcher
        catalog = FakeWindowCatalog(windows: [MCPFixtures.safari, MCPFixtures.terminal], displays: [MCPFixtures.retina])
        let seams = ControllerSeams(
            catalog: catalog, resizer: resizer, frameSource: source, mouse: mouse, clock: clock,
            permissions: permissions, disk: disk, picker: picker, ownPid: 99, encoder: .software,
            realTimeWriter: false, makeSink: sinks.factory(clock: clock, encode: encode))
        host = HeadlessHost(
            seams: seams, settings: ControllerSettings(outputFolder: temp.output, fps: .fps60), socketPath: temp.socket)
        let stderr = stderr
        server = MCPServer(
            environment: MCPEnvironment(
                connector: ControlConnector(
                    socketPath: temp.socket, executablePath: executablePath, launcher: launcher, clock: ManualClock()),
                home: temp.root, currentDirectory: temp.root.appendingPathComponent("work", isDirectory: true),
                log: { stderr.append($0) }))
    }

    var controller: SkreenrekController { host.controller }

    /// Starts the app side and the server reading the stdin pipe.
    @discardableResult
    func start(app: Bool = true) throws -> MCPHarness {
        if app { try host.start() }
        let input = StdioLines.stream(fileDescriptor: stdin.fileHandleForReading.fileDescriptor)
        let server = server
        let stdout = stdout
        serving.withLock { $0 = Task { await server.serve(input: input) { stdout.write($0) } } }
        return self
    }

    /// Closes stdin and waits for the server to return.
    func finish() async throws {
        try stdin.fileHandleForWriting.close()
        let task = serving.withLock { $0 }
        try await within("the server to end") { await task?.value }
    }

    func stop() {
        try? stdin.fileHandleForWriting.close()
        host.stop()
        temp.cleanUp()
    }

    /// Writes raw bytes on stdin.
    func send(raw: String) {
        stdin.fileHandleForWriting.write(Data(raw.utf8))
    }

    /// Sends a notification (no id).
    func notify(_ method: String, params: JSONValue? = nil) throws {
        var message: [String: JSONValue] = ["jsonrpc": "2.0", "method": .string(method)]
        if let params { message["params"] = params }
        send(raw: try JSONValue.object(message).jsonString() + "\n")
    }

    /// Sends a request and waits for its response.
    func request(_ method: String, params: JSONValue? = nil) async throws -> JSONValue {
        let id = nextID.withLock { n in
            defer { n += 1 }
            return n
        }
        var message: [String: JSONValue] = ["jsonrpc": "2.0", "id": .int(id), "method": .string(method)]
        if let params { message["params"] = params }
        return try await exchange(try JSONValue.object(message).jsonString(), id: .int(id))
    }

    /// Writes one raw line and waits for the response with `id`.
    func exchange(_ line: String, id: JSONValue) async throws -> JSONValue {
        send(raw: line + "\n")
        let stdout = stdout
        return try await within("the response to \(line)") {
            while true {
                let messages = try stdout.messages()
                if let match = messages.first(where: { $0["id"] == id }) { return match }
                await stdout.waitForLines(messages.count + 1)
            }
        }
    }

    /// Writes one raw line that gets an answer without an id (`id: null`) and returns that answer.
    func exchangeUnidentified(_ line: String) async throws -> JSONValue {
        let before = try stdout.messages().count
        send(raw: line + "\n")
        let stdout = stdout
        try await within("the response to \(line)") { await stdout.waitForLines(before + 1) }
        return try stdout.messages()[before]
    }

    /// `initialize` as `client` asking for `version`.
    @discardableResult
    func initialize(client: String = "claude-code", version: String = "2025-06-18") async throws -> JSONValue {
        let response = try await request(
            "initialize",
            params: [
                "protocolVersion": .string(version), "capabilities": [:],
                "clientInfo": ["name": .string(client), "version": "1.0.0"],
            ])
        try notify("notifications/initialized")
        return response
    }

    /// Calls a tool and returns the `result` (which holds `isError`).
    func call(_ tool: String, _ arguments: JSONValue? = nil) async throws -> JSONValue {
        var params: [String: JSONValue] = ["name": .string(tool)]
        if let arguments { params["arguments"] = arguments }
        let response = try await request("tools/call", params: .object(params))
        return try #require(response["result"], "No result: \(response.text)")
    }

    /// Waits until the current recording has appended `count` slots.
    func waitForSlots(_ count: Int) async throws {
        let sink = try #require(sinks.latest, "No recording has started.")
        try await within("\(count) slots") { await sink.waitForAppends(count) }
    }
}

extension JSONValue {
    /// The tool result's `structuredContent`, checked against its text item.
    func structured() throws -> JSONValue {
        let content = try #require(self["structuredContent"])
        guard case .array(let items) = try #require(self["content"]), items.count == 1 else {
            Issue.record("Expected one content item in \(text)")
            return content
        }
        #expect(items[0]["type"] == "text")
        let text = try #require(items[0]["text"]?.stringValue)
        #expect(try JSONValue.parse(Data(text.utf8)) == content, "The text item isn't the structured JSON.")
        return content
    }

    /// Compact JSON for test messages.
    var text: String { (try? jsonString()) ?? "?" }

    var intValue: Int? {
        if case .int(let value) = self { return value }
        return nil
    }
}
