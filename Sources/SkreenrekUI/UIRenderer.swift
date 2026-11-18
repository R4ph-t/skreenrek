import AppKit
import SkreenrekControl
import SkreenrekCore
import SwiftUI

/// What `skreenrek debug render-ui` was asked for.
public enum RenderUIRequest: Sendable, Equatable {
    /// The shipping UI. `--direction c` is kept as an alias: C is the shipping UI.
    case shipping(out: URL)
    /// `--direction size13`: Designer's spec 13 v2 Size states (submenu, Custom Size panel, armed menu).
    case size13(out: URL)

    /// Parses the arguments after the executable: `debug render-ui --out DIR [--direction c|size13]`, flags in any
    /// order. Nil for anything else (the CLI handles it).
    public static func parse(_ arguments: [String]) -> RenderUIRequest? {
        guard arguments.count >= 2, arguments[0] == "debug", arguments[1] == "render-ui" else { return nil }
        var out: String?
        var direction: String?
        var rest = arguments.dropFirst(2)[...]
        while let flag = rest.popFirst() {
            guard let value = rest.popFirst() else { return nil }
            switch flag {
            case "--out" where out == nil: out = value
            case "--direction" where direction == nil: direction = value.lowercased()
            default: return nil
            }
        }
        guard let out else { return nil }
        let folder = URL(fileURLWithPath: (out as NSString).expandingTildeInPath, isDirectory: true)
        switch direction {
        case nil, "c": return .shipping(out: folder)
        case "size13": return .size13(out: folder)
        default: return nil
        }
    }
}

/// `skreenrek debug render-ui --out DIR`: the menu-bar icons, a composed dropdown for each state, the Size and Frame
/// Rate submenus, the Settings window, the picker, the HUD and onboarding, as PNGs at 2× in light and dark, named
/// `<surface>-<state>-<light|dark>@2x.png`. How screenshots reach Designer without a hand session.
@MainActor
public enum UIRenderer {
    public enum Appearance: String, CaseIterable, Sendable {
        case light
        case dark

        var nsAppearance: NSAppearance {
            NSAppearance(named: self == .light ? .aqua : .darkAqua)!
        }
    }

    public struct Rendered: Sendable, Hashable {
        public var url: URL
        /// Pixel size of the PNG.
        public var pixelWidth: Int
        public var pixelHeight: Int
    }

    public static let scale: CGFloat = 2

    @discardableResult
    public static func render(_ request: RenderUIRequest) throws -> [Rendered] {
        switch request {
        case .shipping(let out): try renderAll(to: out)
        case .size13(let out): try Size13Renderer.render(to: out)
        }
    }

    /// Renders every surface into `folder` (created when missing) and returns the files written, in order.
    @discardableResult
    public static func renderAll(to folder: URL) throws -> [Rendered] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let thumbnail = SampleFrame.image()
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("skreenrek-preview-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        // Claude Code and Codex found, Cursor not installed: every agent row form shows.
        for agent in [".claude", ".codex"] {
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent(agent), withIntermediateDirectories: true)
        }
        var written: [Rendered] = []
        for appearance in Appearance.allCases {
            func save(_ view: NSView, _ surface: String, _ state: String, active: Bool = false) throws {
                let name = "\(surface)-\(state)-\(appearance.rawValue)@2x.png"
                written.append(
                    try write(view, appearance: appearance, active: active, to: folder.appendingPathComponent(name)))
            }
            for sample in RenderSamples.states {
                try save(menuBarIcon(sample.context), "menubaricon", sample.name)
                try save(dropdown(sample.context, thumbnail: thumbnail), "dropdown", sample.name, active: true)
            }
            for panel in specPanels(preview: thumbnail ?? swatch(width: 320, height: 200)) {
                try save(panel.view, "panel", panel.name, active: true)
            }
            let base = RenderSamples.armed.context
            try save(
                DropdownPreview(
                    MenuModel.sizeSubmenu(
                        base.sizeChoice, display: RenderSamples.display, window: base.snapshot.window
                    ).entries, width: MenuMetrics.sizeSubmenuWidth), "submenu", "size")
            try save(DropdownPreview(MenuModel.frameRateSubmenu(base.snapshot.fps).entries), "submenu", "framerate")
            for sample in settingsSamples {
                try save(settingsView(sample, home: home), "settings", sample.name, active: true)
            }
            try save(selectionOutline(increaseContrast: false), "screen", "outline")
            try save(selectionOutline(increaseContrast: true), "screen", "outline-contrast")
            try save(host(PickerLabel(title: RenderSamples.clipTitle, detail: UIStrings.Picker.detail(RenderSamples.size)),
                          size: NSSize(width: 280, height: 56)), "picker", "label")
            try save(host(PickerHint(), size: NSSize(width: 640, height: 44)), "picker", "hint")
            for state in ["window", "keyboard", "region", "window-contrast", "region-contrast", "empty"] {
                let canvas = PickerCanvas(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
                canvas.increaseContrast = state.hasSuffix("contrast")
                var display = RenderSamples.display
                display.visibleFrame = PointRect(x: 0, y: 0, width: 800, height: 600)
                canvas.display = display
                var model = PickerModel(windows: [RenderSamples.safari], displays: [display], ownPid: -1)
                if state == "keyboard" { model.move() }
                else if state != "empty" { model.hover(CGPoint(x: 200, y: 200)) }
                if state.hasPrefix("region") { model.beginDrag(CGPoint(x: 100, y: 100)); model.drag(to: CGPoint(x: 500, y: 400)) }
                canvas.update(model, pointer: CGPoint(x: 500, y: 400))
                try save(canvas, "picker", state)
            }
            for sample in CaptureRenderSamples.hudStates {
                let view = NSHostingView(rootView: RecordingHUDView(presentation: HUDPresentation(state: sample.state,
                    reduceMotion: sample.name == "writing-reducedmotion", increaseContrast: sample.name == "recording-contrast")))
                view.frame = NSRect(origin: .zero, size: view.fittingSize)
                try save(view, "hud", sample.name)
            }
            for contrast in [false, true] {
                try save(host(RegionOutline(increaseContrast: contrast), size: NSSize(width: 320, height: 200)),
                         "hud", contrast ? "regionoutline-contrast" : "regionoutline")
            }
            for sample in CaptureRenderSamples.onboardingStates {
                let name = "skreenrek.render-onboarding.\(UUID().uuidString)"
                let defaults = UserDefaults(suiteName: name)!
                defer { defaults.removePersistentDomain(forName: name) }
                let model = OnboardingModel.preview(sample, defaults: defaults)
                try save(host(OnboardingView(model: model), size: OnboardingView.size), "onboarding", sample.name)
            }
        }
        return written
    }

    static func host<V: View>(_ view: V, size: NSSize) -> NSView {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        return hosting
    }

    /// The status item as the menu bar draws it: the V1 glyph (mono, or bichrome with the red dot while recording)
    /// and the elapsed time.
    static func menuBarIcon(_ context: MenuContext) -> NSView {
        let icon = StatusIconModel.icon(for: context)
        return BrandStatusGlyphView(
            state: BrandStatusGlyph.state(for: context.displayState), style: icon.tinted ? .bichrome : .mono,
            elapsed: icon.elapsed, sentence: icon.sentence)
    }

    /// The menu panel for `context`. The file names stay `dropdown-…`: this is the shipping menu.
    static func dropdown(_ context: MenuContext, thumbnail: NSImage?) -> NSView {
        panel(
            PanelModel.content(
                for: context, preview: PanelModel.illustratedPhase(for: context), clipFileExists: true,
                closedTitle: context.lastClipTitle ?? context.targetTitle),
            preview: thumbnail, clip: thumbnail)
    }

    /// The spec's panel states, one file each. The 1.0.5 names (`nowindow`, `picked`, `recording`, `clear-hover`,
    /// `window-closed`) use the spec's samples, so their heights are the ones in its `sizes.json`.
    static func specPanels(preview: NSImage) -> [(name: String, view: NSView)] {
        let idle = specArmed(update: "1.0.4")
        let idleContent = PanelModel.content(for: idle, preview: readyStill)
        let picked = PanelModel.content(for: specArmed(update: nil), preview: readyStill)
        return [
            ("idle", panel(idleContent, preview: preview, clip: preview)),
            ("picked", panel(picked, preview: preview, clip: preview)),
            ("clear-hover", panel(picked, preview: preview, clip: preview, clearHover: true)),
            ("recording", panel(
                PanelModel.content(for: specRecording(), preview: readyStill), preview: preview, clip: nil)),
            ("nowindow", panel(
                PanelModel.content(for: specNoWindow(), preview: .noWindow), preview: nil, clip: nil)),
            ("loading", panel(PanelModel.content(for: idle, preview: .loading), preview: nil, clip: preview)),
            ("loading-slow", panel(
                PanelModel.content(for: idle, preview: .loading, showSpinner: true), preview: nil, clip: preview)),
            ("capture-failed", panel(PanelModel.content(for: idle, preview: .failed), preview: nil, clip: preview)),
            ("permission-missing", panel(
                PanelModel.content(for: idle, preview: .permissionMissing(.screenRecording)), preview: nil, clip: preview)),
            ("window-closed", panel(
                PanelModel.content(
                    for: specClosed(), preview: .windowClosed(nil), closedTitle: RenderSamples.clipTitle),
                preview: nil, clip: nil)),
            ("aspect-16x10", panel(idleContent, preview: swatch(width: 320, height: 200), clip: preview)),
            ("aspect-21x9", panel(idleContent, preview: swatch(width: 420, height: 180), clip: preview)),
            ("aspect-9x16", panel(idleContent, preview: swatch(width: 180, height: 320), clip: preview)),
        ]
    }

    private static var readyStill: PanelPreviewPhase {
        .ready(WindowStill(png: Data(), pixelWidth: 320, pixelHeight: 180))
    }

    /// Armed at 1080p with a last clip: 591.5 pt, or the 619.5 pt idle panel with an update.
    private static func specArmed(update: String?) -> MenuContext {
        var context = RenderSamples.armed.context
        let size = SizePreset.p1080.size
        context.sizeChoice = .size(size)
        context.snapshot.size = size
        context.updateAvailable = update
        if var clip = context.snapshot.lastClip {
            clip.recording.width = size.width
            clip.recording.height = size.height
            context.snapshot.lastClip = clip
        }
        return context
    }

    private static func specRecording() -> MenuContext {
        var context = RenderSamples.states.first { $0.name == "recording" }?.context ?? RenderSamples.armed.context
        context.snapshot.size = SizePreset.p1080.size
        return context
    }

    private static func specNoWindow() -> MenuContext {
        var context = RenderSamples.idle.context
        context.sizeChoice = .size(SizePreset.p1080.size)
        return context
    }

    private static func specClosed() -> MenuContext {
        var context = specNoWindow()
        context.snapshot.error = .recordingFailed(.windowClosed(at: 31))
        return context
    }

    /// A solid image of `width` by `height` points, so a render can show letterboxing.
    static func swatch(width: Int, height: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        return image
    }

    /// The panel at its content height, 300 pt wide, opaque so the render has a background.
    static func panel(_ content: PanelContent, preview: NSImage?, clip: NSImage?, clearHover: Bool = false) -> NSView {
        let height = min(PanelMetrics.contentHeight(content), PanelMetrics.availableHeight())
        let root = MenuPanelView(
            content: content, maxHeight: PanelMetrics.availableHeight(), previewImage: preview, clipImage: clip,
            reduceMotion: true, showsMaterial: false, showsClearHover: clearHover, onAction: { _ in })
            .environment(\.controlActiveState, .key)
            .environment(\.drawsActiveControls, true)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = NSRect(x: 0, y: 0, width: PanelMetrics.width, height: height)
        return hosting
    }

    /// One Settings render: a tab, its permission state, and the release the Updates row last saw.
    struct SettingsSample {
        var name: String
        var tab: SettingsTab
        var screenRecording: PermissionStatus = .allowed
        var accessibility: PermissionStatus = .allowed
        var latest = SkreenrekVersion.current
    }

    static let settingsSamples = [
        SettingsSample(name: "default", tab: .general),
        SettingsSample(name: "general", tab: .general),
        SettingsSample(name: "updateavailable", tab: .general, latest: RenderSamples.newerVersion),
        SettingsSample(name: "agents", tab: .agents),
        SettingsSample(name: "permissions", tab: .permissions),
        SettingsSample(
            name: "permissions-notallowed", tab: .permissions, screenRecording: .missing, accessibility: .missing),
    ]

    /// A Settings tab under a drawn stand-in for the window's toolbar, which an offscreen render can't show.
    static func settingsView(_ sample: SettingsSample, home: URL) -> NSView {
        let defaults = UserDefaults(suiteName: "skreenrek.render-ui.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults, home: URL(fileURLWithPath: "/Users/you", isDirectory: true))
        store.outputFolder = URL(fileURLWithPath: "/Users/you/Movies/Skreenrek", isDirectory: true)
        defaults.set(sample.latest, forKey: UpdateChecker.Key.latestVersion)
        let updates = UpdateChecker(
            feed: StaticReleaseFeed(), installer: StaticReleaseFeed(), method: .homebrew, defaults: defaults,
            openURL: { _ in }, relaunch: {})
        let panel = SettingsPanelState(
            permissions: StaticPermissions(
                screenRecording: sample.screenRecording, accessibility: sample.accessibility),
            loginItem: StaticLoginItem(),
            agents: AgentsPanelState(
                installer: AgentInstaller(home: home, executablePath: "/unused/skreenrek", path: "")),
            updates: updates)
        return RefitHostingView.fitted(
            VStack(spacing: 0) {
                SettingsToolbarPreview(selected: sample.tab)
                SettingsView(tab: sample.tab, store: store, panel: panel, actions: .none)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.controlActiveState, .key)
            .environment(\.drawsActiveControls, true))
    }

    /// The on-screen outline around a sample window on a plain desktop.
    static func selectionOutline(increaseContrast: Bool) -> NSView {
        var window = RenderSamples.safari
        window.frame = PointRect(x: 48, y: 48, width: 640, height: 400)
        var model = SelectionOutlineModel(macOSMajorVersion: 26)
        model.update(
            SelectionOutlineInput(
                target: SelectionOutlineTarget(window: window), panelOpen: true, increaseContrast: increaseContrast),
            now: 0)
        let view = SelectionOutlineSampleView(frame: NSRect(x: 0, y: 0, width: 736, height: 496))
        view.sampleFrame = window.frame.cgRect
        view.outline.appearanceModel = model.display(at: 0).appearance
        if let frame = view.outline.appearanceModel?.frame { view.outline.frame = frame.cgRect }
        return view
    }

    /// Draws `view` at 2× with the appearance forced and writes a PNG.
    /// `active` draws controls as in the key window (accent switches and default buttons); the shipping renders
    /// keep the inactive look they've always had.
    static func write(_ view: NSView, appearance: Appearance, active: Bool = false, to url: URL) throws -> Rendered {
        let data = try png(view, appearance: appearance, active: active)
        try data.write(to: url, options: .atomic)
        let size = view.bounds.size
        return Rendered(url: url, pixelWidth: Int(size.width * scale), pixelHeight: Int(size.height * scale))
    }

    static func png(_ view: NSView, appearance: Appearance, active: Bool = false) throws -> Data {
        view.appearance = appearance.nsAppearance
        // An offscreen window gives SwiftUI and the text fields a real layout pass and backing.
        let windowClass: NSWindow.Type = active ? ActiveRenderWindow.self : NSWindow.self
        let window = windowClass.init(
            contentRect: NSRect(origin: .zero, size: view.bounds.size), styleMask: .borderless, backing: .buffered,
            defer: false)
        window.appearance = appearance.nsAppearance
        window.backgroundColor = .clear
        window.isOpaque = false
        let container = NSView(frame: NSRect(origin: .zero, size: view.bounds.size))
        window.contentView = container
        container.addSubview(view)
        view.frame.origin = .zero
        view.layoutSubtreeIfNeeded()
        if view is any RenderRefitting {
            let size = view.fittingSize
            view.frame = NSRect(origin: .zero, size: size)
            window.setContentSize(size)
            container.frame = NSRect(origin: .zero, size: size)
            view.layoutSubtreeIfNeeded()
        }
        view.displayIfNeeded()

        let size = view.bounds.size
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)
        else { throw RenderError.bitmap }
        rep.size = size
        appearance.nsAppearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: rep)
        }
        container.subviews.forEach { $0.removeFromSuperview() }
        window.contentView = nil
        guard let data = rep.representation(using: .png, properties: [:]) else { throw RenderError.png }
        return data
    }

    enum RenderError: Error, CustomStringConvertible {
        case bitmap
        case png

        var description: String {
            switch self {
            case .bitmap: "Couldn't make a bitmap to render into."
            case .png: "Couldn't encode the PNG."
            }
        }
    }
}

/// An offscreen window that reports itself as key, so controls draw in their active state. Never ordered in.
final class ActiveRenderWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

// MARK: - Sample states

/// The states `render-ui` draws, with Designer's sample values (Safari, localhost:3000, 1280 × 800 px).
public enum RenderSamples {
    public struct Sample: Sendable {
        public var name: String
        public var context: MenuContext
    }

    static let display = DisplayInfo(
        id: 1, name: "Built-in Retina Display", scale: 2, frame: PointRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: PointRect(x: 0, y: 33, width: 1512, height: 949))
    static let safari = WindowInfo(
        id: WindowID(4127), app: "Safari", bundleId: "com.apple.Safari", title: "localhost:3000", pid: 812,
        frame: PointRect(x: 120, y: 80, width: 640, height: 400), displayId: 1, onScreen: true)
    static let size = PixelSize(width: 1280, height: 800)

    static func readback(actual: PixelSize) -> Readback {
        Readback(
            window: Readback.Window(safari), display: Readback.Display(display), requested: size, actual: actual,
            frame: PointRect(x: 120, y: 80, width: Double(actual.width) / 2, height: Double(actual.height) / 2),
            exact: actual == size, attempts: actual == size ? 1 : 3)
    }

    public static func clip(codec: VideoCodec = .h264, file: String = "clip.mp4") -> StopBody {
        let folder = "/Users/you/Movies/Skreenrek/2026-11-17_104207_safari"
        return StopBody(
            recording: StopBody.Recording(
                id: "2026-11-17_104207_safari", duration: 42.0, fps: 60, width: 1280, height: 800, codec: codec,
                startedAt: "2026-11-17T10:24:07.120+01:00", startedBy: .mcp,
                stats: RecordingStats(slotsWritten: 2520, framesFresh: 2400, encoder: .hardware),
                video: VideoReadback(file: file, width: 1280, height: 800, scale: 2, codec: codec,
                    container: file.hasSuffix(".mov") ? .mov : .mp4)),
            files: StopBody.Files(
                clip: "\(folder)/\(file)", events: "\(folder)/events.json", snippet: "\(folder)/hyperframes.html"),
            snippet: "<video class=\"clip\"></video>", readback: readback(actual: size))
    }

    static func context(
        _ snapshot: ControllerSnapshot, actionError: SkreenrekError? = nil, title: String? = nil,
        sizeChoice: SizeChoice = .size(size), permissionsMissing: Bool = false, updateAvailable: String? = nil
    ) -> MenuContext {
        MenuContext(
            snapshot: snapshot, actionError: actionError, lastClipTitle: title, sizeChoice: sizeChoice,
            permissionsMissing: permissionsMissing, updateAvailable: updateAvailable,
            timeZone: TimeZone(identifier: "Europe/Paris")!, locale: Locale(identifier: "en_GB"))
    }

    static let clipTitle = "Safari — localhost:3000"
    /// The newer release the update renders show.
    public static let newerVersion = "1.0.3"

    public static let idle = Sample(name: "idle", context: context(ControllerSnapshot(state: .idle, fps: .fps60)))
    public static let armed = Sample(
        name: "armed",
        context: context(
            ControllerSnapshot(
                state: .armed, window: safari, displayId: 1, size: size, readback: readback(actual: size),
                fps: .fps60, lastClip: clip()),
            title: clipTitle))

    public static let states: [Sample] = [
        idle,
        Sample(
            name: "lastclip",
            context: context(ControllerSnapshot(state: .idle, fps: .fps60, lastClip: clip()), title: clipTitle)),
        Sample(
            name: "lastclipmov",
            context: context(
                ControllerSnapshot(state: .idle, fps: .fps60, lastClip: clip(file: "clip.mov")), title: clipTitle)),
        Sample(
            name: "lastclipprores",
            context: context(
                ControllerSnapshot(state: .idle, fps: .fps60, lastClip: clip(codec: .prores, file: "clip.mov")), title: clipTitle)),
        armed,
        Sample(
            name: "armednotexact",
            context: context(
                ControllerSnapshot(
                    state: .armed, window: safari, displayId: 1, size: PixelSize(width: 1286, height: 800),
                    readback: readback(actual: PixelSize(width: 1286, height: 800)), fps: .fps60))),
        Sample(
            name: "updateavailable",
            context: context(
                ControllerSnapshot(
                    state: .armed, window: safari, displayId: 1, size: size, readback: readback(actual: size),
                    fps: .fps60),
                updateAvailable: newerVersion)),
        Sample(
            name: "permissionsneeded",
            context: context(ControllerSnapshot(state: .idle, fps: .fps60), permissionsMissing: true)),
        Sample(
            name: "recording",
            context: context(
                ControllerSnapshot(
                    state: .recording, elapsed: 12.4, window: safari, displayId: 1, size: size, fps: .fps60,
                    startedBy: .mcp, client: "Claude Code"))),
        Sample(
            name: "writing",
            context: context(
                ControllerSnapshot(
                    state: .writing, elapsed: 42, window: safari, displayId: 1, size: size, fps: .fps60,
                    startedBy: .menu))),
        Sample(
            name: "errorwindowclosed",
            context: context(
                ControllerSnapshot(
                    state: .error, fps: .fps60, lastClip: clip(),
                    error: .recordingFailed(.windowClosed(at: 31))), title: clipTitle)),
        Sample(
            name: "errorscreenrecording",
            context: context(
                ControllerSnapshot(state: .idle, fps: .fps60), actionError: .permissionDenied(.screenRecording))),
        Sample(
            name: "errordirectcapture",
            context: context(
                ControllerSnapshot(state: .idle, fps: .fps60), actionError: .permissionDenied(.directCapture))),
        Sample(
            name: "erroraccessibility",
            context: context(
                ControllerSnapshot(state: .armed, window: safari, displayId: 1, size: size, fps: .fps60),
                actionError: .permissionDenied(.accessibility))),
        Sample(
            name: "errornotexact",
            context: context(
                ControllerSnapshot(state: .armed, window: safari, displayId: 1, size: size, fps: .fps60),
                actionError: .notExact(
                    app: "Safari", requested: size, actual: PixelSize(width: 1286, height: 800),
                    reason: .minWidth(1286)))),
        Sample(
            name: "errordisklow",
            context: context(
                ControllerSnapshot(
                    state: .error, fps: .fps60, lastClip: clip(), error: .recordingFailed(.diskLow(at: 252))),
                title: clipTitle)),
        Sample(
            name: "errorwritefailed",
            context: context(
                ControllerSnapshot(state: .error, fps: .fps60, error: .recordingFailed(.notWritable)))),
    ]
}

/// Fixed permission state for previews.
struct StaticPermissions: PermissionProbe {
    var screenRecording: PermissionStatus
    var directCapture: PermissionStatus = .allowed
    var accessibility: PermissionStatus
}

extension OnboardingModel {
    /// A sample's model for renders and layout tests: nothing reaches the system.
    static func preview(_ sample: CaptureRenderSamples.OnboardingSample, defaults: UserDefaults) -> OnboardingModel {
        defaults.set(sample.completed, forKey: completedKey)
        let model = OnboardingModel(
            permissions: StaticPermissions(
                screenRecording: sample.screen, directCapture: sample.direct, accessibility: sample.accessibility),
            requester: PreviewPermissionRequester(), defaults: defaults,
            agents: AgentClient.allCases.map { OnboardingAgent(agent: $0, detected: $0 != .cursor) },
            install: { _ in [] })
        for permission in sample.requested { model.request(permission) }
        model.preview(sample.step)
        return model
    }
}

/// A release feed and installer for previews: the renders never check or install, so neither is called.
struct StaticReleaseFeed: ReleaseFeed, UpdateInstaller {
    struct NotUsed: Error {}
    func latestRelease() async throws -> ReleaseInfo { throw NotUsed() }
    func upgrade(progress: @escaping @Sendable (String) -> Void) async throws { throw NotUsed() }
}

/// An Open at login stand-in for previews: off, and never touches the system.
@MainActor
final class StaticLoginItem: LoginItemService {
    var isEnabled = false
    func setEnabled(_ enabled: Bool) throws { isEnabled = enabled }
}

// MARK: - Preview views

/// The window toolbar as the Settings renders show it: the title over the three tabs.
private struct SettingsToolbarPreview: View {
    let selected: SettingsTab

    var body: some View {
        VStack(spacing: 6) {
            Text(selected.title).font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    VStack(spacing: 2) {
                        Image(systemName: tab.symbol).font(.system(size: 16))
                        Text(tab.title).font(.system(size: 11))
                    }
                    .foregroundStyle(tab == selected ? Color.accentColor : Color.secondary)
                    .frame(width: 76, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: PanelMetrics.radiusControl, style: .continuous)
                            .fill(tab == selected ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear)))
                }
            }
        }
        .frame(width: SettingsMetrics.width, height: 80)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// A sample window on a plain desktop, with the real outline view around it.
final class SelectionOutlineSampleView: NSView {
    let outline = SelectionOutlineView()
    var sampleFrame = CGRect.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(outline)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.blended(withFraction: 0.5, of: .systemBlue)?.setFill()
        bounds.fill()
        let radius = SelectionOutlineModel.windowCornerRadius(macOSMajorVersion: 26)
        NSColor.textBackgroundColor.setFill()
        NSBezierPath(roundedRect: sampleFrame, xRadius: radius, yRadius: radius).fill()
    }
}

/// A composed submenu (Size, Frame Rate): the same entries the `NSMenu` shows, laid out with the design spec's metrics
/// on the menu material's colours (an offscreen `NSMenu` can't be drawn).
final class DropdownPreview: NSView {
    /// The rows in order, with the entry each one draws.
    private(set) var rows: [(entry: MenuEntry, view: NSView)] = []

    init(_ entries: [MenuEntry], width: CGFloat = MenuMetrics.width) {
        let rows = entries.map { Self.view($0, width: width) }
        let height = rows.reduce(MenuMetrics.verticalInset * 2) { $0 + $1.frame.height }
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        self.rows = Array(zip(entries, rows)).map { (entry: $0.0, view: $0.1) }
        var y = MenuMetrics.verticalInset
        for row in rows {
            row.frame.origin = NSPoint(x: 0, y: y)
            addSubview(row)
            y += row.frame.height
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: MenuMetrics.cornerRadius,
            yRadius: MenuMetrics.cornerRadius)
        Self.menuBackground.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    /// The menu material's tone in each appearance.
    static var menuBackground: NSColor { BrandTheme.menuBackgroundColor }

    static func view(_ entry: MenuEntry, width: CGFloat = MenuMetrics.width) -> NSView {
        let view: NSView =
            switch entry {
            case .status(let row): MenuItemPreview(item: MenuItemModel(row.title, action: nil))
            case .separator: SeparatorPreview()
            case .header(let title): MenuItemPreview(header: title)
            case .item(let item): MenuItemPreview(item: item)
            case .submenu(let submenu): MenuItemPreview(submenu: submenu)
            }
        view.frame.size.width = width
        return view
    }
}

final class SeparatorPreview: NSView {
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuMetrics.width, height: MenuMetrics.separatorHeight))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(
            x: MenuMetrics.trailingPadding, y: floor(bounds.midY),
            width: bounds.width - MenuMetrics.trailingPadding * 2,
            height: 1
        ).fill()
    }
}

/// One 24 pt row: checkmark column, 13 pt title at 32 pt, then a shortcut, a detail or a submenu chevron.
final class MenuItemPreview: NSView {
    private var title = ""
    private var titleFont = MenuMetrics.titleFont
    private var titleColor = NSColor.labelColor
    private var checked = false
    private var trailing: String?
    private var trailingFont = MenuMetrics.titleFont
    private var trailingColor = NSColor.secondaryLabelColor
    private var chevron = false

    init(item: MenuItemModel) {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuMetrics.width, height: MenuMetrics.rowHeight))
        title = item.title
        titleColor = item.enabled ? .labelColor : .tertiaryLabelColor
        checked = item.checked
        trailing = item.shortcut?.display
        if let value = item.trailing {
            // A Size preset's clip px: 12 pt secondary, dimmed with the row.
            trailing = value
            trailingFont = MenuMetrics.detailFont
            trailingColor = item.enabled ? .secondaryLabelColor : .quaternaryLabelColor
        }
        toolTip = item.toolTip
    }

    init(submenu: SubmenuModel) {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuMetrics.width, height: MenuMetrics.rowHeight))
        title = submenu.title
        trailing = submenu.detail
        chevron = true
    }

    init(header: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuMetrics.width, height: MenuMetrics.rowHeight))
        title = header
        titleFont = MenuMetrics.headerFont
        titleColor = .secondaryLabelColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: titleColor]
        let size = (title as NSString).size(withAttributes: attributes)
        let y = (bounds.height - size.height) / 2
        if checked {
            let rect = NSRect(
                x: MenuMetrics.symbolX + 2, y: (bounds.height - 12) / 2, width: 12, height: 12)
            MenuMetrics.symbol("checkmark", pointSize: 12, color: titleColor)?.draw(in: rect)
        }
        var right = bounds.width - MenuMetrics.trailingPadding
        if chevron {
            let rect = NSRect(x: right - 8, y: (bounds.height - 12) / 2, width: 8, height: 12)
            MenuMetrics.symbol("chevron.right", pointSize: 11, color: .secondaryLabelColor)?.draw(in: rect)
            right -= 16
        }
        if let trailing {
            let trailingAttributes: [NSAttributedString.Key: Any] = [
                .font: trailingFont, .foregroundColor: trailingColor,
            ]
            let size = (trailing as NSString).size(withAttributes: trailingAttributes)
            (trailing as NSString).draw(
                at: NSPoint(x: right - size.width, y: (bounds.height - size.height) / 2),
                withAttributes: trailingAttributes)
        }
        (title as NSString).draw(at: NSPoint(x: MenuMetrics.textX, y: y), withAttributes: attributes)
    }
}

/// A hosting view the offscreen render re-measures once it sits in a window (grouped forms and wrapping text only
/// settle there).
protocol RenderRefitting: NSView {}

final class RefitHostingView<Content: View>: NSHostingView<Content>, RenderRefitting {}
