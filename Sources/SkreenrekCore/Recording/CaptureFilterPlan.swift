/// Pure exclusion policy shared with ScreenCaptureKit. Pid exclusion works even without a bundle identifier
/// (e.g. a development executable); bundle exclusion also removes any sibling Skreenrek UI processes.
public struct CaptureFilterPlan: Sendable, Equatable {
    public var ownPid: Int32
    public var bundleID: String?
    public init(ownPid: Int32, bundleID: String?) { self.ownPid = ownPid; self.bundleID = bundleID }
    public func excludes(pid: Int32, bundleID: String?) -> Bool {
        pid == ownPid || (self.bundleID != nil && self.bundleID == bundleID)
    }
}
