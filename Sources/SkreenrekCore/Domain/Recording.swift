import Foundation

/// Frames per second. Only 30 and 60 are offered.
public enum FrameRate: Int, Sendable, Hashable, Codable, CaseIterable {
    case fps30 = 30
    case fps60 = 60

    public var framesPerSecond: Int { rawValue }
}

public enum VideoCodec: String, Sendable, Hashable, Codable, CaseIterable {
    case h264
    case hevc
}

/// Options for one recording. Defaults: 60 fps, cursor, click events and HUD on, H.264, no duration, exact size.
public struct RecordingOptions: Sendable, Hashable, Codable {
    public var fps: FrameRate
    public var cursor: Bool
    public var events: Bool
    public var hud: Bool
    /// The parent folder for the clip folder; nil means the default (`~/Movies/Skreenrek/` or Settings).
    public var outDir: URL?
    /// Overrides the app slug in the clip folder name.
    public var name: String?
    /// A HyperFrames project's assets folder to copy the clip into.
    public var assetsDir: URL?
    public var codec: VideoCodec
    /// Auto-stop after this many seconds; nil records until stopped.
    public var duration: TimeInterval?
    public var allowInexact: Bool

    public init(
        fps: FrameRate = .fps60, cursor: Bool = true, events: Bool = true, hud: Bool = true, outDir: URL? = nil,
        name: String? = nil, assetsDir: URL? = nil, codec: VideoCodec = .h264, duration: TimeInterval? = nil,
        allowInexact: Bool = false
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

/// Which surface started a recording.
public enum StartedBy: String, Sendable, Hashable, Codable, CaseIterable {
    case cli
    case mcp
    case menu
}

/// Who started a recording: the surface plus, for MCP, the client name from `initialize` (e.g. "Claude Code").
public struct RecordingOrigin: Sendable, Hashable, Codable {
    public var startedBy: StartedBy
    public var client: String?

    public init(startedBy: StartedBy, client: String? = nil) {
        self.startedBy = startedBy
        self.client = client
    }
}

/// The controller's state. Raw values are the CLI `status` words.
public enum ControllerState: String, Sendable, Hashable, Codable, CaseIterable {
    case idle
    case armed
    case recording
    case writing
    case error
}

/// Which H.264/HEVC encoder the writer asks for. The app uses `.requireHardware`; tests on CI use `.software`.
public enum EncoderPolicy: String, Sendable, Hashable, Codable, CaseIterable {
    case requireHardware
    case software
}

/// The encoder a recording actually used.
public enum EncoderKind: String, Sendable, Hashable, Codable, CaseIterable {
    case hardware
    case software
}

/// Measured numbers for one recording, filled in by the recorder and reported with the result.
public struct RecordingStats: Sendable, Hashable, Codable {
    /// Every slot written; always `duration × fps`.
    public var slotsWritten: Int
    /// Slots that got a new source frame.
    public var framesFresh: Int
    /// Repeats because the source sent nothing (an idle window, not a fault).
    public var framesRepeatedIdle: Int
    /// Slots repeated because the writer wasn't ready, or because a fresh frame arrived more than one slot late.
    public var framesDropped: Int
    /// Fresh source frames never written (superseded or wrong size).
    public var sourceFramesSkipped: Int
    /// From the start call to the first frame appended.
    public var startToFirstFrameMs: Double?
    /// From the stop request to the file being closed.
    public var stopToFinalizedMs: Double?
    public var encoder: EncoderKind
    /// The source pixel format as a four-character code, e.g. `420v`.
    public var pixelFormat: String

    public init(
        slotsWritten: Int = 0, framesFresh: Int = 0, framesRepeatedIdle: Int = 0, framesDropped: Int = 0,
        sourceFramesSkipped: Int = 0, startToFirstFrameMs: Double? = nil, stopToFinalizedMs: Double? = nil,
        encoder: EncoderKind, pixelFormat: String = "420v"
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

    /// A recording is clean when no slot was dropped and no fresh source frame was skipped.
    public var isClean: Bool { framesDropped == 0 && sourceFramesSkipped == 0 }
}
