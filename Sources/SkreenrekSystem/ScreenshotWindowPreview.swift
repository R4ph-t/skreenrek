import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit
import SkreenrekCore
import os

/// One `SCScreenshotManager` still of a window, fitted inside the preview box. Checked for a missing capture
/// permission before any ScreenCaptureKit call, so it never prompts. The work runs off the main thread. No stream.
public struct ScreenshotWindowPreview: WindowPreviewSource {
    private static let log = Logger(subsystem: "it.fraime.skreenrek", category: "preview")
    private let permissions: any PermissionProbe

    public init(permissions: any PermissionProbe = SystemPermissionProbe()) {
        self.permissions = permissions
    }

    public func captureStill(of window: WindowInfo, fitting maxPixels: PixelSize) async throws -> WindowStill {
        if let missing = permissions.missingCapturePermission {
            throw WindowPreviewError.permissionMissing(missing)
        }
        try Task.checkCancellation()
        // A caller on the main thread (the panel opening) must not wait on the capture.
        if Self.isOnMainThread() {
            let permissions = permissions
            return try await Task.detached {
                try await ScreenshotWindowPreview(permissions: permissions).captureOffMain(window, fitting: maxPixels)
            }.value
        }
        return try await captureOffMain(window, fitting: maxPixels)
    }

    /// Synchronous because `Thread.isMainThread` is unavailable from async code. It reports the caller's thread.
    private static func isOnMainThread() -> Bool { Thread.isMainThread }

    private func captureOffMain(_ window: WindowInfo, fitting maxPixels: PixelSize) async throws -> WindowStill {
        try Task.checkCancellation()
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.map(error)
        }
        guard let scWindow = content.windows.first(where: { $0.windowID == window.id.rawValue }) else {
            throw WindowPreviewError.windowClosed
        }
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let configuration = SCStreamConfiguration()
        // The window's own aspect, fitted inside the preview box. No source rect, so the still is the whole window
        // and the panel draws the bars.
        let pixels = PreviewCaptureSize.pixels(
            aspectWidth: window.frame.width, aspectHeight: window.frame.height, box: maxPixels)
        configuration.width = pixels.width
        configuration.height = pixels.height
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.captureResolution = .best
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.map(error)
        }
        return try Self.encode(image)
    }

    private static func encode(_ image: CGImage) throws -> WindowStill {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw WindowPreviewError.failed("Could not encode the preview.")
        }
        return WindowStill(png: png, pixelWidth: image.width, pixelHeight: image.height)
    }

    private static func map(_ error: any Error) -> WindowPreviewError {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain, nsError.code == SCStreamError.Code.userDeclined.rawValue {
            return .permissionMissing(.screenRecording)
        }
        log.info("Window preview failed: \(nsError.localizedDescription, privacy: .public)")
        return .failed("Preview capture failed.")
    }
}
