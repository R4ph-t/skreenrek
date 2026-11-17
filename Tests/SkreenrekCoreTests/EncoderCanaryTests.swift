import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import SkreenrekCore
import SkreenrekTesting
import Testing
import VideoToolbox

/// Proves on the CI runner that synthetic IOSurface-backed `420v` frames encode to a real H.264 MP4 through
/// AVAssetWriter, with no permission.
@Suite struct EncoderCanaryTests {
    static let size = PixelSize(width: 1280, height: 800)
    static let frameCount = 30
    static let fps: Int32 = 30

    @Test func syntheticFramesEncodeToARealH264MP4() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("skreenrek-canary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("clip.mp4")

        let source = SyntheticFrameSource(count: Self.frameCount, fps: Double(Self.fps))
        var frames: [CapturedFrame] = []
        for try await frame in try await source.start(
            target: .window(Fixtures.safari), size: Self.size, fps: .fps30, showsCursor: true)
        {
            frames.append(frame)
        }
        #expect(frames.count == Self.frameCount)

        try await Self.write(frames, to: url)

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        #expect(tracks.count == 1)
        let track = try #require(tracks.first)
        let naturalSize = try await track.load(.naturalSize)
        #expect(naturalSize == CGSize(width: 1280, height: 800))

        let formats = try await track.load(.formatDescriptions)
        #expect(formats.map { CMFormatDescriptionGetMediaSubType($0) } == [kCMVideoCodecType_H264])

        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 1.0) <= 1.0 / 30.0, "duration \(duration) s")

        #expect(try Self.countSamples(asset: asset, track: track) == Self.frameCount)

        print("EncoderCanaryTests: runner accepts .requireHardware H.264: \(Self.hardwareEncoderAvailable())")
    }

    private static func write(_ frames: [CapturedFrame], to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: size.width,
                AVVideoHeightKey: size.height,
            ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        #expect(writer.canAdd(input))
        writer.add(input)
        #expect(writer.startWriting(), "\(String(describing: writer.error))")
        writer.startSession(atSourceTime: .zero)

        let feed = Feed(frames: frames, input: input, adaptor: adaptor)
        let queue = DispatchQueue(label: "skreenrek.canary.writer")
        let appended = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            input.requestMediaDataWhenReady(on: queue) {
                if let result = feed.pump() { continuation.resume(returning: result) }
            }
        }
        #expect(appended, "\(String(describing: writer.error))")
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frames.count), timescale: fps))
        await writer.finishWriting()
        #expect(writer.status == .completed, "\(String(describing: writer.error))")
    }

    /// Appends frames while the input is ready; only touched on the writer queue.
    private final class Feed: @unchecked Sendable {
        let frames: [CapturedFrame]
        let input: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        var next = 0
        var done = false

        init(frames: [CapturedFrame], input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor) {
            self.frames = frames
            self.input = input
            self.adaptor = adaptor
        }

        /// Returns nil to keep going, or whether every frame was appended once finished.
        func pump() -> Bool? {
            guard !done else { return nil }
            while input.isReadyForMoreMediaData && next < frames.count {
                let time = CMTime(value: CMTimeValue(next), timescale: EncoderCanaryTests.fps)
                guard adaptor.append(frames[next].pixelBuffer, withPresentationTime: time) else {
                    done = true
                    input.markAsFinished()
                    return false
                }
                next += 1
            }
            guard next == frames.count else { return nil }
            done = true
            input.markAsFinished()
            return true
        }
    }

    private static func countSamples(asset: AVAsset, track: AVAssetTrack) throws -> Int {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        #expect(reader.startReading(), "\(String(describing: reader.error))")
        var samples = 0
        while let buffer = output.copyNextSampleBuffer() {
            samples += CMSampleBufferGetNumSamples(buffer)
        }
        #expect(reader.status == .completed, "\(String(describing: reader.error))")
        return samples
    }

    /// Informational only: whether a hardware-only H.264 session can be created (`EncoderPolicy.requireHardware`).
    /// GitHub's macOS runners are virtual machines and are expected to say no.
    private static func hardwareEncoderAvailable() -> Bool {
        let specification = [
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: kCFBooleanTrue
        ] as CFDictionary
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: nil, width: Int32(size.width), height: Int32(size.height), codecType: kCMVideoCodecType_H264,
            encoderSpecification: specification, imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &session)
        if let session { VTCompressionSessionInvalidate(session) }
        return status == noErr && session != nil
    }
}
