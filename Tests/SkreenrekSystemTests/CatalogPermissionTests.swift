import SkreenrekCore
import SkreenrekSystem
import Testing

private struct MissingPermissions: PermissionProbe {
    var screenRecording: PermissionStatus = .missing
    var directCapture: PermissionStatus = .missing
    var accessibility: PermissionStatus = .missing
}

@Suite(.timeLimit(.minutes(1))) struct CatalogPermissionTests {
    @Test func missingPermissionRejectsBeforeScreenCaptureKitContentQuery() async {
        // The injected probe never calls a system permission API. The guard throws synchronously,
        // before any ScreenCaptureKit work, so there is no system wait or prompt in this test.
        let catalog = SCWindowCatalog(permissions: MissingPermissions())
        await #expect(throws: SkreenrekError.permissionDenied(.screenRecording)) { try await catalog.windows() }
    }

    @Test func directCaptureNotApprovedRejectsBeforeScreenCaptureKitContentQuery() async {
        // Listing windows is a direct capture call: without onboarding's approval it would raise macOS 15's private
        // window picker prompt here instead of in onboarding.
        let catalog = SCWindowCatalog(permissions: MissingPermissions(screenRecording: .allowed))
        await #expect(throws: SkreenrekError.permissionDenied(.directCapture)) { try await catalog.windows() }
    }
}
