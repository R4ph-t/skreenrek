import CoreGraphics
import SkreenrekCore
@testable import SkreenrekUI
import Testing

@Suite struct PickerModelTests {
    @Test func frontmostHoverKeyboardAndExactCopy() {
        var back = RenderSamples.safari
        back.id = WindowID(99)
        back.app = "Xcode"
        var model = PickerModel(windows: [RenderSamples.safari, back], displays: [RenderSamples.display], ownPid: -1)
        model.hover(CGPoint(x: 200, y: 100))
        #expect(model.selection == .window(WindowID(4127)))
        #expect(model.title == "Safari — localhost:3000")
        #expect(model.detail == "1280 × 800 px · Click to pick")
        #expect(model.voiceOver == "Safari, localhost:3000, 1280 by 800 pixels. Press Return to pick.")
        model.move(); #expect(model.hovered?.id == back.id)
        model.move(); #expect(model.hovered?.id == WindowID(4127))
        model.move(forward: false); #expect(model.hovered?.id == back.id)
        model.hover(CGPoint(x: -10, y: -10)); #expect(model.selection == .cancelled)
    }

    @Test func exclusionsAndEmptyKeyboard() {
        var own = RenderSamples.safari; own.pid = 123
        var dock = RenderSamples.safari; dock.bundleId = "com.apple.dock"
        var menu = RenderSamples.safari; menu.layer = 25
        var hidden = RenderSamples.safari; hidden.onScreen = false
        var model = PickerModel(windows: [own, dock, menu, hidden], displays: [], ownPid: 123)
        #expect(model.windows.isEmpty)
        model.move(); #expect(model.selection == .cancelled)
    }

    @Test(arguments: [1.0, 2.0]) func regionIsDisplayLocalEvenClampedAndReversible(_ scale: Double) {
        var display = RenderSamples.display
        display.scale = scale
        display.frame = PointRect(x: -800, y: -400, width: 800, height: 600)
        var model = PickerModel(windows: [], displays: [display], ownPid: -1)
        model.beginDrag(CGPoint(x: -700, y: -300))
        model.drag(to: CGPoint(x: -598.5, y: -197.5))
        let region = model.region!
        #expect(region.width % 2 == 0 && region.height % 2 == 0)
        #expect(region.x == Int(100 * scale) && region.y == Int(100 * scale))
        #expect(model.selection == .region(region, displayId: display.id))
        model.beginDrag(CGPoint(x: -500, y: -100))
        model.drag(to: CGPoint(x: -900, y: -900))
        #expect(model.region?.x == 0 && model.region?.y == 0)
        #expect(model.region?.width == Int(300 * scale))
        #expect(model.regionFrame?.x == -800)
    }
}
