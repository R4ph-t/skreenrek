import SkreenrekCore
import Synchronization

/// Records every window the controller asked to bring to the front.
public final class FakeWindowFront: WindowFront, Sendable {
    private let state = Mutex<[WindowInfo]>([])

    public init() {}

    /// The windows, in the order they were asked to come forward.
    public var windows: [WindowInfo] { state.withLock { $0 } }

    public func bringToFront(_ window: WindowInfo) async {
        state.withLock { $0.append(window) }
    }
}
