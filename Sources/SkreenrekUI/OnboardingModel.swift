import Foundation
import Observation
import SkreenrekCore

public struct OnboardingAgent: Sendable, Identifiable {
    public let agent: AgentClient
    public let detected: Bool
    public var id: AgentClient { agent }
    public init(agent: AgentClient, detected: Bool) { self.agent = agent; self.detected = detected }
    public var detail: String {
        if agent == .cli { return UIStrings.Onboarding.cliDetail }
        return detected ? UIStrings.Onboarding.found(agent) : UIStrings.Onboarding.notInstalled
    }
}

/// One onboarding page: a permission each, in the order macOS can grant them, then the agents.
public enum OnboardingStep: Int, CaseIterable, Sendable, Hashable {
    case screenRecording = 1
    /// macOS 15's private window picker bypass. It can only be raised once Screen Recording is in effect.
    case directCapture
    case accessibility
    case agents

    public init(_ permission: Permission) {
        switch permission {
        case .screenRecording: self = .screenRecording
        case .directCapture: self = .directCapture
        case .accessibility: self = .accessibility
        }
    }

    public var permission: Permission? {
        switch self {
        case .screenRecording: .screenRecording
        case .directCapture: .directCapture
        case .accessibility: .accessibility
        case .agents: nil
        }
    }

    /// The permission steps, in order.
    public static let permissions: [OnboardingStep] = [.screenRecording, .directCapture, .accessibility]
}

/// The onboarding flow: one step per permission, then the agents. State and effects are explicit. Tests inject the
/// probe, requester and effects; construction and refresh never prompt. Only `request` (a button, or entering the
/// direct-capture step) asks macOS.
@MainActor
@Observable
public final class OnboardingModel {
    static let completedKey = "onboarding.completed"
    /// macOS shows the Screen Recording prompt once per grant, so after one request the step offers System Settings
    /// and Quit & Reopen instead. Kept across relaunches.
    static let screenRecordingRequestedKey = "onboarding.screenRecordingRequested"

    public private(set) var step: OnboardingStep
    public private(set) var completed: Bool
    public private(set) var screenRecording: PermissionStatus
    public private(set) var directCapture: PermissionStatus
    public private(set) var accessibility: PermissionStatus
    public let agents: [OnboardingAgent]
    public var selected: Set<AgentClient>
    public private(set) var results: [AgentSetupResult] = []
    /// The permissions requested in this run of the app.
    public private(set) var requested: Set<Permission> = []
    @ObservationIgnored private let permissions: any PermissionProbe
    @ObservationIgnored private let requester: any PermissionRequester
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let install: ([AgentClient]) -> [AgentSetupResult]
    @ObservationIgnored private let relaunch: () -> Void
    @ObservationIgnored private let openSettings: (Permission) -> Void
    @ObservationIgnored public var didComplete: (() -> Void)?

    public init(permissions: any PermissionProbe, requester: any PermissionRequester, defaults: UserDefaults,
                agents: [OnboardingAgent], install: @escaping ([AgentClient]) -> [AgentSetupResult],
                relaunch: @escaping () -> Void = {}, openSettings: @escaping (Permission) -> Void = { _ in }) {
        self.permissions = permissions; self.requester = requester; self.defaults = defaults
        self.agents = agents; self.install = install; self.relaunch = relaunch; self.openSettings = openSettings
        selected = Set(agents.filter(\.detected).map(\.agent))
        completed = defaults.bool(forKey: Self.completedKey)
        screenRecording = permissions.screenRecording
        directCapture = permissions.directCapture
        accessibility = permissions.accessibility
        step = .screenRecording
        step = startingStep
    }

    // MARK: - State

    public func status(of permission: Permission) -> PermissionStatus {
        switch permission {
        case .screenRecording: screenRecording
        case .directCapture: directCapture
        case .accessibility: accessibility
        }
    }

    /// The first permission still missing, in step order.
    public var firstMissing: Permission? {
        OnboardingStep.permissions.compactMap(\.permission).first { status(of: $0) != .allowed }
    }

    /// What can be recorded needs Screen Recording and direct capture; Accessibility only adds exact sizes.
    public var canCapture: Bool { screenRecording == .allowed && directCapture == .allowed }

    /// On launch: until onboarding is done once, and whenever a capture permission is missing.
    public var shouldShowAtLaunch: Bool { !completed || !canCapture }

    /// The steps this run walks through: the agents only until onboarding is completed once.
    public var steps: [OnboardingStep] { completed ? OnboardingStep.permissions : OnboardingStep.allCases }
    public var stepNumber: Int { (steps.firstIndex(of: step) ?? 0) + 1 }

    private var startingStep: OnboardingStep {
        if let missing = firstMissing { return OnboardingStep(missing) }
        return completed ? .accessibility : .agents
    }

    /// Continue is enabled once the step's permission is allowed. Accessibility isn't blocking.
    public var canContinue: Bool {
        switch step {
        case .screenRecording: screenRecording == .allowed
        case .directCapture: directCapture == .allowed
        case .accessibility, .agents: true
        }
    }

    /// The step after this one: the next permission still missing, else the agents (first run), else none (done).
    var nextStep: OnboardingStep? {
        let index = steps.firstIndex(of: step) ?? 0
        return steps.dropFirst(index + 1).first { $0.permission.map { status(of: $0) != .allowed } ?? true }
    }

    /// "Continue", "Skip" (Accessibility left off) or "Done" (the last step).
    public var continueTitle: String {
        if step == .accessibility, accessibility != .allowed, nextStep != nil { return UIStrings.Onboarding.skip }
        return nextStep == nil ? UIStrings.Onboarding.done : UIStrings.Onboarding.continueButton
    }

    /// The button that asks macOS on this step, or nil when there's nothing to ask: the permission is allowed, or
    /// Screen Recording was already requested once (macOS won't prompt again; System Settings and Quit & Reopen
    /// take over), or direct capture waits for Screen Recording.
    public var requestTitle: String? {
        guard let permission = step.permission, status(of: permission) != .allowed else { return nil }
        switch permission {
        case .screenRecording:
            return screenRecordingRequestedBefore ? nil : UIStrings.Onboarding.allow(.screenRecording)
        case .directCapture:
            guard screenRecording == .allowed else { return nil }
            return requested.contains(.directCapture)
                ? UIStrings.Onboarding.askAgain : UIStrings.Onboarding.allow(.directCapture)
        case .accessibility:
            return UIStrings.Onboarding.allow(.accessibility)
        }
    }

    /// Direct capture can't be asked before Screen Recording is in effect in this process.
    public var waitsForScreenRecording: Bool { step == .directCapture && screenRecording != .allowed }

    private var screenRecordingRequestedBefore: Bool {
        requested.contains(.screenRecording) || defaults.bool(forKey: Self.screenRecordingRequestedKey)
    }

    /// Quit & Reopen: macOS applies a Screen Recording grant only to a new process, so once it was requested and
    /// still reads missing, the Screen Recording step (and direct capture, which waits on it) offers a relaunch.
    /// Accessibility applies live, so it never needs one.
    public var needsRelaunch: Bool {
        (step == .screenRecording || step == .directCapture) && screenRecording == .missing
            && screenRecordingRequestedBefore
    }

    // MARK: - Actions

    /// Reads the permissions again (polled while the window is open). Never prompts.
    public func refresh() {
        screenRecording = permissions.screenRecording
        directCapture = permissions.directCapture
        accessibility = permissions.accessibility
    }

    /// Opens on the first missing permission (or the agents on first run) and asks for it if that step asks on
    /// entry. Used on launch, for "Permissions needed…" and when an action fails for a missing permission.
    public func begin() {
        refresh()
        step = startingStep
        enter()
    }

    /// Asks macOS for this step's permission.
    public func requestCurrent() {
        guard let permission = step.permission else { return }
        request(permission)
    }

    public func request(_ permission: Permission) {
        requested.insert(permission)
        if permission == .screenRecording { defaults.set(true, forKey: Self.screenRecordingRequestedKey) }
        requester.request(permission)
        refresh()
    }

    /// The step's deep link: the exact Privacy & Security pane.
    public func openSystemSettings() {
        guard let permission = step.permission else { return }
        openSettings(permission)
    }

    /// Quit & Reopen: relaunches the app, which opens again on the first missing step.
    public func quitAndReopen() { relaunch() }

    public func advance() {
        refresh()
        guard canContinue else { return }
        guard let next = nextStep else { return finish() }
        step = next
        enter()
    }

    public func connect() {
        let checked = agents.filter { $0.detected && selected.contains($0.agent) }.map(\.agent)
        // AgentInstaller's empty selection means "all detected". Never pass that for an unchecked form.
        results = checked.isEmpty ? [] : install(checked)
        if results.allSatisfy(\.success) { finish() }
    }

    public func skip() { finish() }

    /// Previews only: shows a step without asking for anything.
    func preview(_ step: OnboardingStep) { refresh(); self.step = step }

    /// The direct-capture prompt is raised right away on entering its step, so it appears here and never at the
    /// first recording. Once per run; "Ask Again" repeats it.
    private func enter() {
        if step == .directCapture, screenRecording == .allowed, directCapture != .allowed,
           !requested.contains(.directCapture)
        {
            request(.directCapture)
        }
    }

    private func finish() {
        completed = true; defaults.set(true, forKey: Self.completedKey); didComplete?()
    }
}
