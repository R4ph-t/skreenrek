import Foundation
import SkreenrekCore
import Synchronization

/// Permission state the test sets. All are allowed by default.
public final class FakePermissionProbe: PermissionProbe {
    private let state: Mutex<(screenRecording: PermissionStatus, directCapture: PermissionStatus,
                              accessibility: PermissionStatus)>

    public init(screenRecording: PermissionStatus = .allowed, directCapture: PermissionStatus = .allowed,
                accessibility: PermissionStatus = .allowed) {
        state = Mutex((screenRecording, directCapture, accessibility))
    }

    public var screenRecording: PermissionStatus {
        get { state.withLock { $0.screenRecording } }
        set { state.withLock { $0.screenRecording = newValue } }
    }

    public var directCapture: PermissionStatus {
        get { state.withLock { $0.directCapture } }
        set { state.withLock { $0.directCapture = newValue } }
    }

    public var accessibility: PermissionStatus {
        get { state.withLock { $0.accessibility } }
        set { state.withLock { $0.accessibility = newValue } }
    }
}

/// Free disk space the test sets. 100 GB by default.
public final class FakeDiskSpaceProbe: DiskSpaceProbe {
    private struct State {
        var freeBytes: Int64
        var failure: (any Error)?
        var queried: [URL] = []
    }

    private let state: Mutex<State>

    public static let gigabyte: Int64 = 1_000_000_000

    public init(freeBytes: Int64 = 100 * FakeDiskSpaceProbe.gigabyte) {
        state = Mutex(State(freeBytes: freeBytes))
    }

    public var freeBytes: Int64 {
        get { state.withLock { $0.freeBytes } }
        set { state.withLock { $0.freeBytes = newValue } }
    }

    public var failure: (any Error)? {
        get { state.withLock { $0.failure } }
        set { state.withLock { $0.failure = newValue } }
    }

    /// Every path asked about, in order.
    public var queried: [URL] { state.withLock { $0.queried } }

    public func freeBytes(at url: URL) throws -> Int64 {
        try state.withLock { s in
            s.queried.append(url)
            if let failure = s.failure { throw failure }
            return s.freeBytes
        }
    }
}
