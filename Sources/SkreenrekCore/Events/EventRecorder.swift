import CoreGraphics
import Foundation
import Synchronization

/// Cursor samples and mouse events in video space, ready for `EventsFile`.
public struct EventLog: Sendable, Hashable {
    public var samples: [CursorSample]
    public var events: [EventsFile.Event]

    public init(samples: [CursorSample] = [], events: [EventsFile.Event] = []) {
        self.samples = samples
        self.events = events
    }
}

/// Collects mouse downs and ups and one cursor sample per written video slot for one recording.
///
/// The recorder's tick hook calls `firstFrame(hostTime:)` once with the first frame's host time and `sample(hostTime:)`
/// once per written slot. Everything is kept in raw host time and global points until `stop()`, which converts it to
/// video pixels with `t` = host time − first frame host time (seconds, 3 decimals). Anything before the first frame is
/// dropped; with no first frame the log is empty.
public final class EventRecorder: Sendable {
    private struct RawSample {
        var hostTime: TimeInterval
        var location: CGPoint
    }

    private struct State {
        var firstFrame: TimeInterval?
        var samples: [RawSample] = []
        var events: [MouseEvent] = []
        var consumer: Task<Void, Never>?
        var started = false
    }

    private let source: any MouseEventSource
    public let mapping: VideoMapping
    public let fps: FrameRate
    private let state = Mutex(State())

    public init(source: any MouseEventSource, mapping: VideoMapping, fps: FrameRate) {
        self.source = source
        self.mapping = mapping
        self.fps = fps
    }

    /// The capture target (a window frame in pt or a region in px) on its display, at the display's scale.
    /// `clip` is the video size when it isn't the target's native pixels.
    public convenience init(
        source: any MouseEventSource, target: CaptureTarget, display: DisplayInfo, fps: FrameRate,
        clip: PixelSize? = nil
    ) {
        self.init(source: source, mapping: VideoMapping(target: target, display: display, clip: clip), fps: fps)
    }

    /// Starts the mouse event source. Call before the first frame so early clicks are not missed.
    public func start() async throws {
        let stream = try await source.start()
        let consumer = Task { [self] in
            for await event in stream {
                record(event)
            }
        }
        state.withLock { s in
            s.consumer = consumer
            s.started = true
        }
    }

    private func record(_ event: MouseEvent) {
        state.withLock { $0.events.append(event) }
    }

    /// Sets t = 0. Only the first call counts.
    public func firstFrame(hostTime: TimeInterval) {
        state.withLock { s in
            if s.firstFrame == nil { s.firstFrame = hostTime }
        }
    }

    /// Samples `cursorLocation()` for one written slot at that slot's host time.
    public func sample(hostTime: TimeInterval) {
        let location = source.cursorLocation()
        state.withLock { $0.samples.append(RawSample(hostTime: hostTime, location: location)) }
    }

    /// Stops the source, waits for every delivered event, and returns the log in video space.
    public func stop() async -> EventLog {
        let started = state.withLock { $0.started }
        if started { await source.stop() }
        let consumer = state.withLock { s -> Task<Void, Never>? in
            let c = s.consumer
            s.consumer = nil
            s.started = false
            return c
        }
        await consumer?.value
        return log()
    }

    /// The log so far, in video space.
    public func log() -> EventLog {
        let (first, samples, events) = state.withLock { ($0.firstFrame, $0.samples, $0.events) }
        guard let first else { return EventLog() }
        let mapping = self.mapping
        return EventLog(
            samples: samples.compactMap { s in
                guard s.hostTime >= first else { return nil }
                let p = mapping.pixel(s.location)
                return CursorSample(t: Self.seconds(s.hostTime - first), x: p.x, y: p.y)
            },
            events: events.compactMap { e in
                guard e.hostTime >= first else { return nil }
                let p = mapping.pixel(e.location)
                return EventsFile.Event(
                    t: Self.seconds(e.hostTime - first), type: e.type, button: MouseButton(index: e.button),
                    clickCount: e.clickCount, x: p.x, y: p.y)
            })
    }

    /// Seconds rounded to 3 decimals.
    static func seconds(_ value: TimeInterval) -> Double {
        (value * 1000).rounded() / 1000
    }
}
