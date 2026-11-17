import ApplicationServices
import Foundation
import SkreenrekCore
import Synchronization

/// Sets and reads window frames through Accessibility, public API only. Accessibility uses top-left global pt, the
/// seam's space, so no conversion happens here. It never prompts: `AXIsProcessTrusted()` false is `permission_denied`.
public final class AXWindowResizer: WindowResizer {
    /// An AX element. Treated as immutable once found, which is what makes the `@unchecked` safe.
    private struct Element: @unchecked Sendable {
        let ref: AXUIElement
    }

    /// Elements found so far, by window ID: once the frame changes it no longer matches the listed frame.
    private let found = Mutex<[WindowID: Element]>([:])

    public init() {}

    /// Accessibility is allowed for this process. Never prompts.
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    public func setFrame(_ frame: PointRect, of window: WindowInfo) async throws {
        let element = try await self.element(for: window)
        var origin = CGPoint(x: frame.x, y: frame.y)
        var size = CGSize(width: frame.width, height: frame.height)
        guard let position = AXValueCreate(.cgPoint, &origin), let extent = AXValueCreate(.cgSize, &size) else {
            throw SkreenrekError.internal(message: "Couldn't build the Accessibility frame values.")
        }
        // Move first so a larger size isn't clamped at the old position, then size, then move again because some
        // apps shift the origin while they resize.
        try check(AXUIElementSetAttributeValue(element.ref, kAXPositionAttribute as CFString, position), window)
        try check(AXUIElementSetAttributeValue(element.ref, kAXSizeAttribute as CFString, extent), window)
        try check(AXUIElementSetAttributeValue(element.ref, kAXPositionAttribute as CFString, position), window)
    }

    public func readFrame(of window: WindowInfo) async throws -> PointRect {
        let element = try await self.element(for: window)
        guard let frame = try Self.frame(of: element.ref, window: window) else {
            throw SkreenrekError.internal(message: "Couldn't read the frame of \(window.app)'s window.")
        }
        return frame
    }

    private func element(for window: WindowInfo) async throws -> Element {
        guard Self.isTrusted else { throw SkreenrekError.permissionDenied(.accessibility) }
        if let element = found.withLock({ $0[window.id] }) { return element }
        let app = AXUIElementCreateApplication(window.pid)
        var value: CFTypeRef?
        try check(AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value), window)
        let elements = (value as? [AXUIElement]) ?? []
        let snapshots = try elements.map { element in
            AXWindowSnapshot(title: Self.title(of: element), frame: try Self.frame(of: element, window: window))
        }
        let scale = await Self.scale(for: window.frame)
        let index = try AXWindowMatch.pick(window, among: snapshots, scale: scale)
        let element = Element(ref: elements[index])
        found.withLock { $0[window.id] = element }
        return element
    }

    @MainActor
    private static func scale(for frame: PointRect) -> Double {
        WindowDirectory.display(for: frame, in: AppKitDisplays.current())?.scale ?? 1
    }

    private static func title(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func frame(of element: AXUIElement, window: WindowInfo) throws -> PointRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        try check(AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue), window)
        try check(AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue), window)
        guard let positionValue, let sizeValue, CFGetTypeID(positionValue) == AXValueGetTypeID(),
            CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        return PointRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }

    private func check(_ result: AXError, _ window: WindowInfo) throws {
        try Self.check(result, window)
    }

    private static func check(_ result: AXError, _ window: WindowInfo) throws {
        switch result {
        case .success:
            return
        case .apiDisabled:
            throw SkreenrekError.permissionDenied(.accessibility)
        case .invalidUIElement:
            throw SkreenrekError.windowNotFound(query: String(window.id.rawValue))
        default:
            throw SkreenrekError.internal(
                message: "Couldn't resize \(window.app)'s window (Accessibility error \(result.rawValue)).")
        }
    }
}
