import Foundation
import SkreenrekCore
import SkreenrekTesting
@testable import SkreenrekUI
import Synchronization
import Testing

@MainActor private final class TestPermissionRequester: PermissionRequester {
    var requests: [Permission] = []
    func request(_ permission: Permission) { requests.append(permission) }
}

@Suite struct OnboardingModelTests {
    @Test func livePermissionsGatingExplicitRequestsAndPersistedStep() async throws {
        try await onMain("onboarding permissions") {
            let name = "skreenrek-onboarding-test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let probe = FakePermissionProbe(screenRecording: .missing, accessibility: .missing)
            let requester = TestPermissionRequester()
            @MainActor func make() -> OnboardingModel {
                OnboardingModel(permissions: probe, requester: requester, defaults: defaults, agents: [], install: { _ in [] })
            }
            let model = make()
            #expect(model.step == 1 && !model.canContinue && !model.completed)
            model.refresh(); model.continueToAgents()
            #expect(model.step == 1 && requester.requests.isEmpty)
            model.request(.screenRecording)
            #expect(requester.requests == [.screenRecording])
            probe.screenRecording = .allowed
            model.refresh()
            #expect(model.canContinue && model.accessibility == .missing)
            model.continueToAgents(); #expect(model.step == 2)
            #expect(make().step == 2)
            model.showMissingPermission(); #expect(make().step == 1)
            model.skip(); #expect(make().completed)
        }
    }

    @Test func onlyCheckedDetectedAgentsReachInstallerAndEmptyNeverMeansAll() async throws {
        try await onMain("onboarding connects checked agents") {
            let name = "skreenrek-onboarding-test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            var calls: [[AgentClient]] = []
            let rows = AgentClient.allCases.map { OnboardingAgent(agent: $0, detected: $0 != .cursor) }
            let model = OnboardingModel(permissions: FakePermissionProbe(), requester: TestPermissionRequester(),
                defaults: defaults, agents: rows, install: { calls.append($0); return [] })
            #expect(model.selected == [.claude, .codex, .cli])
            #expect(rows.map(\.detail) == ["Found ~/.claude", "Found ~/.codex", "Not installed", "Links skreenrek into ~/.local/bin"])
            model.selected = [.codex, .cursor]
            model.connect(); #expect(calls == [[.codex]] && model.completed)
            model.selected = []
            model.connect(); #expect(calls == [[.codex]])
        }
    }

    @Test func connectsThroughRealInstallerInAnIsolatedHome() async throws {
        try await onMain("onboarding installer integration") {
            let name = "skreenrek-onboarding-test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let home = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            defer { try? FileManager.default.removeItem(at: home) }
            for folder in [".claude", ".codex"] {
                try FileManager.default.createDirectory(at: home.appendingPathComponent(folder), withIntermediateDirectories: true)
            }
            let installer = AgentInstaller(home: home, executablePath: "/unused/skreenrek", path: "")
            let model = OnboardingModel(permissions: FakePermissionProbe(), requester: TestPermissionRequester(), defaults: defaults,
                agents: installer.connections().map { OnboardingAgent(agent: $0.agent, detected: $0.detected) },
                install: { installer.run(agents: $0) })
            model.selected = [.codex]; model.connect()
            #expect(model.results.count == 1 && model.results.allSatisfy(\.success))
            #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex/config.toml").path))
            #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude.json").path))
        }
    }

    @Test func permissionFailureHookPreservesMenuError() async throws {
        try await onMain("permission rejection opens onboarding without requesting") {
            let h = MenuHarness()
            defer { h.cleanUp() }
            let reported = Mutex<[Permission]>([])
            await h.controller.setPermissionFailureHandler { permission in reported.withLock { $0.append(permission) } }
            h.permissions.accessibility = .missing
            await h.perform(.pickWindow)
            await h.perform(.chooseSize(.size(PixelSize(width: 1280, height: 800))))
            #expect(reported.withLock { $0 } == [.accessibility])
            #expect(h.model.actionError == .permissionDenied(.accessibility))
        }
    }
}
