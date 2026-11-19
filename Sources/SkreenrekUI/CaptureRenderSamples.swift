import SkreenrekCore

/// One catalogue drives the render command and its completeness assertions. No real system effects.
public enum CaptureRenderSamples {
    public struct HUDSample: Sendable {
        public let name: String
        public let state: HUDState
    }
    public struct OnboardingSample: Sendable {
        public let name: String
        public let step: OnboardingStep
        public var screen: PermissionStatus = .missing
        public var direct: PermissionStatus = .missing
        public var accessibility: PermissionStatus = .missing
        /// Permissions requested in this run (Screen Recording shows Quit & Reopen while still missing).
        public var requested: [Permission] = []
        /// Onboarding was completed before (opened again for a missing permission: three steps, no agents).
        public var completed = false
    }
    public static let hudStates: [HUDSample] = [
        HUDSample(name: "recording", state: .recording(target: "Safari", seconds: 12)),
        HUDSample(name: "recording-tenminutes", state: .recording(target: "Safari", seconds: 600)),
        HUDSample(name: "writing", state: .writing),
        HUDSample(name: "saved", state: .saved(duration: 42, path: "/unused/2026-11-17_104207_safari/2026-11-17_104207_safari.mp4")),
        HUDSample(name: "error", state: .error(reason: "the window closed")),
        HUDSample(name: "writing-reducedmotion", state: .writing),
        HUDSample(name: "recording-contrast", state: .recording(target: "Safari", seconds: 12)),
    ]
    public static let onboardingStates: [OnboardingSample] = [
        OnboardingSample(name: "1-screenrecording", step: .screenRecording),
        OnboardingSample(name: "1-screenrecording-relaunch", step: .screenRecording, requested: [.screenRecording]),
        OnboardingSample(name: "2-directcapture", step: .directCapture, screen: .allowed),
        OnboardingSample(name: "2-directcapture-askagain", step: .directCapture, screen: .allowed,
                         requested: [.directCapture]),
        OnboardingSample(name: "2-directcapture-allowed", step: .directCapture, screen: .allowed, direct: .allowed),
        OnboardingSample(name: "3-accessibility", step: .accessibility, screen: .allowed, direct: .allowed),
        OnboardingSample(name: "3-accessibility-allowed", step: .accessibility, screen: .allowed, direct: .allowed,
                         accessibility: .allowed),
        OnboardingSample(name: "4-agents", step: .agents, screen: .allowed, direct: .allowed, accessibility: .allowed),
        OnboardingSample(name: "missing-directcapture-later", step: .directCapture, screen: .allowed,
                         accessibility: .allowed, completed: true),
    ]
}

@MainActor
struct PreviewPermissionRequester: PermissionRequester {
    func request(_ permission: Permission) {}
}
