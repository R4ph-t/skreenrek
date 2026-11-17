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
    public private(set) var encoder: EncoderKind

    private var writer: AVAssetWriter
    private var input: AVAssetWriterInput
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var appended = 0
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
            writer = try AVAssetWriter(outputURL: settings.url, fileType: settings.output.container == .mp4 ? .mp4 : .mov)
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
        case .prores: compression = [:]
        }
        let codec: AVVideoCodecType = switch settings.codec {
        case .h264: .h264
        case .hevc: .hevc
        case .prores:
            switch settings.output.quality ?? .high {
            case .low: .proRes422Proxy; case .medium: .proRes422LT; case .high: .proRes422; case .max: .proRes422HQ
            }
        }
        let specification: [String: Any] =
            hardware
            ? [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true]
            : [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: false]
        return [
            AVVideoCodecKey: codec,
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
        if writer.status == .failed { _ = fallbackBeforeFirstSample() }
        if input.isReadyForMoreMediaData { return true }
        guard !settings.realTime, writer.status == .writing else { return false }
        return waitBlocking(timeout: 10)
    }

    public func append(_ pixelBuffer: CVPixelBuffer, slot: Int) -> Bool {
        let time = CMTime(value: CMTimeValue(slot), timescale: timescale)
        var success = writer.status == .writing && adaptor.append(pixelBuffer, withPresentationTime: time)
        if !success, fallbackBeforeFirstSample() {
            success = adaptor.append(pixelBuffer, withPresentationTime: time)
        }
        if success { appended += 1 }
        return success
    }

    /// VideoToolbox may accept startWriting, then reject the hardware session at the first append.
    /// Retry that same source buffer and timestamp once; never buffer or replay a recording in memory.
    private func fallbackBeforeFirstSample() -> Bool {
        guard encoder == .hardware, appended == 0 else { return false }
        writer.cancelWriting()
        do {
            let started = try Self.start(settings, hardware: false)
            writer = started.writer
            input = started.input
            adaptor = started.adaptor
            encoder = .software
            Self.log.notice("Hardware encoder failed before its first sample; using software.")
            return true
        } catch { return false }
    }

    public func waitUntilReady(timeout: TimeInterval) async -> Bool {
        if writer.status == .failed { _ = fallbackBeforeFirstSample() }
        if input.isReadyForMoreMediaData { return true }
        guard writer.status == .writing, timeout > 0 else { return false }
        let waiter = ReadyWaiter(input: input, writer: writer)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { waiter.start($0, timeout: timeout) }
        } onCancel: { waiter.complete(false) }
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

/// KVO plus a deadline, with exactly one continuation resume even on cancellation/timeout races.
private final class ReadyWaiter: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private let input: AVAssetWriterInput
    private let writer: AVAssetWriter
    private var continuation: CheckedContinuation<Bool, Never>?
    private var observations: [NSKeyValueObservation] = []
    private var finished: Bool?
    init(input: AVAssetWriterInput, writer: AVAssetWriter) { self.input = input; self.writer = writer }
    func start(_ continuation: CheckedContinuation<Bool, Never>, timeout: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        if let finished { continuation.resume(returning: finished); return }
        self.continuation = continuation
        observations = [
            input.observe(\.isReadyForMoreMediaData, options: [.new]) { [weak self] _, _ in self?.check() },
            writer.observe(\.status, options: [.new]) { [weak self] _, _ in self?.check() },
        ]
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in self?.complete(false) }
        check()
    }
    private func check() {
        if writer.status != .writing { complete(false) }
        else if input.isReadyForMoreMediaData { complete(true) }
    }
    func complete(_ value: Bool) {
        lock.lock()
        guard finished == nil else { lock.unlock(); return }
        finished = value
        let continuation = continuation
        self.continuation = nil
        observations.removeAll()
        lock.unlock()
        continuation?.resume(returning: value)
    }
}
