import CoreVideo
import Foundation
import IOSurface
import SkreenrekCore
import SkreenrekTesting
import Testing

extension RecorderSuites {
    @Suite struct ZeroCopyTests {
        @Test func everyAppendedBufferIsOneTheSourceDeliveredIOSurfaceBacked420v() async throws {
            // A gap, a wrong-size frame and a duration, so repeats and skips are in the mix.
            let times = Fixtures.frameTimes(0..<40, fps: 60, skipping: 10..<16)
            let source = TappedFrameSource(
                SyntheticFrameSource(timing: .scripted(times), frameSizes: [20: PixelSize(width: 16, height: 16)]))
            let sink = RecordingSink()
            let session = RecordingSession(
                source: source, clock: ManualClock(), disk: FakeDiskSpaceProbe(), encoder: .software,
                makeSink: { _ in sink })
            try await session.start(
                target: .window(Fixtures.safari), size: PixelSize(width: 320, height: 200),
                options: RecordingOptions(fps: .fps60, duration: 0.5), folder: Fixtures.unusedFolder)
            let result = try await withTestDeadline { await session.waitForEnd() }

            let delivered = source.delivered.map { ObjectIdentifier($0.pixelBuffer) }
            let appended = sink.appended
            #expect(appended.count == 30)
            #expect(result.stats.slotsWritten == 30)
            for entry in appended {
                #expect(delivered.contains(ObjectIdentifier(entry.frame.pixelBuffer)), "slot \(entry.slot) is a copy")
                #expect(CVPixelBufferGetIOSurface(entry.frame.pixelBuffer) != nil)
                #expect(
                    CVPixelBufferGetPixelFormatType(entry.frame.pixelBuffer)
                        == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
            }
            // A repeat re-appends the very same object.
            #expect(appended[10].frame.pixelBuffer === appended[9].frame.pixelBuffer)
            #expect(result.stats.pixelFormat == "420v")
        }

        @Test func theSessionHoldsAtMostTwoSourceBuffers() async throws {
            let clock = ManualClock()
            let session = RecordingSession(
                source: SyntheticFrameSource(timing: .scripted(Fixtures.frameTimes(0..<200, fps: 60))), clock: clock,
                disk: FakeDiskSpaceProbe(), encoder: .software, makeSink: { _ in NoOpSink() })
            try await session.start(
                target: .window(Fixtures.safari), size: PixelSize(width: 64, height: 64), options: RecordingOptions(),
                folder: Fixtures.unusedFolder)
            let maxHeld = try await withTestDeadline {
                var maxHeld = 0
                while await session.framesReceived < 200 {
                    maxHeld = max(maxHeld, await session.heldBufferCount)
                    await Task.yield()
                }
                return maxHeld
            }
            #expect(await session.heldBufferCount <= 2)
            #expect(maxHeld <= 2)
            _ = try await withTestDeadline { try await session.stop() }
        }
    }
}
