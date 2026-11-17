import Foundation

/// Host time. Tests use a manual clock; the app uses the real host clock.
public protocol HostClock: Sendable {
    /// Host time in seconds.
    func now() -> TimeInterval
    /// Resumes once `now() >= deadline`. Throws `CancellationError` when the task is cancelled.
    func sleep(until deadline: TimeInterval) async throws
}

/// Whether a permission is granted.
public enum PermissionStatus: String, Sendable, Codable, Hashable {
    case allowed
    case missing
}

/// Reads permission state. Never prompts.
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

/// Free space on the volume holding a URL.
public protocol DiskSpaceProbe: Sendable {
    func freeBytes(at url: URL) throws -> Int64
}
