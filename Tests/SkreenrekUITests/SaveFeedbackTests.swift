import Foundation
import SkreenrekControl
import SkreenrekCore
import SkreenrekTesting
@testable import SkreenrekUI
import Testing

/// Record → stop with the fake recorder through the real controller, following the controller's snapshot stream the
/// way the app does: the moment the clip is saved, the HUD says so, the icon is back to idle and Last Clip shows it.
@MainActor private final class HUDBox {
    var model = HUDModel()
    var waiter: (condition: () -> Bool, continuation: CheckedContinuation<Void, Never>)?
    /// Returns once `condition` holds, checked on every model change (no polling, no sleeps).
    func until(_ condition: @escaping () -> Bool) async {
        if condition() { return }
        await withCheckedContinuation { waiter = (condition, $0) }
    }
    func changed() {
        if let waiter, waiter.condition() { self.waiter = nil; waiter.continuation.resume() }
    }
}

@Suite struct SaveFeedbackTests {
    @MainActor private static func follow(_ h: MenuHarness, into hud: HUDBox, indicator: Bool) async {
        h.model.onChange = { [model = h.model] in
            hud.model.observe(model.snapshot, now: 0, indicatorEnabled: indicator)
            hud.changed()
        }
        h.model.settings.outputFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("skreenrek-save-feedback-\(UUID().uuidString)")
        await h.model.start()
    }


    @Test(.timeLimit(.minutes(1)), arguments: [true, false])
    func savingShowsTheClipRightAway(indicator: Bool) async throws {
        try await onMain("saved feedback", seconds: 20) {
            let h = MenuHarness(frames: 31)
            defer { h.cleanUp(); h.model.stop() }
            let hud = HUDBox()
            await Self.follow(h, into: hud, indicator: indicator)
            await h.model.perform(.pickWindow)
            await h.model.perform(.record)
            await hud.until { h.model.snapshot.state == .recording }
            #expect(h.model.icon.symbol == StatusIconModel.Symbol.recording)
            try await #require(h.sinks.latest).waitForAppends(30)
            await h.model.perform(.stop)
            await hud.until { h.model.snapshot.state == .idle && h.model.snapshot.lastClip != nil }
            let clip = try #require(h.model.snapshot.lastClip)
            // (1) A confirmation the user sees. Saved is a recording indicator too (control bar addendum 2, §C), so
            // with the indicator turned off it shows nowhere.
            if indicator {
                #expect(hud.model.state == .saved(duration: clip.recording.duration, path: clip.files.clip))
            } else {
                #expect(hud.model.state == .hidden)
            }
            // (2) The menu bar icon is back to idle.
            #expect(h.model.icon.symbol == StatusIconModel.Symbol.idle)
            // (3) Last Clip lists the new clip with its actions.
            let titles = h.model.entries.compactMap { entry -> String? in
                if case .item(let item) = entry { return item.title } else { return nil }
            }
            #expect(titles.contains(UIStrings.Menu.showInFinder) && titles.contains(UIStrings.Menu.copyFilePath))
            #expect(h.model.entries.contains(.header(UIStrings.Menu.lastClip)))
        }
    }

    @Test(.timeLimit(.minutes(1))) func aFailedRecordingShowsItsErrorTheSameWay() async throws {
        try await onMain("failed feedback", seconds: 20) {
            let h = MenuHarness(frames: 31, endError: FrameSourceError.windowClosed)
            defer { h.cleanUp(); h.model.stop() }
            let hud = HUDBox()
            await Self.follow(h, into: hud, indicator: false)
            await h.model.perform(.pickWindow)
            await h.model.perform(.record)
            // The window closes after the last frame: the recorder stops on its own.
            await hud.until { h.model.snapshot.state == .error }
            #expect(hud.model.state == .error(reason: "the window closed"))
            #expect(h.model.icon.symbol != StatusIconModel.Symbol.recording)
        }
    }

    @Test func savedHUDOffersShowInFinderAndCopyPath() {
        #expect(UIStrings.HUD.saved(42) == "Saved · 0:42")
        #expect(UIStrings.Menu.copyFilePath == "Copy File Path")
    }
}
