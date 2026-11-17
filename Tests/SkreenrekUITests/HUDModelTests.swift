import SkreenrekControl
import SkreenrekCore
@testable import SkreenrekUI
import Testing

@Suite struct HUDModelTests {
    @Test func recordingWritingSavedAndDeadlines() {
        var model = HUDModel()
        var snapshot = UIFixtures.recording(.menu)
        model.observe(snapshot, now: 0)
        #expect(model.state == .recording(target: "Safari", seconds: 12))
        snapshot.state = .writing
        model.observe(snapshot, now: 1)
        #expect(model.state == .writing)
        snapshot.state = .idle
        snapshot.lastClip = RenderSamples.clip()
        model.observe(snapshot, now: 2)
        #expect(model.state == .saved(duration: 42, path: RenderSamples.clip().files.clip))
        model.tick(now: 5.99); #expect(model.state != .hidden)
        model.tick(now: 6); #expect(model.state == .hidden)
        model.observe(snapshot, now: 7); #expect(model.state == .hidden)
    }

    @Test func hoveredSavedLastsEightSecondsAndOldClipDoesNotFlashOnLaunch() {
        var model = HUDModel()
        var idle = UIFixtures.idle
        idle.lastClip = RenderSamples.clip()
        model.observe(idle, now: 0); #expect(model.state == .hidden)
        model.observe(UIFixtures.recording(.mcp), now: 1)
        var fresh = RenderSamples.clip(); fresh.recording.id = "new"
        idle.lastClip = fresh
        model.observe(idle, now: 2)
        model.hovered = true
        model.tick(now: 6); #expect(model.state != .hidden)
        model.tick(now: 9.99); #expect(model.state != .hidden)
        model.tick(now: 10); #expect(model.state == .hidden)
    }

    @Test func errorsPersistAndOptionsSuppressAllStates() {
        var model = HUDModel()
        var snapshot = UIFixtures.recording(.cli)
        snapshot.hud = false
        model.observe(snapshot, now: 0); #expect(model.state == .hidden)
        snapshot.state = .error; snapshot.error = .recordingFailed(.windowClosed(at: 31))
        model.observe(snapshot, now: 1); #expect(model.state == .hidden)
        snapshot = UIFixtures.recording(.menu)
        model.observe(snapshot, now: 2)
        snapshot.state = .error; snapshot.error = .recordingFailed(.windowClosed(at: 31))
        model.observe(snapshot, now: 3)
        #expect(model.state == .error(reason: "the window closed"))
        model.tick(now: 1000); #expect(model.state != .hidden)
        model.dismiss(); #expect(model.state == .hidden)
        model.observe(snapshot, now: 1000.5); #expect(model.state == .hidden)
        model.observe(UIFixtures.recording(.menu), now: 1001, indicatorEnabled: false)
        #expect(model.state == .hidden)
    }

    @Test func placementBelowFallbackAndIndependentRememberedDrags() {
        var placement = HUDPlacement()
        var display = RenderSamples.display
        let target = PointRect(x: 120, y: 80, width: 640, height: 400)
        #expect(placement.frame(target: target, display: display, width: 200)
            == PointRect(x: 340, y: 496, width: 200, height: 36))
        let low = PointRect(x: 120, y: 900, width: 640, height: 60)
        #expect(placement.frame(target: low, display: display, width: 200).y == 930)
        placement.remember(PointRect(x: 200, y: 100, width: 200, height: 36), display: display.id)
        #expect(placement.frame(target: target, display: display, width: 200).y == 100)
        display.id = 2
        #expect(placement.frame(target: target, display: display, width: 200).y == 496)
        display.visibleFrame = PointRect(x: -800, y: -600, width: 800, height: 600)
        let clamped = placement.frame(target: target, display: display, width: 200)
        #expect(display.visibleFrame.cgRect.contains(clamped.cgRect))
    }

    @Test func filterPlanExcludesHUDAndOutlineByPidEvenWithoutBundleID() {
        let plan = CaptureFilterPlan(ownPid: 1234, bundleID: nil)
        #expect(plan.excludes(pid: 1234, bundleID: nil))
        #expect(!plan.excludes(pid: 42, bundleID: nil))
        let bundled = CaptureFilterPlan(ownPid: 1234, bundleID: "it.fraime.skreenrek")
        #expect(bundled.excludes(pid: 99, bundleID: "it.fraime.skreenrek"))
        #expect(!bundled.excludes(pid: 99, bundleID: "com.apple.Safari"))
        #expect(UIStrings.HUD.voiceOver(target: "Safari", seconds: 12) == "Recording Safari, 12 seconds")
        #expect(UIStrings.HUD.saved(42) == "Saved · 0:42")
    }
}
