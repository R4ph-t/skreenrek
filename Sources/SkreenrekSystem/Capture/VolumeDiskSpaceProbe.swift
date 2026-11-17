import Foundation
import SkreenrekCore

/// Free space on the volume holding a path: the capacity available for important usage (what Finder shows).
public struct VolumeDiskSpaceProbe: DiskSpaceProbe {
    public init() {}

    public func freeBytes(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values.volumeAvailableCapacityForImportantUsage ?? 0
    }
}
