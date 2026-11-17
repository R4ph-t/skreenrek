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

    public func askCustomSize(current: PixelSize?, display: DisplayInfo?) async -> PixelSize? {
        sizePanel?.close()
        return await withCheckedContinuation { continuation in
            // Borderless, so the SwiftUI content draws the panel's 10 pt radius itself.
            let panel = KeyPanel(
                contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.title = UIStrings.CustomSize.title
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            var finished = false
            let finish: (PixelSize?) -> Void = { [weak self, weak panel] size in
                guard !finished else { return }
                finished = true
                panel?.close()
                self?.sizePanel = nil
                continuation.resume(returning: size)
            }
            let hosting = NSHostingView(
                rootView: CustomSizeView(model: CustomSizeModel(current: current, display: display), finish: finish))
            hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
            panel.contentView = hosting
            panel.setContentSize(hosting.fittingSize)
            let close = PanelCloseObserver(panel: panel) { finish(nil) }
            objc_setAssociatedObject(panel, &PanelCloseObserver.key, close, .OBJC_ASSOCIATION_RETAIN)
            panel.center()
            sizePanel = panel
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// The main display's scale and visible size. Only sizes matter for `WindowFit`, so the frames start at 0, 0.
    public func mainDisplay() -> DisplayInfo? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return DisplayInfo(
            id: number?.uint32Value ?? 0, name: screen.localizedName, scale: Double(screen.backingScaleFactor),
            frame: PointRect(x: 0, y: 0, width: screen.frame.width, height: screen.frame.height),
            visibleFrame: PointRect(x: 0, y: 0, width: screen.visibleFrame.width, height: screen.visibleFrame.height))
    }

    public func quit() {
        NSApp.terminate(nil)
    }
}

/// A borderless panel that still takes the keyboard (for the Custom Size fields).
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
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
