import CoreMedia
import Foundation

/// The real host clock: `CMClockGetHostTimeClock()` seconds, the time base ScreenCaptureKit stamps frames with.
/// Sleeps on the suspending clock (the same uptime base) and re-checks, so it never wakes early.
public struct HostTimeClock: HostClock {
    public init() {}

    public func now() -> TimeInterval {
        CMClockGetTime(CMClockGetHostTimeClock()).seconds
    }

    public func sleep(until deadline: TimeInterval) async throws {
        while true {
            let remaining = deadline - now()
            if remaining <= 0 { return }
            try await Task.sleep(for: .seconds(remaining), tolerance: .microseconds(250), clock: .suspending)
        }
    }
}
