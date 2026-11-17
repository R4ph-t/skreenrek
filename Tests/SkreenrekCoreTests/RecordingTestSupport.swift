import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import SkreenrekCore
import SkreenrekTesting
import Synchronization
import Testing

/// A temporary folder removed by `cleanUp()`.
struct TempFolder {
    let url: URL

    init(_ label: String = "recording") throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("skreenrek-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// A fresh clip folder inside, as `OutputFolder.create` would make.
    func clipFolder(_ name: String = "clip") throws -> URL {
        let folder = url.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func cleanUp() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        try? FileManager.default.removeItem(at: url)
    }
}

/// Builds `CapturedFrame`s for scheduler tests: small IOSurface-backed `420v` buffers.
enum TestFrames {
    static func buffer(_ size: PixelSize) -> CVPixelBuffer {
        let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()]
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            nil, size.width, size.height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            attributes as CFDictionary, &buffer)
        precondition(status == kCVReturnSuccess)
        return buffer!
    }

    static func frame(_ size: PixelSize, at hostTime: TimeInterval) -> CapturedFrame {
        CapturedFrame(pixelBuffer: buffer(size), hostTime: hostTime)
    }
}

/// A sink that keeps every appended buffer (to check identity) and can say "not ready" or fail on chosen calls.
final class RecordingSink: PixelBufferSink, @unchecked Sendable {
    struct Appended {
        var slot: Int
        var frame: CapturedFrame
    }

    private struct State {
        var appended: [Appended] = []
        var finishedSlotCount: Int?
        var cancelled = false
    }

    private let state = Mutex(State())
    let encoder: EncoderKind = .software
    var isReady: Bool { true }

    var appended: [Appended] { state.withLock { $0.appended } }
    var finishedSlotCount: Int? { state.withLock { $0.finishedSlotCount } }
    var cancelled: Bool { state.withLock { $0.cancelled } }

    func append(_ pixelBuffer: CVPixelBuffer, slot: Int) -> Bool {
        let frame = CapturedFrame(pixelBuffer: pixelBuffer, hostTime: 0)
        state.withLock { $0.appended.append(Appended(slot: slot, frame: frame)) }
        return true
    }

    func waitUntilReady(timeout: TimeInterval) async -> Bool { true }

    func finish(slotCount: Int) async throws {
        state.withLock { $0.finishedSlotCount = slotCount }
    }

    func cancel() async {
        state.withLock { $0.cancelled = true }
    }
}

/// A sink that does nothing, so a perf test measures the pipeline and not the encoder.
final class NoOpSink: PixelBufferSink, @unchecked Sendable {
    private let count = Mutex(0)
    let encoder: EncoderKind = .software
    var isReady: Bool { true }
    var appendCount: Int { count.withLock { $0 } }

    func append(_ pixelBuffer: CVPixelBuffer, slot: Int) -> Bool {
        count.withLock { $0 += 1 }
        return true
    }

    func waitUntilReady(timeout: TimeInterval) async -> Bool { true }
    func finish(slotCount: Int) async throws {}
    func cancel() async {}
}

/// Wraps a frame source and keeps every frame it delivered.
final class TappedFrameSource: FrameSource {
    private let inner: any FrameSource
    private let frames = Mutex<[CapturedFrame]>([])

    init(_ inner: any FrameSource) {
        self.inner = inner
    }

    var delivered: [CapturedFrame] { frames.withLock { $0 } }

    func start(target: CaptureTarget, size: PixelSize, fps: FrameRate, showsCursor: Bool) async throws
        -> AsyncThrowingStream<CapturedFrame, any Error>
    {
        let upstream = try await inner.start(target: target, size: size, fps: fps, showsCursor: showsCursor)
        let (stream, continuation) = AsyncThrowingStream<CapturedFrame, any Error>.makeStream()
        Task {
            do {
                for try await frame in upstream {
                    self.frames.withLock { $0.append(frame) }
                    continuation.yield(frame)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        return stream
    }

    func stop() async {
        await inner.stop()
    }
}

/// Free space that drops below 2 GB after the first `highCalls` checks.
final class DroppingDiskProbe: DiskSpaceProbe {
    private let calls = Mutex(0)
    let highCalls: Int

    init(highCalls: Int) {
        self.highCalls = highCalls
    }

    var callCount: Int { calls.withLock { $0 } }

    func freeBytes(at url: URL) throws -> Int64 {
        let n = calls.withLock { c -> Int in
            c += 1
            return c
        }
        return n <= highCalls ? 100 * FakeDiskSpaceProbe.gigabyte : FakeDiskSpaceProbe.gigabyte
    }
}

/// Reads a written clip back with AVAssetReader.
enum VideoFile {
    struct Sample {
        var presentationTime: CMTime
        var duration: CMTime
    }

    static func track(_ url: URL) async throws -> (AVURLAsset, AVAssetTrack) {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        #expect(tracks.count == 1)
        return (asset, try #require(tracks.first))
    }

    static func naturalSize(_ url: URL) async throws -> PixelSize {
        let (_, track) = try await track(url)
        let size = try await track.load(.naturalSize)
        return PixelSize(width: Int(size.width), height: Int(size.height))
    }

    static func codec(_ url: URL) async throws -> FourCharCode? {
        let (_, track) = try await track(url)
        return try await track.load(.formatDescriptions).first.map { CMFormatDescriptionGetMediaSubType($0) }
    }

    /// Every compressed sample's presentation time and duration, in order.
    static func samples(_ url: URL) async throws -> [Sample] {
        let (asset, track) = try await track(url)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        #expect(reader.startReading())
        var samples: [Sample] = []
        while let buffer = output.copyNextSampleBuffer() {
            guard CMSampleBufferGetNumSamples(buffer) > 0 else { continue }
            samples.append(
                Sample(
                    presentationTime: CMSampleBufferGetPresentationTimeStamp(buffer),
                    duration: CMSampleBufferGetDuration(buffer)))
        }
        #expect(reader.status == .completed, "\(String(describing: reader.error))")
        return samples.sorted { $0.presentationTime < $1.presentationTime }
    }

    /// The synthetic frame index (mod 55) each decoded frame shows, from a sparse luma sample.
    static func frameIndices(_ url: URL) async throws -> [Int] {
        let (asset, track) = try await track(url)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ])
        reader.add(output)
        #expect(reader.startReading())
        var indices: [Int] = []
        while let buffer = output.copyNextSampleBuffer() {
            guard let image = CMSampleBufferGetImageBuffer(buffer) else { continue }
            indices.append(SyntheticFrameSource.frameIndex(forLuma: sparseMeanLuma(image)))
        }
        #expect(reader.status == .completed, "\(String(describing: reader.error))")
        return indices
    }

    private static func sparseMeanLuma(_ buffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return 0 }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0
        var count = 0
        for y in Swift.stride(from: height / 8, to: height, by: 16) {
            for x in Swift.stride(from: width / 8, to: width, by: 16) {
                sum += Int(bytes[y * stride + x])
                count += 1
            }
        }
        return Double(sum) / Double(max(1, count))
    }
}

/// Polls an actor-isolated condition every ~1 ms until it holds. After `timeout` seconds of real time it records an
/// issue and returns, so a condition that never comes true fails the test instead of spinning forever. The sleep only
/// paces the polling (it keeps the loop off the CPU); it never drives the test's timing.
func eventually(
    timeout: Double = 10, sourceLocation: SourceLocation = #_sourceLocation, _ condition: () async -> Bool
) async {
    let deadline = ContinuousClock.now + .seconds(timeout)
    while await !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("Condition still false after \(timeout) s.", sourceLocation: sourceLocation)
            return
        }
        try? await Task.sleep(for: .milliseconds(1))
    }
}

extension Fixtures {
    static let size1280x800 = PixelSize(width: 1280, height: 800)
    /// A clip folder for sessions with a fake sink, which never write into it.
    static let unusedFolder = URL(fileURLWithPath: "/nonexistent/skreenrek-unused", isDirectory: true)

    /// Host times `start + n / fps` for n in `range`, minus the indices in `gap`.
    static func frameTimes(_ range: Range<Int>, fps: Int, skipping gap: Range<Int> = 0..<0, start: TimeInterval = 0)
        -> [TimeInterval]
    {
        range.filter { !gap.contains($0) }.map { start + Double($0) / Double(fps) }
    }
}

/// The recorder suites that encode video or measure time run one at a time, so they don't starve each other (or the
/// perf suites) of CPU on the CI virtual machine.
@Suite(.serialized) struct RecorderSuites {}
