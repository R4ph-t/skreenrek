import Foundation
import SkreenrekCore

// The JSON bodies the controller returns. They are the design spec's shapes (CLI `--json` and the MCP tool outputs),
// so the CLI and MCP print them as they are. Optional keys are always present (null when empty), so the shape never
// changes.

/// One window in `windows`: `{id, app, bundleId, title, width, height, unit: "px", displayId, onScreen}`.
public struct WindowEntry: Sendable, Hashable, Codable {
    public var id: WindowID
    public var app: String
    public var bundleId: String?
    public var title: String
    public var width: Int
    public var height: Int
    public var unit: String
    public var displayId: DisplayID
    public var onScreen: Bool

    public init(
        id: WindowID, app: String, bundleId: String?, title: String, width: Int, height: Int, displayId: DisplayID,
        onScreen: Bool
    ) {
        self.id = id
        self.app = app
        self.bundleId = bundleId
        self.title = title
        self.width = width
        self.height = height
        self.unit = "px"
        self.displayId = displayId
        self.onScreen = onScreen
    }

    public init(_ resolved: ResolvedWindow) {
        let size = resolved.pixelSize
        self.init(
            id: resolved.window.id, app: resolved.window.app, bundleId: resolved.window.bundleId,
            title: resolved.window.title, width: size.width, height: size.height, displayId: resolved.display.id,
            onScreen: resolved.window.onScreen)
    }

    private enum CodingKeys: String, CodingKey { case id, app, bundleId, title, width, height, unit, displayId, onScreen }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(app, forKey: .app)
        try c.encode(bundleId, forKey: .bundleId)
        try c.encode(title, forKey: .title)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encode(unit, forKey: .unit)
        try c.encode(displayId, forKey: .displayId)
        try c.encode(onScreen, forKey: .onScreen)
    }
}

/// `windows`: `{ windows: [WindowEntry] }`, front to back.
public struct WindowsBody: Sendable, Hashable, Codable {
    public var windows: [WindowEntry]

    public init(windows: [WindowEntry]) {
        self.windows = windows
    }
}

/// A region the picker returned: `{ region: {x, y, width, height, unit: "px"}, displayId }`.
public struct PickedRegion: Sendable, Hashable, Codable {
    public var region: PixelRect
    public var displayId: DisplayID

    public init(region: PixelRect, displayId: DisplayID) {
        self.region = region
        self.displayId = displayId
    }
}

/// `pick`: the chosen window (a `WindowEntry`), a region, or `{ cancelled: true }`.
public enum PickBody: Sendable, Hashable, Codable {
    case window(WindowEntry)
    case region(PickedRegion)
    case cancelled

    private enum CodingKeys: String, CodingKey { case cancelled, region }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if try c.decodeIfPresent(Bool.self, forKey: .cancelled) == true {
            self = .cancelled
        } else if c.contains(.region) {
            self = .region(try PickedRegion(from: decoder))
        } else {
            self = .window(try WindowEntry(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .window(let entry): try entry.encode(to: encoder)
        case .region(let region): try region.encode(to: encoder)
        case .cancelled:
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(true, forKey: .cancelled)
        }
    }
}

/// `record.start`: `{ recordingId, startedAt, readback, fps }`. `readback` is null when no size was asked for.
public struct StartBody: Sendable, Hashable, Codable {
    /// The clip folder name, e.g. `2026-11-17_104207_safari`.
    public var recordingId: String
    /// ISO 8601 local time with milliseconds and offset, as in events.json.
    public var startedAt: String
    public var readback: Readback?
    public var fps: Int
    public var video: OutputSettings

    public init(recordingId: String, startedAt: String, readback: Readback?, fps: Int,
        video: OutputSettings = .defaults) {
        self.recordingId = recordingId
        self.startedAt = startedAt
        self.readback = readback
        self.fps = fps
        self.video = video
    }

    private enum CodingKeys: String, CodingKey { case recordingId, startedAt, readback, fps, video }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(recordingId, forKey: .recordingId)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(readback, forKey: .readback)
        try c.encode(fps, forKey: .fps)
        try c.encode(video, forKey: .video)
    }
}

/// `record.stop`, `record.wait` and `last`: the design spec's `stop --json` shape plus 03's `stats`:
/// `{ recording: {id, duration, fps, width, height, codec, startedAt, startedBy, stats}, files: {clip, events,
/// snippet}, snippet, readback }`.
public struct StopBody: Sendable, Hashable, Codable {
    public struct Recording: Sendable, Hashable, Codable {
        public var id: String
        public var duration: Double
        public var fps: Int
        public var width: Int
        public var height: Int
        public var codec: VideoCodec
        public var video: VideoReadback
        public var startedAt: String
        public var startedBy: StartedBy
        public var stats: RecordingStats

        public init(
            id: String, duration: Double, fps: Int, width: Int, height: Int, codec: VideoCodec, startedAt: String,
            startedBy: StartedBy, stats: RecordingStats, video: VideoReadback? = nil
        ) {
            self.id = id
            self.duration = duration
            self.fps = fps
            self.width = width
            self.height = height
            self.codec = video?.codec ?? codec
            self.video = video ?? VideoReadback(width: width, height: height, scale: 1, codec: codec)
            self.startedAt = startedAt
            self.startedBy = startedBy
            self.stats = stats
        }
    }

    /// Absolute paths. `events` is null when events were off.
    public struct Files: Sendable, Hashable, Codable {
        public var clip: String
        public var events: String?
        public var snippet: String

        public init(clip: String, events: String?, snippet: String) {
            self.clip = clip
            self.events = events
            self.snippet = snippet
        }

        private enum CodingKeys: String, CodingKey { case clip, events, snippet }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(clip, forKey: .clip)
            try c.encode(events, forKey: .events)
            try c.encode(snippet, forKey: .snippet)
        }
    }

    public var recording: Recording
    public var files: Files
    /// The `hyperframes.html` text.
    public var snippet: String
    /// The read-back from the resize at start, or null when the recording didn't resize.
    public var readback: Readback?

    public init(recording: Recording, files: Files, snippet: String, readback: Readback?) {
        self.recording = recording
        self.files = files
        self.snippet = snippet
        self.readback = readback
    }

    private enum CodingKeys: String, CodingKey { case recording, files, snippet, readback }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(recording, forKey: .recording)
        try c.encode(files, forKey: .files)
        try c.encode(snippet, forKey: .snippet)
        try c.encode(readback, forKey: .readback)
    }
}

/// `record.wait`: the stop body, or `{ discarded: true }` when the recording was discarded.
public enum EndBody: Sendable, Hashable, Codable {
    case saved(StopBody)
    case discarded

    public init(from decoder: any Decoder) throws {
        if let discard = try? DiscardBody(from: decoder), discard.discarded {
            self = .discarded
        } else {
            self = .saved(try StopBody(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .saved(let body): try body.encode(to: encoder)
        case .discarded: try DiscardBody().encode(to: encoder)
        }
    }
}

/// `record.discard`: `{ discarded: true }`.
public struct DiscardBody: Sendable, Hashable, Codable {
    public var discarded: Bool

    public init(discarded: Bool = true) {
        self.discarded = discarded
    }
}

/// `status`: `{ state, window, readback, recording, lastClip, error }`.
public struct StatusBody: Sendable, Hashable, Codable {
    /// The recording in progress.
    public struct Recording: Sendable, Hashable, Codable {
        public var id: String
        /// Seconds since the recording started, 3 decimals.
        public var elapsed: Double
        public var fps: Int
        public var width: Int
        public var height: Int
        public var startedAt: String
        public var startedBy: StartedBy
        /// The MCP client name (e.g. "Claude Code"); null for the CLI and the menu.
        public var client: String?

        public init(
            id: String, elapsed: Double, fps: Int, width: Int, height: Int, startedAt: String, startedBy: StartedBy,
            client: String?
        ) {
            self.id = id
            self.elapsed = elapsed
            self.fps = fps
            self.width = width
            self.height = height
            self.startedAt = startedAt
            self.startedBy = startedBy
            self.client = client
        }

        private enum CodingKeys: String, CodingKey { case id, elapsed, fps, width, height, startedAt, startedBy, client }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(elapsed, forKey: .elapsed)
            try c.encode(fps, forKey: .fps)
            try c.encode(width, forKey: .width)
            try c.encode(height, forKey: .height)
            try c.encode(startedAt, forKey: .startedAt)
            try c.encode(startedBy, forKey: .startedBy)
            try c.encode(client, forKey: .client)
        }
    }

    /// `idle | armed | recording | writing | error`.
    public var state: ControllerState
    /// The armed or recorded window.
    public var window: WindowEntry?
    /// The armed window's last read-back.
    public var readback: Readback?
    public var recording: Recording?
    public var lastClip: StopBody?
    /// The failure the error state holds.
    public var error: ErrorBody?

    public init(
        state: ControllerState, window: WindowEntry?, readback: Readback?, recording: Recording?, lastClip: StopBody?,
        error: ErrorBody?
    ) {
        self.state = state
        self.window = window
        self.readback = readback
        self.recording = recording
        self.lastClip = lastClip
        self.error = error
    }

    private enum CodingKeys: String, CodingKey { case state, window, readback, recording, lastClip, error }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(state, forKey: .state)
        try c.encode(window, forKey: .window)
        try c.encode(readback, forKey: .readback)
        try c.encode(recording, forKey: .recording)
        try c.encode(lastClip, forKey: .lastClip)
        try c.encode(error, forKey: .error)
    }
}

/// `doctor`: permissions, version, the output folder and the socket path.
public struct DoctorBody: Sendable, Hashable, Codable {
    public struct Permissions: Sendable, Hashable, Codable {
        public var screenRecording: PermissionStatus
        public var accessibility: PermissionStatus

        public init(screenRecording: PermissionStatus, accessibility: PermissionStatus) {
            self.screenRecording = screenRecording
            self.accessibility = accessibility
        }
    }

    public struct OutputFolder: Sendable, Hashable, Codable {
        public var path: String
        /// The folder can be written, or created where it doesn't exist yet.
        public var writable: Bool

        public init(path: String, writable: Bool) {
            self.path = path
            self.writable = writable
        }
    }

    public var version: String
    public var permissions: Permissions
    public var outputFolder: OutputFolder
    /// The control socket's path, or null when the controller runs without a server.
    public var socket: String?

    public init(version: String, permissions: Permissions, outputFolder: OutputFolder, socket: String?) {
        self.version = version
        self.permissions = permissions
        self.outputFolder = outputFolder
        self.socket = socket
    }

    private enum CodingKeys: String, CodingKey { case version, permissions, outputFolder, socket }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(permissions, forKey: .permissions)
        try c.encode(outputFolder, forKey: .outputFolder)
        try c.encode(socket, forKey: .socket)
    }
}

/// `hello`: `{ version, protocol: 1, pid }`.
public struct HelloBody: Sendable, Hashable, Codable {
    public var version: String
    public var `protocol`: Int
    public var pid: Int32

    public init(version: String = SkreenrekVersion.current, protocol: Int = ControlProtocol.version, pid: Int32) {
        self.version = version
        self.protocol = `protocol`
        self.pid = pid
    }
}
