import Foundation
import SkreenrekCore
import Synchronization
import Testing

@Suite struct DirectCaptureApprovalTests {
    private final class Clock: Sendable {
        let now = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
        func advance(days: Double) { now.withLock { $0 += days * 24 * 60 * 60 } }
    }

    @Test func approvedOnlyWithScreenRecordingAndForLessThanAMonth() {
        let scratch = ScratchDefaults()
        defer { scratch.remove() }
        let defaults = scratch.defaults
        let clock = Clock()
        let approval = DirectCaptureApproval(defaults: defaults, now: { clock.now.withLock { $0 } })
        #expect(approval.status(screenRecording: .allowed) == .missing)
        approval.record()
        #expect(approval.status(screenRecording: .allowed) == .allowed)
        clock.advance(days: 26.9)
        #expect(approval.status(screenRecording: .allowed) == .allowed)
        // macOS asks again about once a month: onboarding asks first.
        clock.advance(days: 0.2)
        #expect(approval.status(screenRecording: .allowed) == .missing)
        approval.record()
        #expect(approval.status(screenRecording: .allowed) == .allowed)
        // Screen Recording revoked (tccutil reset): the record is cleared, so the next grant asks again.
        #expect(approval.status(screenRecording: .missing) == .missing)
        #expect(approval.approvedAt == nil)
        #expect(approval.status(screenRecording: .allowed) == .missing)
    }

    @Test func aClockSetBackDoesNotCountAsApproved() {
        let scratch = ScratchDefaults()
        defer { scratch.remove() }
        let defaults = scratch.defaults
        let clock = Clock()
        let approval = DirectCaptureApproval(defaults: defaults, now: { clock.now.withLock { $0 } })
        approval.record()
        clock.advance(days: -1)
        #expect(approval.status(screenRecording: .allowed) == .missing)
    }

    @Test func errorsNameTheStepAndExitThree() {
        let error = SkreenrekError.permissionDenied(.directCapture)
        #expect(error.exitCode == 3 && error.code == "permission_denied")
        #expect(error.hint.contains("private window picker"))
    }
}
