import AppKit
import Testing

@testable import SkreenrekUI

/// The panel's event monitor sees every mouse-down. Reading `keyCode` on one raises and AppKit drops the click,
/// which broke opening the panel from the status item in 1.0.4.
@MainActor
@Suite struct MenuMonitorInputTests {
    private func mouse(_ type: NSEvent.EventType) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    @Test func leftMouseDownHasNoKeyCode() {
        let input = MenuController.monitorInput(mouse(.leftMouseDown))
        #expect(!input.isKeyDown)
        #expect(input.keyCode == nil, "\(String(describing: input.keyCode))")
    }

    @Test func rightMouseDownHasNoKeyCode() {
        let input = MenuController.monitorInput(mouse(.rightMouseDown))
        #expect(!input.isKeyDown)
        #expect(input.keyCode == nil, "\(String(describing: input.keyCode))")
    }

    @Test func escapeKeyDownReadsItsKeyCode() {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        let input = MenuController.monitorInput(event)
        #expect(input.isKeyDown)
        #expect(input.keyCode == 53, "\(String(describing: input.keyCode))")
    }
}
