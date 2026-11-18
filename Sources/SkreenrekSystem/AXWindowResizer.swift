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

    /// Elements found so far, by window ID: once the frame changes it no longer matches the listed frame. An entry
    /// is dropped when its element turns out to be gone (`invalidUIElement`), and the whole cache is cleared once it
    /// holds `cacheLimit` windows, so a long-lived app process never keeps closed windows' elements.
    private let found = Mutex<[WindowID: Element]>([:])
    static let cacheLimit = 32
    /// Lists the app's other windows only to name look-alikes in an ambiguity error; nil names only the one asked for.
    private let catalog: (any WindowCatalog)?

    public init(catalog: (any WindowCatalog)? = nil) {
        self.catalog = catalog
    }

    /// Accessibility is allowed for this process. Never prompts.
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    public func setFrame(_ frame: PointRect, of window: WindowInfo) async throws {
        var origin = CGPoint(x: frame.x, y: frame.y)
        var size = CGSize(width: frame.width, height: frame.height)
        guard let position = AXValueCreate(.cgPoint, &origin), let extent = AXValueCreate(.cgSize, &size) else {
            throw SkreenrekError.internal(message: "Couldn't build the Accessibility frame values.")
        }
        // Move first so a larger size isn't clamped at the old position, then size, then move again because some
        // apps shift the origin while they resize.
        try await withElement(for: window) { element in
            try Self.check(AXUIElementSetAttributeValue(element.ref, kAXPositionAttribute as CFString, position), window)
            try Self.check(AXUIElementSetAttributeValue(element.ref, kAXSizeAttribute as CFString, extent), window)
            try Self.check(AXUIElementSetAttributeValue(element.ref, kAXPositionAttribute as CFString, position), window)
        }
    }

    public func readFrame(of window: WindowInfo) async throws -> PointRect {
        try await withElement(for: window) { element in
            guard let frame = try Self.frame(of: element.ref, window: window) else {
                throw SkreenrekError.internal(message: "Couldn't read the frame of \(window.app)'s window.")
            }
            return frame
        }
    }

    /// Puts the window in front of its app's other windows. The caller activates the app.
    public func raise(_ window: WindowInfo) async throws {
        try await withElement(for: window) { element in
            try Self.check(AXUIElementPerformAction(element.ref, kAXRaiseAction as CFString), window, verb: "raise")
        }
    }

    /// Runs `body` on the window's element. A cached element that is gone is evicted and looked up once more.
    private func withElement<T>(for window: WindowInfo, _ body: (Element) throws -> T) async throws -> T {
        guard Self.isTrusted else { throw SkreenrekError.permissionDenied(.accessibility) }
        if let cached = found.withLock({ $0[window.id] }) {
            do {
                return try body(cached)
            } catch let error as SkreenrekError where error.code == "window_not_found" {
                found.withLock { _ = $0.removeValue(forKey: window.id) }
            }
        }
        let element = try await lookUp(window)
        do {
            return try body(element)
        } catch let error as SkreenrekError where error.code == "window_not_found" {
            found.withLock { _ = $0.removeValue(forKey: window.id) }
            throw error
        }
    }

    private func lookUp(_ window: WindowInfo) async throws -> Element {
        let app = AXUIElementCreateApplication(window.pid)
        var value: CFTypeRef?
        try check(AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value), window)
        let elements = (value as? [AXUIElement]) ?? []
        // A window whose frame can't be read is only a non-candidate; it never fails the whole match.
        let snapshots = try elements.map { element in
            AXWindowSnapshot(title: Self.title(of: element), frame: try Self.readableFrame(of: element, window: window))
        }
        let scale = await Self.scale(for: window.frame)
        let index: Int
        do {
            index = try AXWindowMatch.pick(window, among: snapshots, scale: scale)
        } catch let error as SkreenrekError where error.code == "window_ambiguous" {
            // Ask again with the app's listed windows, so each look-alike carries its own window ID.
            let siblings = (try? await catalog?.windows())?.filter { $0.pid == window.pid } ?? []
            index = try AXWindowMatch.pick(window, among: snapshots, siblings: siblings, scale: scale)
        }
        let element = Element(ref: elements[index])
        found.withLock { cache in
            if cache.count >= Self.cacheLimit { cache.removeAll() }
            cache[window.id] = element
        }
        return element
    }

    /// The frame, or nil when this one window can't be read. Only a missing permission is an error.
    private static func readableFrame(of element: AXUIElement, window: WindowInfo) throws -> PointRect? {
        do {
            return try frame(of: element, window: window)
        } catch let error as SkreenrekError where error.code == "permission_denied" {
            throw error
        } catch {
            return nil
        }
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

    private static func check(_ result: AXError, _ window: WindowInfo, verb: String = "resize") throws {
        switch result {
        case .success:
            return
        case .apiDisabled:
            throw SkreenrekError.permissionDenied(.accessibility)
        case .invalidUIElement:
            throw SkreenrekError.windowNotFound(query: String(window.id.rawValue))
        default:
            throw SkreenrekError.internal(
                message: "Couldn't \(verb) \(window.app)'s window (Accessibility error \(result.rawValue)).")
        }
    }
}
