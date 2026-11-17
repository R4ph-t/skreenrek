import Foundation
import SkreenrekControl
import SkreenrekCore
import Synchronization

/// What the server touches outside itself. `skreenrek mcp` passes the real ones; tests pass a fake launcher and a
/// test socket.
public struct MCPEnvironment: Sendable {
    /// Reaches the app, launching it hidden when needed.
    public var connector: ControlConnector
    public var home: URL
    /// Relative `outDir` and `assetsDir` resolve against it: the app runs elsewhere.
    public var currentDirectory: URL
    /// One line of diagnostics on stderr. stdout carries only protocol messages.
    public var log: @Sendable (String) -> Void

    public init(
        connector: ControlConnector, home: URL, currentDirectory: URL, log: @escaping @Sendable (String) -> Void
    ) {
        self.connector = connector
        self.home = home
        self.currentDirectory = currentDirectory
        self.log = log
    }
}

/// The stdio MCP server: JSON-RPC 2.0, one message per line. It never captures: every tool is a call to the app over
/// the control socket, as `client.kind = "mcp"` with the name the client gave in `initialize`.
public final class MCPServer: Sendable {
    let environment: MCPEnvironment
    /// The client's display name from `initialize` ("Claude Code").
    private let clientName = Mutex<String?>(nil)

    public init(environment: MCPEnvironment) {
        self.environment = environment
    }

    /// The client as the app sees it.
    public var client: ClientInfo {
        ClientInfo(kind: .mcp, name: clientName.withLock { $0 })
    }

    /// Serves until `input` ends, writing each response line (newline included) through `output`. `tools/call` runs
    /// concurrently so a long `pick` doesn't hold up `ping`; everything else answers in order. Returns once every
    /// call has answered.
    public func serve(input: AsyncStream<Data>, output: @escaping @Sendable (Data) -> Void) async {
        let writer = Mutex(())
        let write: @Sendable (Data) -> Void = { line in writer.withLock { _ in output(line) } }
        environment.log("skreenrek \(SkreenrekVersion.current): MCP server ready on stdio")
        await withTaskGroup(of: Void.self) { group in
            for await line in input {
                switch classify(line) {
                case .skip:
                    continue
                case .answer(let response):
                    write(response)
                case .call(let id, let params):
                    group.addTask { write(await self.respond(id: id, toCall: params)) }
                }
            }
        }
    }

    /// Answers one line: the response line (newline included), or nil for notifications and blank lines.
    public func handle(_ line: Data) async -> Data? {
        switch classify(line) {
        case .skip: return nil
        case .answer(let response): return response
        case .call(let id, let params): return await respond(id: id, toCall: params)
        }
    }

    // MARK: - Dispatch

    private enum Step {
        case skip
        case answer(Data)
        case call(id: JSONValue, params: JSONValue?)
    }

    /// Everything but `tools/call` answers right here.
    private func classify(_ raw: Data) -> Step {
        let line = Self.trimmed(raw)
        guard !line.isEmpty else { return .skip }
        let message: JSONValue
        do {
            message = try JSONValue.parse(line)
        } catch {
            environment.log("skreenrek mcp: ignored a line that isn't JSON")
            return .answer(Self.error(id: .null, .parse()))
        }
        guard let members = message.objectValue else {
            return .answer(Self.error(id: .null, .invalid("send one JSON-RPC object per line")))
        }
        let id = members["id"]
        guard let method = members["method"] else {
            // A response to a request the server never sends: nothing to do.
            if members["result"] != nil || members["error"] != nil || id == nil { return .skip }
            return .answer(Self.error(id: id ?? .null, .invalid("method is required")))
        }
        guard members["jsonrpc"] == "2.0", let name = method.stringValue else {
            return id == nil ? .skip : .answer(Self.error(id: id ?? .null, .invalid("jsonrpc must be \"2.0\"")))
        }
        let params = members["params"]
        guard let id else {
            // A notification (`notifications/initialized`, `notifications/cancelled`, …): never answered.
            return .skip
        }
        if let params, params != .null, params.objectValue == nil {
            return .answer(Self.error(id: id, .params("params must be an object")))
        }
        switch name {
        case "initialize":
            return .answer(Self.result(id: id, initialize(params)))
        case "ping":
            return .answer(Self.result(id: id, [:]))
        case "tools/list":
            return .answer(Self.result(id: id, ["tools": .array(MCPTool.allCases.map(\.definition))]))
        case "tools/call":
            return .call(id: id, params: params)
        default:
            return .answer(Self.error(id: id, .unknownMethod(name)))
        }
    }

    private func initialize(_ params: JSONValue?) -> JSONValue {
        let name = MCPProtocol.displayName(forClient: params?["clientInfo"]?["name"]?.stringValue)
        clientName.withLock { $0 = name }
        return [
            "protocolVersion": .string(MCPProtocol.negotiate(params?["protocolVersion"]?.stringValue)),
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": .string(MCPProtocol.serverName), "version": .string(SkreenrekVersion.current)],
        ]
    }

    private func respond(id: JSONValue, toCall params: JSONValue?) async -> Data {
        guard let name = params?["name"] else { return Self.error(id: id, .params("name is required")) }
        guard let toolName = name.stringValue, let tool = MCPTool(rawValue: toolName) else {
            let shown = name.stringValue ?? ((try? name.jsonString()) ?? "")
            return Self.error(id: id, .params("\"\(shown)\" isn't a Skreenrek tool"))
        }
        let arguments = params?["arguments"] ?? .null
        let call: PreparedCall
        do {
            call = try PreparedCall(
                tool: tool, arguments: arguments == .null ? [:] : arguments, resolve: resolvePath)
        } catch {
            return Self.error(id: id, error)
        }
        return Self.result(id: id, await run(call))
    }

    /// Runs one tool call against the app: the result as `structuredContent` plus the same JSON as text, or the
    /// `{ error: {code, message, hint} }` body with `isError: true`.
    private func run(_ call: PreparedCall) async -> JSONValue {
        do {
            let connection = try await environment.connector.connect(as: client)
            defer { connection.close() }
            let result = try await call.send(connection).decode(JSONValue.self)
            return Self.toolResult(result, isError: false)
        } catch {
            let body = Self.errorBody(for: error)
            environment.log("skreenrek mcp: \(call.tool.rawValue) failed: \(body.code): \(body.message)")
            let payload: JSONValue = [
                "error": [
                    "code": .string(body.code), "message": .string(body.message), "hint": .string(body.hint),
                ]
            ]
            return Self.toolResult(payload, isError: true)
        }
    }

    static func toolResult(_ value: JSONValue, isError: Bool) -> JSONValue {
        let text = (try? value.jsonString()) ?? "{}"
        return [
            "content": [["type": "text", "text": .string(text)]],
            "structuredContent": value,
            "isError": .bool(isError),
        ]
    }

    static func errorBody(for error: any Error) -> ErrorBody {
        switch error {
        case let error as ControlRemoteError: return error.body
        case let error as ControlConnectError: return error.body
        case let error as ControlClientError: return error.body
        case let error as SkreenrekError: return error.body
        default: return SkreenrekError.internal(message: "Something went wrong: \(error.localizedDescription)").body
        }
    }

    /// `~` and relative folders as absolute paths.
    private var resolvePath: @Sendable (String) -> String {
        let home = environment.home
        let base = environment.currentDirectory
        return { path in
            if path == "~" { return home.path }
            if path.hasPrefix("~/") { return home.appendingPathComponent(String(path.dropFirst(2))).path }
            if path.hasPrefix("/") { return URL(fileURLWithPath: path).standardizedFileURL.path }
            return base.appendingPathComponent(path).standardizedFileURL.path
        }
    }

    // MARK: - Lines

    /// The line without its trailing CR and surrounding blanks.
    private static func trimmed(_ data: Data) -> Data {
        var bytes = data[...]
        while let last = bytes.last, last == 0x0D || last == 0x20 || last == 0x09 { bytes = bytes.dropLast() }
        while let first = bytes.first, first == 0x20 || first == 0x09 { bytes = bytes.dropFirst() }
        return Data(bytes)
    }

    static func result(id: JSONValue, _ result: JSONValue) -> Data {
        line(["jsonrpc": "2.0", "id": id, "result": result])
    }

    static func error(id: JSONValue, _ error: RPCError) -> Data {
        line(["jsonrpc": "2.0", "id": id, "error": ["code": .int(error.code), "message": .string(error.message)]])
    }

    private static func line(_ value: JSONValue) -> Data {
        var data =
            (try? SkreenrekJSON.encode(value))
            ?? Data(#"{"error":{"code":-32603,"message":"Internal error."},"id":null,"jsonrpc":"2.0"}"#.utf8)
        data.append(0x0A)
        return data
    }
}
