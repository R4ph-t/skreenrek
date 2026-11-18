import AppKit
import SkreenrekCore
import SwiftUI

/// The bar's `render-ui` cases: `control-bar-<name>-<light|dark>@2x.png`. Placement cases show the real layout against
/// a stand-in window on a stand-in screen. State cases show the bar alone on a plain backdrop.
@MainActor
enum ControlBarRenderer {
    static let sceneSize = NSSize(width: 1100, height: 760)
    static let plateSize = NSSize(width: 380, height: 96)
    /// Large enough for 1080p, too small for 1440p and 4K, so the menu shows both kinds of preset.
    static let display = DisplayInfo(
        id: 1, name: "Built-in Retina Display", scale: 2, frame: PointRect(x: 0, y: 0, width: 1100, height: 760),
        visibleFrame: PointRect(x: 0, y: 24, width: 1100, height: 700))
    static let p1080 = SizeChoice.size(SizePreset.p1080.size)

    private static let standardWindow = PointRect(x: 70, y: 60, width: 960, height: 540)
    private static let lowWindow = PointRect(x: 70, y: 170, width: 960, height: 540)
    private static let fullHeightWindow = PointRect(x: 70, y: 24, width: 960, height: 700)
    private static let narrowWindow = PointRect(x: 420, y: 120, width: 260, height: 400)
    /// High enough on the screen for the menu to open below the button.
    private static let menuWindow = PointRect(x: 230, y: 60, width: 640, height: 360)

    static func samples() -> [(name: String, view: NSView)] {
        var cases: [(name: String, view: NSView)] = [
            ("below", scene(window: standardWindow)),
            ("above", scene(window: lowWindow)),
            ("docked", scene(window: fullHeightWindow)),
            ("narrow", scene(window: narrowWindow, choice: .keepCurrent)),
            ("size-menu", sizeMenu()),
        ]
        cases += [
            ("recording", plate(activity: .recording(seconds: 12))),
            ("saving", plate(activity: .saving)),
            ("saving-reducedmotion", plate(activity: .saving, reduceMotion: true)),
            ("disabled", plate(permissions: ControlBarPermissions(screenRecording: .missing))),
            ("disabled-size", plate(permissions: ControlBarPermissions(accessibility: .missing))),
            ("custom", plate(choice: .keepCurrent)),
            ("resizing", plate(resizingTo: SizePreset.p720.size)),
            ("not-exact", plate(readback: notExactReadback)),
            ("refused", plate(refusedFrom: SizePreset.p720.size)),
        ]
        return cases
    }

    private static var notExactReadback: Readback {
        let requested = SizePreset.p1080.size
        return Readback(
            window: Readback.Window(RenderSamples.safari), display: Readback.Display(display), requested: requested,
            actual: PixelSize(width: 1926, height: 1080), frame: standardWindow, exact: false, attempts: 3)
    }

    private static func model(
        window: PointRect, choice: SizeChoice = p1080, activity: ControlBarActivity = .idle,
        permissions: ControlBarPermissions = ControlBarPermissions(), readback: Readback? = nil,
        reduceMotion: Bool = false
    ) -> ControlBarModel {
        var info = RenderSamples.safari
        info.frame = window
        var model = ControlBarModel()
        model.update(displays: [display])
        model.update(permissions: permissions)
        model.update(presence: .onScreen(window))
        model.update(
            ControlBarInput(
                target: SelectionOutlineTarget(window: info), activity: activity, sizeChoice: choice,
                readback: readback, clipSize: SizePreset.p1080.size, reduceMotion: reduceMotion),
            now: 0)
        return model
    }

    private static func scene(window: PointRect, choice: SizeChoice = p1080) -> NSView {
        let view = UIRenderer.outlineSample(window: window, size: sceneSize, increaseContrast: false)
        if let display = model(window: window, choice: choice).display(at: 0) {
            addBar(display.content, frame: display.frame.cgRect, to: view)
        }
        return view
    }

    /// The bar with its menu open. An offscreen `NSMenu` can't be drawn, so the menu is the composed preview of the
    /// same entries, 4 pt under the button with its left edge aligned.
    private static func sizeMenu() -> NSView {
        let view = UIRenderer.outlineSample(window: menuWindow, size: sceneSize, increaseContrast: false)
        guard let display = model(window: menuWindow).display(at: 0),
            case .size(let control) = display.content.leading
        else { return view }
        addBar(display.content, frame: display.frame.cgRect, to: view, menuOpen: true)
        let menu = DropdownPreview(control.entries, width: MenuMetrics.sizeSubmenuWidth)
        let bar = display.frame.cgRect
        menu.frame.origin = NSPoint(
            x: bar.minX + ControlBarMetrics.padding,
            y: bar.minY + ControlBarMetrics.padding + ControlBarMetrics.controlHeight + 4)
        view.addSubview(menu)
        return view
    }

    private static func plate(
        choice: SizeChoice = p1080, activity: ControlBarActivity = .idle,
        permissions: ControlBarPermissions = ControlBarPermissions(), readback: Readback? = nil,
        reduceMotion: Bool = false
    ) -> NSView {
        let model = model(
            window: standardWindow, choice: choice, activity: activity, permissions: permissions,
            readback: readback, reduceMotion: reduceMotion)
        return plate(model)
    }

    /// 1080p on screen, 720p chosen, and the read-back still to come.
    private static func plate(resizingTo size: PixelSize) -> NSView {
        var model = model(window: standardWindow)
        var input = model.input
        input.sizeChoice = .size(size)
        input.resize = .resizing
        model.update(input, now: 0)
        return plate(model)
    }

    private static func plate(refusedFrom size: PixelSize) -> NSView {
        var model = model(window: standardWindow)
        var input = model.input
        input.sizeChoice = .size(size)
        input.resize = .resizing
        model.update(input, now: 0)
        input.sizeChoice = p1080
        input.resize = .refused(sequence: 1, reason: UIStrings.Errors.cantResizeDetail)
        model.update(input, now: 0)
        return plate(model)
    }

    private static func plate(_ model: ControlBarModel) -> NSView {
        let view = ControlBarPlateView(frame: NSRect(origin: .zero, size: plateSize))
        if let display = model.display(at: 0) {
            let frame = CGRect(
                x: (plateSize.width - display.frame.width) / 2, y: (plateSize.height - display.frame.height) / 2,
                width: display.frame.width, height: display.frame.height)
            addBar(display.content, frame: frame, to: view)
        }
        return view
    }

    /// The real shadow view and the real bar view, as the two windows stack them.
    static func addBar(_ content: ControlBarContent, frame: CGRect, to parent: NSView, menuOpen: Bool = false) {
        let margin = ControlBarShadowView.margin
        let shadow = ControlBarShadowView(frame: frame.insetBy(dx: -margin, dy: -margin))
        parent.addSubview(shadow)
        let presentation = ControlBarPresentation(content: content)
        presentation.showsMenuOpen = menuOpen
        let root = ControlBarView(presentation: presentation, onAction: { _ in })
            .environment(\.controlActiveState, .key)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = frame
        parent.addSubview(hosting)
    }
}

/// A plain backdrop for the bar's states.
final class ControlBarPlateView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.blended(withFraction: 0.5, of: .systemBlue)?.setFill()
        bounds.fill()
    }
}
