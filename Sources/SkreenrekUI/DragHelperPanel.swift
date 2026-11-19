import AppKit
import Observation
import SkreenrekCore
import SwiftUI
import os

// The drag-to-authorize helper's AppKit layer: the panel, its content, the drag source, System Settings' window bounds
// and the controller that polls them. The decisions live in `DragHelperState` and `DragHelperPlacer`.

/// Reads System Settings' window. Fake in tests; `CGWindowListSystemSettings` in the app.
@MainActor
public protocol SystemSettingsWindowSource: AnyObject {
    func current() -> SystemSettingsWindow
}

/// System Settings' main window from CGWindowList: only the owner and the bounds, which need no Screen Recording
/// (window titles and images would, and aren't read).
@MainActor
public final class CGWindowListSystemSettings: SystemSettingsWindowSource {
    public static let bundleID = "com.apple.systempreferences"

    public init() {}

    public func current() -> SystemSettingsWindow {
        guard
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
                .first(where: { !$0.isTerminated })
        else { return .notRunning }
        if app.isHidden { return .hidden }
        guard
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return .unreadable }
        let pid = app.processIdentifier
        let frames = list.compactMap { info -> CGRect? in
            guard (info[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) == pid,
                (info[kCGWindowLayer as String] as? Int) == 0,
                let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                let rect = CGRect(dictionaryRepresentation: bounds), rect.width > 1, rect.height > 1
            else { return nil }
            return rect
        }
        // Its main window is the largest one on screen; none means minimised or still launching.
        return frames.max { $0.width * $0.height < $1.width * $1.height }.map(SystemSettingsWindow.visible) ?? .hidden
    }
}

/// What the panel's content reads.
@MainActor
@Observable
final class DragHelperViewModel {
    var state: DragHelperState
    var icon: NSImage
    var increaseContrast: Bool
    /// The file URL the drag carries: the running bundle.
    @ObservationIgnored var bundleURL: URL?
    @ObservationIgnored var onClose: () -> Void = {}
    @ObservationIgnored var onHover: (Bool) -> Void = { _ in }
    @ObservationIgnored var onDragging: (Bool) -> Void = { _ in }

    init(state: DragHelperState, icon: NSImage, increaseContrast: Bool, bundleURL: URL?) {
        self.state = state
        self.icon = icon
        self.increaseContrast = increaseContrast
        self.bundleURL = bundleURL
    }
}

/// 320 × 88: the icon (the drag source) on the edge facing System Settings, the title and detail, and the ×.
struct DragHelperView: View {
    let model: DragHelperViewModel
    /// Renders pin the loop's clock; the live panel follows the real one.
    var frozenTime: TimeInterval?
    /// The live panel's shadow is the window's; composite renders draw it.
    var shadow: HUDShadowSource = .window

    private typealias M = DragHelperMetrics

    var body: some View {
        let state = model.state
        let mirrored = state.placement?.mirrored ?? false
        let iconX = mirrored ? M.mirroredIconX : M.iconOrigin.x
        let textX = mirrored ? M.mirroredTextTrailing - M.textWidth : M.textX
        ZStack(alignment: .topLeading) {
            ZStack {
                copy(granted: state.isGranted, mirrored: mirrored)
                    .id(state.isGranted)
                    .transition(.opacity)
            }
            .frame(width: M.textWidth, alignment: mirrored ? .trailing : .leading)
            .offset(x: textX, y: M.textTop)
            DragHelperIcon(model: model)
                .frame(width: M.iconSize, height: M.iconSize)
                .overlay(alignment: .bottomTrailing) {
                    if state.isGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: M.badgeSize))
                            .foregroundStyle(Color(nsColor: .systemGreen))
                            .transition(.opacity)
                            .accessibilityHidden(true)
                    }
                }
                .offset(x: iconX, y: M.iconOrigin.y)
            ghost(mirrored: mirrored)
                .offset(x: iconX, y: M.iconOrigin.y)
                .allowsHitTesting(false)
            Button(action: model.onClose) {
                Image(systemName: "xmark").font(.system(size: M.closeGlyph, weight: .semibold))
            }
            .buttonStyle(
                PanelIconButtonStyle(
                    rest: PanelSurface.secondaryText, active: PanelSurface.primaryText, forcedState: nil,
                    size: M.closeHit)
            )
            .help(UIStrings.DragHelper.close)
            .accessibilityLabel(UIStrings.DragHelper.closeLabel)
            .offset(x: mirrored ? M.mirroredCloseX : M.closeOrigin.x, y: M.closeOrigin.y)
        }
        .frame(width: M.size.width, height: M.size.height, alignment: .topLeading)
        .animation(state.reduceMotion ? nil : .easeInOut(duration: M.crossfade), value: state.isGranted)
        .modifier(HUDSurface(shadow: shadow, increaseContrast: model.increaseContrast, radius: M.radius))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(UIStrings.DragHelper.panelLabel(state.permission))
    }

    private func copy(granted: Bool, mirrored: Bool) -> some View {
        VStack(alignment: mirrored ? .trailing : .leading, spacing: M.titleDetailGap) {
            Text(granted ? UIStrings.DragHelper.grantedTitle : UIStrings.DragHelper.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(nsColor: .labelColor))
                .lineLimit(1)
            Text(granted ? UIStrings.DragHelper.grantedDetail : UIStrings.DragHelper.detail(model.state.permission))
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(mirrored ? .trailing : .leading)
        .frame(width: M.textWidth, alignment: mirrored ? .trailing : .leading)
    }

    /// The ghost slides toward System Settings: left when the panel is on its right (or docked), right when mirrored.
    @ViewBuilder private func ghost(mirrored: Bool) -> some View {
        let state = model.state
        if let frozenTime {
            ghostImage(state.ghost(at: frozenTime), mirrored: mirrored)
        } else {
            let now = Date.timeIntervalSinceReferenceDate
            TimelineView(.animation(minimumInterval: nil, paused: !state.loopRunning(at: now))) { context in
                ghostImage(state.ghost(at: context.date.timeIntervalSinceReferenceDate), mirrored: mirrored)
            }
        }
    }

    @ViewBuilder private func ghostImage(_ ghost: DragHelperGhost?, mirrored: Bool) -> some View {
        if let ghost {
            Image(nsImage: model.icon)
                .resizable()
                .frame(width: M.iconSize, height: M.iconSize)
                .opacity(ghost.opacity)
                .offset(x: mirrored ? ghost.offset : -ghost.offset)
                .accessibilityHidden(true)
        }
    }
}

/// The icon as an AppKit view: it is the drag source.
private struct DragHelperIcon: NSViewRepresentable {
    let model: DragHelperViewModel

    func makeNSView(context: Context) -> DragHelperIconView {
        let view = DragHelperIconView(frame: .zero)
        update(view)
        return view
    }

    func updateNSView(_ view: DragHelperIconView, context: Context) { update(view) }

    private func update(_ view: DragHelperIconView) {
        view.image = model.icon
        view.bundleURL = model.bundleURL
        let model = model
        view.onDragging = { [weak model] in model?.onDragging($0) }
    }
}

/// Draws the 56 pt icon and starts a drag carrying the bundle's file URL. A cancelled or refused drop slides back
/// (the system default).
final class DragHelperIconView: NSView, NSDraggingSource {
    var image: NSImage? { didSet { needsDisplay = true } }
    var bundleURL: URL?
    var onDragging: (Bool) -> Void = { _ in }
    private var mouseDownEvent: NSEvent?

    override init(frame: NSRect) {
        super.init(frame: frame)
        toolTip = UIStrings.DragHelper.iconHelp
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(UIStrings.DragHelper.iconLabel)
        setAccessibilityHelp(UIStrings.DragHelper.iconHelp)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    /// The panel never becomes key, so the first click has to count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        image?.draw(in: bounds)
    }

    override func mouseDown(with event: NSEvent) { mouseDownEvent = event }
    override func mouseUp(with event: NSEvent) { mouseDownEvent = nil }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent, let url = bundleURL, let image else { return }
        let start = down.locationInWindow
        let point = event.locationInWindow
        guard hypot(point.x - start.x, point.y - start.y) >= 3 else { return }
        mouseDownEvent = nil
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        let session = beginDraggingSession(with: [item], event: down, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        [.copy, .link, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) { onDragging(true) }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragging(false)
    }
}

/// Non-activating, never key or main, so System Settings keeps focus the whole time.
final class DragHelperPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: DragHelperMetrics.size),
            styleMask: [.nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Takes the first click (the panel is never key) and reports the pointer entering and leaving, whatever app is
/// active.
private final class DragHelperHostingView: NSHostingView<DragHelperView> {
    var onHover: (Bool) -> Void = { _ in }
    private var area: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        self.area = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover(false)
    }
}

/// Owns the one helper: shows it for a pane, polls System Settings and the permission every 250 ms, follows the
/// window, and closes it. After × it stays closed until `show` is called again.
@MainActor
public final class DragHelperController {
    /// Where `Open System Settings…` was clicked.
    public enum Source: Sendable, Equatable {
        case onboarding
        case settings
    }

    private static let log = Logger(subsystem: SkreenrekIdentity.bundleID, category: "drag-helper")

    private let probe: any PermissionProbe
    private let windows: any SystemSettingsWindowSource
    private let now: () -> TimeInterval
    private let eligibility: () -> DragHelperEligibility
    private let icon: () -> NSImage
    private var model: DragHelperViewModel?
    private var panel: DragHelperPanel?
    private var source: Source?
    private var timer: Timer?

    public init(
        probe: any PermissionProbe, windows: any SystemSettingsWindowSource,
        now: @escaping () -> TimeInterval = { Date.timeIntervalSinceReferenceDate },
        eligibility: @escaping () -> DragHelperEligibility = { DragHelperEligibility.current() },
        icon: @escaping () -> NSImage = { NSApp.applicationIconImage }
    ) {
        self.probe = probe
        self.windows = windows
        self.now = now
        self.eligibility = eligibility
        self.icon = icon
    }

    /// The helper's state, nil when there is none.
    var state: DragHelperState? { model?.state }

    /// `Open System Settings…` for `permission`. A helper already up changes its copy in place.
    public func show(_ permission: Permission, from source: Source) {
        guard DragHelperPane.applies(to: permission) else { return }
        let eligibility = eligibility()
        guard eligibility == .eligible else {
            Self.log.info("No drag helper: \(String(describing: eligibility), privacy: .public)")
            return
        }
        self.source = source
        if let model, !model.state.isClosed {
            model.state.switchPane(to: permission, now: now())
            return tick()
        }
        // One fading out after a grant gives way to the new one.
        tearDown()
        self.source = source
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let model = DragHelperViewModel(
            state: DragHelperState(permission: permission, now: now(), reduceMotion: reduceMotion),
            icon: icon(), increaseContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
            bundleURL: Bundle.main.bundleURL)
        model.onClose = { [weak self] in self?.close(.closeButton) }
        model.onHover = { [weak self] hovering in self?.update { $0.setHovering(hovering, now: $1) } }
        model.onDragging = { [weak self] dragging in self?.update { $0.setDragging(dragging, now: $1) } }
        self.model = model
        let timer = Timer(timeInterval: DragHelperMetrics.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    /// The onboarding step or the Settings window it came from went away.
    public func dismiss(from source: Source) {
        guard self.source == source else { return }
        close(.sourceDismissed)
    }

    /// Closes it now, with no success state.
    public func close(_ reason: DragHelperCloseReason) {
        guard let model else { return }
        model.state.close(reason, now: now())
        tearDown()
    }

    private func update(_ change: (inout DragHelperState, TimeInterval) -> Void) {
        guard let model else { return }
        change(&model.state, now())
    }

    private func tick() {
        guard let model else { return }
        let screens = NSScreen.screens.map { DragHelperScreen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        let fallback = (NSScreen.main ?? NSScreen.screens.first).map {
            DragHelperScreen(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        let wasOnScreen = model.state.onScreen
        let hadAppeared = model.state.appearedAt != nil
        model.state.update(
            now: now(), window: windows.current(), screens: screens, fallback: fallback,
            granted: probe.status(of: model.state.permission) == .allowed)
        let state = model.state
        if case .closed(let reason) = state.phase {
            return reason == .granted ? fadeOutAndTearDown(reduceMotion: state.reduceMotion) : tearDown()
        }
        guard state.onScreen, let placement = state.placement else {
            if wasOnScreen { panel?.orderOut(nil) }
            return
        }
        let panel = self.panel ?? makePanel(model)
        if panel.frame != placement.frame { panel.setFrame(placement.frame, display: true, animate: false) }
        guard !wasOnScreen else { return }
        if !hadAppeared, !state.reduceMotion {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = DragHelperMetrics.fadeIn
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
    }

    private func makePanel(_ model: DragHelperViewModel) -> DragHelperPanel {
        let panel = DragHelperPanel()
        let hosting = DragHelperHostingView(rootView: DragHelperView(model: model))
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: DragHelperMetrics.size)
        hosting.onHover = { [weak model] hovering in model?.onHover(hovering) }
        panel.contentView = hosting
        panel.setAccessibilityLabel(UIStrings.DragHelper.panelLabel(model.state.permission))
        self.panel = panel
        return panel
    }

    private func fadeOutAndTearDown(reduceMotion: Bool) {
        timer?.invalidate()
        timer = nil
        guard let panel, !reduceMotion else { return tearDown() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DragHelperMetrics.fadeOut
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            MainActor.assumeIsolated {
                // A new helper may have replaced this one during the fade.
                guard let self, self.panel === panel else { return }
                self.tearDown()
            }
        }
    }

    private func tearDown() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.close()
        panel = nil
        model = nil
        source = nil
    }
}
