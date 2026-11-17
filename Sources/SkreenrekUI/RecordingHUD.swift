import AppKit
import Observation
import SkreenrekControl
import SkreenrekCore
import SwiftUI

/// Updated in place while recording: Stop's native hosting view and accessibility identity survive each tick.
@MainActor @Observable
final class HUDPresentation {
    var state: HUDState
    var reduceMotion: Bool
    var increaseContrast: Bool
    init(state: HUDState = .hidden, reduceMotion: Bool = false, increaseContrast: Bool = false) {
        self.state = state; self.reduceMotion = reduceMotion; self.increaseContrast = increaseContrast
    }
}

struct RecordingHUDView: View {
    @Bindable var presentation: HUDPresentation
    var stop: () -> Void = {}
    var reveal: (String) -> Void = { _ in }
    var details: () -> Void = {}
    var dismiss: () -> Void = {}
    var hover: (Bool) -> Void = { _ in }

    var body: some View {
        content
            .font(.system(size: 13))
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, 12).frame(height: 36)
            .background(HUDMaterial()).clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(presentation.increaseContrast ? Color.primary : Color(nsColor: .separatorColor),
                              lineWidth: presentation.increaseContrast ? 2 : 1))
            .onHover(perform: hover)
    }

    @ViewBuilder private var content: some View {
        switch presentation.state {
        case .hidden: EmptyView()
        case .recording(let target, let seconds):
            HStack(spacing: 12) {
                symbol("record.circle.fill").foregroundStyle(Color(nsColor: .systemRed))
                // Reserve four minute digits so crossing 9:59 never moves Stop during a click.
                Text(TimeFormat.minutesSeconds(599_999)).hidden()
                    .overlay(alignment: .trailing) { Text(TimeFormat.minutesSeconds(Double(seconds))) }
                    .font(.system(size: 12, design: .monospaced))
                Divider().frame(height: 16)
                Button(action: stop) {
                    Label(UIStrings.HUD.stop, systemImage: "stop.fill")
                        .labelStyle(.titleAndIcon).fixedSize()
                        .padding(.horizontal, 8).frame(height: 28)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(UIStrings.HUD.voiceOver(target: target, seconds: seconds))
            .accessibilityAction(named: UIStrings.HUD.stop, stop)
        case .writing:
            HStack(spacing: 12) {
                if presentation.reduceMotion { symbol("arrow.down.circle") }
                else { ProgressView().controlSize(.small).frame(width: 16, height: 16) }
                Text(UIStrings.Menu.savingClip)
            }
        case .saved(let duration, let path):
            HStack(spacing: 12) {
                symbol("checkmark.circle.fill").foregroundStyle(Color(nsColor: .systemGreen))
                Text(UIStrings.HUD.saved(duration))
                Button(UIStrings.Menu.showInFinder) { reveal(path) }
            }
        case .error(let reason):
            HStack(spacing: 12) {
                symbol("exclamationmark.triangle")
                Text(UIStrings.HUD.stopped(reason))
                Button(UIStrings.HUD.showDetails, action: details)
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel(UIStrings.HUD.dismiss)
            }
        }
    }
    private func symbol(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 16)).frame(width: 16, height: 16)
    }
}

struct RegionOutline: View {
    var increaseContrast = false
    var body: some View {
        Rectangle().strokeBorder(Color(nsColor: .systemRed), lineWidth: increaseContrast ? 2 : 1)
    }
}

/// Thin presentation around HUDModel. Its timer supplies deadlines; the capture controller owns Stop.
@MainActor
final class RecordingHUD: NSObject, NSWindowDelegate {
    private var model = HUDModel()
    private var placement = HUDPlacement()
    private let defaults: UserDefaults
    private let panel = CapturePanel(frame: .zero)
    private var outline: CapturePanel?
    private var timer: Timer?
    private let presentation = HUDPresentation()
    private var display: DisplayInfo?
    private var target: PointRect?
    private var programmaticMove = false
    private var renderedKind: HUDState.Kind?
    private var placedTarget: PointRect?
    private var placedDisplay: DisplayInfo?
    private var fading = false
    var stop: () -> Void = {}
    var showDetails: () -> Void = {}

    init(defaults: UserDefaults) {
        self.defaults = defaults
        super.init()
        panel.delegate = self
        panel.isMovableByWindowBackground = true
    }

    func update(_ snapshot: ControllerSnapshot, indicatorEnabled: Bool) {
        model.observe(snapshot, now: ProcessInfo.processInfo.systemUptime, indicatorEnabled: indicatorEnabled)
        if snapshot.state == .recording || snapshot.state == .writing { updateTarget(snapshot) }
        render()
    }

    private var geometry: ScreenGeometry { ScreenGeometry(primaryHeight: Double(NSScreen.screens.first?.frame.height ?? 0)) }

    private func updateTarget(_ snapshot: ControllerSnapshot) {
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == snapshot.displayId
        }) ?? NSScreen.screens.first else { return }
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        let display = DisplayInfo(id: id, name: screen.localizedName, scale: screen.backingScaleFactor,
                                  frame: geometry.topLeft(fromAppKit: screen.frame),
                                  visibleFrame: geometry.topLeft(fromAppKit: screen.visibleFrame))
        self.display = display
        if let stored = defaults.array(forKey: "hud.position.\(id)") as? [Double], stored.count == 2 {
            placement.remember(PointRect(x: stored[0], y: stored[1], width: 0, height: 36), display: id)
        }
        if let window = snapshot.window {
            // Window-server bounds are public geometry; this never requests a permission or reads pixels.
            let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, window.id.rawValue) as? [[String: Any]]
            let bounds = list?.first?[kCGWindowBounds as String] as? [String: Any]
            target = bounds.flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }.map(PointRect.init) ?? window.frame
        }
        else if let region = snapshot.region {
            target = PointRect(x: display.frame.x + Double(region.x) / display.scale,
                               y: display.frame.y + Double(region.y) / display.scale,
                               width: Double(region.width) / display.scale, height: Double(region.height) / display.scale)
        }
        if snapshot.state == .recording, snapshot.region != nil, let target, model.state != .hidden {
            if outline == nil {
                let outline = CapturePanel(frame: .zero)
                outline.ignoresMouseEvents = true
                outline.contentView = NSHostingView(rootView: RegionOutline(
                    increaseContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast))
                self.outline = outline
            }
            outline?.setFrame(geometry.appKit(fromTopLeft: target), display: true)
            outline?.orderFrontRegardless()
        } else { outline?.orderOut(nil) }
    }

    private func render() {
        guard model.state != .hidden else {
            outline?.orderOut(nil)
            timer?.invalidate(); timer = nil
            renderedKind = nil
            guard panel.isVisible, !fading else { return }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                panel.orderOut(nil)
            } else {
                fading = true
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    panel.animator().alphaValue = 0
                } completionHandler: { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.fading = false
                        if self.model.state == .hidden { self.panel.orderOut(nil) }
                        self.panel.alphaValue = 1
                    }
                }
            }
            return
        }
        if presentation.state != model.state { presentation.state = model.state }
        presentation.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        presentation.increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        if timer == nil {
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.model.tick(now: ProcessInfo.processInfo.systemUptime)
                    self.render()
                }
            }
            RunLoop.main.add(timer, forMode: .common); self.timer = timer
        }
        let kindChanged = renderedKind != model.state.kind
        if kindChanged {
            renderedKind = model.state.kind
            let view = NSHostingView(rootView: RecordingHUDView(
                presentation: presentation,
                stop: { [weak self] in self?.stop() },
                reveal: { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: $0)]) },
                details: { [weak self] in self?.showDetails() },
                dismiss: { [weak self] in self?.model.dismiss(); self?.render() },
                hover: { [weak self] in self?.model.hovered = $0 }))
            let size = view.fittingSize
            view.frame = NSRect(origin: .zero, size: size)
            panel.contentView = view
        }
        if let display, let target, let view = panel.contentView,
           kindChanged || placedDisplay != display || (placedTarget != target && placement.remembered[display.id] == nil) {
            programmaticMove = true
            panel.setFrame(geometry.appKit(fromTopLeft: placement.frame(target: target, display: display, width: view.frame.width)), display: true)
            programmaticMove = false
            placedTarget = target; placedDisplay = display
        }
        panel.alphaValue = 1
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func windowDidMove(_ notification: Notification) {
        guard !programmaticMove, let display else { return }
        let frame = geometry.topLeft(fromAppKit: panel.frame)
        placement.remember(frame, display: display.id)
        defaults.set([frame.x, frame.y], forKey: "hud.position.\(display.id)")
    }

    func close() {
        timer?.invalidate(); timer = nil
        panel.orderOut(nil); outline?.orderOut(nil)
    }
}
