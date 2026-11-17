import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import SkreenrekCore

/// Only onboarding/Settings buttons call this. Launch, polling and control requests only probe.
public struct SystemPermissionRequester: PermissionRequester {
    public init() {}
    public func request(_ permission: Permission) {
        let pane: String
        switch permission {
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
            pane = "Privacy_ScreenCapture"
        case .accessibility:
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            pane = "Privacy_Accessibility"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
