import CoreVideo
import Foundation
import SkreenrekCore
import Testing

/// Drives a `CFRScheduler` by hand and records what it appended.
private struct Harness {
    var scheduler: CFRScheduler
    var appended: [(slot: Int, buffer: CVPixelBuffer)] = []
    /// `isReady` answers, consumed one per append attempt; empty means ready.
    var readiness: [Bool] = []
    var failOnSlot: Int?
    var maxHeld = 0

    init(fps: Int = 60, size: PixelSize = PixelSize(width: 64, height: 32), limit: Int? = nil) {
        scheduler = CFRScheduler(fps: fps, outputSize: size, slotLimit: limit)
    }

    var size: PixelSize { scheduler.outputSize }
    var fps: Double { Double(scheduler.fps) }
    var counts: CFRCounts { scheduler.counts }

    mutating func frame(slot: Double, size: PixelSize? = nil) -> CapturedFrame {
        let frame = TestFrames.frame(size ?? self.size, at: (scheduler.t0 ?? 0) + slot / fps)
        receive(frame)
        return frame
    }

    mutating func receive(_ frame: CapturedFrame) {
        var log = appended
        var readiness = readiness
        let failOnSlot = failOnSlot
        scheduler.receive(frame) { buffer, slot in
            Self.attempt(buffer, slot, &log, &readiness, failOnSlot)
        }
        appended = log
        self.readiness = readiness
        maxHeld = max(maxHeld, scheduler.heldBufferCount)
    }

    mutating func advance(to count: Int) {
        var log = appended
        var readiness = readiness
        let failOnSlot = failOnSlot
        scheduler.advance(to: count) { buffer, slot in
            Self.attempt(buffer, slot, &log, &readiness, failOnSlot)
        }
        appended = log
        self.readiness = readiness
        maxHeld = max(maxHeld, scheduler.heldBufferCount)
    }

    private static func attempt(
        _ buffer: CVPixelBuffer, _ slot: Int, _ log: inout [(slot: Int, buffer: CVPixelBuffer)],
        _ readiness: inout [Bool], _ failOnSlot: Int?
    ) -> SlotAppendOutcome {
        if !readiness.isEmpty, !readiness.removeFirst() { return .notReady }
        if slot == failOnSlot { return .failed }
        log.append((slot, buffer))
        return .appended
    }

    func buffer(atSlot slot: Int) -> CVPixelBuffer? {
        appended.first { $0.slot == slot }?.buffer
    }

    /// Every slot is fresh, idle or dropped.
    func checkInvariant(sourceLocation: SourceLocation = #_sourceLocation) {
        let c = counts
        #expect(
            c.framesFresh + c.framesRepeatedIdle + c.framesDropped == c.slotsWritten, sourceLocation: sourceLocation)
        #expect(maxHeld <= 2, sourceLocation: sourceLocation)
    }
}

@Suite struct CFRSchedulerTests {
    @Test func slotNHasTimeT0PlusNOverFps() {
        var h = Harness(fps: 60)
        h.receive(TestFrames.frame(h.size, at: 10))
        #expect(h.scheduler.t0 == 10)
        #expect(h.scheduler.slotTime(0) == 10)
        #expect(abs(h.scheduler.slotTime(60)! - 11) < 1e-9)
    }

    @Test func aFrameBelongsToTheNearestSlotWithJitterRoundingDown() {
        var h = Harness(fps: 60)
        h.receive(TestFrames.frame(h.size, at: 100))
        let slot = { (s: Double) in h.scheduler.slot(forHostTime: 100 + s / 60) }
        #expect(slot(3) == 3)
        #expect(slot(2.6) == 3)
        #expect(slot(3.4) == 3)
        #expect(slot(3.5) == 3)
        #expect(slot(3.51) == 4)
        #expect(slot(-5) == 0)
    }

    @Test func theFirstFrameIsWrittenAtOnceAsSlotZero() {
        var h = Harness()
        let first = h.frame(slot: 0)
        #expect(h.scheduler.decidedSlots == 1)
        #expect(h.buffer(atSlot: 0) === first.pixelBuffer)
    }

    @Test func aSteadySourceWritesEachFrameInItsSlotWhenTheNextOneArrives() {
        var h = Harness()
        let frames = (0..<10).map { h.frame(slot: Double($0)) }
        #expect(h.scheduler.decidedSlots == 9)
        h.advance(to: 10)
        for (n, frame) in frames.enumerated() {
            #expect(h.buffer(atSlot: n) === frame.pixelBuffer)
        }
        #expect(h.counts.framesFresh == 10)
        #expect(h.counts.framesRepeatedIdle == 0)
        h.checkInvariant()
    }

    @Test func aRepeatReappendsTheSameBufferObject() {
        var h = Harness()
        let first = h.frame(slot: 0)
        h.advance(to: 4)
        #expect(h.appended.map(\.slot) == [0, 1, 2, 3])
        #expect(h.appended.allSatisfy { $0.buffer === first.pixelBuffer })
    }

    @Test func noFrameIsWrittenPastTheLimit() {
        var h = Harness(limit: 5)
        for n in 0..<20 { _ = h.frame(slot: Double(n)) }
        #expect(h.scheduler.decidedSlots == 5)
        #expect(h.scheduler.isAtLimit)
        #expect(h.appended.map(\.slot) == [0, 1, 2, 3, 4])
        #expect(h.counts.sourceFramesSkipped == 0)
        h.advance(to: 100)
        #expect(h.scheduler.decidedSlots == 5)
    }

    @Test func dueAndStopSlotCounts() {
        var h = Harness(fps: 30)
        #expect(h.scheduler.dueSlotCount(at: 5, grace: 0.1) == 0)
        h.receive(TestFrames.frame(h.size, at: 2))
        #expect(h.scheduler.dueSlotCount(at: 2.0, grace: 0.1) == 0)
        #expect(h.scheduler.dueSlotCount(at: 2.1, grace: 0.1) == 1)
        #expect(h.scheduler.dueSlotCount(at: 3.1, grace: 0.1) == 31)
        #expect(h.scheduler.stopSlotCount(at: 2.5) == 16)
        // A pending frame ahead of the clock is still part of the clip on stop.
        h.receive(TestFrames.frame(h.size, at: 2 + 20.0 / 30))
        #expect(h.scheduler.stopSlotCount(at: 2.0) == 21)
    }

    @Test func memoryStaysFlatForALongRun() {
        var h = Harness(fps: 60)
        for n in 0..<3_000 {
            if n % 7 == 3 { continue }
            _ = h.frame(slot: Double(n))
            if n % 100 == 0 { h.advance(to: h.scheduler.decidedSlots + 1) }
        }
        #expect(h.maxHeld <= 2)
        h.checkInvariant()
    }
}

/// The accounting rules for `RecordingStats`, deterministic (no clock, no tasks).
@Suite struct StatsAccountingTests {
    @Test func anIdleGapCountsAsRepeatedIdleNotDrops() {
        var h = Harness()
        let frames = (0..<10).map { h.frame(slot: Double($0)) }
        h.advance(to: 20)
        let late = h.frame(slot: 20)
        h.advance(to: 21)
        #expect(h.counts.framesFresh == 11)
        #expect(h.counts.framesRepeatedIdle == 10)
        #expect(h.counts.framesDropped == 0)
        #expect(h.counts.sourceFramesSkipped == 0)
        #expect((10..<20).allSatisfy { h.buffer(atSlot: $0) === frames[9].pixelBuffer })
        #expect(h.buffer(atSlot: 20) === late.pixelBuffer)
        h.checkInvariant()
    }

    @Test func aGapFilledWhenTheNextFrameArrivesIsIdleToo() {
        var h = Harness()
        for n in 0..<5 { _ = h.frame(slot: Double(n)) }
        _ = h.frame(slot: 12)
        #expect(h.counts.framesRepeatedIdle == 7)
        #expect(h.counts.framesDropped == 0)
        h.checkInvariant()
    }

    @Test func aWriterNotReadySlotRepeatsAndCountsAsDropped() {
        var h = Harness()
        let frames = (0..<5).map { h.frame(slot: Double($0)) }
        // Slot 4 (frame 4) finds the input busy; the next attempts succeed.
        h.readiness = [false]
        let next = h.frame(slot: 5)
        h.advance(to: 6)
        #expect(h.counts.framesDropped == 1)
        #expect(h.buffer(atSlot: 4) === frames[3].pixelBuffer, "the busy slot repeats the previous frame")
        // Frame 4 never got a slot: frame 5 superseded it while it waited.
        #expect(h.counts.sourceFramesSkipped == 1)
        #expect(h.buffer(atSlot: 5) === next.pixelBuffer)
        #expect(h.appended.map(\.slot) == Array(0..<6))
        h.checkInvariant()
    }

    @Test func aBusySlotWithNoNewFrameIsAlsoDropped() {
        var h = Harness()
        _ = h.frame(slot: 0)
        h.readiness = [false, false]
        h.advance(to: 3)
        // Slots 1 and 2 were busy; nothing was appended for them yet.
        #expect(h.appended.map(\.slot) == [0])
        #expect(h.counts.framesDropped == 2)
        #expect(h.counts.framesRepeatedIdle == 0)
        var log = h.appended
        let flushed = h.scheduler.flushOwed { buffer, slot in
            log.append((slot, buffer))
            return .appended
        }
        #expect(flushed)
        #expect(log.map(\.slot) == [0, 1, 2])
        h.checkInvariant()
    }

    @Test func aFrameTwoSlotsLateCountsAsDropped() {
        var h = Harness()
        for n in 0..<5 { _ = h.frame(slot: Double(n)) }
        h.advance(to: 7)  // slots 5 and 6 repeat: nothing has arrived yet
        #expect(h.counts.framesRepeatedIdle == 2)
        let late = h.frame(slot: 5)  // frame 5 arrives two slots late
        h.advance(to: 8)
        #expect(h.buffer(atSlot: 7) === late.pixelBuffer)
        #expect(h.counts.framesDropped == 2)
        #expect(h.counts.framesRepeatedIdle == 0)
        #expect(h.counts.framesFresh == 6)
        h.checkInvariant()
    }

    @Test func aFrameOneSlotLateIsNotADrop() {
        var h = Harness()
        for n in 0..<5 { _ = h.frame(slot: Double(n)) }
        h.advance(to: 6)
        _ = h.frame(slot: 5)
        h.advance(to: 7)
        #expect(h.counts.framesDropped == 0)
        #expect(h.counts.framesRepeatedIdle == 1)
        h.checkInvariant()
    }

    @Test func aSupersededFrameCountsAsSkipped() {
        var h = Harness()
        _ = h.frame(slot: 0)
        _ = h.frame(slot: 1)
        let newer = h.frame(slot: 1.3)
        h.advance(to: 2)
        #expect(h.counts.sourceFramesSkipped == 1)
        #expect(h.buffer(atSlot: 1) === newer.pixelBuffer)
        #expect(h.counts.framesDropped == 0)
        h.checkInvariant()
    }

    @Test func aWrongSizeFrameIsSkippedAndThePreviousFrameRepeats() {
        var h = Harness()
        let first = h.frame(slot: 0)
        _ = h.frame(slot: 1, size: PixelSize(width: 10, height: 10))
        h.advance(to: 2)
        #expect(h.counts.sourceFramesSkipped == 1)
        #expect(h.counts.wrongSizeFrames == 1)
        #expect(h.buffer(atSlot: 1) === first.pixelBuffer)
        #expect(h.counts.framesRepeatedIdle == 1)
        h.checkInvariant()
    }

    @Test func aPendingFrameLeftAtTheEndIsSkipped() {
        var h = Harness(limit: 3)
        _ = h.frame(slot: 0)
        _ = h.frame(slot: 1)
        h.scheduler.finish()
        #expect(h.counts.sourceFramesSkipped == 1)
    }

    @Test func aWriteFailureStopsTheScheduler() {
        var h = Harness()
        h.failOnSlot = 2
        for n in 0..<6 { _ = h.frame(slot: Double(n)) }
        #expect(h.scheduler.failed)
        #expect(h.appended.map(\.slot) == [0, 1])
    }
}
