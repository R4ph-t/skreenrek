import AppKit
import SkreenrekCore
import SwiftUI

/// The real `UIEffects`: Finder, the pasteboard, alerts, the folder panel and the custom size panel. Thin: the
/// decisions live in `AppModel`.
@MainActor
public final class SystemEffects: UIEffects {
    /// Opens the Settings window.
    public var showSettings: () -> Void = {}
    private var sizePanel: NSPanel?

    public init() {}

    public func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    public func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    public func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    public func openSettings() {
        showSettings()
    }

    public func confirmDiscard() async -> Bool {
        let alert = Alerts.discard()
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    public func chooseFolder(current: URL) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = current
        panel.prompt = UIStrings.Settings.chooseFolderPrompt
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url : nil
    }

    public func askCustomSize(current: PixelSize?, scale: Double) async -> PixelSize? {
        sizePanel?.close()
        return await withCheckedContinuation { continuation in
            let panel = NSPanel(
                contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = UIStrings.CustomSize.title
            panel.titleVisibility = .hidden
            panel.isReleasedWhenClosed = false
            var finished = false
            let finish: (PixelSize?) -> Void = { [weak self, weak panel] size in
                guard !finished else { return }
                finished = true
                panel?.close()
                self?.sizePanel = nil
                continuation.resume(returning: size)
            }
            panel.contentView = NSHostingView(
                rootView: CustomSizeView(model: CustomSizeModel(current: current, scale: scale), finish: finish))
            let close = PanelCloseObserver(panel: panel) { finish(nil) }
            objc_setAssociatedObject(panel, &PanelCloseObserver.key, close, .OBJC_ASSOCIATION_RETAIN)
            panel.center()
            sizePanel = panel
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    public func scale(of display: DisplayID?) -> Double {
        let screens = NSScreen.screens
        if let display,
            let screen = screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display
            })
        {
            return Double(screen.backingScaleFactor)
        }
        return Double((NSScreen.main ?? screens.first)?.backingScaleFactor ?? 2)
    }

    public func quit() {
        NSApp.terminate(nil)
    }
}

/// Calls back once when the panel's close button closes it.
@MainActor
private final class PanelCloseObserver: NSObject {
    nonisolated(unsafe) static var key: UInt8 = 0
    private var token: (any NSObjectProtocol)?

    init(panel: NSPanel, onClose: @escaping @MainActor () -> Void) {
        super.init()
        token = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main
        ) { _ in
            MainActor.assumeIsolated { onClose() }
        }
    }
}

/// The native alerts, with the design spec's copy.
@MainActor
public enum Alerts {
    /// "Discard this recording?" [Cancel] [Discard] (destructive; Return doesn't discard).
    public static func discard() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = UIStrings.Alerts.discardTitle
        alert.informativeText = UIStrings.Alerts.discardMessage
        alert.alertStyle = .warning
        let discard = alert.addButton(withTitle: UIStrings.Alerts.discard)
        discard.hasDestructiveAction = true
        discard.keyEquivalent = ""
        let cancel = alert.addButton(withTitle: UIStrings.Alerts.cancel)
        cancel.keyEquivalent = "\u{1b}"
        return alert
    }

    /// "Stop and save the recording before quitting?" [Cancel] [Stop and Quit].
    public static func quitWhileRecording() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = UIStrings.Alerts.quitTitle
        alert.addButton(withTitle: UIStrings.Alerts.stopAndQuit)
        alert.addButton(withTitle: UIStrings.Alerts.cancel)
        return alert
    }
}
