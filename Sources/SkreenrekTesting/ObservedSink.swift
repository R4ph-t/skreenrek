import CoreVideo
import Foundation
import SkreenrekCore
import Synchronization

/// Wraps a real sink (usually `ClipWriter`) and counts appended slots, noting the clock time of the first append.
/// Tests wait on the count instead of sleeping; perf tests time requests against the first append.
public final class ObservedSink: PixelBufferSink {
    private struct State {
        var appended = 0
        var firstAppend: TimeInterval?
        var watchers: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    }

    private let inner: any PixelBufferSink
    private let clock: any HostClock
    private let state = Mutex(State())

    public init(_ inner: any PixelBufferSink, clock: any HostClock) {
        self.inner = inner
        self.clock = clock
    }

    /// Slots appended so far.
    public var appendedCount: Int { state.withLock { $0.appended } }
    /// The clock time of the first successful append.
    public var firstAppendTime: TimeInterval? { state.withLock { $0.firstAppend } }

    /// Returns once `count` slots have been appended.
    public func waitForAppends(_ count: Int) async {
        await withCheckedContinuation { continuation in
            let done = state.withLock { s -> Bool in
                if s.appended >= count { return true }
                s.watchers.append((count, continuation))
                return false
            }
            if done { continuation.resume() }
        }
    }

    public var encoder: EncoderKind { inner.encoder }
    public var isReady: Bool { inner.isReady }

    public func append(_ pixelBuffer: CVPixelBuffer, slot: Int) -> Bool {
        let ok = inner.append(pixelBuffer, slot: slot)
        if ok {
            let now = clock.now()
            let ready = state.withLock { s in
                s.appended += 1
                if s.firstAppend == nil { s.firstAppend = now }
                let ready = s.watchers.filter { $0.count <= s.appended }.map(\.continuation)
                s.watchers.removeAll { $0.count <= s.appended }
                return ready
            }
            for continuation in ready { continuation.resume() }
        }
        return ok
    }

    public func waitUntilReady(timeout: TimeInterval) async -> Bool { await inner.waitUntilReady(timeout: timeout) }
    public func finish(slotCount: Int) async throws { try await inner.finish(slotCount: slotCount) }
    public func cancel() async { await inner.cancel() }
}

/// A sink that takes every slot at once and writes nothing: never blocks, so many recordings can run side by side in
/// one test process. Use `ClipWriter` (through `SinkLog.factory(clock:encode: true)`) when a test reads the video.
public final class NullSink: PixelBufferSink {
    public init() {}

    public var encoder: EncoderKind { .software }
    public var isReady: Bool { true }
    public func append(_ pixelBuffer: CVPixelBuffer, slot: Int) -> Bool { true }
    public func waitUntilReady(timeout: TimeInterval) async -> Bool { true }
    public func finish(slotCount: Int) async throws {}
    public func cancel() async {}
}

/// Collects the sinks a factory made, newest last.
public final class SinkLog: Sendable {
    private let sinks = Mutex<[ObservedSink]>([])

    public init() {}

    public var all: [ObservedSink] { sinks.withLock { $0 } }
    public var latest: ObservedSink? { sinks.withLock { $0.last } }

    /// A `RecordingSession.SinkFactory` that makes a `ClipWriter` (or, with `encode: false`, a `NullSink`), wraps it
    /// and logs it. An offline `ClipWriter` blocks its thread while the encoder catches up, so only a test that reads
    /// the video should encode.
    public func factory(clock: any HostClock, encode: Bool = true) -> RecordingSession.SinkFactory {
        { [self] settings in
            let inner: any PixelBufferSink = encode ? try ClipWriter(settings: settings) : NullSink()
            let sink = ObservedSink(inner, clock: clock)
            sinks.withLock { $0.append(sink) }
            return sink
        }
    }
}
