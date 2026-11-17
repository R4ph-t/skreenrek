import AppKit
import SkreenrekControl
import SkreenrekCore
import SwiftUI
import os

/// The Settings window: one pane hosting `SettingsView`.
@MainActor
final class SettingsWindowController {
    private let store: SettingsStore
    private let panel: SettingsPanelState
    private let actions: SettingsActions
    private var window: NSWindow?
    private var observer: (any NSObjectProtocol)?

    init(store: SettingsStore, panel: SettingsPanelState, actions: SettingsActions) {
        self.store = store
        self.panel = panel
        self.actions = actions
        // Permission status updates live: read again whenever Skreenrek becomes active (back from System Settings).
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak panel] _ in
            MainActor.assumeIsolated { panel?.refresh() }
        }
    }

    func show() {
        panel.refresh()
        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsView(
                    store: store, panel: panel, actions: actions, version: SkreenrekVersion.current))
            let window = NSWindow(contentViewController: hosting)
            window.title = UIStrings.Settings.windowTitle
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// The app delegate: the controller, the control socket and the menu bar, with no Dock icon and no main window.
@MainActor
public final class MenuBarAppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: "it.fraime.skreenrek", category: "app")

    private let host: HeadlessHost
    private let permissions: any PermissionProbe
    private let defaults: UserDefaults
    private var model: AppModel?
    private var menuController: MenuController?
    private var settingsWindow: SettingsWindowController?

    public init(host: HeadlessHost, permissions: any PermissionProbe, defaults: UserDefaults = .standard) {
        self.host = host
        self.permissions = permissions
        self.defaults = defaults
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let store = SettingsStore(defaults: defaults)
        let effects = SystemEffects()
        let model = AppModel(controller: host.controller, settings: store, effects: effects)
        let agents = AgentsPanelState(installer: AgentInstaller(
            home: FileManager.default.homeDirectoryForCurrentUser,
            executablePath: Bundle.main.executablePath ?? CommandLine.arguments[0],
            path: ProcessInfo.processInfo.environment["PATH"] ?? ""))
        let panel = SettingsPanelState(permissions: permissions, loginItem: MainAppLoginItem(), agents: agents)
        let settingsWindow = SettingsWindowController(
            store: store, panel: panel,
            actions: SettingsActions(
                chooseOutputFolder: { [weak model] in
                    guard let model else { return }
                    Task { await model.perform(.chooseOutputFolder) }
                },
                openPrivacyPane: { effects.open(PrivacyPane.url($0)) },
                settingsChanged: { [weak model] in
                    guard let model else { return }
                    Task { await model.pushSettings() }
                }))
        effects.showSettings = { [weak settingsWindow] in settingsWindow?.show() }
        self.model = model
        self.settingsWindow = settingsWindow
        menuController = MenuController(model: model)
        Task { await model.start() }
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        switch model.quitDecision {
        case .now:
            return .terminateNow
        case .askToStop:
            NSApp.activate()
            guard Alerts.quitWhileRecording().runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        case .afterWriting:
            break
        }
        Task {
            await model.finishForQuit()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    public func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
        host.stop()
    }
}

/// Runs Skreenrek as a menu-bar app (LSUIElement-style): controller, control server and menu bar.
@MainActor
public enum MenuBarApp {
    public static func run(seams: ControllerSeams) -> Never {
        let host = HeadlessHost(seams: seams, settings: SettingsStore().controllerSettings)
        do {
            try host.start()
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = MenuBarAppDelegate(host: host, permissions: seams.permissions)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(0)
    }
}
