import Foundation
import SkreenrekControl
import SkreenrekCore
import SkreenrekTesting
@testable import SkreenrekUI
import Synchronization
import Testing

/// Recording is never where a macOS prompt first appears: with a capture permission missing, Record opens
/// onboarding and nothing reaches the capture or resize seams.
@Suite struct RecordingPermissionGateTests {
    @Test(.timeLimit(.minutes(1)), arguments: [Permission.screenRecording, .directCapture])
    func recordWithAMissingCapturePermissionOpensOnboardingAndDoesntStart(_ missing: Permission) async throws {
        try await onMain("record gate \(missing)", seconds: 10) {
            let h = MenuHarness()
            defer { h.cleanUp() }
            let reported = Mutex<[Permission]>([])
            await h.controller.setPermissionFailureHandler { permission in reported.withLock { $0.append(permission) } }
            await h.perform(.pickWindow)
            switch missing {
            case .screenRecording: h.permissions.screenRecording = .missing
            case .directCapture: h.permissions.directCapture = .missing
            case .accessibility: break
            }
            h.model.settings.sizeChoice = .size(SizePreset.p720.size)
            await h.perform(.record)
            #expect(reported.withLock { $0 } == [missing])
            #expect(h.frames.startCalls.isEmpty && h.resizer.calls.isEmpty)
            #expect(h.model.snapshot.state != .recording)
            #expect(h.model.actionError == .permissionDenied(missing))
        }
    }

    @Test func directCaptureErrorRowOffersSetup() {
        let rows = MenuModel.errorEntries(.permissionDenied(.directCapture), lastClip: nil)
        #expect(rows.contains(.item(MenuItemModel(UIStrings.Menu.permissionsNeeded, action: .showPermissions))))
    }
}
