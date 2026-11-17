/// Permission requests are explicit user actions in onboarding. Probing permissions never calls this seam.
///
/// - `.screenRecording`: `CGRequestScreenCaptureAccess` (the system prompt, once per grant).
/// - `.directCapture`: the same ScreenCaptureKit calls recording makes, which raise macOS 15's private window picker
///   bypass prompt; a call that goes through is recorded in `DirectCaptureApproval`. Asynchronous: callers poll.
/// - `.accessibility`: `AXIsProcessTrustedWithOptions` with the prompt option.
@MainActor
public protocol PermissionRequester: Sendable {
    func request(_ permission: Permission)
}
