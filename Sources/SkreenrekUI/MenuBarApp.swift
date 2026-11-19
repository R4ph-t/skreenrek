import AppKit
import SkreenrekControl
import SkreenrekCore
import SwiftUI
import os

/// The three standard toolbar tabs (gearshape, terminal, hand.raised) with the system's selection styling; the
/// window title is the selected tab's name, as macOS does. This is what a SwiftUI `Settings` scene builds, which isn't
/// available to an app with an AppKit delegate and no `App`. Every tab has the same fixed size (the tallest tab's),
/// so the tab controller never resizes the window: a tab click just swaps the content, with no animation.
final class SettingsTabsController: NSTabViewController {
    private let store: SettingsStore

    init(store: SettingsStore, panel: SettingsPanelState, actions: SettingsActions, height: CGFloat) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        transitionOptions = []
        let size = NSSize(width: SettingsMetrics.width, height: height)
        for tab in SettingsTab.allCases {
            let hosting = NSHostingController(
                rootView: SettingsTabContent(tab: tab, store: store, panel: panel, actions: actions, height: height))
            hosting.sizingOptions = []
            hosting.preferredContentSize = size
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
    }
}

/// The Settings window: standard toolbar tabs on the shared solid surface, one tone from the top edge down (the
/// toolbar draws no band of its own). One fixed content height, the tallest tab's, measured once when the window is
/// built; shorter tabs sit at the top. Nothing reports heights back and nothing resizes the window on a tab switch.
@MainActor
final class SettingsWindowController {
    private let store: SettingsStore
    private let panel: SettingsPanelState
    private let actions: SettingsActions
    private(set) var window: NSWindow?
    private var tabs: SettingsTabsController?
    private var observer: (any NSObjectProtocol)?
    /// The content height every tab gets: the tallest tab, measured once.
    private(set) var contentHeight: CGFloat = 0

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
        let window = prepareWindow()
        if let tab { select(tab) }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Builds the window once, centred, at the fixed size.
    @discardableResult
    func prepareWindow() -> NSWindow {
        if let window { return window }
        contentHeight = Self.tallestTabHeight(store: store, panel: panel, actions: actions)
        let tabs = SettingsTabsController(store: store, panel: panel, actions: actions, height: contentHeight)
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.titlebarAppearsTransparent = true
        window.backgroundColor = SkreenrekSurface.baseColor
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: SettingsMetrics.width, height: contentHeight))
        window.center()
        self.tabs = tabs
        self.window = window
        return window
    }

    func select(_ tab: SettingsTab) {
        tabs?.select(tab)
    }

    /// The tallest tab's content (General, with the identity row), measured once off screen.
    static func tallestTabHeight(store: SettingsStore, panel: SettingsPanelState, actions: SettingsActions) -> CGFloat {
        SettingsTab.allCases.map { tab in
            NSHostingView(rootView: SettingsView(tab: tab, store: store, panel: panel, actions: actions))
                .fittingSize.height + SettingsChromeMetrics.contentTopGap
        }.max() ?? 0
    }
}

/// The app delegate: the controller, the control socket and the menu bar, with no Dock icon and no main window.
@MainActor
public final class MenuBarAppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: SkreenrekIdentity.bundleID, category: "app")

    private let host: HeadlessHost
    private let permissions: any PermissionProbe
    private let requester: any PermissionRequester
    private let previews: any WindowPreviewSource
    private let displays: @MainActor () -> [DisplayInfo]
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
        previews: any WindowPreviewSource, displays: @escaping @MainActor () -> [DisplayInfo],
        defaults: UserDefaults = .standard
    ) {
        self.host = host
        self.permissions = permissions
        self.requester = requester
        self.previews = previews
        self.displays = displays
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
        let menu = MenuController(model: model, previews: previews, permissions: permissions, displays: displays)
        menuController = menu
        let hud = RecordingHUD(defaults: defaults)
        self.hud = hud
        hud.stop = { [weak model] in Task { await model?.perform(.stop) } }
        hud.showDetails = { [weak menu] in menu?.showDropdown() }
        let renderMenu = model.onChange
        let updateHUD = { [weak model, weak hud, weak menu] in
            guard let model else { return }
            hud?.update(
                model.snapshot, indicatorEnabled: model.settings.hud,
                controlBarVisible: menu?.controlBarVisible ?? false,
                controlBarSaved: menu?.controlBarShowsSaved ?? false)
        }
        model.onChange = {
            renderMenu?()
            updateHUD()
        }
        menu.onControlBarVisibilityChange = updateHUD
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
        seams: ControllerSeams, requester: any PermissionRequester, previews: any WindowPreviewSource,
        displays: @escaping @MainActor () -> [DisplayInfo]
    ) -> Never {
        migrateLegacyDefaults()
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
            host: host, permissions: seams.permissions, requester: requester, previews: previews,
            displays: displays)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(0)
    }

    /// Runs before anything reads settings. Only the real app has the new ID's defaults as `.standard`.
    private static func migrateLegacyDefaults() {
        guard Bundle.main.bundleIdentifier == SkreenrekIdentity.bundleID else { return }
        LegacyDefaultsMigration.run(
            old: UserDefaults(suiteName: SkreenrekIdentity.legacyBundleID), new: .standard,
            excluding: OnboardingModel.permissionStateKeys)
    }
}
