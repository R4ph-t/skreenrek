import Carbon.HIToolbox
import Foundation
import os

/// The global ⌃⌘⎋ stop shortcut: a Carbon hot key (no Accessibility needed), registered only while a recording runs so
/// it never shadows macOS's own ⌃⌘⎋ at other times. If registration fails, the menu item still works and the failure
/// is logged.
@MainActor
final class StopHotKey {
    private static let log = Logger(subsystem: "it.fraime.skreenrek", category: "hotkey")
    /// `SKRK`.
    private static let signature: OSType = 0x534B_524B

    var onPress: (@MainActor () -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    var isRegistered: Bool { hotKey != nil }

    func register() {
        guard hotKey == nil else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(
                GetApplicationEventTarget(), stopHotKeyCallback, 1, &spec, Unmanaged.passUnretained(self).toOpaque(),
                &handler)
            guard status == noErr else {
                Self.log.error("Couldn't install the stop shortcut handler (\(status, privacy: .public)).")
                return
            }
        }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            UInt32(kVK_Escape), UInt32(controlKey | cmdKey), id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            Self.log.error("Couldn't register the ⌃⌘⎋ stop shortcut (\(status, privacy: .public)); the menu still stops.")
            return
        }
        hotKey = ref
    }

    func unregister() {
        guard let hotKey else { return }
        UnregisterEventHotKey(hotKey)
        self.hotKey = nil
    }

    fileprivate func pressed() {
        onPress?()
    }
}

/// Carbon calls this on the main thread for every hot key press of the app.
private func stopHotKeyCallback(
    _ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let box = UInt(bitPattern: userData)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: box) else { return }
        Unmanaged<StopHotKey>.fromOpaque(pointer).takeUnretainedValue().pressed()
    }
    return noErr
}
