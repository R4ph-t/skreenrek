import Foundation

/// Free space on the volume holding a path. Fake: `FakeDiskSpaceProbe`.
public protocol DiskSpaceProbe: Sendable {
    func freeBytes(at url: URL) throws -> Int64
}
