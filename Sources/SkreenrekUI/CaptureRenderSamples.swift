import SkreenrekCore

/// One catalogue drives the render command and its completeness assertions. No real system effects.
public enum CaptureRenderSamples {
    public struct HUDSample: Sendable {
        public let name: String
        public let state: HUDState
    }
    public struct OnboardingSample: Sendable {
        public let name: String
        public let step: Int
        public let screen: PermissionStatus
        public let accessibility: PermissionStatus
    }
    public static let hudStates: [HUDSample] = [
        HUDSample(name: "recording", state: .recording(target: "Safari", seconds: 12)),
        HUDSample(name: "writing", state: .writing),
        HUDSample(name: "saved", state: .saved(duration: 42, path: "/unused/clip.mp4")),
        HUDSample(name: "error", state: .error(reason: "the window closed")),
        HUDSample(name: "writing-reducedmotion", state: .writing),
        HUDSample(name: "recording-contrast", state: .recording(target: "Safari", seconds: 12)),
    ]
    public static let onboardingStates: [OnboardingSample] = [
        OnboardingSample(name: "permissions-missing", step: 1, screen: .missing, accessibility: .missing),
        OnboardingSample(name: "permissions-screenallowed", step: 1, screen: .allowed, accessibility: .missing),
        OnboardingSample(name: "permissions-accessibilityallowed", step: 1, screen: .missing, accessibility: .allowed),
        OnboardingSample(name: "permissions-allowed", step: 1, screen: .allowed, accessibility: .allowed),
        OnboardingSample(name: "agents", step: 2, screen: .allowed, accessibility: .allowed),
    ]
}

@MainActor
struct PreviewPermissionRequester: PermissionRequester {
    func request(_ permission: Permission) {}
}
