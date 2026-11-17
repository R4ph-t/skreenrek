import CoreVideo
import Foundation

/// What happened when the scheduler tried to append one slot.
public enum SlotAppendOutcome: Sendable, Hashable {
    case appended
    /// The writer input wasn't ready; the slot repeats (counted as dropped) instead of queueing the frame.
    case notReady
    /// The writer failed; recording must stop.
    case failed
}

/// Counters the scheduler keeps; they become `RecordingStats`.
public struct CFRCounts: Sendable, Hashable {
    /// Slots decided (each one is, or will be, one sample in the clip).
    public var slotsWritten = 0
    public var framesFresh = 0
    public var framesRepeatedIdle = 0
    public var framesDropped = 0
    public var sourceFramesSkipped = 0
    /// The part of `sourceFramesSkipped` that was the wrong pixel size.
    public var wrongSizeFrames = 0

    public init() {}
}

/// Turns source frames that arrive at any rate into a constant-frame-rate sequence of slots. Pure: no clock, no I/O;
/// the caller passes the current host time and an `append` function.
///
/// Slot n has host time `t0 + n / fps`, where t0 is the first frame's host time. A frame belongs to the first slot
/// whose time is at least its host time minus half a slot, so capture jitter around a slot boundary doesn't push a
/// frame into the next slot. Each slot takes the newest frame that belongs to it or to an earlier slot; when none
/// arrived, it repeats the last appended buffer. Besides the last appended buffer the scheduler holds at most one
/// pending frame, so memory stays flat for any length and the source's buffer pool never runs dry.
///
/// Slots are decided two ways: when a frame arrives, every slot before it is decided at once (so a steady source
/// never waits on a tick); and `advance(to:)` decides slots that fell due with no new frame (an idle window).
public struct CFRScheduler {
    public let fps: Int
    public let outputSize: PixelSize
    /// Total slots (`duration × fps`), or nil for no limit.
    public let slotLimit: Int?

    public private(set) var t0: TimeInterval?
    /// Slots decided so far: the clip length in frames.
    public private(set) var decidedSlots = 0
    /// Slots actually appended. Lower than `decidedSlots` only while the writer isn't ready (see `flushOwed`).
    public private(set) var appendedSlots = 0
    public private(set) var counts = CFRCounts()
    public private(set) var failed = false

    private var pending: (frame: CapturedFrame, slot: Int)?
    private var lastAppended: CapturedFrame?
    /// Idle repeats directly before the next slot, so a late frame can reclassify them as dropped.
    private var idleRun = 0

    public typealias Append = (CVPixelBuffer, Int) -> SlotAppendOutcome

    public init(fps: Int, outputSize: PixelSize, slotLimit: Int? = nil) {
        self.fps = fps
        self.outputSize = outputSize
        self.slotLimit = slotLimit
    }

    /// True once `slotLimit` slots are decided.
    public var isAtLimit: Bool { slotLimit.map { decidedSlots >= $0 } ?? false }

    /// Source buffers the scheduler holds right now (never more than two).
    public var heldBufferCount: Int { (pending == nil ? 0 : 1) + (lastAppended == nil ? 0 : 1) }

    public var hasPendingFrame: Bool { pending != nil }

    /// The host time of slot n, once the first frame has arrived.
    public func slotTime(_ n: Int) -> TimeInterval? {
        t0.map { $0 + Double(n) / Double(fps) }
    }

    /// The slot a frame with this host time belongs to (0 before the first frame).
    public func slot(forHostTime hostTime: TimeInterval) -> Int {
        guard let t0 else { return 0 }
        // The epsilon keeps float noise at an exact half slot from rounding up.
        return max(0, Int(((hostTime - t0) * Double(fps) - 0.5 - 1e-6).rounded(.up)))
    }

    /// How many slots are due at `now` when a slot falls due `grace` seconds after its time.
    public func dueSlotCount(at now: TimeInterval, grace: TimeInterval) -> Int {
        guard let t0 else { return 0 }
        let x = (now - grace - t0) * Double(fps)
        guard x >= 0 else { return 0 }
        return Int((x + 1e-9).rounded(.down)) + 1
    }

    /// The clip length when recording stops at `now`: every slot up to now, and always the pending frame.
    public func stopSlotCount(at now: TimeInterval) -> Int {
        guard t0 != nil else { return 0 }
        var count = max(decidedSlots, dueSlotCount(at: now, grace: 0))
        if let pending { count = max(count, max(pending.slot, decidedSlots) + 1) }
        return count
    }

    /// Takes one source frame. Returns the slots this decided (possibly none).
    @discardableResult
    public mutating func receive(_ frame: CapturedFrame, append: Append) -> Range<Int> {
        let start = decidedSlots
        guard !failed, !isAtLimit else { return start..<start }
        let buffer = frame.pixelBuffer
        guard CVPixelBufferGetWidth(buffer) == outputSize.width, CVPixelBufferGetHeight(buffer) == outputSize.height
        else {
            counts.sourceFramesSkipped += 1
            counts.wrongSizeFrames += 1
            return start..<start
        }
        guard t0 != nil else {
            // The first frame defines t0 and is slot 0 by definition: write it now, for a fast start.
            t0 = frame.hostTime
            pending = (frame, 0)
            decideNext(append)
            return start..<decidedSlots
        }
        let slot = slot(forHostTime: frame.hostTime)
        while decidedSlots < slot, !isAtLimit, !failed {
            decideNext(append)
        }
        // A frame past the end of a fixed-length clip isn't part of the clip.
        guard !isAtLimit, !failed else { return start..<decidedSlots }
        if pending != nil { counts.sourceFramesSkipped += 1 }
        pending = (frame, slot)
        return start..<decidedSlots
    }

    /// Decides slots until `slotCount` are decided (capped by the limit). Returns the slots this decided.
    @discardableResult
    public mutating func advance(to slotCount: Int, append: Append) -> Range<Int> {
        let start = decidedSlots
        guard t0 != nil else { return start..<start }
        let target = min(slotCount, slotLimit ?? .max)
        while decidedSlots < target, !failed {
            decideNext(append)
        }
        return start..<decidedSlots
    }

    /// Appends slots that were decided while the writer wasn't ready (as repeats). Returns true when none are left.
    public mutating func flushOwed(append: Append) -> Bool {
        while appendedSlots < decidedSlots, !failed {
            guard appendOwed(append) else { return false }
        }
        return appendedSlots == decidedSlots
    }

    /// Ends the recording: a frame still pending was never written.
    public mutating func finish() {
        if pending != nil {
            counts.sourceFramesSkipped += 1
            pending = nil
        }
    }

    // MARK: - Deciding one slot

    private mutating func decideNext(_ append: Append) {
        let n = decidedSlots
        decidedSlots += 1
        counts.slotsWritten = decidedSlots

        // Catch up slots owed while the writer wasn't ready.
        while appendedSlots < n {
            guard appendOwed(append) else { break }
        }
        if failed { return }

        let fresh = pending.flatMap { $0.slot <= n ? $0 : nil }
        if appendedSlots == n, let content = fresh?.frame ?? lastAppended {
            switch append(content.pixelBuffer, n) {
            case .appended:
                appendedSlots = n + 1
                if let fresh {
                    counts.framesFresh += 1
                    // A frame more than one slot late turns the idle repeats it should have filled into drops.
                    let lateness = n - fresh.slot
                    if lateness > 1 {
                        let moved = min(lateness, idleRun)
                        counts.framesRepeatedIdle -= moved
                        counts.framesDropped += moved
                    }
                    idleRun = 0
                    lastAppended = fresh.frame
                    pending = nil
                } else {
                    counts.framesRepeatedIdle += 1
                    idleRun += 1
                }
                return
            case .notReady:
                break
            case .failed:
                failed = true
                return
            }
        }
        // The writer wasn't ready: this slot repeats the previous frame later (see `flushOwed`), and a fresh frame
        // stays pending for the next slot instead of queueing.
        counts.framesDropped += 1
        idleRun = 0
    }

    /// Appends the oldest owed slot as a repeat. Returns false when the writer isn't ready (or failed).
    private mutating func appendOwed(_ append: Append) -> Bool {
        // Before anything was appended the only frame to show is the pending one.
        let usesPending = lastAppended == nil
        guard let content = lastAppended ?? pending?.frame else { return false }
        switch append(content.pixelBuffer, appendedSlots) {
        case .appended:
            appendedSlots += 1
            if usesPending {
                // The owed slot was counted as dropped; it now shows a fresh frame.
                counts.framesDropped -= 1
                counts.framesFresh += 1
                lastAppended = content
                pending = nil
            }
            return true
        case .notReady:
            return false
        case .failed:
            failed = true
            return false
        }
    }
}
