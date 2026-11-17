import Foundation

/// `events.json`: the design spec's `skreenrek.events/1` schema, plus `recording.stats` (03's `RecordingStats`).
///
/// Everything is in video pixels, top-left origin, with `t` in seconds from the first video frame. There is no
/// keystroke, scroll or modifier field of any kind.
public struct EventsFile: Sendable, Hashable, Codable {
    public static let schemaID = "skreenrek.events/1"
    public static let fileName = "events.json"

    public var schema: String
    public var complete: Bool
    public var recording: Recording
    public var coordinates: Coordinates
    public var cursor: Cursor
    public var events: [Event]
    public var clicks: [Click]

    public init(
        schema: String = EventsFile.schemaID, complete: Bool, recording: Recording,
        coordinates: Coordinates = Coordinates(), cursor: Cursor, events: [Event], clicks: [Click]
    ) {
        self.schema = schema
        self.complete = complete
        self.recording = recording
        self.coordinates = coordinates
        self.cursor = cursor
        self.events = events
        self.clicks = clicks
    }

    /// Builds the file from a finished recording and its event log. `clicks` is derived from the `down` events.
    public init(recording: Recording, complete: Bool, log: EventLog) {
        self.init(
            complete: complete, recording: recording,
            cursor: Cursor(sampleRate: recording.fps, samples: log.samples), events: log.events,
            clicks: Click.derive(from: log.events, width: recording.video.width, height: recording.video.height))
    }

    // MARK: - recording

    public struct Recording: Sendable, Hashable, Codable {
        /// The clip folder name, e.g. `2026-11-17_104207_safari`.
        public var id: String
        /// ISO 8601, local time with its offset and milliseconds (see `EventsFile.timestamp`).
        public var startedAt: String
        public var duration: Double
        public var fps: Int
        public var video: Video
        public var source: Source
        public var startedBy: StartedBy
        /// The MCP client name (e.g. "Claude Code"); null for the CLI and the menu.
        public var client: String?
        public var stats: RecordingStats

        public init(
            id: String, startedAt: String, duration: Double, fps: Int, video: Video, source: Source,
            startedBy: StartedBy, client: String?, stats: RecordingStats
        ) {
            self.id = id
            self.startedAt = startedAt
            self.duration = duration
            self.fps = fps
            self.video = video
            self.source = source
            self.startedBy = startedBy
            self.client = client
            self.stats = stats
        }

        private enum CodingKeys: String, CodingKey {
            case id, startedAt, duration, fps, video, source, startedBy, client, stats
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            startedAt = try c.decode(String.self, forKey: .startedAt)
            duration = try c.decode(Double.self, forKey: .duration)
            fps = try c.decode(Int.self, forKey: .fps)
            video = try c.decode(Video.self, forKey: .video)
            source = try c.decode(Source.self, forKey: .source)
            startedBy = try c.decode(StartedBy.self, forKey: .startedBy)
            client = try c.decodeIfPresent(String.self, forKey: .client)
            stats = try c.decode(RecordingStats.self, forKey: .stats)
        }

        /// `client` is always present (null when there is none), so readers never need to probe for the key.
        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(startedAt, forKey: .startedAt)
            try c.encode(duration, forKey: .duration)
            try c.encode(fps, forKey: .fps)
            try c.encode(video, forKey: .video)
            try c.encode(source, forKey: .source)
            try c.encode(startedBy, forKey: .startedBy)
            try c.encode(client, forKey: .client)
            try c.encode(stats, forKey: .stats)
        }
    }

    public typealias Video = VideoReadback

    /// `{kind: "window", app, bundleId, title, windowId, frame}` or `{kind: "region", displayId, rect}`.
    public enum Source: Sendable, Hashable, Codable {
        case window(app: String, bundleId: String?, title: String, windowId: WindowID, frame: PointRect)
        case region(displayId: DisplayID, rect: PixelRect)

        public init(target: CaptureTarget) {
            switch target {
            case .window(let w):
                self = .window(app: w.app, bundleId: w.bundleId, title: w.title, windowId: w.id, frame: w.frame)
            case .region(let rect, let displayId):
                self = .region(displayId: displayId, rect: rect)
            }
        }

        private enum CodingKeys: String, CodingKey { case kind, app, bundleId, title, windowId, frame, displayId, rect }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try c.decode(String.self, forKey: .kind)
            switch kind {
            case "window":
                self = .window(
                    app: try c.decode(String.self, forKey: .app),
                    bundleId: try c.decodeIfPresent(String.self, forKey: .bundleId),
                    title: try c.decode(String.self, forKey: .title),
                    windowId: try c.decode(WindowID.self, forKey: .windowId),
                    frame: try c.decode(PointRect.self, forKey: .frame))
            case "region":
                self = .region(
                    displayId: try c.decode(DisplayID.self, forKey: .displayId),
                    rect: try c.decode(PixelRect.self, forKey: .rect))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .kind, in: c, debugDescription: "Unknown source kind \"\(kind)\"")
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .window(let app, let bundleId, let title, let windowId, let frame):
                try c.encode("window", forKey: .kind)
                try c.encode(app, forKey: .app)
                try c.encode(bundleId, forKey: .bundleId)
                try c.encode(title, forKey: .title)
                try c.encode(windowId, forKey: .windowId)
                try c.encode(frame, forKey: .frame)
            case .region(let displayId, let rect):
                try c.encode("region", forKey: .kind)
                try c.encode(displayId, forKey: .displayId)
                try c.encode(rect, forKey: .rect)
            }
        }
    }

    // MARK: - coordinates, cursor, events, clicks

    public struct Coordinates: Sendable, Hashable, Codable {
        public var unit: String
        public var origin: String
        public var space: String

        public init(unit: String = "px", origin: String = "top-left", space: String = "video") {
            self.unit = unit
            self.origin = origin
            self.space = space
        }
    }

    public struct Cursor: Sendable, Hashable, Codable {
        /// Samples per second: the clip fps.
        public var sampleRate: Int
        public var samples: [CursorSample]

        public init(sampleRate: Int, samples: [CursorSample]) {
            self.sampleRate = sampleRate
            self.samples = samples
        }
    }

    public struct Event: Sendable, Hashable, Codable {
        public var t: Double
        public var type: MouseEventType
        public var button: MouseButton
        public var clickCount: Int
        public var x: Int
        public var y: Int

        public init(t: Double, type: MouseEventType, button: MouseButton, clickCount: Int, x: Int, y: Int) {
            self.t = t
            self.type = type
            self.button = button
            self.clickCount = clickCount
            self.x = x
            self.y = y
        }
    }

    public struct Click: Sendable, Hashable, Codable {
        public var t: Double
        public var button: MouseButton
        public var x: Int
        public var y: Int
        /// x / width × 100, one decimal: how HyperFrames' Zoom Follow Cursor takes click points.
        public var xPct: Double
        public var yPct: Double

        public init(t: Double, button: MouseButton, x: Int, y: Int, xPct: Double, yPct: Double) {
            self.t = t
            self.button = button
            self.x = x
            self.y = y
            self.xPct = xPct
            self.yPct = yPct
        }

        /// One click per `down` event, with percentages of the video size rounded to one decimal.
        public static func derive(from events: [Event], width: Int, height: Int) -> [Click] {
            events.filter { $0.type == .down }.map { e in
                Click(
                    t: e.t, button: e.button, x: e.x, y: e.y,
                    xPct: percent(e.x, of: width), yPct: percent(e.y, of: height))
            }
        }

        static func percent(_ value: Int, of total: Int) -> Double {
            guard total > 0 else { return 0 }
            return (Double(value) / Double(total) * 1000).rounded() / 10
        }
    }

    // MARK: - writing

    /// Encodes with the shared settings (sorted keys, unescaped slashes) plus a trailing newline.
    public func data() throws -> Data {
        var data = try SkreenrekJSON.encode(self)
        data.append(0x0A)
        return data
    }

    /// Writes `events.json` into `folder` atomically (a temp file, then a rename) and returns its URL.
    @discardableResult
    public func write(to folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(Self.fileName)
        try data().write(to: url, options: .atomic)
        return url
    }

    /// `2026-11-17T10:42:07.120+01:00`: local time, milliseconds and the offset (never `Z`).
    public static func timestamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSxxx"
        return formatter.string(from: date)
    }
}

/// `left` for button index 0, `right` 1, `middle` 2, `other` above.
public enum MouseButton: String, Sendable, Hashable, Codable, CaseIterable {
    case left
    case right
    case middle
    case other

    public init(index: Int) {
        switch index {
        case 0: self = .left
        case 1: self = .right
        case 2: self = .middle
        default: self = .other
        }
    }
}

/// One cursor sample. Encodes as a `[t, x, y]` array to keep the file small.
public struct CursorSample: Sendable, Hashable, Codable {
    public var t: Double
    public var x: Int
    public var y: Int

    public init(t: Double, x: Int, y: Int) {
        self.t = t
        self.x = x
        self.y = y
    }

    public init(from decoder: any Decoder) throws {
        var c = try decoder.unkeyedContainer()
        t = try c.decode(Double.self)
        x = try c.decode(Int.self)
        y = try c.decode(Int.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(t)
        try c.encode(x)
        try c.encode(y)
    }
}
