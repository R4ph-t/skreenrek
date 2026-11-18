import AppKit
import SkreenrekControl
import SkreenrekCore
import SwiftUI
import os

/// The three toolbar tabs. The window title follows the selected tab, and the window fits that tab's content. This is
/// what a SwiftUI `Settings` scene builds, which isn't available to an app with an AppKit delegate and no `App`.
final class SettingsTabsController: NSTabViewController {
    private let store: SettingsStore

    init(store: SettingsStore, panel: SettingsPanelState, actions: SettingsActions) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        transitionOptions = []
        for tab in SettingsTab.allCases {
            let hosting = NSHostingController(
                rootView: SettingsView(tab: tab, store: store, panel: panel, actions: actions))
            hosting.sizingOptions = [.preferredContentSize]
            hosting.title = tab.title
            let item = NSTabViewItem(viewController: hosting)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: nil)
            addTabViewItem(item)
        }
        selectedTabViewItemIndex = SettingsTab.allCases.firstIndex(of: store.settingsTab) ?? 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func select(_ tab: SettingsTab) {
        selectedTabViewItemIndex = SettingsTab.allCases.firstIndex(of: tab) ?? 0
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        store.settingsTab = SettingsTab.allCases[selectedTabViewItemIndex]
        fitWindow()
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        if viewController === tabViewItems[selectedTabViewItemIndex].viewController { fitWindow() }
    }

    /// Resizes to the selected tab, keeping the title bar where it is.
    func fitWindow(animated: Bool = true) {
        guard let window = view.window,
            let content = tabViewItems[selectedTabViewItemIndex].viewController?.preferredContentSize,
            content.height > 0
        else { return }
        // Measured against the area under the toolbar, which `frameRect(forContentRect:)` doesn't know about. A window
        // that isn't on screen yet only reports that area correctly after its first resize, so it gets a second pass.
        let animate = animated && window.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for _ in 0..<(window.isVisible ? 1 : 2) {
            var frame = window.frame
            frame.size.width = content.width
            frame.size.height += content.height - window.contentLayoutRect.height
            frame.origin.y = window.frame.maxY - frame.height
            window.setFrame(frame, display: true, animate: animate)
            window.layoutIfNeeded()
            window.contentView?.layoutSubtreeIfNeeded()
        }
    }
}

/// The Settings window.
@MainActor
final class SettingsWindowController {
    private let store: SettingsStore
    private let panel: SettingsPanelState
    private let actions: SettingsActions
    private var window: NSWindow?
    private var tabs: SettingsTabsController?
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

    /// Opens on `tab`, or on the tab used last.
    func show(tab: SettingsTab? = nil) {
        panel.refresh()
        let opening = window == nil
        if window == nil {
            let tabs = SettingsTabsController(store: store, panel: panel, actions: actions)
            let window = NSWindow(contentViewController: tabs)
            window.styleMask = [.titled, .closable]
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            self.tabs = tabs
            self.window = window
            if let tab { tabs.select(tab) }
            tabs.fitWindow()
            window.center()
        } else if let tab {
            tabs?.select(tab)
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        // The toolbar's height is only final on screen. This lands before the window first draws.
        if opening {
            tabs?.fitWindow(animated: false)
            window?.center()
        }
    }
}

/// The app delegate: the controller, the control socket and the menu bar, with no Dock icon and no main window.
@MainActor
public final class MenuBarAppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: "it.fraime.skreenrek", category: "app")

    private let host: HeadlessHost
    private let permissions: any PermissionProbe
    private let requester: any PermissionRequester
    private let previews: any WindowPreviewSource
    private let defaults: UserDefaults
    private var model: AppModel?
    private var menuController: MenuController?
    private var settingsWindow: SettingsWindowController?
    private var onboarding: OnboardingWindowController?
    private var hud: RecordingHUD?
    private var updates: UpdateChecker?
    private var updateTimer: Timer?

    public init(
        host: HeadlessHost, permissions: any PermissionProbe, requester: any PermissionRequester,
        previews: any WindowPreviewSource, defaults: UserDefaults = .standard
    ) {
        self.host = host
        self.permissions = permissions
        self.requester = requester
        self.previews = previews
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
            install: { installer.run(agents: $0) }, relaunch: { AppRelauncher.relaunch() },
            openSettings: { NSWorkspace.shared.open(PrivacyPane.url($0)) })
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
                // The rows' "Open System Settings…" opens the pane. The prompts belong to onboarding.
                openPrivacyPane: { NSWorkspace.shared.open(PrivacyPane.url($0)) },
                settingsChanged: { [weak model] in
                    guard let model else { return }
                    Task { await model.pushSettings() }
                }))
        effects.showSettings = { [weak settingsWindow] in settingsWindow?.show() }
        effects.showSettingsUpdates = { [weak settingsWindow] in settingsWindow?.show(tab: .general) }
        effects.showOnboardingPermissions = { [weak onboarding] in onboarding?.show() }
        self.model = model
        self.settingsWindow = settingsWindow
        let menu = MenuController(model: model, previews: previews, permissions: permissions)
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
                Task { @MainActor in onboarding?.show() }
            }
            await model.start()
            if onboardingModel.shouldShowAtLaunch { onboarding.show() }
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
    public static func run(
        seams: ControllerSeams, requester: any PermissionRequester, previews: any WindowPreviewSource
    ) -> Never {
        let host = HeadlessHost(seams: seams, settings: SettingsStore().controllerSettings)
        do {
            try host.start()
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = MenuBarAppDelegate(
            host: host, permissions: seams.permissions, requester: requester, previews: previews)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(0)
    }
}
