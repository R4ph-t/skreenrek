import Foundation
import SkreenrekCore

/// A permission probe whose answers the test sets.
public final class FakePermissionProbe: PermissionProbe, @unchecked Sendable {
    private let state: Locked<(screenRecording: PermissionStatus, accessibility: PermissionStatus)>

    public init(screenRecording: PermissionStatus = .allowed, accessibility: PermissionStatus = .allowed) {
        state = Locked((screenRecording, accessibility))
    }

    public var screenRecording: PermissionStatus {
        get { state.withLock { $0.screenRecording } }
        set { state.withLock { $0.screenRecording = newValue } }
    }

    public var accessibility: PermissionStatus {
        get { state.withLock { $0.accessibility } }
        set { state.withLock { $0.accessibility = newValue } }
    }
}

/// A disk-space probe whose answer the test sets, or that throws.
public final class FakeDiskSpaceProbe: DiskSpaceProbe, @unchecked Sendable {
    private let state: Locked<(bytes: Int64, error: SkreenrekError?, queries: [URL])>

    public init(freeBytes: Int64 = 500_000_000_000) {
        state = Locked((freeBytes, nil, []))
    }

    public var bytes: Int64 {
        get { state.withLock { $0.bytes } }
        set { state.withLock { $0.bytes = newValue } }
    }

    /// When set, `freeBytes(at:)` throws it.
    public var error: SkreenrekError? {
        get { state.withLock { $0.error } }
        set { state.withLock { $0.error = newValue } }
    }

    /// Every URL asked about, in order.
    public var queries: [URL] { state.withLock { $0.queries } }

    public func freeBytes(at url: URL) throws -> Int64 {
        try state.withLock { s in
            s.queries.append(url)
            if let error = s.error { throw error }
            return s.bytes
        }
    }
}
