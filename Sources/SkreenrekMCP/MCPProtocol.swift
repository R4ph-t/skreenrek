import Foundation

/// The MCP protocol facts the server needs: JSON-RPC 2.0, one message per line on stdin/stdout.
public enum MCPProtocol {
    /// The versions the server speaks, newest first. `initialize` answers with the client's version when it is one of
    /// these, else with the newest.
    public static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    public static let latestVersion = supportedVersions[0]

    public static let serverName = "skreenrek"

    /// The version `initialize` answers with for a client that asked for `requested`.
    public static func negotiate(_ requested: String?) -> String {
        guard let requested, supportedVersions.contains(requested) else { return latestVersion }
        return requested
    }

    /// The name an MCP client gives in `initialize.clientInfo.name`, as the app shows it ("Started by Claude Code
    /// over MCP"). Unknown names show as given; an empty name is nil.
    public static func displayName(forClient name: String?) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return knownClients[name] ?? name
    }

    static let knownClients = [
        "claude-code": "Claude Code",
        "codex-mcp-client": "Codex",
        "cursor-vscode": "Cursor",
    ]
}

/// A JSON-RPC 2.0 error: `{ code, message }`.
public struct RPCError: Error, Sendable, Hashable, Codable {
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603

    public var code: Int
    public var message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }

    static func parse() -> RPCError {
        RPCError(code: parseError, message: "Parse error: the line isn't one valid JSON message.")
    }

    static func invalid(_ detail: String) -> RPCError {
        RPCError(code: invalidRequest, message: "Invalid request: \(detail).")
    }

    static func unknownMethod(_ method: String) -> RPCError {
        RPCError(code: methodNotFound, message: "Method not found: \(method).")
    }

    static func params(_ detail: String) -> RPCError {
        RPCError(code: invalidParams, message: "Invalid params: \(detail).")
    }
}
