import AppKit
import SkreenrekCore
@testable import SkreenrekUI
import SwiftUI
import Testing

@Suite struct OnboardingLayoutTests {
    /// Every step shares one fixed 520 × 400 pt window: step 2's content plus the 24 pt gap to the footer fills it
    /// exactly, and step 1 is shorter, so nothing grows past the window or leaves the old ~100 pt gap.
    @Test func bothStepsFitOneTrimmedWindow() async throws {
        try await onMain("onboarding layout") {
            #expect(OnboardingView.size == CGSize(width: 520, height: 400))
            #expect(OnboardingView.footerGap == 24)
            for sample in CaptureRenderSamples.onboardingStates {
                let name = "skreenrek-onboarding-layout.\(UUID().uuidString)"
                let defaults = UserDefaults(suiteName: name)!
                defer { defaults.removePersistentDomain(forName: name) }
                let model = OnboardingModel.preview(sample, defaults: defaults)
                let size = NSHostingView(rootView: OnboardingView(model: model)).fittingSize
                #expect(size == OnboardingView.size, "\(sample.name)")
            }
        }
    }

    /// Four long errors don't fit 400 pt. The window grows with them, so nothing is clipped and the buttons stay.
    @Test func windowGrowsToFitConnectErrors() async throws {
        try await onMain("onboarding window grows") {
            let name = "skreenrek-onboarding-layout.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let home = FileManager.default.temporaryDirectory.appendingPathComponent(name).resolvingSymlinksInPath()
            defer { try? FileManager.default.removeItem(at: home) }
            let files = FileManager.default
            for folder in [".claude", ".codex", ".cursor", ".local/bin"] {
                try files.createDirectory(at: home.appendingPathComponent(folder), withIntermediateDirectories: true)
            }
            for file in [".claude.json", ".cursor/mcp.json", ".codex/config.toml", ".local/bin/skreenrek"] {
                try Data("{ broken".utf8).write(to: home.appendingPathComponent(file))
            }
            let installer = AgentInstaller(home: home, executablePath: "/unused/skreenrek", path: "")
            let model = OnboardingModel.preview(CaptureRenderSamples.onboardingStates[0], defaults: defaults, install: {
                installer.run(agents: $0)
            })
            model.preview(.agents)
            let window = OnboardingWindowController.makeWindow(model: model)
            defer { window.close() }
            #expect(window.contentLayoutRect.size == OnboardingView.size)
            let view = try #require(window.contentViewController?.view)
            model.selected = [.claude, .codex, .cli]
            model.connect()
            #expect(model.allConnectsFailed)
            for _ in 0..<200 where window.contentLayoutRect.height <= OnboardingView.size.height {
                await Task.yield()
                window.layoutIfNeeded()
            }
            #expect(window.contentLayoutRect.height > OnboardingView.size.height)
            #expect(window.contentLayoutRect.height == view.fittingSize.height)
        }
    }
}
