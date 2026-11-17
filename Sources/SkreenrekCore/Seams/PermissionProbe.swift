public enum PermissionStatus: String, Sendable, Hashable, Codable {
    case allowed
    case missing
}

/// Reads the permission state. Read-only: it never prompts. Fake: `FakePermissionProbe`.
public protocol PermissionProbe: Sendable {
    var screenRecording: PermissionStatus { get }
    /// Whether onboarding has raised and passed macOS 15's direct-capture prompt recently (`DirectCaptureApproval`).
    var directCapture: PermissionStatus { get }
    var accessibility: PermissionStatus { get }
}

extension PermissionProbe {
    public func status(of permission: Permission) -> PermissionStatus {
        switch permission {
        case .screenRecording: screenRecording
        case .directCapture: directCapture
        case .accessibility: accessibility
        }
    }

    /// Screen Recording and direct capture: what any capture (listing windows, recording) needs first.
    public var canCapture: Bool { screenRecording == .allowed && directCapture == .allowed }

    /// The first capture permission that's missing, in onboarding order.
    public var missingCapturePermission: Permission? {
        if screenRecording != .allowed { return .screenRecording }
        if directCapture != .allowed { return .directCapture }
        return nil
    }
}
