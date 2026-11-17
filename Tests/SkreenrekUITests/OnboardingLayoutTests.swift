import AppKit
import SkreenrekCore
@testable import SkreenrekUI
import SwiftUI
import Testing

@Suite struct OnboardingLayoutTests {
    /// Both steps share one fixed 520 × 400 pt window: step 2's content plus the 24 pt gap to the footer fills it
    /// exactly, and step 1 is shorter, so nothing grows past the window or leaves the old ~100 pt gap.
    @Test func bothStepsFitOneTrimmedWindow() async throws {
        try await onMain("onboarding layout") {
            #expect(OnboardingView.size == CGSize(width: 520, height: 400))
            #expect(OnboardingView.footerGap == 24)
            for sample in CaptureRenderSamples.onboardingStates {
                let name = "skreenrek-onboarding-layout.\(UUID().uuidString)"
                let defaults = UserDefaults(suiteName: name)!
                defer { defaults.removePersistentDomain(forName: name) }
                defaults.set(sample.step, forKey: "onboarding.step")
                let model = OnboardingModel(
                    permissions: StaticPermissions(screenRecording: sample.screen, accessibility: sample.accessibility),
                    requester: PreviewPermissionRequester(), defaults: defaults,
                    agents: AgentClient.allCases.map { OnboardingAgent(agent: $0, detected: $0 != .cursor) },
                    install: { _ in [] })
                for permission in sample.requested { model.request(permission) }
                let size = NSHostingView(rootView: OnboardingView(model: model)).fittingSize
                #expect(size == OnboardingView.size, "\(sample.name)")
            }
        }
    }
}
