import Darwin
import Dispatch
import SkreenrekCore

/// SIGINT through a dispatch signal source. While a stream is alive SIGINT is ignored by the process (so Ctrl-C
/// doesn't kill it) and arrives on the stream; the default action comes back when the stream ends.
public struct SignalInterruptSource: InterruptSource {
    /// A dispatch source, only touched to cancel it once.
    private struct Source: @unchecked Sendable {
        let source: any DispatchSourceSignal
    }

    public init() {}

    public func interrupts() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        source.setEventHandler { continuation.yield() }
        source.resume()
        let box = Source(source: source)
        continuation.onTermination = { _ in
            box.source.cancel()
            signal(SIGINT, SIG_DFL)
        }
        return stream
    }
}
