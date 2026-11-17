import Foundation
import SkreenrekControl
import SkreenrekCore
import SkreenrekTesting
@testable import SkreenrekUI
import Testing

@MainActor private final class CountingRequester: PermissionRequester {
    var requests: [Permission] = []
    func request(_ permission: Permission) { requests.append(permission) }
}

/// A missing permission is always reachable: onboarding offers Quit & Reopen after a request that hasn't taken
/// effect, and the dropdown offers "Permissions needed…" whenever either permission is missing.
@Suite struct PermissionsReachTests {
    @MainActor private static func onboarding(
        _ probe: FakePermissionProbe, _ requester: CountingRequester, defaults: UserDefaults,
        relaunch: @escaping () -> Void
    ) -> OnboardingModel {
        OnboardingModel(
            permissions: probe, requester: requester, defaults: defaults, agents: [], install: { _ in [] },
            relaunch: relaunch)
    }

    @Test func quitAndReopenShowsOnlyAfterARequestThatStillReadsMissing() async throws {
        try await onMain("quit and reopen") {
            let name = "skreenrek-permissions-reach.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let probe = FakePermissionProbe(screenRecording: .missing, accessibility: .missing)
            let requester = CountingRequester()
            var relaunches = 0
            let model = Self.onboarding(probe, requester, defaults: defaults) { relaunches += 1 }
            // Missing but never requested: nothing to relaunch for yet, and construction never prompts.
            #expect(!model.needsRelaunch && requester.requests.isEmpty)
            model.request(.screenRecording)
            #expect(requester.requests == [.screenRecording])
            // The user allowed it in System Settings, but this process keeps reading "missing".
            model.refresh()
            #expect(model.needsRelaunch)
            model.quitAndReopen()
            #expect(relaunches == 1)
            // A fresh process (or a live flip) reads allowed: no button.
            probe.screenRecording = .allowed
            model.refresh()
            #expect(!model.needsRelaunch)
            // Accessibility requested and still missing also offers it; allowed clears it.
            model.request(.accessibility)
            #expect(model.needsRelaunch)
            probe.accessibility = .allowed
            model.refresh()
            #expect(!model.needsRelaunch)
            #expect(relaunches == 1)
        }
    }

    @Test func dropdownOffersPermissionsNeededWheneverOneIsMissing() {
        func titles(_ context: MenuContext) -> [String] {
            MenuModel.entries(for: context).compactMap { entry in
                if case .item(let item) = entry { return item.title }
                return nil
            }
        }
        func context(_ snapshot: ControllerSnapshot, missing: Bool, error: SkreenrekError? = nil) -> MenuContext {
            MenuContext(snapshot: snapshot, actionError: error, permissionsMissing: missing)
        }
        let needed = "Permissions needed…"
        #expect(titles(context(UIFixtures.idle, missing: true)).contains(needed))
        #expect(titles(context(UIFixtures.armed, missing: true)).contains(needed))
        let screenOff = context(UIFixtures.idle, missing: true, error: .permissionDenied(.screenRecording))
        #expect(titles(screenOff).contains(needed))
        #expect(!titles(context(UIFixtures.idle, missing: false)).contains(needed))
        // Picking and sizing are hidden while recording; so is this.
        #expect(!titles(context(UIFixtures.recording(.menu), missing: true)).contains(needed))
        // It sits right under the status row and opens onboarding's permissions step.
        let entries = MenuModel.entries(for: context(UIFixtures.idle, missing: true))
        #expect(entries[1] == .item(MenuItemModel(needed, action: .showPermissions)))
    }

    @Test func theAppModelReadsTheProbeAndOpensOnboarding() async throws {
        try await onMain("permissions needed in the app model") {
            let h = MenuHarness()
            defer { h.cleanUp() }
            #expect(!h.model.context.permissionsMissing)
            h.permissions.accessibility = .missing
            #expect(h.model.context.permissionsMissing)
            #expect(h.model.entries.contains(.item(MenuItemModel("Permissions needed…", action: .showPermissions))))
            await h.perform(.showPermissions)
            #expect(h.effects.permissionsShown == 1)
            h.permissions.accessibility = .allowed
            h.permissions.screenRecording = .missing
            #expect(h.model.context.permissionsMissing)
            h.permissions.screenRecording = .allowed
            #expect(!h.model.context.permissionsMissing)
        }
    }
}
