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

/// State and effects are explicit. Tests inject a requester and installer; construction and refresh never prompt.
@MainActor
@Observable
public final class OnboardingModel {
    public private(set) var step: Int
    public private(set) var completed: Bool
    public private(set) var screenRecording: PermissionStatus
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
    @ObservationIgnored public var didComplete: (() -> Void)?

    public init(permissions: any PermissionProbe, requester: any PermissionRequester, defaults: UserDefaults,
                agents: [OnboardingAgent], install: @escaping ([AgentClient]) -> [AgentSetupResult],
                relaunch: @escaping () -> Void = {}) {
        self.permissions = permissions; self.requester = requester; self.defaults = defaults
        self.agents = agents; self.install = install; self.relaunch = relaunch
        selected = Set(agents.filter(\.detected).map(\.agent))
        step = defaults.integer(forKey: "onboarding.step") == 2 ? 2 : 1
        completed = defaults.bool(forKey: "onboarding.completed")
        screenRecording = permissions.screenRecording; accessibility = permissions.accessibility
    }

    public var canContinue: Bool { screenRecording == .allowed }
    public func refresh() {
        screenRecording = permissions.screenRecording
        accessibility = permissions.accessibility
    }
    public func request(_ permission: Permission) {
        requested.insert(permission)
        requester.request(permission)
        refresh()
    }
    /// A permission was requested and still reads missing. macOS keeps Screen Recording "missing" in the running
    /// process even after the user allows it, so polling can't flip it: the app has to relaunch.
    public var needsRelaunch: Bool {
        requested.contains { permission in
            (permission == .screenRecording ? screenRecording : accessibility) == .missing
        }
    }
    /// Quit & Reopen: relaunches the app, which keeps the onboarding step.
    public func quitAndReopen() { relaunch() }
    public func continueToAgents() {
        refresh()
        guard canContinue else { return }
        step = 2; defaults.set(2, forKey: "onboarding.step")
    }
    public func showMissingPermission() { step = 1; defaults.set(1, forKey: "onboarding.step"); refresh() }
    public func connect() {
        let checked = agents.filter { $0.detected && selected.contains($0.agent) }.map(\.agent)
        // AgentInstaller's empty selection means "all detected". Never pass that for an unchecked form.
        results = checked.isEmpty ? [] : install(checked)
        if results.allSatisfy(\.success) { finish() }
    }
    public func skip() { finish() }
    private func finish() {
        completed = true; defaults.set(true, forKey: "onboarding.completed"); didComplete?()
    }
}
