import AppKit
import Observation
import SkreenrekControl
import SkreenrekCore
import SwiftUI

/// The panel the status item shows. The view reads it, so a one-second timer can change the elapsed time without
/// rebuilding the view and dropping a hover.
@MainActor
@Observable
final class PanelStore {
    var content: PanelContent
    var previewImage: NSImage?
    var clipImage: NSImage?
    var maxHeight: CGFloat
    var reduceMotion = false
    var heroFocusRequest = 0

    init(content: PanelContent, maxHeight: CGFloat) {
        self.content = content
        self.maxHeight = maxHeight
    }
}

/// The status item and the menu panel anchored under it. The panel is the menu: same actions, no `NSMenu`.
@MainActor
public final class MenuController: NSObject {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let hotKey: StopHotKey
    private let thumbnails = ClipThumbnails()
    private let previews: WindowPreviewModel
    private let store: PanelStore
    private let panel: MenuKeyPanel
    private let outline: SelectionOutlineController
    private let controlBar: ControlBarController
    private let controlBarWindow = ControlBarWindow()
    private var hosting: NSHostingView<StoredMenuPanel>?
    private var accessibilityKey: String?
    private var iconKey: String?
    private var timer: Timer?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var closedAt: TimeInterval = 0
    private var positioned = false
    /// Clear was clicked. Focus and the announcement wait for the panel to reach its compact layout.
    private var clearPending = false
    /// The frame the panel is on, or animating to.
    private var targetFrame: NSRect?

    /// Called when the control bar appears or goes away.
    var onControlBarVisibilityChange: (() -> Void)? {
        get { controlBar.onVisibilityChange }
        set { controlBar.onVisibilityChange = newValue }
    }

    /// While the bar is up it has the timer and Stop, so the HUD stands down.
    var controlBarVisible: Bool { controlBar.isVisible }

    public init(
        model: AppModel, previews: any WindowPreviewSource, permissions: any PermissionProbe,
        displays: @escaping @MainActor () -> [DisplayInfo]
    ) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        hotKey = StopHotKey()
        self.previews = WindowPreviewModel(source: previews, permissions: permissions)
        let content = PanelModel.content(for: model.context, preview: .noWindow)
        store = PanelStore(content: content, maxHeight: PanelMetrics.availableHeight())
        panel = MenuKeyPanel(contentRect: NSRect(x: 0, y: 0, width: PanelMetrics.width, height: contentHeight(content)))
        let tracker = SharedWindowFrameTracker(source: LiveWindowFrameTracker(permissions: permissions))
        outline = SelectionOutlineController(
            surface: SelectionOutlineWindow(), tracker: tracker.makeClient(), clock: HostTimeClock())
        controlBar = ControlBarController(
            surface: controlBarWindow, tracker: tracker.makeClient(), clock: HostTimeClock(),
            permissions: permissions, displays: displays)
        super.init()
        controlBarWindow.onAction = { [weak self] in self?.actOnControlBar($0) }
        hotKey.onPress = { [weak model] in
            guard let model else { return }
            Task { await model.perform(.stop) }
        }
        thumbnails.onLoad = { [weak self] in self?.refreshClipImage() }
        self.previews.onChange = { [weak self] in self?.applyPreview() }
        model.onChange = { [weak self] in self?.render() }
        installMonitors()
        render()
    }

    /// The HUD's "show details" opens the panel, the same as clicking the status item.
    public func showDropdown() { openPanel() }

    // MARK: - Icon

    private func render() {
        let context = model.context
        renderIcon(model.icon, state: context.displayState)
        if panel.isVisible { refresh(opening: false) }
        updateOutline()
        updateControlBar()
        updateTimer()
        updateHotKey()
    }

    /// The on-screen outline follows the same state as the panel. A closed window counts only for the window the
    /// last still was taken of, so a stale result can't hide the outline of a newer pick.
    private func updateOutline() {
        let workspace = NSWorkspace.shared
        outline.update(
            SelectionOutlineInput(
                snapshot: model.snapshot, panelOpen: panel.isVisible, windowClosed: pickedWindowClosed,
                reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
                increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast))
    }

    private var pickedWindowClosed: Bool {
        if case .windowClosed = previews.phase, previews.requestedWindow == model.snapshot.window?.id { return true }
        return false
    }

    private func updateControlBar() {
        let context = model.context
        let idleWithWindow = context.snapshot.window != nil && context.isArmed
        controlBar.update(
            ControlBarInput(
                context: context, windowClosed: pickedWindowClosed,
                outputWritable: !idleWithWindow || SkreenrekController.canWrite(model.settings.outputFolder),
                resize: model.barResize, recordStarting: model.recordStarting,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion))
    }

    /// Record and Stop go the panel's way. A preset goes through the bar's own resize, which reports back to it.
    private func actOnControlBar(_ action: MenuAction) {
        if case .chooseSize(.size(let size)) = action {
            let frame = controlBar.windowFrame
            Task { await model.chooseBarSize(size, currentFrame: frame) }
        } else {
            act(action)
        }
    }

    /// The V1 menu-bar glyph for the state: a template image (mono), or while recording the bichrome glyph with the
    /// red record dot, then the elapsed time.
    private func renderIcon(_ icon: StatusIcon, state: ControllerState) {
        guard let button = statusItem.button else { return }
        if button.target == nil {
            button.target = self
            button.action = #selector(togglePanel(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        let kitState = BrandStatusGlyph.state(for: state)
        let key = "\(kitState.rawValue) \(icon.tinted)"
        if key != iconKey {
            iconKey = key
            button.image = BrandStatusGlyph.statusItemImage(kitState, accent: icon.tinted)
        }
        if let elapsed = icon.elapsed {
            button.imagePosition = .imageLeading
            button.attributedTitle = NSAttributedString(
                string: " " + elapsed, attributes: [.font: MenuMetrics.elapsedFont])
        } else {
            button.imagePosition = .imageOnly
            button.title = ""
        }
        // The tooltip and VoiceOver sentence change on state changes and every 10 s while recording, never every
        // second.
        if icon.accessibilityKey != accessibilityKey {
            accessibilityKey = icon.accessibilityKey
            button.toolTip = icon.sentence
            button.setAccessibilityLabel(icon.sentence)
        }
    }

    // MARK: - Panel

    @objc private func togglePanel(_ sender: Any?) {
        if panel.isVisible {
            closePanel()
            return
        }
        // The click that closed the panel (the status item, or a click outside) also arrives as this action.
        if ProcessInfo.processInfo.systemUptime - closedAt < 0.25 { return }
        openPanel()
    }

    private func openPanel() {
        if panel.isVisible { return }
        model.menuWillOpen()
        if hosting == nil { installHosting() }
        refresh(opening: true)
        layoutPanel(anchor: true)
        panel.makeKeyAndOrderFront(nil)
        panel.refreshShadow()
        statusItem.button?.highlight(true)
        positioned = true
        updateOutline()
    }

    private func closePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        closedAt = ProcessInfo.processInfo.systemUptime
        positioned = false
        targetFrame = nil
        clearPending = false
        previews.cancel()
        updateOutline()
        Task { await model.menuDidClose() }
    }

    private func installHosting() {
        let hosting = NSHostingView(
            rootView: StoredMenuPanel(store: store, onAction: { [weak self] in self?.act($0) }, onClose: { [weak self] in
                self?.closePanel()
            }))
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = NSRect(origin: .zero, size: panel.frame.size)
        panel.contentView = hosting
        self.hosting = hosting
    }

    /// Rebuilds the panel from the model. `opening` takes one new still. A timer tick does not.
    private func refresh(opening: Bool) {
        let context = model.context
        let window = context.snapshot.window
        let scale = statusItem.button?.window?.screen?.backingScaleFactor ?? 2
        if opening || previews.requestedWindow != window?.id {
            previews.load(window: window, hasRegion: context.snapshot.region != nil, scale: scale)
        }
        store.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        store.maxHeight = screenBudget()
        applyContent(context, opening: opening)
    }

    private func applyPreview() {
        applyContent(model.context, opening: false)
        updateOutline()
        updateControlBar()
    }

    /// Opening never animates. While the panel is open, a change of height animates its top-anchored frame and the
    /// content together.
    private func applyContent(_ context: MenuContext, opening: Bool) {
        let exists = context.snapshot.lastClip.map { FileManager.default.fileExists(atPath: $0.files.clip) } ?? true
        let closed = previews.lastTitle
            ?? context.snapshot.lastClip?.readback.map {
                UIStrings.Menu.windowTitle(app: $0.window.app, title: $0.window.title)
            }
        let content = PanelModel.content(
            for: context, preview: previews.phase, showSpinner: previews.showSpinner, clipFileExists: exists,
            closedTitle: closed)
        let animated = PanelMetrics.animatesChange(
            from: store.content, to: content, panelOpen: !opening && panel.isVisible,
            reduceMotion: store.reduceMotion)
        if animated {
            withAnimation(.easeInOut(duration: PanelMetrics.transitionSeconds)) { store.content = content }
        } else {
            store.content = content
        }
        store.previewImage = previews.phase.still.flatMap { NSImage(data: $0.png) }
        refreshClipImage()
        if clearPending, content.isCompact {
            clearPending = false
            store.heroFocusRequest += 1
            VoiceOverAnnouncement.post(UIStrings.Menu.noWindowPicked)
        }
        if positioned { layoutPanel(anchor: false, animated: animated) }
    }

    private func refreshClipImage() {
        guard let clip = store.content.lastClip, clip.fileExists else {
            store.clipImage = nil
            return
        }
        store.clipImage = thumbnails.image(for: clip.path)
    }

    private func act(_ action: MenuAction) {
        if !PanelModel.keepsPanelOpen(action) { closePanel() }
        if action == .clearWindow { clearPending = true }
        Task { await model.perform(action) }
    }

    private func screenBudget() -> CGFloat {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        guard let screen else { return PanelMetrics.availableHeight() }
        return max(200, screen.visibleFrame.height - 8)
    }

    /// Puts the panel under the status item, or keeps its top edge there when the content gets shorter.
    private func layoutPanel(anchor: Bool, animated: Bool = false) {
        let height = min(PanelMetrics.contentHeight(store.content), store.maxHeight)
        let size = NSSize(width: PanelMetrics.width, height: height)
        guard let button = statusItem.button, let window = button.window else {
            hosting?.frame = NSRect(origin: .zero, size: size)
            panel.setContentSize(size)
            return
        }
        let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        var frame = NSRect(origin: .zero, size: size)
        if anchor || !positioned {
            frame.origin.x = buttonRect.midX - size.width / 2
            frame.origin.y = buttonRect.minY - size.height - 4
        } else {
            let current = targetFrame ?? panel.frame
            frame.origin.x = current.origin.x
            frame.origin.y = current.maxY - size.height
        }
        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            frame.origin.x = min(max(frame.origin.x, visible.minX + 4), visible.maxX - size.width - 4)
            if frame.minY < visible.minY { frame.origin.y = visible.minY + 4 }
            if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - size.height - 4 }
        }
        // A timer tick lands here too. Leave the frame alone so it can't cut a running animation short.
        guard frame != targetFrame else { return }
        targetFrame = frame
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = PanelMetrics.transitionSeconds
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            } completionHandler: { [panel] in
                MainActor.assumeIsolated { panel.refreshShadow() }
            }
        } else {
            hosting?.frame = NSRect(origin: .zero, size: size)
            panel.setFrame(frame, display: true)
        }
    }

    private func installMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) {
            [weak self] event -> NSEvent? in
            // NSEvent isn't Sendable, so only its values cross into the main-actor closure.
            let (isKeyDown, keyCode) = MenuController.monitorInput(event)
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                if keyCode == 53, self.panel.isVisible {
                    self.closePanel()
                    return true
                }
                if !isKeyDown { self.closeIfClickIsOutside() }
                return false
            }
            return consumed ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.closeIfClickIsOutside() }
        }
    }

    /// The values the event monitor needs. `keyCode` is read only on key events: on a mouse event it raises, and
    /// AppKit then drops the click, so the status item never opens the panel.
    nonisolated static func monitorInput(_ event: NSEvent) -> (isKeyDown: Bool, keyCode: UInt16?) {
        let isKeyDown = event.type == .keyDown
        return (isKeyDown, isKeyDown ? event.keyCode : nil)
    }

    /// A click in the panel, on the status item, or on a Size / Frame Rate menu stays. Anything else closes.
    private func closeIfClickIsOutside() {
        guard panel.isVisible else { return }
        let point = NSEvent.mouseLocation
        if panel.frame.contains(point) { return }
        if let button = statusItem.button, let window = button.window {
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            if rect.contains(point) { return }
        }
        // The outline overlay covers the picked window but takes no clicks, so a click there is still outside.
        let ownWindowClicked = NSApp.windows.contains {
            $0 !== panel && $0.isVisible && !$0.ignoresMouseEvents && $0.frame.contains(point)
        }
        if ownWindowClicked { return }
        closePanel()
    }

    // MARK: - Elapsed timer and hot key

    private func updateTimer() {
        let recording = model.snapshot.state == .recording
        if recording, timer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Task { await self.model.tick() }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !recording, let timer {
            timer.invalidate()
            self.timer = nil
        }
    }

    private func updateHotKey() {
        if model.wantsStopHotKey { hotKey.register() } else { hotKey.unregister() }
    }

    // MARK: - Shared with the layout tests

    /// A hosted SwiftUI view sized to its content. The dropdown layout tests measure the header and the clip row.
    static func hosted<V: View>(_ view: V) -> NSHostingView<V> {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        return hosting
    }

    /// The leading icon: a 13 pt template symbol that follows the menu's highlight, or red (Record Window, Stop
    /// Recording) or the accent (Pick Window… before a window is picked) for the primary item.
    static func icon(_ symbol: String?, _ tint: DropdownModel.IconTint) -> NSImage? {
        guard let symbol, let image = MenuMetrics.symbol(symbol, pointSize: MenuMetrics.iconPointSize, color: tint.nsColor)
        else { return nil }
        image.isTemplate = tint.nsColor == nil
        return image
    }
}

/// The panel under the status item. Key, so Tab and Return work, and non-activating, so the app being recorded
/// stays frontmost. The window is clear only so the corners stay round: `MenuPanelView` draws the opaque surface. The
/// system window shadow is the panel's one shadow, and the window server derives it from the drawn shape.
class MenuKeyPanel: NSPanel {
    private var shadowRefreshPending = false

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        let resized = frameRect.size != frame.size
        super.setFrame(frameRect, display: flag)
        if resized { refreshShadow() }
    }

    /// Recomputes the shadow now, and once more after SwiftUI has committed what it draws at the new size.
    func refreshShadow() {
        invalidateShadow()
        guard !shadowRefreshPending else { return }
        shadowRefreshPending = true
        Task { @MainActor [weak self] in
            self?.shadowRefreshPending = false
            self?.invalidateShadow()
        }
    }
}

/// The panel view bound to the store, so the elapsed time can change without replacing the view.
@MainActor
private struct StoredMenuPanel: View {
    var store: PanelStore
    var onAction: (MenuAction) -> Void
    var onClose: () -> Void

    var body: some View {
        MenuPanelView(
            content: store.content, maxHeight: store.maxHeight, previewImage: store.previewImage,
            clipImage: store.clipImage, reduceMotion: store.reduceMotion,
            heroFocusRequest: store.heroFocusRequest, onAction: onAction, onClose: onClose)
    }
}

private func contentHeight(_ content: PanelContent) -> CGFloat {
    PanelMetrics.contentHeight(content)
}
