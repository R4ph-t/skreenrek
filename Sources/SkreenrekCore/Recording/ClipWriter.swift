import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox
import os

/// Writes an MP4 or MOV video track, presentation time exactly `slot / fps`, appending the source's
/// own IOSurface-backed buffers through a pixel buffer adaptor (no pixel copies). `shouldOptimizeForNetworkUse` is off,
/// so finishing never rewrites the file.
///
/// With `EncoderPolicy.requireHardware` it asks VideoToolbox for the hardware encoder and falls back to software
/// (logged, and reported as `encoder: software`) when the writer can't start with it.
public final class ClipWriter: PixelBufferSink, @unchecked Sendable {
    public static let fileName = "clip.mp4"

    public let settings: ClipWriterSettings
    public private(set) var encoder: EncoderKind
    public private(set) var videoReadback: VideoReadback?

    private var writer: AVAssetWriter
    private var input: AVAssetWriterInput
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var appended = 0
    private let makeBackend: BackendFactory
    private let timescale: CMTimeScale
    private static let log = Logger(subsystem: "it.fraime.skreenrek", category: "recorder")

    /// Creates the file and starts the writer, so the first frame appends with no setup left.
    /// Throws `recording_failed` (`The output folder isn't writable.`) when the file can't be written.
    public convenience init(settings: ClipWriterSettings) throws {
        try self.init(settings: settings, makeBackend: Self.start)
    }

    /// A backend seam lets tests reproduce hardware failure after startWriting succeeded.
    typealias BackendFactory = (ClipWriterSettings, Bool) throws -> Started
    init(settings: ClipWriterSettings, makeBackend: @escaping BackendFactory) throws {
        self.settings = settings
        self.makeBackend = makeBackend
        timescale = CMTimeScale(settings.fps.framesPerSecond)
        let started: Started
        switch settings.encoder {
        case .software:
            started = try makeBackend(settings, false)
        case .requireHardware:
            do {
                started = try makeBackend(settings, true)
            } catch {
                Self.log.notice(
                    "Hardware \(settings.codec.rawValue, privacy: .public) encoder unavailable; using software.")
                started = try makeBackend(settings, false)
            }
        }
        writer = started.writer
        input = started.input
        adaptor = started.adaptor
        encoder = started.hardware ? .hardware : .software
    }

    struct Started {
        var writer: AVAssetWriter
        var input: AVAssetWriterInput
        var adaptor: AVAssetWriterInputPixelBufferAdaptor
        var hardware: Bool
    }

    private struct StartFailure: Error {}

    static func start(_ settings: ClipWriterSettings, hardware: Bool) throws -> Started {
        if hardware { try prepareHardware(settings) }
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

    /// Force VideoToolbox's lazy encoder allocation before accepting capture frames. A VM can successfully create
    /// a hardware session but fail to prepare it; that must take the same software fallback as startWriting.
    private static func prepareHardware(_ settings: ClipWriterSettings) throws {
        let output = outputSettings(settings, hardware: true)
        let codec = output[AVVideoCodecKey] as! AVVideoCodecType
        let type: CMVideoCodecType = switch codec {
        case .h264: kCMVideoCodecType_H264
        case .hevc: kCMVideoCodecType_HEVC
        case .proRes422Proxy: kCMVideoCodecType_AppleProRes422Proxy
        case .proRes422LT: kCMVideoCodecType_AppleProRes422LT
        case .proRes422HQ: kCMVideoCodecType_AppleProRes422HQ
        default: kCMVideoCodecType_AppleProRes422
        }
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(allocator: nil, width: Int32(settings.size.width),
            height: Int32(settings.size.height), codecType: type,
            encoderSpecification: [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true] as CFDictionary,
            imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: nil, refcon: nil,
            compressionSessionOut: &session)
        guard status == noErr, let session else { throw StartFailure() }
        defer { VTCompressionSessionInvalidate(session) }
        guard VTCompressionSessionPrepareToEncodeFrames(session) == noErr else { throw StartFailure() }
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
        guard writer.status == .writing else { return false }
        if input.isReadyForMoreMediaData { return true }
        guard !settings.realTime else { return false }
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
            let started = try makeBackend(settings, false)
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
        guard writer.status == .writing else { return false }
        if input.isReadyForMoreMediaData { return true }
        guard timeout.isFinite, timeout > 0 else { return false }
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
        videoReadback = try await VideoReadback.inspect(url: settings.url, settings: settings.output)
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
