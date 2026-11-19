import AppKit
import SkreenrekCore
import SwiftUI

/// `render-ui`'s drag-to-authorize helper: the bare 320 × 88 panel in each state, and the panel in place beside a
/// stand-in System Settings window (or in a screen's corner when docked), at the addendum's gap and offset.
@MainActor
enum DragHelperRenderer {
    /// A 1440 × 900 screen with a 25 pt menu bar.
    static let screen = DragHelperScreen(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))
    /// System Settings' window in CGWindowList coordinates: room on the right, only on the left, on neither side.
    static let settingsRight = CGRect(x: 120, y: 120, width: 680, height: 560)
    static let settingsLeft = CGRect(x: 740, y: 120, width: 680, height: 560)
    static let settingsWide = CGRect(x: 40, y: 60, width: 1360, height: 700)
    /// The stand-in window in the composites.
    static let standIn = CGSize(width: 480, height: 360)
    static let margin: CGFloat = 40
    /// Mid-slide: 0.6 s delay, then half of the 0.9 s slide.
    static let midLoopTime = DragHelperMetrics.loopDelay + DragHelperMetrics.slide / 2

    static func samples() -> [(name: String, view: NSView)] {
        let shown = state(settings: settingsRight)
        let mirrored = state(settings: settingsLeft)
        let docked = state(settings: settingsWide)
        var granted = shown
        granted.update(now: 0.1, window: .visible(settingsRight), screens: [screen], granted: true)
        let reduceMotion = state(settings: settingsRight, reduceMotion: true)
        return [
            ("default", panel(shown)),
            ("mirrored", panel(mirrored)),
            ("docked", panel(docked)),
            ("midloop", panel(shown, time: midLoopTime)),
            ("granted", panel(granted)),
            ("reducedmotion", panel(reduceMotion, time: midLoopTime)),
            ("accessibility", panel(state(settings: settingsRight, permission: .accessibility))),
            ("beside-default", beside(shown, mirrored: false)),
            ("beside-mirrored", beside(mirrored, mirrored: true)),
            ("beside-midloop", beside(shown, mirrored: false, time: midLoopTime)),
            ("beside-granted", beside(granted, mirrored: false)),
            ("beside-docked", dockedCorner(docked)),
        ]
    }

    /// Shown at 0 with System Settings at `settings` on `screen`.
    static func state(
        settings: CGRect, permission: Permission = .screenRecording, reduceMotion: Bool = false
    ) -> DragHelperState {
        var state = DragHelperState(permission: permission, now: 0, reduceMotion: reduceMotion)
        state.update(now: 0, window: .visible(settings), screens: [screen], granted: false)
        return state
    }

    static func content(_ state: DragHelperState, time: TimeInterval, shadow: HUDShadowSource) -> DragHelperView {
        let model = DragHelperViewModel(
            state: state, icon: BrandIcon.appIcon(size: DragHelperMetrics.iconSize), increaseContrast: false,
            bundleURL: nil)
        return DragHelperView(model: model, frozenTime: time, shadow: shadow)
    }

    /// The panel alone, exactly 320 × 88 (its window shadow belongs to the window server).
    static func panel(_ state: DragHelperState, time: TimeInterval = 0) -> NSView {
        UIRenderer.host(content(state, time: time, shadow: .window), size: DragHelperMetrics.size)
    }

    /// The panel 12 pt beside a stand-in System Settings window, its top 96 pt below the window's top.
    static func beside(_ state: DragHelperState, mirrored: Bool, time: TimeInterval = 0) -> NSView {
        let size = DragHelperMetrics.size
        let width = margin * 2 + standIn.width + DragHelperMetrics.gap + size.width
        let height = margin * 2 + standIn.height
        let windowX = mirrored ? margin + size.width + DragHelperMetrics.gap : margin
        let panelX = mirrored ? margin : margin + standIn.width + DragHelperMetrics.gap
        let view = ZStack(alignment: .topLeading) {
            Color(nsColor: .systemGray)
            SettingsStandIn(title: "System Settings (stand-in)")
                .frame(width: standIn.width, height: standIn.height)
                .offset(x: windowX, y: margin)
            content(state, time: time, shadow: .drawn)
                .offset(x: panelX, y: margin + DragHelperMetrics.topOffset)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        return UIRenderer.host(view, size: NSSize(width: width, height: height))
    }

    /// Docked: the bottom-right corner of a screen's visible frame, 16 pt in.
    static func dockedCorner(_ state: DragHelperState) -> NSView {
        let size = DragHelperMetrics.size
        let inset = DragHelperMetrics.screenInset
        let canvas = CGSize(width: 640, height: 280)
        let view = ZStack(alignment: .topLeading) {
            Color(nsColor: .systemGray)
            Text(verbatim: "Screen's visible frame, bottom-right corner (stand-in)")
                .font(.system(size: 12)).foregroundStyle(.white)
                .offset(x: 16, y: 16)
            content(state, time: 0, shadow: .drawn)
                .offset(x: canvas.width - inset - size.width, y: canvas.height - inset - size.height)
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
        return UIRenderer.host(view, size: NSSize(width: canvas.width, height: canvas.height))
    }
}

/// A plain neutral window standing in for System Settings, labelled as one.
private struct SettingsStandIn: View {
    let title: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(Color(nsColor: .windowBackgroundColor))
            shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            Text(verbatim: title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .padding(16)
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
                .offset(y: DragHelperMetrics.topOffset - 1)
        }
    }
}
