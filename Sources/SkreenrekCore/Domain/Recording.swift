import Foundation

/// Output frame rate. Only 30 and 60 are offered.
public enum FrameRate: Int, Sendable, Codable, Hashable, CaseIterable {
    case fps30 = 30
    case fps60 = 60
}

/// Output codec.
public enum VideoCodec: String, Sendable, Codable, Hashable, CaseIterable {
    case h264
    case hevc
}

/// What the caller asked for when starting a recording.
public struct RecordingOptions: Sendable, Codable, Hashable {
    public var fps: FrameRate
    /// Show the cursor in the clip.
    public var cursor: Bool
    /// Write `events.json`.
    public var events: Bool
    /// Show the recording HUD.
    public var hud: Bool
    /// Output folder; `nil` means the default (`~/Movies/Skreenrek/`).
    public var outDir: String?
    /// Clip name (slug); `nil` derives it from the app.
    public var name: String?
    /// Assets folder referenced by the HyperFrames snippet.
    public var assetsDir: String?
    public var codec: VideoCodec
    /// Stop after this many seconds; `nil` records until stopped.
    public var duration: TimeInterval?
    /// Record even when the resize wasn't pixel-exact.
    public var allowInexact: Bool

    public init(
        fps: FrameRate = .fps60, cursor: Bool = true, events: Bool = true, hud: Bool = true,
        outDir: String? = nil, name: String? = nil, assetsDir: String? = nil, codec: VideoCodec = .h264,
        duration: TimeInterval? = nil, allowInexact: Bool = false
    ) {
        self.fps = fps
        self.cursor = cursor
        self.events = events
        self.hud = hud
        self.outDir = outDir
        self.name = name
        self.assetsDir = assetsDir
        self.codec = codec
        self.duration = duration
        self.allowInexact = allowInexact
    }
}

/// Who started a recording.
public struct StartedBy: Sendable, Codable, Hashable {
    public enum Source: String, Sendable, Codable, Hashable, CaseIterable {
        case cli
        case mcp
        case menu
    }

    public var source: Source
    /// The client's own name when it gave one (for example an MCP client's name).
    public var client: String?

    public init(_ source: Source, client: String? = nil) {
        self.source = source
        self.client = client
    }
}

/// The controller's state. Raw values are the CLI `status` words.
public enum ControllerState: String, Sendable, Codable, Hashable, CaseIterable {
    case idle
    case armed
    case recording
    case writing
    case error
}

/// Whether the writer must use the hardware H.264 encoder.
public enum EncoderPolicy: String, Sendable, Codable, Hashable {
    case requireHardware
    case software
}

/// Which encoder a recording actually used.
public enum EncoderKind: String, Sendable, Codable, Hashable {
    case hardware
    case software
}

/// Per-recording counters, filled in by the recorder (03) and reported by 04–06.
public struct RecordingStats: Sendable, Codable, Hashable {
    /// Slots written to the file; always `duration × fps`.
    public var slotsWritten: Int
    /// Slots that got a new source frame.
    public var framesFresh: Int
    /// Repeats because the source sent nothing (an idle window, not a fault).
    public var framesRepeatedIdle: Int
    /// Slots that repeated because the writer wasn't ready or a fresh frame came more than one slot late.
    public var framesDropped: Int
    /// Fresh source frames never written (superseded or wrong size).
    public var sourceFramesSkipped: Int
    public var startToFirstFrameMs: Double?
    public var stopToFinalizedMs: Double?
    public var encoder: EncoderKind
    /// FourCC of the pixel format, for example `420v`.
    public var pixelFormat: String

    public init(
        slotsWritten: Int = 0, framesFresh: Int = 0, framesRepeatedIdle: Int = 0, framesDropped: Int = 0,
        sourceFramesSkipped: Int = 0, startToFirstFrameMs: Double? = nil, stopToFinalizedMs: Double? = nil,
        encoder: EncoderKind, pixelFormat: String
    ) {
        self.slotsWritten = slotsWritten
        self.framesFresh = framesFresh
        self.framesRepeatedIdle = framesRepeatedIdle
        self.framesDropped = framesDropped
        self.sourceFramesSkipped = sourceFramesSkipped
        self.startToFirstFrameMs = startToFirstFrameMs
        self.stopToFinalizedMs = stopToFinalizedMs
        self.encoder = encoder
        self.pixelFormat = pixelFormat
    }

    /// Clean means nothing was dropped or skipped.
    public var isClean: Bool { framesDropped == 0 && sourceFramesSkipped == 0 }
}
