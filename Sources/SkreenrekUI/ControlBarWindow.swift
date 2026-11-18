import AppKit
import SkreenrekCore
import SwiftUI

/// The bar's one shadow, around a clear middle. It is drawn rather than left to the window server, and it lives in
/// its own click-through window: inside the bar's window its soft edge would swallow clicks meant for the recorded
/// window underneath.
final class ControlBarShadowView: NSView {
    /// Room around the bar for the largest blur and offset.
    static let margin: CGFloat = 40

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let tokens = PanelPalette(isDark ? .dark : .light).dropShadow
        let radius = PanelMetrics.radiusPanel
        let bar = bounds.insetBy(dx: Self.margin, dy: Self.margin)
        let barPath = NSBezierPath(roundedRect: bar, xRadius: radius, yRadius: radius)
        // Only outside the bar, so nothing shows at its antialiased corners.
        let outside = NSBezierPath(rect: bounds)
        outside.append(barPath)
        outside.windingRule = .evenOdd
        NSGraphicsContext.saveGraphicsState()
        outside.addClip()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(tokens.opacity)
        shadow.shadowBlurRadius = tokens.blur
        // AppKit's shadow offset is not flipped with the view: negative is down the screen.
        shadow.shadowOffset = NSSize(width: 0, height: -tokens.y)
        shadow.set()
        NSColor.black.setFill()
        barPath.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// A hosting view whose first click acts, because the bar's window is never key.
final class ControlBarHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The two windows of the bar. Never key, never main, and kept out of screen capture like the outline.
final class ControlBarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        sharingType = .none
        // `.transient` hides a panel when Skreenrek deactivates. The bar has to stay up while the
        // user works in the picked window, which is never Skreenrek.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }
}

/// The bar on screen, directly above the picked window, so windows in front of that window cover it too.
@MainActor
final class ControlBarWindow: ControlBarSurface {
    private let panel = ControlBarPanel()
    private let shadowPanel = ControlBarPanel()
    private let shadowView = ControlBarShadowView()
    var onAction: (MenuAction) -> Void = { _ in }
    private var presentation: ControlBarPresentation?
    /// Moves on every show and hide, so a fade that finishes late can't remove a bar that came back.
    private var generation = 0

    init() {
        shadowPanel.ignoresMouseEvents = true
        shadowPanel.setAccessibilityElement(false)
        shadowPanel.contentView = shadowView
    }

    func show(_ display: ControlBarDisplay, fade: TimeInterval) {
        generation += 1
        // Clear before it is ordered in, so a fade never starts with a frame of the finished bar.
        setAlpha(fade > 0 ? 0 : 1, duration: 0)
        update(display)
        if fade > 0 { setAlpha(1, duration: fade) }
    }

    func update(_ display: ControlBarDisplay) {
        if let presentation {
            if presentation.content != display.content { presentation.content = display.content }
        } else {
            install(display.content)
        }
        let geometry = ScreenGeometry(primaryHeight: Double(NSScreen.screens.first?.frame.height ?? 0))
        let frame = geometry.appKit(fromTopLeft: display.frame)
        let margin = ControlBarShadowView.margin
        if panel.frame != frame {
            shadowPanel.setFrame(frame.insetBy(dx: -margin, dy: -margin), display: true)
            panel.setFrame(frame, display: true)
        }
        keepAbove(display.windowID)
    }

    func hide(fade: TimeInterval) {
        generation += 1
        guard fade > 0 else {
            orderOut()
            return
        }
        let current = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fade
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
            shadowPanel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                self.orderOut()
            }
        }
    }

    func keepAbove(_ window: WindowID) {
        shadowPanel.order(.above, relativeTo: Int(window.rawValue))
        // Relative order can leave a never-shown panel off screen; the HUD uses the same fallback.
        if !shadowPanel.isVisible { shadowPanel.orderFrontRegardless() }
        panel.order(.above, relativeTo: shadowPanel.windowNumber)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func announce(_ text: String) {
        VoiceOverAnnouncement.post(text)
    }

    private func install(_ content: ControlBarContent) {
        let presentation = ControlBarPresentation(content: content)
        self.presentation = presentation
        let hosting = ControlBarHostingView(
            rootView: ControlBarView(presentation: presentation, onAction: { [weak self] in self?.onAction($0) }))
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
    }

    private func orderOut() {
        panel.orderOut(nil)
        shadowPanel.orderOut(nil)
        setAlpha(1, duration: 0)
    }

    /// Through the animator, so this also replaces a fade that is still running.
    private func setAlpha(_ alpha: CGFloat, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().alphaValue = alpha
            shadowPanel.animator().alphaValue = alpha
        }
    }
}
