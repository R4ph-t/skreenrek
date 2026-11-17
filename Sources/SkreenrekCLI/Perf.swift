import AVFoundation
import Foundation
import SkreenrekControl
import SkreenrekCore

/// What `debug perf` records: timed starts, then clips checked frame by frame.
public struct PerfPlan: Sendable, Hashable {
    public struct Clip: Sendable, Hashable {
        public var fps: Int
        public var size: PixelSize
        public var seconds: Double
        /// Stop to finalized, at most.
        public var finalizeBudgetMs: Double

        public init(fps: Int, size: PixelSize, seconds: Double, finalizeBudgetMs: Double) {
            self.fps = fps
            self.size = size
            self.seconds = seconds
            self.finalizeBudgetMs = finalizeBudgetMs
        }

        /// `60 fps 1920 × 1080 px 60 s`.
        var label: String {
            "\(fps) fps \(size) \(seconds >= 60 ? "\(HumanFormat.number(seconds / 60)) min" : "\(HumanFormat.number(seconds)) s")"
        }
    }

    public var startRuns: Int
    /// Each timed start records this long, so the stats come back with the clip.
    public var startRunSeconds: Double
    public var startP95BudgetMs: Double
    public var clips: [Clip]
    /// Added with `--long`.
    public var longClip: Clip

    public init(startRuns: Int, startRunSeconds: Double, startP95BudgetMs: Double, clips: [Clip], longClip: Clip) {
        self.startRuns = startRuns
        self.startRunSeconds = startRunSeconds
        self.startP95BudgetMs = startP95BudgetMs
        self.clips = clips
        self.longClip = longClip
    }

    /// The spec's targets: 10 starts with p95 ≤ 250 ms, 60 s at 60 fps 1920 × 1080 and 60 s at 30 fps 1280 × 800
    /// with stop to finalized ≤ 500 ms, and with `--long` 15 min at 60 fps 1920 × 1080 within 1 s.
    public static let standard = PerfPlan(
        startRuns: 10, startRunSeconds: 1, startP95BudgetMs: 250,
        clips: [
            Clip(fps: 60, size: PixelSize(width: 1920, height: 1080), seconds: 60, finalizeBudgetMs: 500),
            Clip(fps: 30, size: PixelSize(width: 1280, height: 800), seconds: 60, finalizeBudgetMs: 500),
        ],
        longClip: Clip(fps: 60, size: PixelSize(width: 1920, height: 1080), seconds: 15 * 60, finalizeBudgetMs: 1000))
}

/// Records one clip to its end (the duration in `params`) and returns what was saved.
public protocol PerfRecorder: Sendable {
    func record(_ params: StartParams) async throws -> StopBody
}

/// What a clip holds, read back from the file.
public struct ClipFacts: Sendable, Hashable {
    public var frameCount: Int
    /// Every frame lasts the same time.
    public var constantFrameDuration: Bool

    public init(frameCount: Int, constantFrameDuration: Bool) {
        self.frameCount = frameCount
        self.constantFrameDuration = constantFrameDuration
    }
}

/// Reads a clip's frames. Real: `AssetClipInspector`.
public protocol ClipInspector: Sendable {
    func inspect(clip: URL) async throws -> ClipFacts
}

/// `debug perf`'s recorder and inspector. Tests pass fakes; nil fields use the app and `AVAssetReader`.
public struct PerfSeams: Sendable {
    public var recorder: (any PerfRecorder)?
    public var inspector: any ClipInspector
    public var plan: PerfPlan
    /// Where the clip folder goes; nil is the temporary folder.
    public var tempRoot: URL?

    public init(
        recorder: (any PerfRecorder)? = nil, inspector: any ClipInspector = AssetClipInspector(),
        plan: PerfPlan = .standard, tempRoot: URL? = nil
    ) {
        self.recorder = recorder
        self.inspector = inspector
        self.plan = plan
        self.tempRoot = tempRoot
    }
}

/// Counts a clip's video samples with `AVAssetReader` (no decoding) and checks that their durations are equal.
public struct AssetClipInspector: ClipInspector {
    public init() {}

    public func inspect(clip: URL) async throws -> ClipFacts {
        let asset = AVURLAsset(url: clip)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw SkreenrekError.internal(message: "\(clip.lastPathComponent) has no video track.")
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else {
            throw SkreenrekError.internal(
                message: "Couldn't read \(clip.lastPathComponent): \(reader.error?.localizedDescription ?? "unknown")")
        }
        var count = 0
        var first: CMTime?
        var constant = true
        while let buffer = output.copyNextSampleBuffer() {
            let samples = CMSampleBufferGetNumSamples(buffer)
            guard samples > 0 else { continue }
            var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: samples)
            var filled = 0
            CMSampleBufferGetSampleTimingInfoArray(
                buffer, entryCount: samples, arrayToFill: &timing, entriesNeededOut: &filled)
            for info in timing.prefix(filled) {
                if let first {
                    if CMTimeCompare(info.duration, first) != 0 { constant = false }
                } else {
                    first = info.duration
                }
            }
            count += samples
        }
        if reader.status == .failed {
            throw SkreenrekError.internal(
                message: "Couldn't read \(clip.lastPathComponent): \(reader.error?.localizedDescription ?? "unknown")")
        }
        return ClipFacts(frameCount: count, constantFrameDuration: constant && first.map { $0.isValid } ?? false)
    }
}

/// One measured-versus-target row of the report.
public struct PerfRow: Sendable, Hashable, Codable {
    public var check: String
    public var measured: String
    public var target: String
    public var met: Bool

    public init(check: String, measured: String, target: String, met: Bool) {
        self.check = check
        self.measured = measured
        self.target = target
        self.met = met
    }
}

/// `debug perf --json`: `{ met, rows, clips }`; `clips` is the kept folder, or null.
public struct PerfReport: Sendable, Hashable, Codable {
    public var met: Bool
    public var rows: [PerfRow]
    public var clips: String?

    public init(rows: [PerfRow], clips: String?) {
        self.met = rows.allSatisfy(\.met)
        self.rows = rows
        self.clips = clips
    }

    private enum CodingKeys: String, CodingKey { case met, rows, clips }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(met, forKey: .met)
        try c.encode(rows, forKey: .rows)
        try c.encode(clips, forKey: .clips)
    }
}

/// Runs the plan and judges every number against its target. Pure apart from its seams.
struct PerfRun: Sendable {
    var plan: PerfPlan
    var recorder: any PerfRecorder
    var inspector: any ClipInspector

    func rows(app: String, title: String?, folder: URL, long: Bool) async throws -> [PerfRow] {
        var rows: [PerfRow] = []
        var starts: [Double] = []
        var missingStarts = 0
        for run in 0..<plan.startRuns {
            var params = base(app: app, title: title, folder: folder, name: "start-\(run + 1)")
            params.fps = 60
            params.durationSeconds = plan.startRunSeconds
            let body = try await recorder.record(params)
            if let ms = body.recording.stats.startToFirstFrameMs { starts.append(ms) } else { missingStarts += 1 }
        }
        if plan.startRuns > 0 {
            let p95 = Self.p95(starts)
            rows.append(
                PerfRow(
                    check: "start p95 (request → first frame), \(plan.startRuns) runs",
                    measured: p95.map { "\(Int($0.rounded())) ms" } ?? "–",
                    target: "≤ \(HumanFormat.number(plan.startP95BudgetMs)) ms",
                    met: missingStarts == 0 && (p95.map { $0 <= plan.startP95BudgetMs } ?? false)))
        }
        for (index, clip) in (plan.clips + (long ? [plan.longClip] : [])).enumerated() {
            var params = base(app: app, title: title, folder: folder, name: "clip-\(index + 1)")
            params.fps = clip.fps
            params.width = clip.size.width
            params.height = clip.size.height
            params.durationSeconds = clip.seconds
            let body = try await recorder.record(params)
            let facts = try await inspector.inspect(clip: URL(fileURLWithPath: body.files.clip))
            rows += clipRows(clip, body: body, facts: facts)
        }
        return rows
    }

    func clipRows(_ clip: PerfPlan.Clip, body: StopBody, facts: ClipFacts) -> [PerfRow] {
        let stats = body.recording.stats
        let expected = Int((clip.seconds * Double(clip.fps)).rounded())
        let label = clip.label
        let finalize = stats.stopToFinalizedMs
        return [
            PerfRow(
                check: "\(label): dropped frames", measured: String(stats.framesDropped), target: "0",
                met: stats.framesDropped == 0),
            PerfRow(
                check: "\(label): skipped frames", measured: String(stats.sourceFramesSkipped), target: "0",
                met: stats.sourceFramesSkipped == 0),
            PerfRow(
                check: "\(label): encoder", measured: stats.encoder.rawValue, target: EncoderKind.hardware.rawValue,
                met: stats.encoder == .hardware),
            PerfRow(
                check: "\(label): frames in clip", measured: String(facts.frameCount), target: String(expected),
                met: facts.frameCount == expected),
            PerfRow(
                check: "\(label): frame duration", measured: facts.constantFrameDuration ? "constant" : "varies",
                target: "constant", met: facts.constantFrameDuration),
            PerfRow(
                check: "\(label): stop → finalized", measured: finalize.map { "\(Int($0.rounded())) ms" } ?? "–",
                target: "≤ \(HumanFormat.number(clip.finalizeBudgetMs)) ms",
                met: finalize.map { $0 <= clip.finalizeBudgetMs } ?? false),
        ]
    }

    private func base(app: String, title: String?, folder: URL, name: String) -> StartParams {
        StartParams(app: app, title: title, events: false, hud: false, outDir: folder.path, name: name)
    }

    /// The nearest-rank 95th percentile; nil for no samples.
    static func p95(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = Int((0.95 * Double(sorted.count)).rounded(.up))
        return sorted[max(0, min(sorted.count - 1, rank - 1))]
    }
}

/// Records through the app: `record.start`, then waits for the duration to end it.
struct SocketPerfRecorder: PerfRecorder {
    var runner: Runner

    func record(_ params: StartParams) async throws -> StopBody {
        let client = try await runner.connector.connect()
        let start = try await client.call(.recordStart, params: params, as: StartBody.self)
        let (end, _) = try await runner.awaitEnd(of: start, client: client, interrupts: nil)
        guard case .saved(let body) = end else {
            throw SkreenrekError.internal(message: "The perf recording was discarded before it ended.")
        }
        return body
    }
}

extension Runner {
    func perf(_ c: PerfCommand) async throws -> Int32 {
        guard c.runs >= 0 else {
            throw SkreenrekError.usage(message: "--runs must be 0 or more.", hint: "Pass --runs 10.")
        }
        let seams = environment.perf ?? PerfSeams()
        var plan = seams.plan
        plan.startRuns = c.runs
        let run = PerfRun(plan: plan, recorder: seams.recorder ?? SocketPerfRecorder(runner: self), inspector: seams.inspector)
        let root = seams.tempRoot ?? FileManager.default.temporaryDirectory
        let folder = root.appendingPathComponent("skreenrek-perf-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { if !c.keep { try? FileManager.default.removeItem(at: folder) } }
        let rows = try await run.rows(app: c.app, title: c.title, folder: folder, long: c.long)
        let report = PerfReport(rows: rows, clips: c.keep ? folder.path : nil)
        if mode.json {
            try sayJSON(report)
        } else {
            say(perfTable(report))
        }
        return report.met ? 0 : 1
    }

    func perfTable(_ report: PerfReport) -> String {
        let style = Style(enabled: mode.color)
        var rows = [["check", "measured", "target", "result"]]
        rows += report.rows.map { [$0.check, $0.measured, $0.target, $0.met ? "met" : "missed"] }
        var text = format.table(rows)
        // Colour after aligning, so the escape codes don't count as width.
        if style.enabled {
            text = text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
                if line.hasSuffix("  missed") { return line.dropLast(6) + style.red("missed") }
                if line.hasSuffix("  met") { return line.dropLast(3) + style.green("met") }
                return String(line)
            }.joined(separator: "\n")
        }
        text += report.met ? "Every target is met.\n" : "\(report.rows.filter { !$0.met }.count) of \(report.rows.count) targets missed.\n"
        if let clips = report.clips { text += "Clips kept in \(format.tilde(clips))\n" }
        return text
    }
}
