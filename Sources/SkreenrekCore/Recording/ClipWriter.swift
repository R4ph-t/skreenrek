import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox
import os

/// Writes `clip.mp4`: one H.264 (or HEVC) video track, presentation time exactly `slot / fps`, appending the source's
/// own IOSurface-backed buffers through a pixel buffer adaptor (no pixel copies). `shouldOptimizeForNetworkUse` is off,
/// so finishing never rewrites the file.
///
/// With `EncoderPolicy.requireHardware` it asks VideoToolbox for the hardware encoder and falls back to software
/// (logged, and reported as `encoder: software`) when the writer can't start with it.
public final class ClipWriter: PixelBufferSink, @unchecked Sendable {
    public static let fileName = "clip.mp4"

    public let settings: ClipWriterSettings
    public let encoder: EncoderKind

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let timescale: CMTimeScale
    private static let log = Logger(subsystem: "it.fraime.skreenrek", category: "recorder")

    /// Creates the file and starts the writer, so the first frame appends with no setup left.
    /// Throws `recording_failed` (`The output folder isn't writable.`) when the file can't be written.
    public init(settings: ClipWriterSettings) throws {
        self.settings = settings
        timescale = CMTimeScale(settings.fps.framesPerSecond)
        let started: Started
        switch settings.encoder {
        case .software:
            started = try Self.start(settings, hardware: false)
        case .requireHardware:
            do {
                started = try Self.start(settings, hardware: true)
            } catch {
                Self.log.notice(
                    "Hardware \(settings.codec.rawValue, privacy: .public) encoder unavailable; using software.")
                started = try Self.start(settings, hardware: false)
            }
        }
        writer = started.writer
        input = started.input
        adaptor = started.adaptor
        encoder = started.hardware ? .hardware : .software
    }

    private struct Started {
        var writer: AVAssetWriter
        var input: AVAssetWriterInput
        var adaptor: AVAssetWriterInputPixelBufferAdaptor
        var hardware: Bool
    }

    private struct StartFailure: Error {}

    private static func start(_ settings: ClipWriterSettings, hardware: Bool) throws -> Started {
        try? FileManager.default.removeItem(at: settings.url)
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: settings.url, fileType: .mp4)
        } catch {
            throw SkreenrekError.recordingFailed(.notWritable)
        }
        writer.shouldOptimizeForNetworkUse = false
        let outputSettings = Self.outputSettings(settings, hardware: hardware)
        guard writer.canApply(outputSettings: outputSettings, forMediaType: .video) else { throw StartFailure() }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = settings.realTime
        guard writer.canAdd(input) else { throw StartFailure() }
        writer.add(input)
        // No source attributes: the adaptor would allocate a buffer pool we never use.
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.startWriting() else {
            let directory = settings.url.deletingLastPathComponent().path
            try? FileManager.default.removeItem(at: settings.url)
            if !FileManager.default.isWritableFile(atPath: directory) {
                throw SkreenrekError.recordingFailed(.notWritable)
            }
            throw StartFailure()
        }
        writer.startSession(atSourceTime: .zero)
        return Started(writer: writer, input: input, adaptor: adaptor, hardware: hardware)
    }

    /// The writer input's output settings: codec, size, profile, average bit rate, keyframe interval, Rec. 709
    /// colour, and the encoder specification (hardware required, or hardware off).
    public static func outputSettings(_ settings: ClipWriterSettings, hardware: Bool) -> [String: Any] {
        let fps = settings.fps.framesPerSecond
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: settings.averageBitRate,
            AVVideoMaxKeyFrameIntervalKey: fps * ClipWriterSettings.keyframeInterval,
            AVVideoMaxKeyFrameIntervalDurationKey: ClipWriterSettings.keyframeInterval,
            AVVideoExpectedSourceFrameRateKey: fps,
            AVVideoAllowFrameReorderingKey: false,
        ]
        switch settings.codec {
        case .h264: compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        case .hevc: compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main_AutoLevel as String
        }
        let specification: [String: Any] =
            hardware
            ? [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true]
            : [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: false]
        return [
            AVVideoCodecKey: settings.codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: settings.size.width,
            AVVideoHeightKey: settings.size.height,
            AVVideoCompressionPropertiesKey: compression,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoEncoderSpecificationKey: specification,
        ]
    }

    // MARK: - PixelBufferSink

    public var isReady: Bool {
        if input.isReadyForMoreMediaData { return true }
        guard !settings.realTime, writer.status == .writing else { return false }
        return waitBlocking(timeout: 10)
    }

    public func append(_ pixelBuffer: CVPixelBuffer, slot: Int) -> Bool {
        guard writer.status == .writing else { return false }
        return adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(slot), timescale: timescale))
    }

    public func waitUntilReady(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !input.isReadyForMoreMediaData {
            guard writer.status == .writing, Date() < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return true
    }

    public func finish(slotCount: Int) async throws {
        guard writer.status == .writing else { throw writer.error ?? SkreenrekError.recordingFailed(.notWritable) }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(slotCount), timescale: timescale))
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? SkreenrekError.recordingFailed(.notWritable)
        }
    }

    public func cancel() async {
        if writer.status == .writing { writer.cancelWriting() }
        try? FileManager.default.removeItem(at: settings.url)
    }

    /// Offline mode only: blocks until the input is ready again (key-value observed), or the timeout passes.
    private func waitBlocking(timeout: TimeInterval) -> Bool {
        let ready = DispatchSemaphore(value: 0)
        let observation = input.observe(\.isReadyForMoreMediaData, options: [.new]) { input, _ in
            if input.isReadyForMoreMediaData { ready.signal() }
        }
        defer { observation.invalidate() }
        if input.isReadyForMoreMediaData { return true }
        _ = ready.wait(timeout: .now() + timeout)
        return input.isReadyForMoreMediaData
    }
}
