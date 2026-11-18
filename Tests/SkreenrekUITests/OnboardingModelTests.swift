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
    @MainActor private static func make(
        _ probe: FakePermissionProbe, _ requester: TestPermissionRequester, _ defaults: UserDefaults,
        opened: @escaping (Permission) -> Void = { _ in }
    ) -> OnboardingModel {
        OnboardingModel(permissions: probe, requester: requester, defaults: defaults, agents: [], install: { _ in [] },
                        openSettings: opened)
    }

    /// First launch on a fresh Mac: one step per permission, in order, each asking macOS only when its step asks.
    @Test(.timeLimit(.minutes(1))) func walksThePermissionsInOrderAndAsksOnlyOnItsStep() async throws {
        try await onMain("onboarding step order", seconds: 10) {
            let name = "skreenrek-onboarding-test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let probe = FakePermissionProbe(screenRecording: .missing, directCapture: .missing, accessibility: .missing)
            let requester = TestPermissionRequester()
            var opened: [Permission] = []
            let model = Self.make(probe, requester, defaults) { opened.append($0) }
            // Construction and refresh never ask.
            #expect(model.shouldShowAtLaunch && model.steps == [.screenRecording, .directCapture, .accessibility, .agents])
            model.begin(); model.refresh()
            #expect(model.step == .screenRecording && model.stepNumber == 1 && requester.requests.isEmpty)
            #expect(!model.canContinue && model.requestTitle == "Allow Screen Recording" && !model.needsRelaunch)
            model.advance(); #expect(model.step == .screenRecording)

            // Step 1: the Screen Recording prompt, then the pane, then Quit & Reopen (the grant needs a new process).
            model.requestCurrent()
            #expect(requester.requests == [.screenRecording])
            model.openSystemSettings(); #expect(opened == [.screenRecording])
            #expect(model.needsRelaunch && model.requestTitle == nil)

            // After the relaunch: Screen Recording reads allowed, and onboarding opens on direct capture and raises
            // macOS 15's private window picker prompt right away.
            probe.screenRecording = .allowed
            let relaunched = Self.make(probe, requester, defaults) { opened.append($0) }
            #expect(relaunched.shouldShowAtLaunch)
            relaunched.begin()
            #expect(relaunched.step == .directCapture && relaunched.stepNumber == 2)
            #expect(requester.requests == [.screenRecording, .directCapture])
            #expect(!relaunched.canContinue && relaunched.requestTitle == "Ask Again" && !relaunched.needsRelaunch)
            // Polling (refresh) never asks again; the user clicks Allow on the system prompt and polling sees it.
            relaunched.refresh(); relaunched.begin()
            #expect(requester.requests == [.screenRecording, .directCapture])
            relaunched.openSystemSettings(); #expect(opened.last == .directCapture)
            probe.directCapture = .allowed
            relaunched.refresh()
            #expect(relaunched.canContinue && relaunched.requestTitle == nil)

            // Step 3: Accessibility isn't blocking, so Skip moves on; Allow prompts through AX.
            relaunched.advance()
            #expect(relaunched.step == .accessibility && relaunched.continueTitle == "Skip")
            #expect(relaunched.requestTitle == "Allow Accessibility")
            relaunched.requestCurrent()
            #expect(requester.requests == [.screenRecording, .directCapture, .accessibility])
            #expect(!relaunched.needsRelaunch)
            probe.accessibility = .allowed; relaunched.refresh()
            #expect(relaunched.continueTitle == "Continue")
            relaunched.advance()
            #expect(relaunched.step == .agents && relaunched.stepNumber == 4 && !relaunched.completed)
            relaunched.skip()
            #expect(relaunched.completed && !Self.make(probe, requester, defaults).shouldShowAtLaunch)
        }
    }

    /// Once completed, a missing permission reopens the flow on that step, without the agents, and Done closes it.
    @Test(.timeLimit(.minutes(1))) func reopensOnTheMissingStepAfterOnboarding() async throws {
        try await onMain("onboarding reopens", seconds: 10) {
            let name = "skreenrek-onboarding-test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            defaults.set(true, forKey: "onboarding.completed")
            // macOS asks about direct capture again about once a month: the record expired.
            let probe = FakePermissionProbe(directCapture: .missing)
            let requester = TestPermissionRequester()
            let model = Self.make(probe, requester, defaults)
            var closed = 0
            model.didComplete = { closed += 1 }
            #expect(model.shouldShowAtLaunch && model.steps == [.screenRecording, .directCapture, .accessibility])
            model.begin()
            #expect(model.step == .directCapture && model.stepNumber == 2 && requester.requests == [.directCapture])
            #expect(model.continueTitle == "Done")
            probe.directCapture = .allowed; model.refresh()
            model.advance()
            #expect(closed == 1 && model.completed)
            // Accessibility alone missing doesn't open it at launch (recording works), but the menu still offers it.
            probe.accessibility = .missing
            let later = Self.make(probe, requester, defaults)
            #expect(!later.shouldShowAtLaunch)
            later.begin(); #expect(later.step == .accessibility)
        }
    }

    /// Direct capture can't be asked before Screen Recording is in effect: no request, a plain sentence instead.
    @Test(.timeLimit(.minutes(1))) func directCaptureWaitsForScreenRecording() async throws {
        try await onMain("direct capture waits", seconds: 10) {
            let name = "skreenrek-onboarding-test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let probe = FakePermissionProbe(screenRecording: .missing, directCapture: .missing)
            let requester = TestPermissionRequester()
            let model = Self.make(probe, requester, defaults)
            model.preview(.directCapture)
            #expect(model.waitsForScreenRecording && model.requestTitle == nil && !model.canContinue)
            model.requestCurrent()
            #expect(requester.requests == [.directCapture])
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

    /// A temp home with Claude Code, Codex and Cursor found. Nothing here reads the real home.
    @MainActor private static func connectModel(
        home: URL, defaults: UserDefaults
    ) throws -> OnboardingModel {
        for folder in [".claude", ".codex", ".cursor", ".local/bin"] {
            try FileManager.default.createDirectory(at: home.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try Data("user executable".utf8).write(to: home.appendingPathComponent(".local/bin/skreenrek"))
        let installer = AgentInstaller(home: home, executablePath: "/unused/skreenrek", path: "")
        let model = OnboardingModel(permissions: FakePermissionProbe(), requester: TestPermissionRequester(), defaults: defaults,
            agents: installer.connections().map { OnboardingAgent(agent: $0.agent, detected: $0.detected) },
            install: { installer.run(agents: $0) })
        model.preview(.agents)
        return model
    }

    @Test func partialConnectTriesEveryItemCompletesAndKeepsItsErrors() async throws {
        try await onMain("partial connect") {
            let name = "skreenrek-onboarding-test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let home = FileManager.default.temporaryDirectory.appendingPathComponent(name).resolvingSymlinksInPath()
            defer { try? FileManager.default.removeItem(at: home) }
            let model = try Self.connectModel(home: home, defaults: defaults)
            // The first agent fails, and the ones after it still connect.
            try Data("{".utf8).write(to: home.appendingPathComponent(".claude.json"))
            var closed = 0
            model.didComplete = { closed += 1 }
            model.connect()
            #expect(model.results.map(\.agent) == AgentClient.allCases)
            #expect(model.didConnect(.codex) && model.didConnect(.cursor))
            #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex/config.toml").path))
            #expect(model.connectError(for: .claude) != nil && model.connectError(for: .codex) == nil)
            #expect(model.connectError(for: .cli) == "~/.local/bin/skreenrek is another file. Move or delete it, then click Connect again.")
            // Onboarding is done, and the window stays so the errors can be read.
            #expect(model.completed && defaults.bool(forKey: OnboardingModel.completedKey) && closed == 0)
            #expect(!model.allConnectsFailed && model.connectSummary == UIStrings.Onboarding.someConnected)
            #expect(model.skipTitle == "Done" && model.stepNumber == 4 && model.steps.count == 4)

            // Fixing both and connecting again closes it.
            try FileManager.default.removeItem(at: home.appendingPathComponent(".claude.json"))
            try FileManager.default.removeItem(at: home.appendingPathComponent(".local/bin/skreenrek"))
            model.connect()
            #expect(model.results.allSatisfy(\.success) && model.connectSummary == nil && closed == 1)
        }
    }

    @Test func connectWhereEverythingFailsSaysSoAndStaysOpen() async throws {
        try await onMain("all connects fail") {
            let name = "skreenrek-onboarding-test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let home = FileManager.default.temporaryDirectory.appendingPathComponent(name).resolvingSymlinksInPath()
            defer { try? FileManager.default.removeItem(at: home) }
            let model = try Self.connectModel(home: home, defaults: defaults)
            try Data("{".utf8).write(to: home.appendingPathComponent(".claude.json"))
            try Data("{".utf8).write(to: home.appendingPathComponent(".cursor/mcp.json"))
            try Data("broken".utf8).write(to: home.appendingPathComponent(".codex/config.toml"))
            var closed = 0
            model.didComplete = { closed += 1 }
            model.connect()
            #expect(model.results.count == 4 && model.allConnectsFailed)
            #expect(AgentClient.allCases.allSatisfy { model.connectError(for: $0) != nil })
            #expect(model.connectSummary == UIStrings.Onboarding.nothingConnected)
            #expect(!model.completed && closed == 0 && model.skipTitle == "Skip")
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
