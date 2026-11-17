import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import SkreenrekCore
import SkreenrekTesting
import Testing
import VideoToolbox

/// Proves on the CI virtual machine that synthetic IOSurface-backed `420v` frames encode to a real H.264 MP4
/// through AVAssetWriter, and reports (without failing) whether the hardware encoder is available.
@Suite struct EncoderCanaryTests {
    static let size = PixelSize(width: 1280, height: 800)
    static let frameCount = 30
    static let fps: Int32 = 30

    @Test func syntheticFramesEncodeToH264MP4() async throws {
        let folder = try TempFolder()
        let url = folder.url.appendingPathComponent("canary.mp4")
        let frames = try (0..<Self.frameCount).map { try SyntheticFrames.makeBuffer(size: Self.size, index: $0) }
        for frame in frames {
            #expect(CVPixelBufferGetIOSurface(frame) != nil)
            #expect(CVPixelBufferGetPixelFormatType(frame) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        }

        let outcome = try await CanaryWriter.write(frames: frames, to: url, size: Self.size, fps: Self.fps, policy: .software)
        #expect(outcome.status == .completed, "writer failed: \(String(describing: outcome.error))")

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        #expect(tracks.count == 1)
        let track = try #require(tracks.first)

        let naturalSize = try await track.load(.naturalSize)
        #expect(naturalSize == CGSize(width: 1280, height: 800))

        let formats = try await track.load(.formatDescriptions)
        let codec = try #require(formats.first).mediaSubType
        #expect(codec == .h264)

        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 1.0) <= 1.0 / 30, "duration \(duration) s")

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        #expect(reader.startReading())
        var samples = 0
        while let sample = output.copyNextSampleBuffer() {
            samples += CMSampleBufferGetNumSamples(sample)
        }
        #expect(reader.status == .completed)
        #expect(samples == Self.frameCount)
    }

    @Test func reportsWhetherHardwareEncoderIsAccepted() async throws {
        let folder = try TempFolder()
        let url = folder.url.appendingPathComponent("hardware.mp4")
        let frames = try (0..<Self.frameCount).map { try SyntheticFrames.makeBuffer(size: Self.size, index: $0) }
        let outcome = try await CanaryWriter.write(
            frames: frames, to: url, size: Self.size, fps: Self.fps, policy: .requireHardware)
        if outcome.status == .completed {
            print("EncoderCanary: .requireHardware accepted (hardware H.264 encoder available)")
        } else {
            print(
                "EncoderCanary: .requireHardware not accepted (\(outcome.status.rawValue)): "
                    + "\(outcome.error?.localizedDescription ?? "no error"); expected on a virtual machine")
        }
    }
}

/// The smallest AVAssetWriter path: H.264, pixel-buffer adaptor, presentation time n / fps, no copies.
enum CanaryWriter {
    struct Outcome {
        var status: AVAssetWriter.Status
        var error: Error?
    }

    /// AVFoundation objects aren't `Sendable`; this box hands them to the writer's serial queue, which is the only
    /// place they are touched while appending.
    private final class Job: @unchecked Sendable {
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        let frames: [CVPixelBuffer]
        let fps: Int32
        var next = 0
        var finished = false

        init(
            writer: AVAssetWriter, input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor,
            frames: [CVPixelBuffer], fps: Int32
        ) {
            self.writer = writer
            self.input = input
            self.adaptor = adaptor
            self.frames = frames
            self.fps = fps
        }
    }

    static func write(frames: [CVPixelBuffer], to url: URL, size: PixelSize, fps: Int32, policy: EncoderPolicy)
        async throws -> Outcome
    {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        var settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
        ]
        if policy == .requireHardware {
            settings[AVVideoEncoderSpecificationKey] = [
                kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true
            ]
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: SyntheticFrames.pixelFormat,
                kCVPixelBufferWidthKey as String: size.width,
                kCVPixelBufferHeightKey as String: size.height,
            ])
        guard writer.canAdd(input) else {
            return Outcome(status: .failed, error: writer.error)
        }
        writer.add(input)
        guard writer.startWriting() else {
            return Outcome(status: writer.status, error: writer.error)
        }
        writer.startSession(atSourceTime: .zero)

        let job = Job(writer: writer, input: input, adaptor: adaptor, frames: frames, fps: fps)
        let queue = DispatchQueue(label: "skreenrek.canary.writer")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            job.input.requestMediaDataWhenReady(on: queue) {
                guard !job.finished else { return }
                while job.input.isReadyForMoreMediaData, job.next < job.frames.count {
                    let time = CMTime(value: CMTimeValue(job.next), timescale: job.fps)
                    if !job.adaptor.append(job.frames[job.next], withPresentationTime: time) {
                        job.next = job.frames.count
                        break
                    }
                    job.next += 1
                }
                if job.next >= job.frames.count || job.writer.status != .writing {
                    job.finished = true
                    job.input.markAsFinished()
                    continuation.resume()
                }
            }
        }

        if writer.status == .writing {
            writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frames.count), timescale: fps))
            await writer.finishWriting()
        } else {
            writer.cancelWriting()
        }
        return Outcome(status: writer.status, error: writer.error)
    }
}

/// A temp folder removed when the value goes away.
final class TempFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("skreenrek-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
