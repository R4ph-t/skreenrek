import AVFoundation
import Foundation
@testable import SkreenrekCore
import SkreenrekTesting
import Testing

extension RecorderSuites {
    @Suite struct LazyEncoderFallbackTests {
        @Test func aFailureAfterStartWritingRetriesTheFirstBufferInSoftware() async throws {
            try await withTestDeadline {
                let temp = try TempFolder("lazy-encoder")
                defer { temp.cleanUp() }
                let settings = ClipWriterSettings(url: temp.url.appendingPathComponent("clip.mp4"),
                    size: PixelSize(width: 320, height: 200), fps: .fps30, encoder: .requireHardware)
                var hardwareWriter: AVAssetWriter?
                var attempts: [Bool] = []
                let writer = try ClipWriter(settings: settings) { settings, hardware in
                    attempts.append(hardware)
                    // Use a real, permission-free writer, and inject failure only after successful startup.
                    var backend = try ClipWriter.start(settings, hardware: false)
                    backend.hardware = hardware
                    if hardware { hardwareWriter = backend.writer }
                    return backend
                }
                #expect(writer.encoder == .hardware)
                #expect(hardwareWriter?.status == .writing)
                hardwareWriter?.cancelWriting()
                let source = SyntheticFrameSource(count: 30, fps: 30)
                let stream = try await source.start(target: .window(Fixtures.safari), size: settings.size,
                    fps: .fps30, showsCursor: false)
                var slot = 0
                for try await frame in stream {
                    if slot > 0 { #expect(await writer.waitUntilReady(timeout: 2)) }
                    #expect(writer.append(frame.pixelBuffer, slot: slot))
                    slot += 1
                }
                try await writer.finish(slotCount: slot)
                await source.stop()
                #expect(attempts == [true, false] && writer.encoder == .software)
                let samples = try await VideoFile.samples(settings.url)
                #expect(samples.count == 30 && samples.first?.presentationTime == .zero)
                #expect(writer.videoReadback?.codec == .h264)
                #expect(!(await writer.waitUntilReady(timeout: 0.01)))
            }
        }

        @Test func aHardwareSetupFailureAlsoFallsBack() async throws {
            try await withTestDeadline {
                struct Unavailable: Error {}
                let temp = try TempFolder("unavailable-encoder")
                defer { temp.cleanUp() }
                var attempts: [Bool] = []
                let writer = try ClipWriter(settings: ClipWriterSettings(url: temp.url.appendingPathComponent("clip.mp4"),
                    size: PixelSize(width: 320, height: 200), fps: .fps30)) { settings, hardware in
                    attempts.append(hardware)
                    if hardware { throw Unavailable() }
                    return try ClipWriter.start(settings, hardware: false)
                }
                #expect(attempts == [true, false] && writer.encoder == .software)
                #expect(await writer.waitUntilReady(timeout: 2))
                await writer.cancel()
                #expect(!(await writer.waitUntilReady(timeout: 0.01)))
            }
        }
    }
}
