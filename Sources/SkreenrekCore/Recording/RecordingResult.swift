import Foundation

/// How a frame source says its stream ended for a reason the recorder reports to the user.
public enum FrameSourceError: Error, Sendable, Hashable {
    /// The captured window went away. The recording stops with a playable partial clip.
    case windowClosed
}

/// Why a recording stopped.
public enum StopReason: Sendable, Hashable {
    /// `stop()` was called.
    case stopped
    /// `options.duration` was reached.
    case duration
    /// The window closed at this clip time (seconds).
    case windowClosed(at: TimeInterval)
    /// Free space fell below 2 GB at this clip time (seconds).
    case diskLow(at: TimeInterval)
    /// The writer failed (the output folder isn't writable).
    case writeFailed
    /// The frame source failed for another reason.
    case sourceFailed(SkreenrekError)
    /// `discard()` was called; the clip folder is gone.
    case discarded

    /// True when the clip holds everything that was asked for.
    public var isComplete: Bool {
        switch self {
        case .stopped, .duration: true
        default: false
        }
    }

    /// The error to report, if this stop is a failure (`recording_failed`, exit 7, unless the source said otherwise).
    public var error: SkreenrekError? {
        switch self {
        case .stopped, .duration, .discarded: nil
        case .windowClosed(let at): .recordingFailed(.windowClosed(at: at))
        case .diskLow(let at): .recordingFailed(.diskLow(at: at))
        case .writeFailed: .recordingFailed(.notWritable)
        case .sourceFailed(let error): error
        }
    }

    /// A stable machine word for logs and JSON.
    public var code: String {
        switch self {
        case .stopped: "stopped"
        case .duration: "duration"
        case .windowClosed: "window_closed"
        case .diskLow: "disk_low"
        case .writeFailed: "write_failed"
        case .sourceFailed: "source_failed"
        case .discarded: "discarded"
        }
    }
}

/// What a finished recording produced. Every stop returns one, including failures (with a partial clip).
public struct RecordingResult: Sendable, Hashable {
    /// The clip folder's name, e.g. `2026-11-17_104207_safari`.
    public var id: String
    /// Seconds of video: frames / fps.
    public var duration: TimeInterval
    public var fps: FrameRate
    public var width: Int
    public var height: Int
    public var codec: VideoCodec
    public var video: VideoReadback
    public var startedAt: Date
    /// Who started it (`startedBy` plus the MCP client name).
    public var origin: RecordingOrigin
    public var folder: URL
    /// False after a failure: the clip is a playable partial clip (or missing when no frame was written).
    public var complete: Bool
    public var stopReason: StopReason
    public var stats: RecordingStats
    /// The host time of the first frame (clip time zero), shared with events.json; nil when no frame arrived.
    public var firstFrameHostTime: TimeInterval?

    public init(
        id: String, duration: TimeInterval, fps: FrameRate, width: Int, height: Int, codec: VideoCodec,
        startedAt: Date, origin: RecordingOrigin, folder: URL, complete: Bool, stopReason: StopReason,
        stats: RecordingStats, firstFrameHostTime: TimeInterval?, video: VideoReadback? = nil
    ) {
        self.id = id
        self.duration = duration
        self.fps = fps
        self.width = width
        self.height = height
        self.codec = video?.codec ?? codec
        self.video = video ?? VideoReadback(width: width, height: height, scale: 1, codec: codec)
        self.startedAt = startedAt
        self.origin = origin
        self.folder = folder
        self.complete = complete
        self.stopReason = stopReason
        self.stats = stats
        self.firstFrameHostTime = firstFrameHostTime
    }

    public var startedBy: StartedBy { origin.startedBy }
    public var size: PixelSize { PixelSize(width: width, height: height) }
    public var clipURL: URL { folder.appendingPathComponent(video.file) }
    /// The error to report for this stop, if it was a failure.
    public var error: SkreenrekError? { stopReason.error }
}
