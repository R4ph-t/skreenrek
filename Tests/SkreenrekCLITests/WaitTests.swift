import Foundation
import SkreenrekCLI
import SkreenrekControl
import SkreenrekCore
import SkreenrekTesting
import Testing

/// `record --wait`: blocks until the recording ends; a simulated Ctrl-C stops, saves and exits 130.
@Suite(.timeLimit(.minutes(2))) struct WaitTests {
    @Test func ctrlCStopsSavesPrintsTheStopOutputAndExits130() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        async let run = h.run(["record", "--app", "Safari", "--wait"])
        let interrupts = h.interrupts
        try await within("the interrupt stream") { await interrupts.waitForSubscriptions(1) }
        try await h.waitForEndWaiters(1)
        try await h.waitForSlots(5)
        interrupts.interrupt()
        let result = try await run
        #expect(result.code == 130, "\(result)")
        #expect(result.err.isEmpty)
        let body = try await h.client().call(.last, as: StopBody.self)
        let folder = h.tildeFolder(body.recording.id)
        #expect(result.out == """
            ● Recording at 60 fps. Stop with: skreenrek stop
            ✓ Saved \(TimeFormat.minutesSeconds(body.recording.duration)) · 1280 × 800 px · 60 fps
              clip    \(folder)/\(body.recording.id).mp4
              events  \(folder)/events.json
              snippet \(folder)/hyperframes.html
              note    software encoder

            """)
        #expect(try await h.client().call(.status, as: StatusBody.self).state == .idle)
    }

    @Test func ctrlCWithJSONPrintsOnlyTheStopBody() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        async let run = h.run(["record", "--app", "Safari", "--wait", "--json"])
        let interrupts = h.interrupts
        try await within("the interrupt stream") { await interrupts.waitForSubscriptions(1) }
        try await h.waitForEndWaiters(1)
        try await h.waitForSlots(5)
        interrupts.interrupt()
        let result = try await run
        #expect(result.code == 130, "\(result)")
        #expect(result.out.split(separator: "\n").count == 1)
        let body = try result.decode(StopBody.self)
        #expect(body == (try await h.client().call(.last, as: StopBody.self)))
    }

    @Test func theDurationEndsTheWaitWithExit0() async throws {
        // 1 s at 30 fps: frames arrive as the manual clock reaches them.
        let clock = ManualClock()
        let source = SyntheticFrameSource(timing: .onClock(clock, (0...30).map { Double($0) / 30 }))
        let h = try CLIHarness(source: source, clock: clock).start()
        defer { h.stop() }
        async let run = h.run(["record", "--app", "Safari", "--fps", "30", "--duration", "1s", "--wait"])
        try await h.waitForEndWaiters(1)
        clock.advance(to: 1 + RecordingSession.defaultTickGrace)
        let result = try await run
        #expect(result.code == 0, "\(result)")
        let body = try await h.client().call(.last, as: StopBody.self)
        #expect(body.recording.duration == 1)
        #expect(result.out.contains("✓ Saved 0:01 · 1280 × 800 px · 30 fps\n"))
    }

    @Test func aDiscardElsewhereEndsTheWait() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        async let run = h.run(["record", "--app", "Safari", "--wait"])
        try await h.waitForEndWaiters(1)
        _ = try await h.client().call(.recordDiscard, as: DiscardBody.self)
        let result = try await run
        #expect(result.code == 0, "\(result)")
        #expect(result.out.hasSuffix("✓ Discarded the recording.\n"))
    }

    @Test func withoutWaitRecordReturnsAndNeverListensForCtrlC() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        let result = try await h.run(["record", "--app", "Safari"])
        #expect(result.code == 0)
        #expect(h.interrupts.subscriptionCount == 0)
        #expect(try await h.client().call(.status, as: StatusBody.self).state == .recording)
        _ = try await h.client().call(.recordDiscard, as: DiscardBody.self)
    }
}
