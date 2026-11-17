public enum PermissionStatus: String, Sendable, Hashable, Codable {
    case allowed
    case missing
}

/// Reads the permission state. Read-only: it never prompts. Fake: `FakePermissionProbe`.
public protocol PermissionProbe: Sendable {
    var screenRecording: PermissionStatus { get }
    var accessibility: PermissionStatus { get }
}

extension PermissionProbe {
    public func status(of permission: Permission) -> PermissionStatus {
        switch permission {
        case .screenRecording: screenRecording
        case .accessibility: accessibility
        }
    }
}
