import ApplicationServices
import CoreGraphics
import Foundation
import SkreenrekCore

/// The real permission state, read-only: `CGPreflightScreenCaptureAccess` and `AXIsProcessTrusted` never prompt, and
/// direct capture is the record onboarding keeps (`DirectCaptureApproval`).
public struct SystemPermissionProbe: PermissionProbe {
    private let approval: DirectCaptureApproval

    public init(defaults: UserDefaults = .standard) { approval = DirectCaptureApproval(defaults: defaults) }

    public var screenRecording: PermissionStatus { CGPreflightScreenCaptureAccess() ? .allowed : .missing }
    public var directCapture: PermissionStatus { approval.status(screenRecording: screenRecording) }
    public var accessibility: PermissionStatus { AXIsProcessTrusted() ? .allowed : .missing }
}
