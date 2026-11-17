import AppKit
import Carbon.HIToolbox
import SkreenrekCore
import SwiftUI

/// Panels deliberately never take key or main status away from the recorded app.
final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(frame: CGRect, level: NSWindow.Level = .floating) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
    }
}

struct HUDMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct PickerLabel: View {
    let title: String
    let detail: String
    var voiceOver: String = ""
    var pick: () -> Void = {}
    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).frame(width: 280, height: 56)
        .background(HUDMaterial()).clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voiceOver.isEmpty ? title + ", " + detail : voiceOver)
        .accessibilityAction(named: UIStrings.Picker.pick, pick)
    }
}

struct PickerHint: View {
    var cancel: () -> Void = {}
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "viewfinder").font(.system(size: 16)).frame(width: 16)
            Text(UIStrings.Picker.hint).font(.system(size: 13))
            Text(UIStrings.Picker.escape).font(.system(size: 12)).foregroundStyle(.secondary)
            Button(UIStrings.Picker.cancel, action: cancel)
        }
        .padding(.horizontal, 16).frame(height: 44)
        .background(HUDMaterial()).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// The same WindowPicker serves the menu, CLI and MCP. Carbon keys are scoped to the overlay's lifetime, allowing
/// keyboard picking without a key panel, an event tap or an Accessibility grant.
@MainActor
public final class PickerOverlay: WindowPicker {
    private let catalog: any WindowCatalog
    private let ownPid: Int32
    private var model: PickerModel?
    private var panels: [CapturePanel] = []
    private var continuation: CheckedContinuation<PickResult, any Error>?
    private var watchdog: Task<Void, Never>?
    private var keyboard: PickerKeyboard?
    private var pointer = CGPoint.zero

    public init(catalog: any WindowCatalog, ownPid: Int32 = ProcessInfo.processInfo.processIdentifier) {
        self.catalog = catalog
        self.ownPid = ownPid
    }

    public func pick(timeout: TimeInterval) async throws -> PickResult {
        guard continuation == nil else { throw SkreenrekError.internal(message: UIStrings.Picker.alreadyOpen) }
        let directory = WindowDirectory(catalog: catalog, ownPid: ownPid)
        let windows = try await directory.windows()
        let displays = try await catalog.displays()
        guard continuation == nil else { throw SkreenrekError.internal(message: UIStrings.Picker.alreadyOpen) }
        guard !Task.isCancelled else { return .cancelled }
        model = PickerModel(windows: windows, displays: displays, ownPid: ownPid)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                show(displays)
                watchdog = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(max(0, timeout))) } catch { return }
                    self?.finish(.cancelled)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.cancelled) }
        }
    }

    private var geometry: ScreenGeometry { ScreenGeometry(primaryHeight: Double(NSScreen.screens.first?.frame.height ?? 0)) }

    private func show(_ displays: [DisplayInfo]) {
        for display in displays {
            // Above floating windows, below the menu bar and screen saver. Menu bar remains usable.
            let panel = CapturePanel(frame: geometry.appKit(fromTopLeft: display.visibleFrame),
                                     level: NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1))
            let canvas = PickerCanvas(frame: NSRect(origin: .zero, size: panel.frame.size))
            canvas.overlay = self
            canvas.display = display
            panel.contentView = canvas
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        keyboard = PickerKeyboard { [weak self] key in self?.key(key) }
        keyboard?.start()
        updatePointer(NSEvent.mouseLocation, phase: .moved)
    }

    fileprivate enum PointerPhase { case moved, down, dragged, up }
    fileprivate func updatePointer(_ appKitPoint: CGPoint, phase: PointerPhase) {
        pointer = geometry.topLeft(fromAppKit: appKitPoint)
        switch phase {
        case .moved: model?.hover(pointer)
        case .down: model?.hover(pointer); model?.beginDrag(pointer)
        case .dragged: model?.drag(to: pointer); NSCursor.crosshair.set()
        case .up:
            model?.drag(to: pointer)
            finish(model?.selection ?? .cancelled)
            return
        }
        redraw()
    }

    private func key(_ key: UInt32) {
        switch Int(key) {
        case kVK_Escape: finish(.cancelled)
        case kVK_Return: finish(model?.selection ?? .cancelled)
        case kVK_LeftArrow, kVK_UpArrow: model?.move(forward: false); redraw()
        default: model?.move(); redraw()
        }
    }

    private func redraw() {
        guard let model else { return }
        for panel in panels {
            (panel.contentView as? PickerCanvas)?.update(model, pointer: pointer)
        }
    }

    fileprivate func finish(_ result: PickResult) {
        guard let continuation else { return }
        self.continuation = nil
        watchdog?.cancel(); watchdog = nil
        keyboard?.stop(); keyboard = nil
        panels.forEach { $0.orderOut(nil) }
        panels = []
        model = nil
        NSCursor.arrow.set()
        continuation.resume(returning: result)
    }
}

final class PickerCanvas: NSView {
    weak var overlay: PickerOverlay?
    var display: DisplayInfo?
    private var model: PickerModel?
    private var label: NSView?
    private var hint: NSView?
    private var chip: NSView?
    var increaseContrast: Bool?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        // The label and size chip are decorations. Picking and dragging must work through them;
        // only the hint bar's Cancel control handles its own pointer events.
        if let hint, hint.frame.contains(local) { return super.hitTest(point) }
        return self
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }
    override func mouseMoved(with event: NSEvent) { overlay?.updatePointer(NSEvent.mouseLocation, phase: .moved) }
    override func mouseDown(with event: NSEvent) { overlay?.updatePointer(NSEvent.mouseLocation, phase: .down) }
    override func mouseDragged(with event: NSEvent) { overlay?.updatePointer(NSEvent.mouseLocation, phase: .dragged) }
    override func mouseUp(with event: NSEvent) { overlay?.updatePointer(NSEvent.mouseLocation, phase: .up) }

    func update(_ model: PickerModel, pointer: CGPoint) {
        guard let display else { return }
        let oldAnnouncement = self.model?.voiceOver
        self.model = model
        label?.removeFromSuperview(); chip?.removeFromSuperview()
        if hint == nil {
            let view = NSHostingView(rootView: PickerHint { [weak self] in self?.overlay?.finish(.cancelled) })
            let size = view.fittingSize
            view.frame = NSRect(x: (bounds.width - size.width) / 2, y: bounds.height - 44 - 16, width: size.width, height: 44)
            addSubview(view); hint = view
        }
        if let window = model.hovered, window.frame.cgRect.intersects(display.visibleFrame.cgRect) {
            let rect = local(window.frame).intersection(bounds)
            let view = NSHostingView(rootView: PickerLabel(title: model.title, detail: model.detail, voiceOver: model.voiceOver,
                pick: { [weak self] in self?.overlay?.finish(model.selection) }))
            view.frame = NSRect(x: max(0, min(bounds.width - 280, rect.midX - 140)),
                                y: max(0, min(bounds.height - 56, rect.midY - 28)), width: 280, height: 56)
            view.setAccessibilityLabel(model.voiceOver)
            addSubview(view); label = view
            if oldAnnouncement != model.voiceOver {
                NSAccessibility.post(element: self, notification: .announcementRequested,
                    userInfo: [.announcement: model.voiceOver, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
            }
        }
        if let region = model.region, model.regionDisplay?.id == display.id {
            let view = NSHostingView(rootView: Text(region.size.description).font(.system(size: 12))
                .padding(4).background(HUDMaterial()).clipShape(RoundedRectangle(cornerRadius: 4)))
            let size = view.fittingSize
            view.frame = NSRect(x: min(bounds.width - size.width, pointer.x - display.visibleFrame.x + 16),
                                y: min(bounds.height - size.height, pointer.y - display.visibleFrame.y + 16),
                                width: size.width, height: size.height)
            addSubview(view); chip = view
        }
        needsDisplay = true
    }

    private func local(_ rect: PointRect) -> CGRect {
        CGRect(x: rect.x - (display?.visibleFrame.x ?? 0), y: rect.y - (display?.visibleFrame.y ?? 0),
               width: rect.width, height: rect.height)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let model, let rect = model.regionFrame ?? model.hovered?.frame else { return }
        let region = model.region != nil
        let contrast = increaseContrast ?? NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let width: CGFloat = contrast ? (region ? 2 : 3) : (region ? 1 : 2)
        let path = NSBezierPath(roundedRect: local(rect).insetBy(dx: width / 2, dy: width / 2),
                                xRadius: region ? 0 : 10, yRadius: region ? 0 : 10)
        if !region { NSColor.controlAccentColor.withAlphaComponent(0.18).setFill(); path.fill() }
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = width
        path.stroke()
    }
}

@MainActor
private final class PickerKeyboard {
    let pressed: (UInt32) -> Void
    var keys: [EventHotKeyRef] = []
    var handler: EventHandlerRef?
    init(pressed: @escaping (UInt32) -> Void) { self.pressed = pressed }
    func start() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, data in
            guard let data, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                  id.signature == 0x5049_434B else { return OSStatus(eventNotHandledErr) }
            let key = id.id
            MainActor.assumeIsolated { Unmanaged<PickerKeyboard>.fromOpaque(data).takeUnretainedValue().pressed(key) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        for key in [kVK_Tab, kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Return, kVK_Escape] {
            var ref: EventHotKeyRef?
            if RegisterEventHotKey(UInt32(key), 0, EventHotKeyID(signature: 0x5049_434B, id: UInt32(key)),
                                   GetApplicationEventTarget(), 0, &ref) == noErr, let ref { keys.append(ref) }
        }
    }
    func stop() {
        keys.forEach { UnregisterEventHotKey($0) }; keys = []
        if let handler { RemoveEventHandler(handler) }; handler = nil
    }
}
