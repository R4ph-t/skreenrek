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
}
