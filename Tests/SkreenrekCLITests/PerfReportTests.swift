import Foundation
@testable import SkreenrekCLI
import SkreenrekControl
import SkreenrekCore
import SkreenrekTesting
import Synchronization
import Testing

/// Records nothing: answers each `record` with a stop body built from the params and the stats the test chose.
final class FakePerfRecorder: PerfRecorder {
    private let calls = Mutex<[StartParams]>([])
    let stats: @Sendable (StartParams) -> RecordingStats

    init(stats: @escaping @Sendable (StartParams) -> RecordingStats) {
        self.stats = stats
    }

    var received: [StartParams] { calls.withLock { $0 } }

    func record(_ params: StartParams) async throws -> StopBody {
        calls.withLock { $0.append(params) }
        let folder = URL(fileURLWithPath: try #require(params.outDir)).appendingPathComponent(params.name ?? "clip")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return StopBody(
            recording: StopBody.Recording(
                id: folder.lastPathComponent, duration: params.durationSeconds ?? 0, fps: params.fps ?? 60,
                width: params.width ?? 1280, height: params.height ?? 800, codec: .h264, startedAt: "", startedBy: .cli,
                stats: stats(params)),
            files: StopBody.Files(
                clip: folder.appendingPathComponent("clip.mp4").path, events: nil,
                snippet: folder.appendingPathComponent("hyperframes.html").path),
            snippet: "", readback: nil)
    }
}

/// Says every clip has the frame count its name asks for, or a fixed answer.
struct FakeInspector: ClipInspector {
    var facts: @Sendable (URL) -> ClipFacts

    func inspect(clip: URL) async throws -> ClipFacts { facts(clip) }
}

@Suite(.timeLimit(.minutes(2))) struct PerfReportTests {
    static let goodStats: @Sendable (StartParams) -> RecordingStats = { params in
        RecordingStats(
            slotsWritten: Int((params.durationSeconds ?? 0) * Double(params.fps ?? 60)), startToFirstFrameMs: 120,
            stopToFinalizedMs: 200, encoder: .hardware)
    }

    /// The standard plan's frame counts: 3600 for 60 fps clips, 1800 for 30 fps.
    static let exactFrames = FakeInspector { url in
        ClipFacts(frameCount: url.path.contains("clip-1") ? 3600 : 1800, constantFrameDuration: true)
    }

    @Test func everyTargetMetExits0AndPrintsTheTable() async throws {
        let h = CLIHarness()
        defer { h.temp.cleanUp() }
        let recorder = FakePerfRecorder(stats: Self.goodStats)
        let seams = PerfSeams(recorder: recorder, inspector: Self.exactFrames, tempRoot: h.temp.root)
        let result = try await h.run(["debug", "perf", "--app", "Safari"], perf: seams)
        #expect(result.code == 0, "\(result)")
        #expect(result.out == """
            check                                          measured  target    result
            start p95 (request → first frame), 10 runs     120 ms    ≤ 250 ms  met
            60 fps 1920 × 1080 px 1 min: dropped frames    0         0         met
            60 fps 1920 × 1080 px 1 min: skipped frames    0         0         met
            60 fps 1920 × 1080 px 1 min: encoder           hardware  hardware  met
            60 fps 1920 × 1080 px 1 min: frames in clip    3600      3600      met
            60 fps 1920 × 1080 px 1 min: frame duration    constant  constant  met
            60 fps 1920 × 1080 px 1 min: stop → finalized  200 ms    ≤ 500 ms  met
            30 fps 1280 × 800 px 1 min: dropped frames     0         0         met
            30 fps 1280 × 800 px 1 min: skipped frames     0         0         met
            30 fps 1280 × 800 px 1 min: encoder            hardware  hardware  met
            30 fps 1280 × 800 px 1 min: frames in clip     1800      1800      met
            30 fps 1280 × 800 px 1 min: frame duration     constant  constant  met
            30 fps 1280 × 800 px 1 min: stop → finalized   200 ms    ≤ 500 ms  met
            Every target is met.

            """)
        // 10 timed starts, then the two clips, all without events or the HUD, into a temp folder that is gone now.
        let calls = recorder.received
        #expect(calls.count == 12)
        #expect(calls.prefix(10).allSatisfy { $0.fps == 60 && $0.durationSeconds == 1 && $0.width == nil })
        #expect(calls[10].fps == 60 && calls[10].width == 1920 && calls[10].height == 1080
            && calls[10].durationSeconds == 60)
        #expect(calls[11].fps == 30 && calls[11].width == 1280 && calls[11].height == 800)
        #expect(calls.allSatisfy { $0.app == "Safari" && $0.events == false && $0.hud == false })
        let folder = try #require(calls.first?.outDir)
        #expect(folder.hasPrefix(h.temp.root.path))
        #expect(!FileManager.default.fileExists(atPath: folder))
    }

    @Test func aMissedTargetExits1AndJSONSaysWhich() async throws {
        let h = CLIHarness()
        defer { h.temp.cleanUp() }
        let recorder = FakePerfRecorder { params in
            var stats = Self.goodStats(params)
            stats.encoder = .software
            stats.startToFirstFrameMs = params.width == nil ? 300 : nil
            return stats
        }
        let inspector = FakeInspector { _ in ClipFacts(frameCount: 3599, constantFrameDuration: false) }
        let seams = PerfSeams(recorder: recorder, inspector: inspector, tempRoot: h.temp.root)
        let result = try await h.run(
            ["debug", "perf", "--app", "Safari", "--runs", "3", "--json", "--keep"], perf: seams)
        #expect(result.code == 1, "\(result)")
        let report = try JSONDecoder().decode(PerfReport.self, from: Data(result.out.utf8))
        #expect(!report.met)
        let missed = Set(report.rows.filter { !$0.met }.map(\.check))
        #expect(missed.contains("start p95 (request → first frame), 3 runs"))
        #expect(missed.contains("60 fps 1920 × 1080 px 1 min: encoder"))
        #expect(missed.contains("60 fps 1920 × 1080 px 1 min: frames in clip"))
        #expect(missed.contains("30 fps 1280 × 800 px 1 min: frame duration"))
        #expect(!missed.contains("60 fps 1920 × 1080 px 1 min: dropped frames"))
        #expect(report.rows.first?.measured == "300 ms")
        #expect(recorder.received.count == 5)
        // --keep leaves the clips and says where.
        let kept = try #require(report.clips)
        #expect(FileManager.default.fileExists(atPath: kept))

        let human = try await h.run(["debug", "perf", "--app", "Safari", "--runs", "1"], perf: seams)
        #expect(human.code == 1)
        #expect(human.out.hasSuffix("7 of 13 targets missed.\n"))
    }

    @Test func longAddsTheFifteenMinuteClipWithItsOneSecondBudget() async throws {
        let h = CLIHarness()
        defer { h.temp.cleanUp() }
        let recorder = FakePerfRecorder(stats: Self.goodStats)
        let inspector = FakeInspector { url in
            ClipFacts(
                frameCount: url.path.contains("clip-3") ? 54000 : url.path.contains("clip-1") ? 3600 : 1800,
                constantFrameDuration: true)
        }
        let seams = PerfSeams(recorder: recorder, inspector: inspector, tempRoot: h.temp.root)
        let result = try await h.run(["debug", "perf", "--app", "Safari", "--runs", "0", "--long"], perf: seams)
        #expect(result.code == 0, "\(result)")
        #expect(result.out.contains("60 fps 1920 × 1080 px 15 min: stop → finalized  200 ms    ≤ 1000 ms  met"))
        #expect(recorder.received.last?.durationSeconds == 900)
    }

    @Test func p95IsTheNearestRank() {
        #expect(PerfRun.p95([]) == nil)
        #expect(PerfRun.p95([5]) == 5)
        #expect(PerfRun.p95(Array(1...10).map(Double.init)) == 10)
        #expect(PerfRun.p95(Array(1...20).map(Double.init)) == 19)
    }

    /// The real path: `record.start` over the socket, the duration ends it, and `AVAssetReader` reads the real clip.
    @Test func theSocketRecorderAndTheAssetInspectorMeasureARealClip() async throws {
        let clock = ManualClock()
        let source = SyntheticFrameSource(timing: .onClock(clock, (0...30).map { Double($0) / 30 }))
        let h = try CLIHarness(source: source, clock: clock, encode: true).start()
        defer { h.stop() }
        var plan = PerfPlan.standard
        plan.clips = [PerfPlan.Clip(fps: 30, size: PixelSize(width: 1280, height: 800), seconds: 1, finalizeBudgetMs: 500)]
        let seams = PerfSeams(plan: plan, tempRoot: h.temp.root)
        async let run = h.run(["debug", "perf", "--app", "Safari", "--runs", "0", "--json"], perf: seams)
        try await h.waitForEndWaiters(1)
        clock.advance(to: 1 + RecordingSession.defaultTickGrace)
        let result = try await run
        let report = try JSONDecoder().decode(PerfReport.self, from: Data(result.out.utf8))
        let rows = Dictionary(uniqueKeysWithValues: report.rows.map { ($0.check, $0) })
        #expect(rows["30 fps 1280 × 800 px 1 s: frames in clip"]?.measured == "30")
        #expect(rows["30 fps 1280 × 800 px 1 s: frames in clip"]?.met == true)
        #expect(rows["30 fps 1280 × 800 px 1 s: frame duration"]?.met == true)
        // Tests encode in software, so the encoder target is missed and the exit code says so.
        #expect(rows["30 fps 1280 × 800 px 1 s: encoder"]?.met == false)
        #expect(result.code == 1)
    }
}
