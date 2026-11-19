import AppKit
import SkreenrekCore
@testable import SkreenrekUI
import SwiftUI
import Testing

@Suite struct OnboardingLayoutTests {
    /// Every step shares one fixed 520 × 400 pt content area under the 28 pt title bar band: step 2's content plus the
    /// 24 pt gap to the footer fills it exactly, and step 1 is shorter, so nothing grows past the window or leaves the
    /// old ~100 pt gap.
    @Test func bothStepsFitOneTrimmedWindow() async throws {
        try await onMain("onboarding layout") {
            #expect(OnboardingView.size == CGSize(width: 520, height: 400))
            #expect(OnboardingView.footerGap == 24)
            #expect(OnboardingView.titleBarHeight == 28)
            #expect(OnboardingView.windowSize == CGSize(width: 520, height: 428))
            for sample in CaptureRenderSamples.onboardingStates {
                let name = "skreenrek-onboarding-layout.\(UUID().uuidString)"
                let defaults = UserDefaults(suiteName: name)!
                defer { defaults.removePersistentDomain(forName: name) }
                let model = OnboardingModel.preview(sample, defaults: defaults)
                let size = NSHostingView(rootView: OnboardingView(model: model)).fittingSize
                #expect(size == OnboardingView.windowSize, "\(sample.name)")
            }
        }
    }

    /// Onboarding shares Settings' surface: a transparent title bar over `surface.base`, with the title kept for the
    /// Window menu and VoiceOver.
    @Test func theWindowIsOneToneUnderATransparentTitleBar() async throws {
        try await onMain("onboarding window chrome") {
            let name = "skreenrek-onboarding-chrome.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let model = OnboardingModel.preview(CaptureRenderSamples.onboardingStates[0], defaults: defaults)
            let window = OnboardingWindowController.makeWindow(model: model)
            defer { window.close() }
            #expect(window.styleMask.contains(.fullSizeContentView))
            #expect(window.titlebarAppearsTransparent)
            #expect(window.titleVisibility == .hidden)
            #expect(window.backgroundColor == SkreenrekSurface.baseColor)
            #expect(window.title == UIStrings.Onboarding.title)
            #expect(!window.title.isEmpty)
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
            let view = try #require(window.contentViewController?.view)
            // The content runs under the transparent title bar: the whole window is the band plus the steps.
            #expect(view.frame.size == OnboardingView.windowSize)
            model.selected = [.claude, .codex, .cli]
            model.connect()
            #expect(model.allConnectsFailed)
            for _ in 0..<200 where view.frame.height <= OnboardingView.windowSize.height {
                await Task.yield()
                window.layoutIfNeeded()
            }
            #expect(view.frame.height > OnboardingView.windowSize.height)
            #expect(view.frame.height == view.fittingSize.height)
        }
    }
}
