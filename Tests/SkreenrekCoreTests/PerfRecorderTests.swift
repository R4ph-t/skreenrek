import AVFoundation
import CoreMedia
import Foundation
import SkreenrekCore
import SkreenrekTesting
import Synchronization
import Testing

// Performance suites: real clock, no permission. Budgets are loose multiples of the real targets because they run on
// a hosted macOS virtual machine; each test prints what it measured.

extension RecorderSuites {
    /// Start to first frame appended: software encoder, 1920 × 1080, a frame ready at once. Median of 5 runs ≤ 150 ms.
    @Suite(.serialized) struct PerfStartTests {
        @Test func startToFirstFrameMedianIsWithinBudget() async throws {
            var samples: [Double] = []
            // Run 0 is a warm-up that loads the encoder into the process; it isn't counted.
            for run in 0..<6 {
                let temp = try TempFolder("perf-start-\(run)")
                defer { temp.cleanUp() }
                let clock = HostTimeClock()
                let firstSlot = AsyncStream<Void>.makeStream()
                let session = RecordingSession(
                    source: SyntheticFrameSource(timing: .scripted([clock.now()])), clock: clock,
                    disk: FakeDiskSpaceProbe(), encoder: .software,
                    onSlot: { tick in if tick.index == 0 { firstSlot.continuation.yield() } })
                try await session.start(
                    target: .window(Fixtures.safari), size: PixelSize(width: 1920, height: 1080),
                    options: RecordingOptions(fps: .fps60), folder: try temp.clipFolder())
                try await withTestDeadline {
                    for await _ in firstSlot.stream { break }
                }
                let stats = await session.stats
                let ms = try #require(stats.startToFirstFrameMs)
                if run > 0 { samples.append(ms) } else { print("PerfStartTests: warm-up run \(Int(ms.rounded())) ms") }
                _ = try await withTestDeadline { try await session.stop() }
            }
            let median = samples.sorted()[samples.count / 2]
            print("PerfStartTests: startToFirstFrameMs runs \(samples.map { Int($0.rounded()) }) median \(median)")
            #expect(median <= 150)
        }
    }

    /// Sustained real-time capture through the pipeline (no-op sink): 3 s at 60 fps and at 30 fps are clean.
    @Suite(.serialized) struct PerfSustainTests {
        @Test(arguments: [FrameRate.fps60, .fps30])
        func threeSecondsAreClean(fps: FrameRate) async throws {
            let clock = HostTimeClock()
            let sink = NoOpSink()
            let session = RecordingSession(
                source: SyntheticFrameSource(timing: .realTime(clock, fps: Double(fps.framesPerSecond), count: nil)),
                clock: clock, disk: FakeDiskSpaceProbe(), encoder: .software, makeSink: { _ in sink })
            try await session.start(
                target: .window(Fixtures.safari), size: PixelSize(width: 1920, height: 1080),
                options: RecordingOptions(fps: fps, duration: 3), folder: Fixtures.unusedFolder)
            let result = try await withTestDeadline { await session.waitForEnd() }
            let s = result.stats
            print(
                "PerfSustainTests \(fps.framesPerSecond) fps: slots \(s.slotsWritten) fresh \(s.framesFresh) "
                    + "idle \(s.framesRepeatedIdle) dropped \(s.framesDropped) skipped \(s.sourceFramesSkipped) "
                    + "start \(s.startToFirstFrameMs ?? -1) ms")
            #expect(result.stopReason == .duration)
            #expect(s.slotsWritten == 3 * fps.framesPerSecond)
            #expect(sink.appendCount == 3 * fps.framesPerSecond)
            #expect(s.framesDropped == 0)
            #expect(s.sourceFramesSkipped == 0)
            #expect(s.isClean)
        }
    }

    /// Stop to finalized for a 10 s 1280 × 800 clip at 30 fps (software encoder) ≤ 1500 ms, playable right after.
    @Suite(.serialized) struct PerfFinalizeTests {
        @Test func finalizingATenSecondClipIsFast() async throws {
            let temp = try TempFolder("perf-finalize")
            defer { temp.cleanUp() }
            let session = RecordingSession(
                source: SyntheticFrameSource(count: 301, fps: 30, start: 0), clock: HostTimeClock(),
                disk: FakeDiskSpaceProbe(), encoder: .software, realTimeWriter: false)
            try await session.start(
                target: .window(Fixtures.safari), size: Fixtures.size1280x800,
                options: RecordingOptions(fps: .fps30, duration: 10), folder: try temp.clipFolder())
            let result = try await withTestDeadline { await session.waitForEnd() }
            let ms = try #require(result.stats.stopToFinalizedMs)
            print("PerfFinalizeTests: stopToFinalizedMs \(ms) for \(result.stats.slotsWritten) frames")
            #expect(result.stopReason == .duration)
            #expect(ms <= 1500)

            let asset = AVURLAsset(url: result.clipURL)
            #expect(try await asset.load(.isPlayable))
            #expect(try await asset.load(.duration) == CMTime(value: 300, timescale: 30))
            #expect(try await VideoFile.samples(result.clipURL).count == 300)
        }
    }
}
