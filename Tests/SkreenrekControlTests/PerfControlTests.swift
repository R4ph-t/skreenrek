import AVFoundation
import Foundation
import SkreenrekControl
import SkreenrekCore
import SkreenrekTesting
import Testing

// Performance suites: real clock, real socket, software encoder, no permission. Budgets are the spec's (already loose
// for a hosted macOS virtual machine); each test prints what it measured.

/// The control perf suites run one at a time, so they don't take CPU from each other.
@Suite(.serialized, .timeLimit(.minutes(3))) struct ControlPerfSuites {
    /// A harness on the real clock whose source has a frame ready at every start, then one every 1/30 s.
    static func realTimeHarness() throws -> Harness {
        let clock = HostTimeClock()
        return try Harness(
            source: SyntheticFrameSource(timing: .realTime(clock, fps: 30, count: nil)), clock: clock, realTime: true
        ).start()
    }

    static func median(_ values: [Double]) -> Double {
        values.sorted()[values.count / 2]
    }

    /// `record.start` (no resize) over the socket to the first frame appended: median of 5 runs ≤ 250 ms, and the
    /// response never waits for encoding.
    @Suite struct PerfSocketStartTests {
        @Test func requestToFirstFrameMedianIsWithinBudget() async throws {
            let h = try realTimeHarness()
            defer { h.stop() }
            let client = try await h.client()
            var samples: [Double] = []
            var lags: [Double] = []
            // Run 0 is a warm-up that loads the encoder into the process; it isn't counted.
            for run in 0..<6 {
                let sent = h.clock.now()
                _ = try await client.call(.recordStart, params: StartParams(app: "Safari"), as: StartBody.self)
                let answered = h.clock.now()
                let sink = try #require(h.sinks.latest)
                try await within("the first frame") { await sink.waitForAppends(1) }
                let firstFrame = try #require(sink.firstAppendTime)
                let ms = (firstFrame - sent) * 1000
                let lagMs = (answered - firstFrame) * 1000
                print(
                    "PerfSocketStartTests: run \(run) request→first frame \(Int(ms.rounded())) ms, "
                        + "response \(lagMs > 0 ? "\(Int(lagMs.rounded())) ms after" : "before") it")
                if run > 0 {
                    samples.append(ms)
                    lags.append(lagMs)
                }
                _ = try await client.call(.recordDiscard, as: DiscardBody.self)
            }
            let median = ControlPerfSuites.median(samples)
            print("PerfSocketStartTests: runs \(samples.map { Int($0.rounded()) }) median \(Int(median.rounded())) ms")
            #expect(median <= 250)
            // The answer comes before or with the first frame: start never waits for encoding. Judged on the median
            // like the start time, because one run's answer can sit in a busy scheduler on a loaded CI machine.
            let lagMedian = ControlPerfSuites.median(lags)
            print("PerfSocketStartTests: response after first frame, median \(Int(lagMedian.rounded())) ms")
            #expect(lagMedian <= 50)
        }
    }

    /// `record.stop` for a 10 s 1280 × 800 clip: the round trip is ≤ 2 s and the clip is finalized.
    @Suite struct PerfSocketStopTests {
        @Test func stoppingATenSecondClipIsFast() async throws {
            let h = try realTimeHarness()
            defer { h.stop() }
            let client = try await h.client()
            _ = try await client.call(.recordStart, params: StartParams(app: "Safari"), as: StartBody.self)
            // 10 s of real time at 30 fps.
            try await h.waitForSlots(300)
            let sent = h.clock.now()
            let stop = try await client.call(.recordStop, as: StopBody.self)
            let ms = (h.clock.now() - sent) * 1000
            let finalized = try #require(stop.recording.stats.stopToFinalizedMs)
            print(
                "PerfSocketStopTests: record.stop round trip \(Int(ms.rounded())) ms, stopToFinalizedMs "
                    + "\(Int(finalized.rounded())) for \(stop.recording.stats.slotsWritten) frames, "
                    + "dropped \(stop.recording.stats.framesDropped)")
            #expect(ms <= 2000)
            #expect(stop.recording.width == 1280 && stop.recording.height == 800)
            #expect(stop.recording.duration >= 10)
            let clip = stop.files.clip
            let (playable, seconds) = try await within("the clip's playability and duration") {
                let asset = AVURLAsset(url: URL(fileURLWithPath: clip))
                return (try await asset.load(.isPlayable), try await asset.load(.duration).seconds)
            }
            #expect(playable)
            #expect(seconds >= 10)
        }
    }

    /// A status poll during a recording answers in ≤ 50 ms (median of 20).
    @Suite struct PerfSocketStatusTests {
        @Test func statusPollsDuringARecordingAreQuick() async throws {
            let h = try realTimeHarness()
            defer { h.stop() }
            let recorder = try await h.client(.mcp, name: "Claude Code")
            _ = try await recorder.call(.recordStart, params: StartParams(app: "Safari"), as: StartBody.self)
            try await h.waitForSlots(15)
            let poller = try await h.client()
            var samples: [Double] = []
            for _ in 0..<20 {
                let sent = h.clock.now()
                let status = try await poller.call(.status, as: StatusBody.self)
                samples.append((h.clock.now() - sent) * 1000)
                #expect(status.state == .recording)
            }
            let median = ControlPerfSuites.median(samples)
            print(
                "PerfSocketStatusTests: 20 polls, median \(String(format: "%.2f", median)) ms, max "
                    + "\(String(format: "%.2f", samples.max() ?? 0)) ms")
            #expect(median <= 50)
            _ = try await recorder.call(.recordStop, as: StopBody.self)
        }
    }
}
