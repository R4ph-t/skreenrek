import CoreGraphics
import Foundation
import SkreenrekControl
import SkreenrekCore
@testable import SkreenrekMCP
import SkreenrekTesting
import Testing

/// The stdio server end to end: JSON-RPC over an in-memory stdin pipe, against a `HeadlessHost` with fakes on a real
/// control socket.
@Suite(.timeLimit(.minutes(2))) struct MCPServerTests {
    @Test(arguments: [
        ("2025-06-18", "2025-06-18"), ("2025-03-26", "2025-03-26"), ("2024-11-05", "2024-11-05"),
        ("2099-01-01", "2025-06-18"), ("", "2025-06-18"),
    ])
    func initializeNegotiatesTheProtocolVersion(asked: String, answered: String) async throws {
        let h = try MCPHarness().start()
        defer { h.stop() }
        let response = try await h.initialize(version: asked)
        #expect(try response.jsonString() == """
            {"id":1,"jsonrpc":"2.0","result":{"capabilities":{"tools":{"listChanged":false}},\
            "protocolVersion":"\(answered)","serverInfo":{"name":"skreenrek","version":"\(SkreenrekVersion.current)"}}}
            """)
    }

    @Test func initializeWithoutAVersionAnswersTheNewest() async throws {
        let h = try MCPHarness().start()
        defer { h.stop() }
        let response = try await h.request("initialize", params: [:])
        #expect(response["result"]?["protocolVersion"] == "2025-06-18")
    }

    @Test func pingAnswersAnEmptyResult() async throws {
        let h = try MCPHarness().start()
        defer { h.stop() }
        let response = try await h.request("ping")
        #expect(try response.jsonString() == #"{"id":1,"jsonrpc":"2.0","result":{}}"#)
    }

    @Test func listStartStopProducesTheClipEventsAndSnippet() async throws {
        let h = try MCPHarness(encode: true).start()
        defer { h.stop() }
        try await h.initialize(client: "claude-code")

        let list = try await h.call("skreenrek_list_windows")
        #expect(list["isError"] == false)
        #expect(try list.structured().jsonString() == """
            {"windows":[{"app":"Safari","bundleId":"com.apple.Safari","displayId":1,"height":800,"id":4127,\
            "onScreen":true,"title":"localhost:3000","unit":"px","width":1280},{"app":"Terminal",\
            "bundleId":"com.apple.Terminal","displayId":1,"height":400,"id":5001,"onScreen":true,"title":"zsh",\
            "unit":"px","width":640}]}
            """)

        let start = try await h.call(
            "skreenrek_start_recording", ["windowId": 4127, "width": 1440, "height": 900, "fps": 30])
        #expect(start["isError"] == false, "\(start.text)")
        let started = try start.structured()
        let recordingId = try #require(started["recordingId"]?.stringValue)
        #expect(started["fps"] == 30)
        #expect(started["readback"]?["exact"] == true)
        #expect(started["readback"]?["actual"]?["width"] == 1440)
        #expect(started["readback"]?["actual"]?["height"] == 900)

        // The client name reaches the app: the dropdown's "Started by Claude Code over MCP".
        let snapshot = await h.controller.snapshot()
        #expect(snapshot.startedBy == .mcp)
        #expect(snapshot.client == "Claude Code")
        let status = try await h.call("skreenrek_status").structured()
        #expect(status["state"] == "recording")
        #expect(status["recording"]?["startedBy"] == "mcp")
        #expect(status["recording"]?["client"] == "Claude Code")

        try await h.waitForSlots(5)
        let stop = try await h.call("skreenrek_stop_recording")
        #expect(stop["isError"] == false, "\(stop.text)")
        let stopped = try stop.structured()
        #expect(Set(try #require(stopped.objectValue).keys) == ["recording", "files", "snippet", "readback"])
        #expect(stopped["recording"]?["id"] == .string(recordingId))
        #expect(stopped["recording"]?["startedBy"] == "mcp")
        #expect(stopped["readback"]?["exact"] == true)
        let snippet = try #require(stopped["snippet"]?.stringValue)
        #expect(snippet.contains("assets/\(recordingId).mp4"))

        let files = try #require(stopped["files"])
        let fm = FileManager.default
        for key in ["clip", "events", "snippet"] {
            let path = try #require(files[key]?.stringValue, "files.\(key)")
            #expect(fm.fileExists(atPath: path), "\(key) at \(path)")
        }
        let clip = try #require(files["clip"]?.stringValue)
        #expect(clip.hasSuffix("/\(recordingId)/clip.mp4"))
        #expect(try String(contentsOfFile: try #require(files["snippet"]?.stringValue), encoding: .utf8) == snippet)
        let events = try JSONValue.parse(Data(contentsOf: URL(fileURLWithPath: try #require(files["events"]?.stringValue))))
        #expect(events["recording"]?["startedBy"] == "mcp")
        #expect(events["recording"]?["client"] == "Claude Code")
    }

    @Test(arguments: [
        ("claude-code", "Claude Code"), ("codex-mcp-client", "Codex"), ("cursor-vscode", "Cursor"),
        ("Zed", "Zed"), ("my-agent", "my-agent"),
    ])
    func theClientNameIsMappedForDisplay(name: String, shown: String) async throws {
        let h = try MCPHarness().start()
        defer { h.stop() }
        try await h.initialize(client: name)
        let start = try await h.call("skreenrek_start_recording", ["app": "Terminal"])
        #expect(start["isError"] == false, "\(start.text)")
        let snapshot = await h.controller.snapshot()
        #expect(snapshot.client == shown)
        #expect(snapshot.startedBy == .mcp)
        _ = try await h.call("skreenrek_discard_recording")
    }

    @Test func clientNamesMapAndBlankNamesAreNil() {
        #expect(MCPProtocol.displayName(forClient: "claude-code") == "Claude Code")
        #expect(MCPProtocol.displayName(forClient: "codex-mcp-client") == "Codex")
        #expect(MCPProtocol.displayName(forClient: "cursor-vscode") == "Cursor")
        #expect(MCPProtocol.displayName(forClient: "Windsurf") == "Windsurf")
        #expect(MCPProtocol.displayName(forClient: "  ") == nil)
        #expect(MCPProtocol.displayName(forClient: nil) == nil)
    }

    @Test func withoutInitializeTheRecordingIsStillMarkedMCP() async throws {
        let h = try MCPHarness().start()
        defer { h.stop() }
        let start = try await h.call("skreenrek_start_recording", ["app": "Safari"])
        #expect(start["isError"] == false, "\(start.text)")
        let snapshot = await h.controller.snapshot()
        #expect(snapshot.startedBy == .mcp)
        #expect(snapshot.client == nil)
        let discard = try await h.call("skreenrek_discard_recording")
        #expect(try discard.structured() == ["discarded": true])
    }

    /// Spec 13: MCP `size` takes the CLI's strings; the clip is exact and the window fits the display.
    @Test func sizeTakesPresetsAndPixels() async throws {
        let h = try MCPHarness().start()
        defer { h.stop() }
        try await h.initialize()
        let preset = try await h.call("skreenrek_resize_window", ["app": "Safari", "size": "1080p"])
        #expect(preset["isError"] != true)
        let readback = try preset.structured()
        #expect(readback["actual"]?["width"] == 1920 && readback["actual"]?["height"] == 1080)
        #expect(readback["frame"]?["width"] == 1440 && readback["frame"]?["height"] == 810)
        let pixels = try await h.call("skreenrek_resize_window", ["app": "Safari", "size": "1280x720px"])
        #expect(try pixels.structured()["actual"]?["width"] == 1280)
        let tooBig = try await h.call("skreenrek_resize_window", ["app": "Safari", "size": "4k"])
        #expect(tooBig["isError"] == true)
        let error = try #require(try tooBig.structured()["error"])
        #expect(error["code"] == "usage")
        #expect(error["message"]?.stringValue?.hasPrefix("4K needs a window at least 1920 × 1080 on screen") == true)
    }

    @Test func aSizeThatIsNotExactIsAToolError() async throws {
        let h = try MCPHarness().start()
        defer { h.stop() }
        try await h.initialize()
        h.resizer.rules = ResizeRules(minimumSize: CGSize(width: 1286, height: 100))

        let resize = try await h.call("skreenrek_resize_window", ["app": "Safari", "width": 1280, "height": 800])
        #expect(resize["isError"] == true)
        let error = try #require(try resize.structured()["error"])
        #expect(error["code"] == "not_exact")
        #expect(Set(try #require(error.objectValue).keys) == ["code", "message", "hint"])
        #expect(error["message"]?.stringValue?.isEmpty == false)
        #expect(error["hint"]?.stringValue?.isEmpty == false)

        let start = try await h.call("skreenrek_start_recording", ["app": "Safari", "width": 1280, "height": 800])
        #expect(start["isError"] == true)
        #expect(try start.structured()["error"]?["code"] == "not_exact")
        #expect(await h.controller.snapshot().state != .recording)

        let inexact = try await h.call(
            "skreenrek_start_recording", ["app": "Safari", "width": 1280, "height": 800, "allowInexact": true])
        #expect(inexact["isError"] == false, "\(inexact.text)")
        #expect(try inexact.structured()["readback"]?["exact"] == false)
        _ = try await h.call("skreenrek_discard_recording")
    }

    @Test func callsInTheWrongStateAreToolErrors() async throws {
        let h = try MCPHarness().start()
        defer { h.stop() }
        try await h.initialize()
        for tool in ["skreenrek_stop_recording", "skreenrek_discard_recording"] {
            let result = try await h.call(tool)
            #expect(result["isError"] == true)
            #expect(try result.structured()["error"]?["code"] == "wrong_state")
        }
        _ = try await h.call("skreenrek_start_recording", ["app": "Safari"])
        let again = try await h.call("skreenrek_start_recording", ["app": "Terminal"])
        #expect(again["isError"] == true)
        #expect(try again.structured()["error"]?["code"] == "wrong_state")
        _ = try await h.call("skreenrek_discard_recording")
    }

    @Test func appErrorsLikeAMissingWindowOrABadFrameRateAreToolErrors() async throws {
        let h = try MCPHarness().start()
        defer { h.stop() }
        let missing = try await h.call("skreenrek_start_recording", ["windowId": 9999])
        #expect(missing["isError"] == true)
        #expect(try missing.structured()["error"]?["code"] == "window_not_found")
        let fps = try await h.call("skreenrek_start_recording", ["app": "Safari", "fps": 45])
        #expect(fps["isError"] == true)
        #expect(try fps.structured()["error"]?["code"] == "usage")
    }

    @Test func theJSONRPCErrorCodes() async throws {
        let h = try MCPHarness().start()
        defer { h.stop() }
        func code(_ response: JSONValue) -> Int? { response["error"]?["code"]?.intValue }

        let parse = try await h.exchangeUnidentified("{not json")
        #expect(code(parse) == -32700)
        #expect(parse["id"] == .null)

        #expect(code(try await h.request("resources/list")) == -32601)
        #expect(code(try await h.request("prompts/list")) == -32601)
        #expect(code(try await h.request("tools/call", params: ["name": "skreenrek_record"])) == -32602)
        #expect(code(try await h.request("tools/call", params: [:])) == -32602)
        #expect(code(try await h.request("tools/call", params: ["name": 7])) == -32602)
        let bad: [JSONValue] = [
            ["name": "skreenrek_resize_window", "arguments": ["app": "Safari", "width": "1280", "height": 800]],
            ["name": "skreenrek_resize_window", "arguments": ["app": "Safari", "height": 800]],
            ["name": "skreenrek_start_recording", "arguments": ["app": "Safari", "window_id": 4127]],
            ["name": "skreenrek_start_recording", "arguments": ["region": ["x": 0, "y": 0, "width": 10, "height": 10, "z": 1]]],
            ["name": "skreenrek_start_recording", "arguments": ["windowId": -1]],
            ["name": "skreenrek_start_recording", "arguments": "Safari"],
            ["name": "skreenrek_status", "arguments": ["verbose": true]],
            ["name": "skreenrek_pick_window", "arguments": ["timeoutSeconds": "soon"]],
            ["name": "skreenrek_resize_window", "arguments": ["app": "Safari", "size": "8k"]],
            ["name": "skreenrek_resize_window", "arguments": ["app": "Safari", "size": 1080]],
            ["name": "skreenrek_resize_window", "arguments": ["app": "Safari", "size": "1080p", "width": 1920]],
            ["name": "skreenrek_start_recording", "arguments": ["app": "Safari", "size": "huge"]],
        ]
        for params in bad {
            let response = try await h.request("tools/call", params: params)
            #expect(code(response) == -32602, "\(params.text) → \(response.text)")
        }
        let message = try await h.request(
            "tools/call", params: ["name": "skreenrek_resize_window", "arguments": ["app": "Safari", "height": 800]])
        #expect(message["error"]?["message"] == "Invalid params: width is required.")

        let invalid = try await h.exchange(#"{"id":"x","method":"ping"}"#, id: "x")
        #expect(code(invalid) == -32600)
        let array = try await h.exchangeUnidentified("[1,2]")
        #expect(array["id"] == .null)
        #expect(code(array) == -32600)
        // Nothing reached the app.
        #expect(await h.controller.snapshot().state == .idle)
    }

    @Test func stdoutCarriesOnlyOneResponsePerRequestAndLogsGoToStderr() async throws {
        let h = try MCPHarness().start()
        defer { h.stop() }
        try await h.initialize()
        try h.notify("notifications/cancelled", params: ["requestId": 99])
        try h.notify("notifications/whatever")
        h.send(raw: "\n   \n")
        _ = try await h.request("tools/list")
        _ = try await h.call("skreenrek_status")
        _ = try await h.call("skreenrek_stop_recording")
        _ = try await h.request("nope")
        // A response the client sends back is never answered.
        h.send(raw: #"{"jsonrpc":"2.0","id":42,"result":{}}"# + "\n")
        try await h.finish()

        let messages = try h.stdout.messages()
        #expect(h.stdout.text.hasSuffix("\n"))
        #expect(messages.map { $0["id"] } == [1, 2, 3, 4, 5])
        for message in messages {
            #expect(message["jsonrpc"] == "2.0")
            #expect((message["result"] == nil) != (message["error"] == nil))
        }
        let stderr = h.stderr.text
        #expect(stderr.contains("MCP server ready on stdio"))
        #expect(stderr.contains("skreenrek_stop_recording failed: wrong_state"))
    }

    @Test func aLongPickDoesNotHoldUpOtherRequests() async throws {
        let h = try MCPHarness(picker: FakeWindowPicker(result: nil)).start()
        defer { h.stop() }
        try await h.initialize()
        let server = h
        async let pick = h.call("skreenrek_pick_window", ["timeoutSeconds": 5])
        try await within("the picker to open") { await server.picker.waitForPick() }
        #expect(try await h.request("ping")["result"] == [:])
        h.picker.answer(.cancelled)
        #expect(try await pick.structured() == ["cancelled": true])
        #expect(h.picker.timeouts == [5])

        let picker = FakeWindowPicker(result: .window(MCPFixtures.terminal.id))
        let h2 = try MCPHarness(picker: picker).start()
        defer { h2.stop() }
        let picked = try await h2.call("skreenrek_pick_window")
        #expect(try picked.structured()["id"] == 5001)
        #expect(picker.timeouts == [60])
    }

    @Test func outDirAndAssetsDirResolveAgainstTheServersFolder() async throws {
        let h = try MCPHarness().start()
        defer { h.stop() }
        let start = try await h.call("skreenrek_start_recording", ["app": "Safari", "outDir": "clips"])
        #expect(start["isError"] == false, "\(start.text)")
        let id = try #require(try start.structured()["recordingId"]?.stringValue)
        let folder = h.temp.root.appendingPathComponent("work/clips/\(id)")
        #expect(FileManager.default.fileExists(atPath: folder.path))
        _ = try await h.call("skreenrek_discard_recording")
    }

    @Test func whenTheAppIsNotRunningTheCallSaysSoAsAToolError() async throws {
        let h = try MCPHarness().start(app: false)
        defer { h.stop() }
        let result = try await h.call("skreenrek_status")
        #expect(result["isError"] == true)
        #expect(try result.structured() == [
            "error": [
                "code": "internal",
                "message": """
                    Skreenrek isn't running, and /usr/local/bin/skreenrek isn't inside an app bundle, so it can't be \
                    opened.
                    """,
                "hint": "Open Skreenrek.app, or run: skreenrek app",
            ]
        ])
    }

    @Test func insideTheBundleTheAppIsLaunchedHidden() async throws {
        let temp = ShortTemp()
        defer { temp.cleanUp() }
        let fm = FileManager.default
        let macOS = temp.root.appendingPathComponent("Skreenrek.app/Contents/MacOS", isDirectory: true)
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        let executable = macOS.appendingPathComponent("skreenrek")
        fm.createFile(atPath: executable.path, contents: Data())

        let started = HostBox()
        let launcher = FakeAppLauncher { _ in try started.host?.start() }
        let h = MCPHarness(executablePath: executable.path, launcher: launcher)
        started.host = h.host
        try h.start(app: false)
        defer { h.stop() }
        let result = try await h.call("skreenrek_status")
        #expect(result["isError"] == false, "\(result.text)")
        #expect(try result.structured()["state"] == "idle")
        #expect(launcher.launches.count == 1)
        _ = try await h.call("skreenrek_status")
        #expect(launcher.launches.count == 1)
    }
}

/// The host a fake launch starts, set after the harness exists.
private final class HostBox: @unchecked Sendable {
    nonisolated(unsafe) var host: HeadlessHost?
}
