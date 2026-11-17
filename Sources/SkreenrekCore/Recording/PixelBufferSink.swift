import CoreVideo
import Foundation

/// Where the recorder appends slots. Real: `ClipWriter` (AVAssetWriter through a pixel buffer adaptor). Tests: a
/// recording sink (checks buffer identity) or a no-op sink (measures the pipeline without an encoder).
///
/// The recorder only calls a sink from its own actor, one call at a time.
public protocol PixelBufferSink: AnyObject, Sendable {
    /// The encoder actually in use.
    var encoder: EncoderKind { get }
    /// Whether `append` can take a buffer now. Never blocks in real-time mode.
    var isReady: Bool { get }
    /// Appends the source's own buffer (no copy) as slot `slot`: presentation time `slot / fps`.
    /// Returns false when the writer failed.
    func append(_ pixelBuffer: CVPixelBuffer, slot: Int) -> Bool
    /// Waits until `isReady` or the timeout passes. Used only when finishing, to append owed repeats.
    func waitUntilReady(timeout: TimeInterval) async -> Bool
    /// Ends the clip after `slotCount` slots and closes the file.
    func finish(slotCount: Int) async throws
    /// Abandons the clip and deletes the file.
    func cancel() async
}

/// Settings for one clip file.
public struct ClipWriterSettings: Sendable, Hashable {
    public var url: URL
    public var size: PixelSize
    public var fps: FrameRate
    public var codec: VideoCodec
    public var encoder: EncoderPolicy
    /// True for live capture: `isReady` never blocks, and a slot that finds the input busy repeats instead.
    /// False for offline writing (tests): `isReady` waits for the encoder, so every slot gets its own frame.
    public var realTime: Bool

    public init(
        url: URL, size: PixelSize, fps: FrameRate, codec: VideoCodec = .h264, encoder: EncoderPolicy = .requireHardware,
        realTime: Bool = true
    ) {
        self.url = url
        self.size = size
        self.fps = fps
        self.codec = codec
        self.encoder = encoder
        self.realTime = realTime
    }

    /// Bits per pixel per frame for the average bit rate.
    public static let bitsPerPixelPerFrame = 0.08
    public static let minimumBitRate = 4_000_000
    public static let maximumBitRate = 80_000_000
    /// Seconds between keyframes, at most.
    public static let keyframeInterval = 2

    /// `width × height × fps × 0.08` bits/s, clamped to 4–80 Mbit/s.
    public static func averageBitRate(size: PixelSize, fps: FrameRate) -> Int {
        let raw = Double(size.width) * Double(size.height) * Double(fps.framesPerSecond) * bitsPerPixelPerFrame
        return min(max(Int(raw.rounded()), minimumBitRate), maximumBitRate)
    }

    public var averageBitRate: Int { Self.averageBitRate(size: size, fps: fps) }
}
