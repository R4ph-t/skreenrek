import Foundation
import SkreenrekCore
import Synchronization

/// Records launches and runs `onLaunch` (e.g. starting a `HeadlessHost`, so the socket appears).
public final class FakeAppLauncher: AppLauncher {
    private struct State {
        var launches: [URL] = []
    }

    private let state = Mutex(State())
    private let onLaunch: @Sendable (URL) throws -> Void

    public init(onLaunch: @escaping @Sendable (URL) throws -> Void = { _ in }) {
        self.onLaunch = onLaunch
    }

    /// Every bundle asked for, in order.
    public var launches: [URL] { state.withLock { $0.launches } }

    public func launchHidden(appAt bundle: URL) async throws {
        state.withLock { $0.launches.append(bundle) }
        try onLaunch(bundle)
    }
}
