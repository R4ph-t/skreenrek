import Foundation
import SkreenrekControl
import SkreenrekCore

/// The design spec's seven tools. Inputs and outputs are the CLI's JSON: each tool is one control-socket call whose
/// result goes back as it is.
public enum MCPTool: String, Sendable, CaseIterable {
    case listWindows = "skreenrek_list_windows"
    case resizeWindow = "skreenrek_resize_window"
    case startRecording = "skreenrek_start_recording"
    case stopRecording = "skreenrek_stop_recording"
    case status = "skreenrek_status"
    case discardRecording = "skreenrek_discard_recording"
    case pickWindow = "skreenrek_pick_window"

    /// One sentence each, as `tools/list` shows it.
    public var summary: String {
        switch self {
        case .listWindows:
            "List the macOS windows Skreenrek can record, with their IDs, apps, titles and sizes in pixels."
        case .resizeWindow:
            "Size a window for an exact clip size (a preset like 1080p, or pixels) and read the size back to "
                + "confirm it."
        case .startRecording:
            "Start recording a window or screen region at a constant 30 or 60 fps, sizing the window for an exact "
                + "clip size first when size, or width and height, is given."
        case .stopRecording:
            "Stop the recording and return the paths of the clip, events.json and hyperframes.html, plus the "
                + "HyperFrames snippet."
        case .status:
            "Tell whether Skreenrek is idle, armed, recording, writing or in error, with the current recording and "
                + "the last clip."
        case .discardRecording:
            "Stop the recording and delete its clip folder."
        case .pickWindow:
            "Open the window picker on the Mac so a person can choose a window, and return it or { cancelled: true }."
        }
    }

    /// The JSON Schema for the tool's arguments.
    public var inputSchema: JSONValue {
        switch self {
        case .listWindows:
            return Self.object(["app": Self.app("Only windows of this app (name or bundle ID).")])
        case .resizeWindow:
            return Self.object(
                [
                    "windowId": Self.windowId, "app": Self.app("The app whose window to resize (name or bundle ID)."),
                    "title": Self.title, "size": Self.size,
                    "width": Self.pixels("The clip width in pixels (with height, instead of size)."),
                    "height": Self.pixels("The clip height in pixels (with width, instead of size)."),
                ])
        case .startRecording:
            return Self.object([
                "windowId": Self.windowId, "app": Self.app("The app whose window to record (name or bundle ID)."),
                "title": Self.title,
                "region": Self.object(
                    [
                        "x": ["type": "integer", "description": "Left edge in pixels of the display."],
                        "y": ["type": "integer", "description": "Top edge in pixels of the display."],
                        "width": Self.pixels("The width in pixels."), "height": Self.pixels("The height in pixels."),
                    ], required: ["x", "y", "width", "height"],
                    description: "Record this screen region instead of a window, in pixels, top-left origin."),
                "displayId": [
                    "type": "integer", "minimum": 0,
                    "description": "With region: the display (default: the main display).",
                ],
                "size": Self.size,
                "width": Self.pixels("Resize the window to this width in pixels first (with height)."),
                "height": Self.pixels("Resize the window to this height in pixels first (with width)."),
                "allowInexact": [
                    "type": "boolean", "default": false,
                    "description": "Record even when the size read back isn't exact.",
                ],
                "fps": [
                    "type": "integer", "enum": [30, 60],
                    "description": "Frames per second (default from Settings, otherwise 60).",
                ],
                "format": ["type": "string", "enum": ["mp4", "mov"], "default": "mp4"],
                "codec": ["type": "string", "enum": ["h264", "hevc", "prores"], "default": "h264"],
                "quality": ["type": "string", "enum": ["low", "medium", "high", "max"], "default": "high"],
                "bitrateMbps": ["type": "number", "minimum": 1, "maximum": 200],
                "durationSeconds": [
                    "type": "number", "exclusiveMinimum": 0, "description": "Stop on its own after this many seconds.",
                ],
                "cursor": ["type": "boolean", "default": true, "description": "Show the cursor in the video."],
                "events": ["type": "boolean", "default": true, "description": "Write events.json."],
                "hud": ["type": "boolean", "default": true, "description": "Show the recording indicator."],
                "outDir": [
                    "type": "string",
                    "description": "The folder for the clip folder (default: ~/Movies/Skreenrek or Settings).",
                ],
                "assetsDir": [
                    "type": "string",
                    "description": "Also copy the clip into this HyperFrames assets folder and point the snippet at it.",
                ],
            ])
        case .stopRecording, .status, .discardRecording:
            return Self.object([:])
        case .pickWindow:
            return Self.object([
                "timeoutSeconds": [
                    "type": "number", "exclusiveMinimum": 0, "default": 60,
                    "description": "How long to wait for the person to pick, in seconds.",
                ]
            ])
        }
    }

    /// The `tools/list` entry.
    public var definition: JSONValue {
        ["name": .string(rawValue), "description": .string(summary), "inputSchema": inputSchema]
    }

    // MARK: - Schema pieces

    static func object(
        _ properties: [String: JSONValue], required: [String] = [], description: String? = nil
    ) -> JSONValue {
        var schema: [String: JSONValue] = [
            "type": "object", "properties": .object(properties), "additionalProperties": false,
        ]
        if !required.isEmpty { schema["required"] = .array(required.map { .string($0) }) }
        if let description { schema["description"] = .string(description) }
        return .object(schema)
    }

    static let windowId: JSONValue = [
        "type": "integer", "minimum": 0, "description": "A window ID from skreenrek_list_windows.",
    ]
    static let title: JSONValue = ["type": "string", "description": "With app: a part of the window title."]

    static func app(_ description: String) -> JSONValue {
        ["type": "string", "description": .string(description)]
    }

    /// The clip size as `--size` spells it.
    static let size: JSONValue = [
        "type": "string",
        "description": .string(
            "The clip size: 720p, 1080p, 1440p, 4k, square, portrait, or WxH in pixels (WxHpx also works). "
                + "Skreenrek sizes the window to fit its display and records the exact clip size."),
    ]

    static func pixels(_ description: String) -> JSONValue {
        ["type": "integer", "minimum": 1, "description": .string(description)]
    }
}

/// A tool call checked against its schema and ready to send to the app.
struct PreparedCall: Sendable {
    let tool: MCPTool
    let send: @Sendable (ControlClient) async throws -> ControlReply

    /// Checks the arguments: unknown keys and wrong types are `-32602`, before the app is contacted. `resolve` turns
    /// `outDir` and `assetsDir` into absolute paths (the app runs in another folder).
    init(tool: MCPTool, arguments: JSONValue, resolve: @Sendable (String) -> String) throws(RPCError) {
        self.tool = tool
        try Self.checkKeys(arguments, schema: tool.inputSchema, path: "")
        switch tool {
        case .listWindows:
            let params = try Self.decode(WindowsParams.self, arguments)
            send = { try await $0.send(.windows, params: params) }
        case .resizeWindow:
            let params = try Self.decode(ResizeParams.self, Self.expandingSize(arguments))
            send = { try await $0.send(.resize, params: params) }
        case .startRecording:
            var params = try Self.decode(StartParams.self, Self.expandingSize(arguments))
            params.outDir = params.outDir.map(resolve)
            params.assetsDir = params.assetsDir.map(resolve)
            let resolved = params
            send = { try await $0.send(.recordStart, params: resolved) }
        case .stopRecording:
            send = { try await $0.send(.recordStop) }
        case .status:
            send = { try await $0.send(.status) }
        case .discardRecording:
            send = { try await $0.send(.recordDiscard) }
        case .pickWindow:
            let params = try Self.decode(PickParams.self, arguments)
            send = { try await $0.send(.pick, params: params) }
        }
    }

    /// Every key must be one of the schema's properties, in nested objects too.
    private static func checkKeys(_ value: JSONValue, schema: JSONValue, path: String) throws(RPCError) {
        guard let members = value.objectValue else {
            throw .params(path.isEmpty ? "arguments must be an object" : "\(path) must be an object")
        }
        let properties = schema["properties"]?.objectValue ?? [:]
        for key in members.keys.sorted() {
            let at = path.isEmpty ? key : "\(path).\(key)"
            guard let property = properties[key] else { throw .params("\(at) isn't an argument of this tool") }
            if property["type"] == "object", let member = members[key], member != .null {
                try checkKeys(member, schema: property, path: at)
            }
        }
    }

    /// `size` (a preset or `WxH`) becomes `width` and `height` in pixels, which the app takes.
    static func expandingSize(_ arguments: JSONValue) throws(RPCError) -> JSONValue {
        guard var members = arguments.objectValue, let value = members.removeValue(forKey: "size") else {
            return arguments
        }
        guard case .string(let text) = value else { throw .params("size must be a string") }
        guard members["width"] == nil, members["height"] == nil else {
            throw .params("pass size, or width and height, not both")
        }
        guard let size = try? SizeSpec.parse(text) else {
            throw .params("size \"\(text)\" isn't a size; use \(SizePreset.names), or WxH in pixels")
        }
        members["width"] = .int(size.width)
        members["height"] = .int(size.height)
        return .object(members)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ arguments: JSONValue) throws(RPCError) -> T {
        do {
            return try arguments.decode(type)
        } catch let error as DecodingError {
            throw .params(describe(error))
        } catch {
            throw .params("the arguments can't be read")
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map(\.stringValue).joined(separator: ".")
        }
        switch error {
        case .keyNotFound(let key, let context):
            let parent = path(context)
            return "\(parent.isEmpty ? "" : parent + ".")\(key.stringValue) is required"
        case .typeMismatch(_, let context), .dataCorrupted(let context):
            let at = path(context)
            return at.isEmpty ? "arguments must be an object" : "\(at) has the wrong type"
        case .valueNotFound(_, let context):
            let at = path(context)
            return at.isEmpty ? "arguments must be an object" : "\(at) can't be null"
        @unknown default:
            return "the arguments can't be read"
        }
    }
}
