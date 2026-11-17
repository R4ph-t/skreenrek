import Foundation
import SkreenrekCore

/// `skreenrek.control/1`: one JSON object per line, UTF-8, over a stream Unix socket.
///
/// Request: `{"v":1,"id":7,"method":"record.start","params":{…},"client":{"kind":"cli","name":"…"}}`.
/// Response: `{"v":1,"id":7,"result":{…}}` or `{"v":1,"id":7,"error":{"code","message","hint","exit"}}`.
public enum ControlProtocol {
    public static let name = "skreenrek.control/1"
    public static let version = 1

    /// Every method the app answers.
    public enum Method: String, Sendable, Hashable, CaseIterable {
        case hello
        case windows
        case pick
        case resize
        case recordStart = "record.start"
        case recordStop = "record.stop"
        case recordDiscard = "record.discard"
        case recordWait = "record.wait"
        case status
        case last
        case doctor

        /// Calls that wait for a human or for the recording to end have no client timeout.
        public var waitsIndefinitely: Bool { self == .pick || self == .recordWait }
    }

    /// The hint for a request from a different protocol version.
    public static let mismatchHint = "Quit and reopen Skreenrek so the app and the command match."
}

/// Who sent a request: `{"kind": "cli|mcp|menu", "name": "Claude Code"}`.
public struct ClientInfo: Sendable, Hashable, Codable {
    public var kind: StartedBy
    public var name: String?

    public init(kind: StartedBy, name: String? = nil) {
        self.kind = kind
        self.name = name
    }
}

/// The request envelope without its params.
struct RequestEnvelope: Decodable {
    var v: Int?
    var id: Int?
    var method: String?
    var client: ClientInfo?
}

/// Decodes only `params` from a request line.
struct RequestParams<P: Decodable>: Decodable {
    var params: P?
}

/// What a client sends.
struct OutgoingRequest<P: Encodable>: Encodable {
    var v = ControlProtocol.version
    var id: Int
    var method: String
    var params: P?
    var client: ClientInfo?
}

/// A success response.
struct ResultResponse<R: Encodable>: Encodable {
    var v = ControlProtocol.version
    var id: Int?
    var result: R

    private enum CodingKeys: String, CodingKey { case v, id, result }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(v, forKey: .v)
        try c.encode(id, forKey: .id)
        try c.encode(result, forKey: .result)
    }
}

/// An error response.
struct ErrorResponse: Encodable {
    var v = ControlProtocol.version
    var id: Int?
    var error: ErrorBody

    private enum CodingKeys: String, CodingKey { case v, id, error }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(v, forKey: .v)
        try c.encode(id, forKey: .id)
        try c.encode(error, forKey: .error)
    }
}

/// A response as a client reads it, with the result decoded as `R`.
struct IncomingResponse<R: Decodable>: Decodable {
    var v: Int?
    var id: Int?
    var result: R?
    var error: ErrorBody?
}

/// Params with no fields (`status`, `record.stop`, …).
public struct NoParams: Sendable, Hashable, Codable {
    public init() {}
}

/// `windows`: `{ app? }`.
public struct WindowsParams: Sendable, Hashable, Codable {
    public var app: String?

    public init(app: String? = nil) {
        self.app = app
    }
}

/// `pick`: `{ timeoutSeconds? }` (default 60).
public struct PickParams: Sendable, Hashable, Codable {
    public static let defaultTimeout: TimeInterval = 60

    public var timeoutSeconds: Double?

    public init(timeoutSeconds: Double? = nil) {
        self.timeoutSeconds = timeoutSeconds
    }
}

/// `resize`: `{ windowId | app, title?, width, height, allowInexact? }`. With neither `windowId` nor `app`, the armed
/// window.
public struct ResizeParams: Sendable, Hashable, Codable {
    public var windowId: UInt32?
    public var app: String?
    public var title: String?
    public var width: Int
    public var height: Int
    public var allowInexact: Bool?

    public init(
        windowId: UInt32? = nil, app: String? = nil, title: String? = nil, width: Int, height: Int,
        allowInexact: Bool? = nil
    ) {
        self.windowId = windowId
        self.app = app
        self.title = title
        self.width = width
        self.height = height
        self.allowInexact = allowInexact
    }
}

/// A region in `record.start`: `{ x, y, width, height }` in pixels of the display, top-left origin.
public struct RegionParams: Sendable, Hashable, Codable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var rect: PixelRect { PixelRect(x: x, y: y, width: width, height: height) }
}

/// `record.start`, with the design spec's MCP field names. With no window and no region, the armed target.
public struct StartParams: Sendable, Hashable, Codable {
    public var windowId: UInt32?
    public var app: String?
    public var title: String?
    public var region: RegionParams?
    public var displayId: UInt32?
    /// Resize first to `width` × `height` px.
    public var width: Int?
    public var height: Int?
    public var allowInexact: Bool?
    /// 30 or 60; default from Settings.
    public var fps: Int?
    public var durationSeconds: Double?
    public var cursor: Bool?
    public var events: Bool?
    public var hud: Bool?
    public var outDir: String?
    public var assetsDir: String?
    public var name: String?
    /// `h264` or `hevc`.
    public var codec: String?

    public init(
        windowId: UInt32? = nil, app: String? = nil, title: String? = nil, region: RegionParams? = nil,
        displayId: UInt32? = nil, width: Int? = nil, height: Int? = nil, allowInexact: Bool? = nil, fps: Int? = nil,
        durationSeconds: Double? = nil, cursor: Bool? = nil, events: Bool? = nil, hud: Bool? = nil,
        outDir: String? = nil, assetsDir: String? = nil, name: String? = nil, codec: String? = nil
    ) {
        self.windowId = windowId
        self.app = app
        self.title = title
        self.region = region
        self.displayId = displayId
        self.width = width
        self.height = height
        self.allowInexact = allowInexact
        self.fps = fps
        self.durationSeconds = durationSeconds
        self.cursor = cursor
        self.events = events
        self.hud = hud
        self.outDir = outDir
        self.assetsDir = assetsDir
        self.name = name
        self.codec = codec
    }

    /// The window the params name, if any.
    public var windowQuery: WindowQuery? {
        if let windowId { return .id(WindowID(windowId)) }
        if let app { return .app(name: app, title: title) }
        return nil
    }
}

extension ResizeParams {
    public var windowQuery: WindowQuery? {
        if let windowId { return .id(WindowID(windowId)) }
        if let app { return .app(name: app, title: title) }
        return nil
    }
}
