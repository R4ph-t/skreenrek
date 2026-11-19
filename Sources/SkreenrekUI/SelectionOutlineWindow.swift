import AppKit
import ApplicationServices
import SkreenrekCore

/// Draws the outline: a stroke filling the view's edge, with a contrast hairline on its outer edge. No fill.
final class SelectionOutlineView: NSView {
    var appearanceModel: SelectionOutlineAppearance? {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    nonisolated static func color(_ tone: SelectionOutlineTone) -> NSColor {
        switch tone {
        case .accent: .controlAccentColor
        case .record: BrandTheme.recordRed
        }
    }

    /// Sets the next appearance. A change of colour crossfades over `crossfade` seconds; 0 swaps it in one frame.
    func set(_ appearance: SelectionOutlineAppearance, crossfade: TimeInterval) {
        if crossfade > 0, let old = appearanceModel, old.tone != appearance.tone {
            wantsLayer = true
            let transition = CATransition()
            transition.type = .fade
            transition.duration = crossfade
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer?.add(transition, forKey: "tone")
        }
        appearanceModel = appearance
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let model = appearanceModel else { return }
        stroke(
            inset: model.strokeWidth / 2, width: model.strokeWidth, radius: model.cornerRadius,
            Self.color(model.tone))
        stroke(
            inset: model.hairlineWidth / 2, width: model.hairlineWidth, radius: model.cornerRadius,
            NSColor.black.withAlphaComponent(model.hairlineOpacity))
    }

    private func stroke(inset: CGFloat, width: CGFloat, radius: CGFloat, _ color: NSColor) {
        let corner = max(0, radius - inset)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), xRadius: corner, yRadius: corner)
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }
}

/// The outline overlay. `.transient` is omitted: it would hide the outline when focus returns to the picked
/// window, the same bug that hid the control bar. `sharingType = .none` keeps the red recording frame out of every
/// clip, so it must never be added to a content filter's excepted windows.
final class SelectionOutlinePanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        sharingType = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        setAccessibilityElement(false)
    }
}

/// The click-through overlay around the picked window. It sits directly above that window, so windows in front of
/// the target still cover it, and it is kept out of screen capture.
@MainActor
final class SelectionOutlineWindow: SelectionOutlineSurface {
    private let outlineView = SelectionOutlineView()
    private let panel = SelectionOutlinePanel()

    init() {
        panel.contentView = outlineView
    }

    func show(_ appearance: SelectionOutlineAppearance, crossfade: TimeInterval) {
        place(appearance, crossfade: crossfade)
        setAlpha(1)
    }

    func fadeOut(_ appearance: SelectionOutlineAppearance, duration: TimeInterval) {
        place(appearance, crossfade: 0)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        }
    }

    func hide() {
        panel.orderOut(nil)
        setAlpha(1)
    }

    func keepAbove(_ window: WindowID) {
        panel.order(.above, relativeTo: Int(window.rawValue))
        // Relative order can leave a never-shown panel off screen; the control bar uses the same fallback.
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func announce(_ text: String) {
        VoiceOverAnnouncement.post(text)
    }

    /// Through the animator, so this also replaces a fade that is still running.
    private func setAlpha(_ alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = alpha
        }
    }

    private func place(_ appearance: SelectionOutlineAppearance, crossfade: TimeInterval) {
        outlineView.set(appearance, crossfade: crossfade)
        let geometry = ScreenGeometry(primaryHeight: Double(NSScreen.screens.first?.frame.height ?? 0))
        panel.setFrame(geometry.appKit(fromTopLeft: appearance.frame), display: true)
        if let windowID = appearance.windowID {
            panel.level = .normal
            keepAbove(windowID)
        } else {
            // A region has no window to sit above, so its frame floats over everything, like the picker's.
            panel.level = .floating
            panel.orderFrontRegardless()
        }
    }
}

enum VoiceOverAnnouncement {
    @MainActor
    static func post(_ text: String) {
        guard let app = NSApp else { return }
        NSAccessibility.post(
            element: app, notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}

/// Reads a window's place from the window server's description of it. Pure, so it can be tested.
enum WindowServerPresence {
    static func presence(from descriptions: [[String: Any]]) -> WindowPresence {
        guard let description = descriptions.first,
            description[kCGWindowIsOnscreen as String] as? Bool == true,
            let bounds = description[kCGWindowBounds as String] as? NSDictionary,
            let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
        else { return .notVisible }
        return .onScreen(PointRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height))
    }
}

/// Follows the picked window. It polls the window server every 100 ms, which also catches a minimise or a Space
/// change, and with Accessibility allowed an `AXObserver` reports moves and resizes as they happen.
@MainActor
final class LiveWindowFrameTracker: WindowFrameTracking {
    private let permissions: any PermissionProbe
    private var windowID: CGWindowID = 0
    private var onChange: (@MainActor (WindowPresence) -> Void)?
    private var timer: Timer?
    private var observer: AXObserver?

    init(permissions: any PermissionProbe) {
        self.permissions = permissions
    }

    func start(_ window: WindowInfo, onChange: @escaping @MainActor (WindowPresence) -> Void) {
        stop()
        windowID = CGWindowID(window.id.rawValue)
        self.onChange = onChange
        sample()
        let timer = Timer(timeInterval: SelectionOutlineModel.trackingInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        if permissions.accessibility == .allowed { observe(window) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        onChange = nil
    }

    fileprivate func sample() {
        let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]] ?? []
        onChange?(WindowServerPresence.presence(from: list))
    }

    private func observe(_ window: WindowInfo) {
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let tracker = Unmanaged<LiveWindowFrameTracker>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { tracker.sample() }
        }
        guard let element = Self.element(for: window) else { return }
        var created: AXObserver?
        guard AXObserverCreate(window.pid, callback, &created) == .success, let created else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXMovedNotification, kAXResizedNotification] {
            AXObserverAddNotification(created, element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
    }

    private static func element(for window: WindowInfo) -> AXUIElement? {
        var value: CFTypeRef?
        let app = AXUIElementCreateApplication(window.pid)
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
            let elements = value as? [AXUIElement]
        else { return nil }
        let snapshots = elements.map { AXWindowSnapshot(title: title(of: $0), frame: frame(of: $0)) }
        guard let index = try? AXWindowMatch.pick(window, among: snapshots, scale: 1) else { return nil }
        return elements[index]
    }

    private static func title(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func frame(of element: AXUIElement) -> PointRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
            let position, let size, CFGetTypeID(position) == AXValueGetTypeID(),
            CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
            AXValueGetValue(size as! AXValue, .cgSize, &extent)
        else { return nil }
        return PointRect(x: origin.x, y: origin.y, width: extent.width, height: extent.height)
    }
}
