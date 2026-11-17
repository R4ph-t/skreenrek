import ApplicationServices
import CoreGraphics
import SkreenrekCore

/// The real permission state, read-only: `CGPreflightScreenCaptureAccess` and `AXIsProcessTrusted` never prompt.
public struct SystemPermissionProbe: PermissionProbe {
    public init() {}

    public var screenRecording: PermissionStatus { CGPreflightScreenCaptureAccess() ? .allowed : .missing }
    public var accessibility: PermissionStatus { AXIsProcessTrusted() ? .allowed : .missing }
}
