import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit
import SkreenrekCore
import os

/// Only onboarding calls this, one step at a time. Launch, polling and control requests only probe.
public struct SystemPermissionRequester: PermissionRequester {
    private static let log = Logger(subsystem: "it.fraime.skreenrek", category: "permissions")
    private let approval: DirectCaptureApproval

    public init(defaults: UserDefaults = .standard) { approval = DirectCaptureApproval(defaults: defaults) }

    public func request(_ permission: Permission) {
        switch permission {
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        case .directCapture:
            let approval = approval
            Task.detached { await Self.directCapture(approval) }
        case .accessibility:
            _ = AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
    }

    /// Raises macOS 15's "bypass the system private window picker" prompt now, during onboarding, with the calls
    /// recording makes: `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)` (as
    /// `SCStreamFrameSource.start` does), then one direct capture of a 2 × 2 px corner of the main display through
    /// `SCScreenshotManager` (the stream recording starts is the same kind of direct, picker-less capture). Apple's
    /// DTS reproduces the prompt with exactly that pair (developer.apple.com/forums/thread/765103). The image is
    /// thrown away. Only a call that goes through is recorded.
    private static func directCapture(_ approval: DirectCaptureApproval) async {
        guard CGPreflightScreenCaptureAccess() else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                ?? content.displays.first
            else { return }
            let configuration = SCStreamConfiguration()
            configuration.width = 2
            configuration.height = 2
            configuration.sourceRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            configuration.showsCursor = false
            configuration.capturesAudio = false
            let filter = SCContentFilter(display: display, excludingWindows: [])
            _ = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            approval.record()
        } catch {
            log.info("Direct capture request failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
