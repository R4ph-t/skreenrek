import AVFoundation
import CoreMedia
import Foundation
import SkreenrekCore
import SkreenrekTesting
import Testing
import VideoToolbox

extension RecorderSuites {
    @Suite struct ClipFormatTests {
        @Test(arguments: [VideoContainer.mp4, .mov])
        func h264(container: VideoContainer) async throws {
            try await Self.check(codec: .h264, container: container)
        }

        @Test(.enabled(if: softwareEncoderAvailable(kCMVideoCodecType_HEVC)), arguments: [VideoContainer.mp4, .mov])
        func hevc(container: VideoContainer) async throws {
            try await Self.check(codec: .hevc, container: container)
        }

        @Test(.enabled(if: softwareEncoderAvailable(kCMVideoCodecType_AppleProRes422)), arguments: QualityPreset.allCases)
        func prores(quality: QualityPreset) async throws {
            try await Self.check(codec: .prores, container: .mov, quality: quality)
        }

        /// A folder that took the `-2` collision suffix names its movie `<base>-2.mp4`, and the snippet's copy line and
        /// events.json point at that real file.
        @Test func aCollisionFolderNamesTheMovieWithItsSuffix() async throws {
            try await withTestDeadline(seconds: 60) {
                let temp = try TempFolder("collision")
                defer { temp.cleanUp() }
                let date = Date(timeIntervalSince1970: 1_794_908_527)
                let paris = TimeZone(identifier: "Europe/Paris")!
                func make() throws -> URL {
                    try OutputFolder.create(in: temp.url, target: .window(Fixtures.safari), name: nil, date: date,
                        timeZone: paris)
                }
                _ = try make()
                let folder = try make()
                #expect(folder.lastPathComponent == "2026-11-17_104207_safari-2")
                let session = RecordingSession(source: SyntheticFrameSource(count: 31, fps: 30), clock: ManualClock(),
                    disk: FakeDiskSpaceProbe(), encoder: .software, realTimeWriter: false)
                try await session.start(target: .window(Fixtures.safari), size: Fixtures.size1280x800,
                    options: RecordingOptions(fps: .fps30, duration: 1), folder: folder)
                let result = await session.waitForEnd()
                #expect(result.complete)
                #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path)
                    == ["2026-11-17_104207_safari-2.mp4"])
                #expect(result.video.file == "2026-11-17_104207_safari-2.mp4")
                #expect(result.clipURL == folder.appendingPathComponent("2026-11-17_104207_safari-2.mp4"))

                let recording = EventsFile.Recording(id: result.id, startedAt: "", duration: 1, fps: 30,
                    video: result.video, source: .init(target: .window(Fixtures.safari)), startedBy: .cli, client: nil,
                    stats: result.stats)
                let written = try ClipArtifacts.write(recording: recording, complete: true, log: EventLog(),
                    events: true, assetsDir: nil, clipFolder: folder, homeDirectory: temp.url)
                #expect(written.snippet.contains(
                    "cp ~/2026-11-17_104207_safari-2/2026-11-17_104207_safari-2.mp4 assets/2026-11-17_104207_safari-2.mp4"))
                #expect(written.snippet.contains("src=\"assets/2026-11-17_104207_safari-2.mp4\""))
                let json = try JSONSerialization.jsonObject(with: Data(contentsOf: try #require(written.eventsFile)))
                let video = (json as? [String: Any])?["recording"] as? [String: Any]
                #expect((video?["video"] as? [String: Any])?["file"] as? String == "2026-11-17_104207_safari-2.mp4")
                #expect(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
                    == ["2026-11-17_104207_safari-2.mp4", "events.json", "hyperframes.html"])
            }
        }

        private static func check(codec: VideoCodec, container: VideoContainer, quality: QualityPreset = .high) async throws {
            try await withTestDeadline(seconds: 60) {
                let temp = try TempFolder("format")
                defer { temp.cleanUp() }
                let source = SyntheticFrameSource(count: 61, fps: 30)
                let session = RecordingSession(source: source, clock: ManualClock(), disk: FakeDiskSpaceProbe(),
                    encoder: .software, realTimeWriter: false)
                let folder = try temp.clipFolder()
                try await session.start(target: .window(Fixtures.safari), size: Fixtures.size1280x800,
                    options: RecordingOptions(fps: .fps30, codec: codec, duration: 2, container: container, quality: quality),
                    folder: folder)
                let result = await session.waitForEnd()
                #expect(result.complete)
                let video = result.video
                #expect(video.container == container && video.codec == codec)
                #expect(video.profile == (try OutputSettings.resolve(container: container.rawValue,
                    codec: codec.rawValue, quality: quality.rawValue)).profile)
                // The movie is named after its folder: `<folder>.mp4` / `<folder>.mov`.
                #expect(video.file == "\(folder.lastPathComponent).\(container.rawValue)")
                #expect(result.clipURL == folder.appendingPathComponent(video.file))
                #expect(FileManager.default.fileExists(atPath: result.clipURL.path))
                #expect(video.width == 1280 && video.height == 800)
                #expect(result.codec == video.codec)
                let samples = try await VideoFile.samples(result.clipURL)
                #expect(samples.count == 60)
                for (index, sample) in samples.enumerated() {
                    #expect(sample.presentationTime == CMTime(value: Int64(index), timescale: 30))
                    #expect(sample.duration == CMTime(value: 1, timescale: 30))
                }
                let bytes = try result.clipURL.resourceValues(forKeys: [.fileSizeKey]).fileSize!
                #expect(video.bitrateMbps == (Double(bytes) * 8 / 2 / 1_000_000 * 10).rounded() / 10)
                // Deliberately supply the wrong container/codec and change the extension: file facts must still win.
                let renamed = folder.appendingPathComponent("misleading.\(container == .mov ? "mp4" : "mov")")
                try FileManager.default.copyItem(at: result.clipURL, to: renamed)
                let wrongRequest = try OutputSettings.resolve(container: "mov", codec: codec == .h264 ? "hevc" : "h264")
                let inspected = try await VideoReadback.inspect(url: renamed, settings: wrongRequest)
                #expect(inspected.container == container && inspected.codec == codec && inspected.profile == video.profile)
                let recording = EventsFile.Recording(id: result.id, startedAt: "", duration: 2, fps: 30,
                    video: video, source: .init(target: .window(Fixtures.safari)), startedBy: .cli, client: nil, stats: result.stats)
                let assets = temp.url.appendingPathComponent("assets")
                let written = try ClipArtifacts.write(recording: recording, complete: true, log: EventLog(),
                    events: true, assetsDir: assets, clipFolder: folder)
                #expect(written.assetCopy?.lastPathComponent == "\(result.id).\(container.rawValue)")
                #expect(written.snippet.contains("assets/\(result.id).\(container.rawValue)"))
                #expect(try Data(contentsOf: written.assetCopy!) == Data(contentsOf: result.clipURL))
                let events = try JSONDecoder().decode(EventsFile.self, from: Data(contentsOf: written.eventsFile!))
                #expect(events.recording.video == video)
                print("ClipFormatTests: \(container.rawValue) \(codec.rawValue) \(video.profile), 60 samples, \(video.bitrateMbps!) Mbps")
            }
        }
    }

    @Suite struct BitrateTargetTests {
        @Test func fiveSecondsOfSyntheticMotionAtEightMbps() async throws {
            try await withTestDeadline(seconds: 90) {
                let temp = try TempFolder("bitrate")
                defer { temp.cleanUp() }
                let source = SyntheticFrameSource(timing: .scripted(Fixtures.frameTimes(0..<151, fps: 30)), motion: true)
                let session = RecordingSession(source: source, clock: ManualClock(), disk: FakeDiskSpaceProbe(),
                    encoder: .software, realTimeWriter: false)
                try await session.start(target: .window(Fixtures.safari), size: Fixtures.size1280x800,
                    options: RecordingOptions(fps: .fps30, duration: 5, bitrateMbps: 8), folder: try temp.clipFolder())
                let result = await session.waitForEnd()
                #expect(result.complete && result.stats.slotsWritten == 150)
                let bitrate = try #require(result.video.bitrateMbps)
                print("BitrateTargetTests: requested 8 Mbps, measured \(bitrate) Mbps, \(result.duration) s synthetic motion")
                #expect((5.6...10.4).contains(bitrate))
                #expect(result.video.quality == nil && result.video.requestedBitrateMbps == 8)
            }
        }
    }
}

private func softwareEncoderAvailable(_ codec: CMVideoCodecType) -> Bool {
    var session: VTCompressionSession?
    let status = VTCompressionSessionCreate(allocator: nil, width: 1280, height: 800, codecType: codec,
        encoderSpecification: [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: false] as CFDictionary,
        imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: nil, refcon: nil,
        compressionSessionOut: &session)
    guard status == noErr, let session else { return false }
    defer { VTCompressionSessionInvalidate(session) }
    return VTCompressionSessionPrepareToEncodeFrames(session) == noErr
}
