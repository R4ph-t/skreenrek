import AppKit
import SkreenrekCore
import Synchronization

/// Mouse downs and ups from global and local `NSEvent` monitors, and the cursor from `NSEvent.mouseLocation`.
///
/// Thin: it only forwards what AppKit reports. Mouse-button monitors need no permission, and this never asks for one;
/// if no events arrive, the events file is still written with empty `events` and `clicks`. Host times come from the
/// injected clock so they share the recorder's time base.
public final class NSEventMouseSource: MouseEventSource {
    /// An `NSEvent` monitor token. AppKit hands back `Any`; it is only touched on the main actor.
    private struct Monitor: @unchecked Sendable {
        let token: Any
    }

    private struct State {
        var continuation: AsyncStream<MouseEvent>.Continuation?
        var monitors: [Monitor] = []
    }

    private static let mask: NSEvent.EventTypeMask = [
        .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
    ]

    private let clock: any HostClock
    private let state = Mutex(State())

    public init(clock: any HostClock) {
        self.clock = clock
    }

    public func start() async throws -> AsyncStream<MouseEvent> {
        await stop()
        let (stream, continuation) = AsyncStream<MouseEvent>.makeStream()
        state.withLock { $0.continuation = continuation }
        let monitors = await MainActor.run { [self] () -> [Monitor] in
            var monitors: [Monitor] = []
            if let global = NSEvent.addGlobalMonitorForEvents(matching: Self.mask, handler: { [self] event in
                forward(event)
            }) {
                monitors.append(Monitor(token: global))
            }
            if let local = NSEvent.addLocalMonitorForEvents(matching: Self.mask, handler: { [self] event in
                forward(event)
                return event
            }) {
                monitors.append(Monitor(token: local))
            }
            return monitors
        }
        state.withLock { $0.monitors = monitors }
        return stream
    }

    public func stop() async {
        let (continuation, monitors) = state.withLock { s in
            defer {
                s.continuation = nil
                s.monitors = []
            }
            return (s.continuation, s.monitors)
        }
        if !monitors.isEmpty {
            await MainActor.run {
                for monitor in monitors { NSEvent.removeMonitor(monitor.token) }
            }
        }
        continuation?.finish()
    }

    public func cursorLocation() -> CGPoint {
        Self.geometry.topLeft(fromAppKit: NSEvent.mouseLocation)
    }

    @MainActor
    private func forward(_ event: NSEvent) {
        let type: MouseEventType
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: type = .down
        case .leftMouseUp, .rightMouseUp, .otherMouseUp: type = .up
        default: return
        }
        let appKit = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? event.locationInWindow
        let mouseEvent = MouseEvent(
            type: type, button: event.buttonNumber, clickCount: event.clickCount,
            location: Self.geometry.topLeft(fromAppKit: appKit),
            hostTime: clock.now())
        state.withLock { $0.continuation }?.yield(mouseEvent)
    }

    /// AppKit's y axis starts at the primary display's bottom edge; `ScreenGeometry` flips it with that height.
    private static var geometry: ScreenGeometry {
        ScreenGeometry(primaryHeight: Double(CGDisplayBounds(CGMainDisplayID()).height))
    }
}
