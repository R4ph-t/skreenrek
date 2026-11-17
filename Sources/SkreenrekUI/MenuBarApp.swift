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
    private let requester: any PermissionRequester
    private let defaults: UserDefaults
    private var model: AppModel?
    private var menuController: MenuController?
    private var settingsWindow: SettingsWindowController?
    private var onboarding: OnboardingWindowController?
    private var hud: RecordingHUD?
    private var updates: UpdateChecker?
    private var updateTimer: Timer?

    public init(host: HeadlessHost, permissions: any PermissionProbe, requester: any PermissionRequester,
                defaults: UserDefaults = .standard) {
        self.host = host
        self.permissions = permissions
        self.requester = requester
        self.defaults = defaults
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let store = SettingsStore(defaults: defaults)
        let effects = SystemEffects()
        let model = AppModel(controller: host.controller, settings: store, effects: effects, permissions: permissions)
        let installer = AgentInstaller(
            home: FileManager.default.homeDirectoryForCurrentUser,
            executablePath: Bundle.main.executablePath ?? CommandLine.arguments[0],
            path: ProcessInfo.processInfo.environment["PATH"] ?? "")
        let agents = AgentsPanelState(installer: installer)
        let onboardingModel = OnboardingModel(
            permissions: permissions, requester: requester, defaults: defaults,
            agents: installer.connections().map { OnboardingAgent(agent: $0.agent, detected: $0.detected) },
            install: { installer.run(agents: $0) }, relaunch: { AppRelauncher.relaunch() })
        let onboarding = OnboardingWindowController(model: onboardingModel)
        self.onboarding = onboarding
        let updates = makeUpdateChecker(model: model, effects: effects)
        let panel = SettingsPanelState(
            permissions: permissions, loginItem: MainAppLoginItem(), agents: agents, updates: updates)
        let settingsWindow = SettingsWindowController(
            store: store, panel: panel,
            actions: SettingsActions(
                chooseOutputFolder: { [weak model] in
                    guard let model else { return }
                    Task { await model.perform(.chooseOutputFolder) }
                },
                openPrivacyPane: { [requester] in requester.request($0) },
                settingsChanged: { [weak model] in
                    guard let model else { return }
                    Task { await model.pushSettings() }
                }))
        effects.showSettings = { [weak settingsWindow] in settingsWindow?.show() }
        effects.showOnboardingPermissions = { [weak onboarding] in onboarding?.show(missingPermission: true) }
        self.model = model
        self.settingsWindow = settingsWindow
        let menu = MenuController(model: model)
        menuController = menu
        let hud = RecordingHUD(defaults: defaults)
        self.hud = hud
        hud.stop = { [weak model] in Task { await model?.perform(.stop) } }
        hud.showDetails = { [weak menu] in menu?.showDropdown() }
        let renderMenu = model.onChange
        model.onChange = { [weak model, weak hud] in
            renderMenu?()
            guard let model else { return }
            hud?.update(model.snapshot, indicatorEnabled: model.settings.hud)
        }
        Task {
            await host.controller.setPermissionFailureHandler { [weak onboarding] _ in
                Task { @MainActor in onboarding?.show(missingPermission: true) }
            }
            await model.start()
            if !onboardingModel.completed { onboarding.show() }
            await updates.checkIfDue()
        }
    }

    /// The update check: on launch, then hourly the timer asks whether 24 h have passed. The dropdown's footer
    /// follows its state.
    private func makeUpdateChecker(model: AppModel, effects: SystemEffects) -> UpdateChecker {
        let method = HomebrewUpgrader.method()
        let updates = UpdateChecker(
            feed: GitHubReleaseFeed(), installer: method == .homebrew ? HomebrewUpgrader() : nil, method: method,
            defaults: defaults, openURL: { effects.open($0) }, relaunch: { AppRelauncher.relaunch() })
        updates.onChange = { [weak model, weak updates] in
            model?.updateAvailable = updates?.availableVersion?.description
        }
        model.updateAvailable = updates.availableVersion?.description
        let timer = Timer(timeInterval: 60 * 60, repeats: true) { [weak updates] _ in
            MainActor.assumeIsolated {
                guard let updates else { return }
                Task { await updates.checkIfDue() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
        self.updates = updates
        return updates
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        // The cask's `uninstall quit:` asks the app to quit mid-upgrade; stay up so the upgrade can offer Relaunch.
        if updates?.isInstalling == true { return .terminateCancel }
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
        hud?.close()
        host.stop()
    }
}

/// Runs Skreenrek as a menu-bar app (LSUIElement-style): controller, control server and menu bar.
@MainActor
public enum MenuBarApp {
    public static func run(seams: ControllerSeams, requester: any PermissionRequester) -> Never {
        let host = HeadlessHost(seams: seams, settings: SettingsStore().controllerSettings)
        do {
            try host.start()
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = MenuBarAppDelegate(host: host, permissions: seams.permissions, requester: requester)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(0)
    }
}
