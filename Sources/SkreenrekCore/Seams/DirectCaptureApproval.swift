import Foundation

/// macOS 15 shows a second prompt after Screen Recording is allowed: "Skreenrek is requesting to bypass the system
/// private window picker and directly access your screen and audio" [Allow] [Open System Settings]. There is no API
/// to read that approval, and ScreenCaptureKit raises the prompt on the first direct capture call
/// (`SCShareableContent` plus a capture) once Screen Recording is allowed.
///
/// So onboarding makes that call on purpose, and this records when it went through. Capture is gated on a recent
/// record, so recording is never the first place the prompt appears. macOS asks again about once a month, so a
/// record older than `lifetime` counts as missing and onboarding asks again first. Revoking Screen Recording (for
/// example `tccutil reset ScreenCapture`) clears the record.
public struct DirectCaptureApproval: Sendable {
    public static let key = "permissions.directCapture.approvedAt"
    /// A little under macOS's monthly re-prompt, so onboarding asks before macOS would at a recording.
    public static let lifetime: TimeInterval = 27 * 24 * 60 * 60

    nonisolated(unsafe) private let defaults: UserDefaults
    private let now: @Sendable () -> Date

    public init(defaults: UserDefaults, now: @escaping @Sendable () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
    }

    /// When the last direct capture call went through, if one did.
    public var approvedAt: Date? { defaults.object(forKey: Self.key) as? Date }

    /// Allowed when Screen Recording is allowed and a direct capture went through less than `lifetime` ago.
    /// A missing Screen Recording clears the record: the next grant starts over.
    public func status(screenRecording: PermissionStatus) -> PermissionStatus {
        guard screenRecording == .allowed else {
            if approvedAt != nil { clear() }
            return .missing
        }
        guard let approvedAt else { return .missing }
        let age = now().timeIntervalSince(approvedAt)
        return age >= 0 && age < Self.lifetime ? .allowed : .missing
    }

    public func record() { defaults.set(now(), forKey: Self.key) }
    public func clear() { defaults.removeObject(forKey: Self.key) }
}
