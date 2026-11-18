import CoreVideo
import Foundation
import os

/// One written slot, for the tick hook (04 samples the cursor once per slot).
public struct SlotTick: Sendable, Hashable {
    /// The slot index: frame n of the clip.
    public var index: Int
    /// The slot's host time, `t0 + index / fps`.
    public var hostTime: TimeInterval
    /// The first frame's host time (clip time zero).
    public var firstFrameHostTime: TimeInterval

    public init(index: Int, hostTime: TimeInterval, firstFrameHostTime: TimeInterval) {
        self.index = index
        self.hostTime = hostTime
        self.firstFrameHostTime = firstFrameHostTime
    }
}

/// One recording: a `FrameSource` into a `CFRScheduler` into a `PixelBufferSink` (`ClipWriter`), timed by a
/// `HostClock`, with a free-space check every 5 s of clip time. Runs off the main actor.
///
/// It stops on `stop()`, on `options.duration`, when the source ends with "window closed", when free space falls
/// below 2 GB, or on a write failure. Every stop finalizes a playable clip (full or partial) and returns a
/// `RecordingResult`.
public actor RecordingSession {
    // Offline encoding may synchronously wait for AVAssetWriter on this dedicated dispatch executor.
    // It never parks a thread belonging to Swift's cooperative concurrency pool.
    private nonisolated let executor = RecordingExecutor()
    public nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }
    public typealias SinkFactory = @Sendable (ClipWriterSettings) throws -> any PixelBufferSink

    /// Recording stops below this much free space.
    public static let lowDiskBytes: Int64 = 2_000_000_000
    /// Seconds of clip time between free-space checks.
    public static let diskCheckInterval = 5
    /// How long after its time an idle slot is written by the tick loop. Slots with a new frame are written as soon
    /// as the next frame arrives; the grace only gives a late frame time to land in its own slot.
    public static let defaultTickGrace: TimeInterval = 0.25

    private let source: any FrameSource
    private let clock: any HostClock
    private let disk: any DiskSpaceProbe
    private let encoderPolicy: EncoderPolicy
    private let realTimeWriter: Bool
    private let tickGrace: TimeInterval
    private let makeSink: SinkFactory
    private let onSlot: (@Sendable (SlotTick) -> Void)?
    private static let log = Logger(subsystem: SkreenrekIdentity.bundleID, category: "recorder")

    private enum Phase { case idle, recording, finalizing, finished }

    private struct Context {
        var target: CaptureTarget
        var size: PixelSize
        var options: RecordingOptions
        var output: OutputSettings
        var folder: URL
        var origin: RecordingOrigin
        var startedAt: Date
    }

    private var phase = Phase.idle
    private var context: Context?
    private var scheduler: CFRScheduler?
    private var sink: (any PixelBufferSink)?
    private var consumeTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var finalizeTask: Task<RecordingResult, Never>?
    private var endWaiters: [CheckedContinuation<RecordingResult, Never>] = []
    private var result: RecordingResult?
    private var writtenVideo: VideoReadback?

    private var startCallTime: TimeInterval = 0
    private var firstAppendTime: TimeInterval?
    private var pixelFormat = "420v"
    private var nextDiskCheckSlot = 0
    private var received = 0
    /// The source's drop count, frozen once the source has stopped.
    private var sourceDrops: Int?

    /// - Parameters:
    ///   - encoder: `.requireHardware` in the app; `.software` in tests on the CI virtual machine.
    ///   - realTimeWriter: false only for offline tests that need every slot to get its frame.
    ///   - makeSink: makes the sink for a clip; the default is `ClipWriter`.
    ///   - onSlot: called once per written slot, in order, on the session's executor. Keep it short.
    public init(
        source: any FrameSource, clock: any HostClock, disk: any DiskSpaceProbe, encoder: EncoderPolicy = .requireHardware,
        realTimeWriter: Bool = true, tickGrace: TimeInterval = RecordingSession.defaultTickGrace,
        makeSink: SinkFactory? = nil, onSlot: (@Sendable (SlotTick) -> Void)? = nil
    ) {
        self.source = source
        self.clock = clock
        self.disk = disk
        self.encoderPolicy = encoder
        self.realTimeWriter = realTimeWriter
        self.tickGrace = tickGrace
        self.makeSink = makeSink ?? { try ClipWriter(settings: $0) }
        self.onSlot = onSlot
    }

    // MARK: - Public API

    /// Starts the writer and the source. `folder` is the clip folder (see `OutputFolder.create`); `clip.mp4` or
    /// `clip.mov` is written inside it. `size` is the target's native pixel size, which is also the output size.
    ///
    /// Throws `wrong_state` when already started, `recording_failed` when the clip can't be written, or whatever the
    /// source throws (e.g. `permission_denied`). On a throw the clip folder is removed when it is empty.
    public func start(
        target: CaptureTarget, size: PixelSize, options: RecordingOptions, folder: URL,
        origin: RecordingOrigin = RecordingOrigin(startedBy: .cli), startedAt: Date = Date()
    ) async throws {
        guard phase == .idle else { throw SkreenrekError.wrongState(.alreadyRecording(app: nil)) }
        let output = try options.resolvedOutput()
        phase = .recording
        startCallTime = clock.now()
        let fps = options.fps
        context = Context(
            target: target, size: size, options: options, output: output, folder: folder, origin: origin, startedAt: startedAt)
        let limit = options.duration.map { max(1, Int(($0 * Double(fps.framesPerSecond)).rounded())) }
        scheduler = CFRScheduler(fps: fps.framesPerSecond, outputSize: size, slotLimit: limit)

        let settings = ClipWriterSettings(
            url: folder.appendingPathComponent(output.container.fileName), size: size, fps: fps,
            encoder: encoderPolicy, realTime: realTimeWriter, output: output)
        let sink: any PixelBufferSink
        do {
            sink = try makeSink(settings)
        } catch {
            failStart()
            throw (error as? SkreenrekError) ?? SkreenrekError.recordingFailed(.notWritable)
        }
        self.sink = sink
        if sink.encoder != .hardware, encoderPolicy == .requireHardware {
            Self.log.notice("Recording with the software encoder.")
        }

        let stream: AsyncThrowingStream<CapturedFrame, any Error>
        do {
            stream = try await source.start(target: target, size: size, fps: fps, showsCursor: options.cursor)
        } catch {
            await sink.cancel()
            failStart()
            throw error
        }
        guard phase == .recording else {
            // Stopped or discarded while the source was starting.
            await source.stop()
            return
        }
        consumeTask = Task { [weak self] in
            do {
                for try await frame in stream {
                    guard let self, await self.handle(frame) else { return }
                }
                await self?.sourceEnded(error: nil)
            } catch {
                await self?.sourceEnded(error: error)
            }
        }
    }

    /// Stops and finalizes the clip. Returns the result (also after an automatic stop).
    public func stop() async throws -> RecordingResult {
        switch phase {
        case .idle:
            throw SkreenrekError.wrongState(.notRecording)
        case .recording:
            beginFinalize(.stopped)
        case .finalizing, .finished:
            break
        }
        return await waitForEnd()
    }

    /// Waits until the recording ends (stop, duration, failure or discard) and returns the result.
    public func waitForEnd() async -> RecordingResult {
        if let result { return result }
        if let finalizeTask { return await finalizeTask.value }
        return await withCheckedContinuation { endWaiters.append($0) }
    }

    /// Stops without finalizing and deletes the clip folder.
    public func discard() async {
        let folder = context?.folder
        switch phase {
        case .idle:
            return
        case .recording:
            phase = .finalizing
            let stopRequest = clock.now()
            tickTask?.cancel()
            consumeTask?.cancel()
            await source.stop()
            sourceDrops = source.droppedFrameCount
            await sink?.cancel()
            finishResult(.discarded, stopRequest: stopRequest)
        case .finalizing:
            _ = await waitForEnd()
        case .finished:
            break
        }
        if let folder { try? FileManager.default.removeItem(at: folder) }
    }

    /// Stats so far (final once the recording has ended).
    public var stats: RecordingStats { result?.stats ?? currentStats(stopToFinalizedMs: nil) }

    /// Source frames received so far (tests use it to know the session has caught up).
    public var framesReceived: Int { received }

    /// The first frame's host time, once it has arrived.
    public var firstFrameHostTime: TimeInterval? { scheduler?.t0 }

    /// Source buffers the scheduler holds right now (never more than two).
    public var heldBufferCount: Int { scheduler?.heldBufferCount ?? 0 }

    // MARK: - Frames and ticks

    private func handle(_ frame: CapturedFrame) -> Bool {
        guard phase == .recording, var scheduler, let sink else { return false }
        received += 1
        let hadFirstFrame = scheduler.t0 != nil
        let range = scheduler.receive(frame, append: Self.appender(sink))
        self.scheduler = scheduler
        if !hadFirstFrame, scheduler.t0 != nil {
            pixelFormat = Self.fourCharacterCode(CVPixelBufferGetPixelFormatType(frame.pixelBuffer))
            startTickLoop()
        }
        afterSlots(range)
        return phase == .recording
    }

    private func startTickLoop() {
        let clock = clock
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let deadline = await self?.nextTickDeadline() else { return }
                do {
                    try await clock.sleep(until: deadline)
                } catch {
                    return
                }
                await self?.tick()
            }
        }
    }

    private func nextTickDeadline() -> TimeInterval? {
        guard phase == .recording, let scheduler, let time = scheduler.slotTime(scheduler.decidedSlots) else {
            return nil
        }
        return time + tickGrace
    }

    /// Writes every slot that fell due with no new frame; a late tick catches up all of them.
    private func tick() {
        guard phase == .recording, var scheduler, let sink else { return }
        let due = scheduler.dueSlotCount(at: clock.now(), grace: tickGrace)
        let range = scheduler.advance(to: due, append: Self.appender(sink))
        self.scheduler = scheduler
        afterSlots(range)
    }

    private func afterSlots(_ range: Range<Int>) {
        guard !range.isEmpty, let scheduler, let t0 = scheduler.t0 else { return }
        if firstAppendTime == nil, scheduler.appendedSlots > 0 { firstAppendTime = clock.now() }
        if let onSlot {
            let fps = Double(scheduler.fps)
            for n in range {
                onSlot(SlotTick(index: n, hostTime: t0 + Double(n) / fps, firstFrameHostTime: t0))
            }
        }
        guard phase == .recording else { return }
        if scheduler.failed {
            beginFinalize(.writeFailed)
        } else if scheduler.isAtLimit {
            beginFinalize(.duration)
        } else if scheduler.decidedSlots > nextDiskCheckSlot {
            let checkedSlot = nextDiskCheckSlot
            nextDiskCheckSlot += Self.diskCheckInterval * scheduler.fps
            if let context, let free = try? disk.freeBytes(at: context.folder), free < Self.lowDiskBytes {
                beginFinalize(.diskLow(at: Double(checkedSlot) / Double(scheduler.fps)))
            }
        }
    }

    private func sourceEnded(error: (any Error)?) {
        guard phase == .recording else { return }
        guard let error else {
            // The source finished on its own: keep writing idle slots until stop or duration.
            return
        }
        switch error {
        case FrameSourceError.windowClosed:
            beginFinalize(.windowClosed(at: 0))
        case let error as SkreenrekError:
            beginFinalize(.sourceFailed(error))
        default:
            beginFinalize(
                .sourceFailed(.recordingFailed(.other("Screen capture stopped: \(error.localizedDescription)"))))
        }
    }

    // MARK: - Finalizing

    private func beginFinalize(_ reason: StopReason) {
        guard phase == .recording else { return }
        phase = .finalizing
        let stopRequest = clock.now()
        tickTask?.cancel()
        finalizeTask = Task { await self.finalize(reason, stopRequest: stopRequest) }
    }

    private func finalize(_ reason: StopReason, stopRequest: TimeInterval) async -> RecordingResult {
        consumeTask?.cancel()
        guard var scheduler, let sink else {
            await source.stop()
            return finishResult(reason, stopRequest: stopRequest)
        }
        let append = Self.appender(sink)
        var reason = reason
        switch reason {
        case .stopped, .windowClosed, .sourceFailed:
            // Everything up to now, including the frame still pending.
            let range = scheduler.advance(to: scheduler.stopSlotCount(at: clock.now()), append: append)
            self.scheduler = scheduler
            afterSlots(range)
        default:
            break
        }
        if case .windowClosed = reason {
            reason = .windowClosed(at: Double(scheduler.decidedSlots) / Double(scheduler.fps))
        }
        await source.stop()
        sourceDrops = source.droppedFrameCount

        // Slots decided while the writer was busy get their repeats now.
        while !scheduler.flushOwed(append: append), !scheduler.failed {
            guard await sink.waitUntilReady(timeout: 2) else { break }
        }
        scheduler.finish()
        self.scheduler = scheduler
        if scheduler.failed, reason.isComplete { reason = .writeFailed }

        if scheduler.appendedSlots > 0 {
            do {
                try await sink.finish(slotCount: scheduler.appendedSlots)
                writtenVideo = sink.videoReadback
            } catch {
                Self.log.error("Couldn't finish the clip: \(error.localizedDescription, privacy: .public)")
                if reason.isComplete { reason = .writeFailed }
            }
        } else {
            await sink.cancel()
        }
        return finishResult(reason, stopRequest: stopRequest)
    }

    @discardableResult
    private func finishResult(_ reason: StopReason, stopRequest: TimeInterval) -> RecordingResult {
        let stopToFinalizedMs = (clock.now() - stopRequest) * 1000
        let context = context!
        let fps = context.options.fps
        let frames = scheduler?.appendedSlots ?? 0
        let result = RecordingResult(
            id: context.folder.lastPathComponent, duration: Double(frames) / Double(fps.framesPerSecond), fps: fps,
            width: context.size.width, height: context.size.height, codec: context.options.codec,
            startedAt: context.startedAt, origin: context.origin, folder: context.folder,
            complete: reason.isComplete, stopReason: reason, stats: currentStats(stopToFinalizedMs: stopToFinalizedMs),
            firstFrameHostTime: scheduler?.t0,
            video: writtenVideo ?? VideoReadback(settings: context.output, size: context.size))
        self.result = result
        phase = .finished
        let waiters = endWaiters
        endWaiters = []
        for waiter in waiters { waiter.resume(returning: result) }
        return result
    }

    private func failStart() {
        phase = .idle
        if let folder = context?.folder,
            (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty == true
        {
            try? FileManager.default.removeItem(at: folder)
        }
        context = nil
        scheduler = nil
        sink = nil
    }

    private func currentStats(stopToFinalizedMs: Double?) -> RecordingStats {
        let counts = scheduler?.counts ?? CFRCounts()
        // Frames the source's stream dropped while the recorder lagged were never written either.
        let drops = sourceDrops ?? (phase == .idle ? 0 : source.droppedFrameCount)
        return RecordingStats(
            slotsWritten: scheduler?.appendedSlots ?? 0, framesFresh: counts.framesFresh,
            framesRepeatedIdle: counts.framesRepeatedIdle, framesDropped: counts.framesDropped,
            sourceFramesSkipped: counts.sourceFramesSkipped + drops,
            startToFirstFrameMs: firstAppendTime.map { ($0 - startCallTime) * 1000 },
            stopToFinalizedMs: stopToFinalizedMs, encoder: sink?.encoder ?? .software, pixelFormat: pixelFormat)
    }

    private static func appender(_ sink: any PixelBufferSink) -> CFRScheduler.Append {
        { buffer, slot in
            guard sink.isReady else { return .notReady }
            return sink.append(buffer, slot: slot) ? .appended : .failed
        }
    }

    /// `420v` for `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange`.
    static func fourCharacterCode(_ code: OSType) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return String(code) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

private final class RecordingExecutor: SerialExecutor {
    private let queue = DispatchQueue(label: "\(SkreenrekIdentity.bundleID).recording")
    func enqueue(_ job: UnownedJob) {
        let executor = asUnownedSerialExecutor()
        queue.async { job.runSynchronously(on: executor) }
    }
}
