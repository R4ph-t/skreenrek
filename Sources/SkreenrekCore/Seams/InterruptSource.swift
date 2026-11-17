/// Ctrl-C (SIGINT) while a command waits. Real: `SignalInterruptSource`. Fake: `FakeInterruptSource`.
public protocol InterruptSource: Sendable {
    /// One element per interrupt. While a stream is alive, interrupts don't end the process; they only arrive here.
    func interrupts() -> AsyncStream<Void>
}
