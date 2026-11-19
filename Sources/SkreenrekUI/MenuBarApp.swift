import AppKit
import SkreenrekControl
import SkreenrekCore
import SwiftUI
import os

/// The Settings window: one tone from the top edge down (addendum 3). A transparent title bar with only the traffic
/// lights, the header with the app icon, name, version and the segmented tab switch, then the selected tab's content.
/// The window fits that content, with no scroll view, and its title stays `Skreenrek Settings` on every tab.
@MainActor
final class SettingsWindowController {
    private let store: SettingsStore
    private let panel: SettingsPanelState
    private let actions: SettingsActions
    private(set) var window: NSWindow?
    private var observer: (any NSObjectProtocol)?
    /// Each tab's content height, as last laid out.
    private var heights: [SettingsTab: CGFloat] = [:]

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
        withObservationTracking { _ = store.settingsTab } onChange: { [weak self] in
            Task { @MainActor in self?.tabChanged() }
        }
    }

    /// Opens on `tab`, or on the tab used last.
    func show(tab: SettingsTab? = nil) {
        panel.refresh()
        let opening = window == nil
        let window = prepareWindow()
        if let tab { select(tab) }
        NSApp.activate()
        if opening {
            fitWindow(animated: false)
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    /// Builds the window once, off screen, laid out at the selected tab's height.
    @discardableResult
    func prepareWindow() -> NSWindow {
        if let window { return window }
        let hosting = NSHostingController(
            rootView: SettingsWindowContent(
                store: store, panel: panel, actions: actions,
                contentHeight: { [weak self] tab, height in self?.contentHeightChanged(tab, height) }))
        hosting.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsMetrics.width, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        window.contentViewController = hosting
        window.title = UIStrings.Settings.windowTitle
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = SkreenrekSurface.baseColor
        window.isReleasedWhenClosed = false
        self.window = window
        window.layoutIfNeeded()
        hosting.view.layoutSubtreeIfNeeded()
        fitWindow(animated: false)
        return window
    }

    func select(_ tab: SettingsTab) {
        store.settingsTab = tab
    }

    /// What the window's height should be for the selected tab: the title bar, the header, the gap and the content.
    var fittedHeight: CGFloat? {
        heights[store.settingsTab].map { SettingsChromeMetrics.contentTop + $0 }
    }

    /// Resizes to the selected tab, keeping the top edge where it is. The system animation, instant under Reduce
    /// Motion.
    func fitWindow(animated: Bool = true) {
        guard let window, let height = fittedHeight, abs(window.frame.height - height) >= 0.5
            || window.frame.width != SettingsMetrics.width
        else { return }
        let animate = animated && window.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var frame = window.frame
        frame.size = NSSize(width: SettingsMetrics.width, height: height)
        frame.origin.y = window.frame.maxY - height
        window.setFrame(frame, display: true, animate: animate)
    }

    private func contentHeightChanged(_ tab: SettingsTab, _ height: CGFloat) {
        guard height > 0 else { return }
        heights[tab] = height
        if tab == store.settingsTab { fitWindow() }
    }

    private func tabChanged() {
        withObservationTracking { _ = store.settingsTab } onChange: { [weak self] in
            Task { @MainActor in self?.tabChanged() }
        }
        fitWindow()
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
                controlBarVisible: menu?.controlBarVisible ?? false)
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
