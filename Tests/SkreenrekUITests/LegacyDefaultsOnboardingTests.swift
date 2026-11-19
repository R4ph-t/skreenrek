import Foundation
import SkreenrekCore
import SkreenrekTesting
@testable import SkreenrekUI
import Testing

@MainActor private final class RecordingRequester: PermissionRequester {
    var requests: [Permission] = []
    func request(_ permission: Permission) { requests.append(permission) }
}

@Suite struct LegacyDefaultsOnboardingTests {
    /// macOS grants belong to the bundle ID, so after the switch onboarding has to ask again: it may keep "onboarding
    /// is done", but not the record that the old ID was already prompted or approved.
    @Test(.timeLimit(.minutes(1))) func migratedSettingsStillLetOnboardingAskForTheNewID() async throws {
        try await onMain("migrated onboarding", seconds: 10) {
            // Scratch suites named by path, read by the migration as domains, leave no plist behind.
            let oldScratch = ScratchDefaults(), newScratch = ScratchDefaults()
            defer {
                oldScratch.remove()
                newScratch.remove()
            }
            let (old, oldName) = (oldScratch.defaults, oldScratch.suiteName)
            let (new, newName) = (newScratch.defaults, newScratch.suiteName)
            old.set(true, forKey: OnboardingModel.completedKey)
            old.set(true, forKey: OnboardingModel.screenRecordingRequestedKey)
            old.set(Date(), forKey: DirectCaptureApproval.key)

            LegacyDefaultsMigration.run(
                old: old, oldDomain: oldName, new: new, newDomain: newName,
                excluding: OnboardingModel.permissionStateKeys)

            #expect(new.object(forKey: DirectCaptureApproval.key) == nil)
            let probe = FakePermissionProbe(screenRecording: .missing, directCapture: .missing, accessibility: .missing)
            let model = OnboardingModel(
                permissions: probe, requester: RecordingRequester(), defaults: new, agents: [], install: { _ in [] })
            model.begin()
            #expect(model.completed && model.shouldShowAtLaunch)
            #expect(model.step == .screenRecording)
            #expect(!model.needsRelaunch && model.requestTitle == "Allow Screen Recording")
        }
    }
}
