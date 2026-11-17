import CoreGraphics
import Foundation
import ScreenCaptureKit
import SkreenrekCore

/// Windows from ScreenCaptureKit and displays from AppKit. Filtering and display assignment live in
/// `WindowDirectory`; this only maps types.
public struct SCWindowCatalog: WindowCatalog {
    public init() {}

    public func windows() async throws -> [WindowInfo] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw Self.mapError(error)
        }
        let windows = content.windows.map { window in
            WindowInfo(
                id: WindowID(window.windowID),
                app: window.owningApplication?.applicationName ?? "",
                bundleId: window.owningApplication.map(\.bundleIdentifier).flatMap { $0.isEmpty ? nil : $0 },
                title: window.title ?? "",
                pid: window.owningApplication?.processID ?? 0,
                frame: PointRect(window.frame),
                displayId: 0,
                onScreen: window.isOnScreen,
                layer: window.windowLayer)
        }
        return Self.frontToBack(windows)
    }

    public func displays() async throws -> [DisplayInfo] {
        await AppKitDisplays.current()
    }

    /// Orders windows like the window server's on-screen list (front to back). The list carries IDs and bounds only,
    /// which need no permission.
    static func frontToBack(_ windows: [WindowInfo]) -> [WindowInfo] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let zOrder = list.compactMap { ($0[kCGWindowNumber as String] as? NSNumber).map { WindowID($0.uint32Value) } }
        return WindowDirectory.ordered(windows, byZOrder: zOrder)
    }

    static func mapError(_ error: any Error) -> any Error {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain, nsError.code == SCStreamError.Code.userDeclined.rawValue {
            return SkreenrekError.permissionDenied(.screenRecording)
        }
        return SkreenrekError.internal(message: "Couldn't list windows: \(nsError.localizedDescription)")
    }
}
