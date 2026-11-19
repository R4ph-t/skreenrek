import AppKit
import Foundation
import SkreenrekCore
@testable import SkreenrekUI
import SwiftUI
import Testing

/// The Settings window: its tabs, its row states and where the rows land.
@Suite struct SettingsWindowTests {
    @Test func theTabsAreGeneralAgentsAndPermissions() {
        #expect(SettingsTab.allCases.map(\.title) == ["General", "Agents", "Permissions"])
        #expect(SettingsTab.allCases.map(\.symbol) == ["gearshape", "terminal", "hand.raised"])
    }

    @Test func theMetricsAreTheDesigns() {
        #expect(SettingsMetrics.width == 480)
        #expect(SettingsMetrics.rowHeight == 44)
        #expect(SettingsMetrics.labelX == 28)
        #expect(SettingsMetrics.trailingX == 452)
        #expect(SettingsMetrics.agentButtonWidth == 88)
        #expect(SettingsMetrics.buttonMinWidth == 80)
    }

    @Test func anAllowedPermissionShowsACheck() {
        let row = PermissionRowModel(.screenRecording, status: .allowed)
        #expect(row.title == "Screen Recording")
        #expect(row.detail == "Required. Records the window you pick.")
        #expect(row.allowed)
        #expect(row.symbol == "checkmark.circle.fill")
        #expect(row.warning == nil)
        #expect(row.accessibilityLabel == "Screen Recording, allowed.")
    }

    @Test func aMissingPermissionWarnsAndSaysWhy() {
        let accessibility = PermissionRowModel(.accessibility, status: .missing)
        #expect(!accessibility.allowed)
        #expect(accessibility.symbol == "exclamationmark.triangle.fill")
        #expect(
            accessibility.warning
                == "Accessibility isn't allowed. Skreenrek can record, but windows keep their current size.")
        #expect(
            accessibility.accessibilityLabel
                == "Accessibility, required for exact window sizes, not allowed, Open System Settings…")
        let screen = PermissionRowModel(.screenRecording, status: .missing)
        #expect(screen.warning == "Screen Recording isn't allowed. Skreenrek can't record until you allow it.")
    }

    @Test func theLastTabIsRememberedAndABadValueFallsBack() async throws {
        try await onMain("settings tab") {
            let (defaults, name) = SettingsStoreTests.suite()
            defer { defaults.removePersistentDomain(forName: name) }
            let store = SettingsStore(defaults: defaults)
            #expect(store.settingsTab == .general)
            store.settingsTab = .permissions
            #expect(SettingsStore(defaults: defaults).settingsTab == .permissions)
            defaults.set("nope", forKey: SettingsStore.Key.settingsTab)
            #expect(SettingsStore(defaults: defaults).settingsTab == .general)
        }
    }

    @Test func theWindowIsOneToneUnderATransparentTitleBarWithAConstantTitle() async throws {
        try await onMain("settings window") {
            let (defaults, name) = SettingsStoreTests.suite()
            defer { defaults.removePersistentDomain(forName: name) }
            let store = SettingsStore(defaults: defaults)
            store.settingsTab = .agents
            let controller = SettingsWindowController(store: store, panel: Self.panel(), actions: .none)
            let window = controller.prepareWindow()
            defer { window.contentViewController = nil }
            #expect(window.styleMask.contains(.fullSizeContentView))
            #expect(window.titlebarAppearsTransparent)
            #expect(window.titleVisibility == .hidden)
            #expect(window.toolbar == nil)
            #expect(window.backgroundColor == SkreenrekSurface.baseColor)
            #expect(window.contentViewController is NSHostingController<SettingsWindowContent>)
            // It opens on the tab used last.
            #expect(store.settingsTab == .agents)
            #expect(window.title == "Skreenrek Settings")
            for tab in SettingsTab.allCases.reversed() + SettingsTab.allCases {
                controller.select(tab)
                #expect(store.settingsTab == tab)
                #expect(window.title == "Skreenrek Settings", "\(tab)")
            }
        }
    }

    @Test func theHeaderShowsTheNameAndTheCurrentVersion() {
        let header = SettingsHeaderModel()
        #expect(header.name == "Skreenrek")
        #expect(header.version == "Version \(SkreenrekVersion.current)")
        #expect(header.accessibilityLabel == "Skreenrek, version \(SkreenrekVersion.current)")
        #expect(SettingsHeaderModel(version: "2.0.0").version == "Version 2.0.0")
        #expect(UIStrings.Settings.windowTitle == "Skreenrek Settings")
        #expect(UIStrings.Settings.tabsLabel == "Settings tabs")
    }

    @Test func theHeaderLayoutIsTheAddendums() {
        #expect(SettingsChromeMetrics.titleBarHeight == 28)
        #expect(SettingsChromeMetrics.headerHeight == 56)
        #expect(SettingsChromeMetrics.headerBottom == 84)
        #expect(SettingsChromeMetrics.contentTop == 92)
        #expect(SettingsChromeMetrics.headerInset == 16)
        #expect(SettingsChromeMetrics.iconSize == 32)
        #expect(SettingsChromeMetrics.headerInset + SettingsChromeMetrics.iconSize + SettingsChromeMetrics.textGap == 56)
        #expect(SettingsChromeMetrics.tabsWidth == 264)
        #expect(SettingsChromeMetrics.segmentHeight == 24)
        #expect(SettingsMetrics.width - SettingsChromeMetrics.headerInset == 464)
        #expect(SettingsChromeMetrics.crossfade == 0.15)
    }

    @Test func arrowsMoveOneTabAndStopAtTheEnds() {
        #expect(SettingsTab.general.moved(by: 1) == .agents)
        #expect(SettingsTab.agents.moved(by: 1) == .permissions)
        #expect(SettingsTab.permissions.moved(by: 1) == .permissions)
        #expect(SettingsTab.permissions.moved(by: -1) == .agents)
        #expect(SettingsTab.general.moved(by: -1) == .general)
        #expect(SettingsTab.general.moved(by: 5) == .permissions)
    }

    @Test func theSegmentedControlSwitchesAndRemembersTheTab() async throws {
        try await onMain("settings segmented control") {
            let (defaults, name) = SettingsStoreTests.suite()
            defer { defaults.removePersistentDomain(forName: name) }
            let store = SettingsStore(defaults: defaults)
            let coordinator = SettingsTabsControl.Coordinator(
                selection: Binding(get: { store.settingsTab }, set: { store.settingsTab = $0 }))
            let control = SettingsSegmentedControl.make()
            control.target = coordinator
            control.action = #selector(SettingsTabsControl.Coordinator.changed(_:))
            control.onMove = { coordinator.move(by: $0) }
            #expect(control.segmentCount == 3)
            #expect((0..<3).map { control.label(forSegment: $0) } == ["General", "Agents", "Permissions"])
            #expect((0..<3).map { control.width(forSegment: $0) } == [88, 88, 88])
            #expect(control.accessibilityLabel() == "Settings tabs")
            #expect(control.canBecomeKeyView)
            #expect(control.acceptsFirstResponder)

            // A click on Permissions.
            control.selectedSegment = 2
            coordinator.changed(control)
            #expect(store.settingsTab == .permissions)
            #expect(SettingsStore(defaults: defaults).settingsTab == .permissions)

            // → at the last tab stays there; ← walks back and stops at General.
            control.keyDown(with: Self.arrow(right: true))
            #expect(store.settingsTab == .permissions)
            control.keyDown(with: Self.arrow(right: false))
            #expect(store.settingsTab == .agents)
            control.keyDown(with: Self.arrow(right: false))
            control.keyDown(with: Self.arrow(right: false))
            #expect(store.settingsTab == .general)
            control.keyDown(with: Self.arrow(right: true))
            #expect(store.settingsTab == .agents)
            #expect(SettingsStore(defaults: defaults).settingsTab == .agents)
        }
    }

    @Test(arguments: [(SettingsTab.general, 9), (.agents, 4), (.permissions, 2)])
    func everyRowIsFortyFourTallOnTheLabelAndTrailingEdges(tab: SettingsTab, rows: Int) async throws {
        try await onMain("settings rows") {
            let (defaults, name) = SettingsStoreTests.suite()
            defer { defaults.removePersistentDomain(forName: name) }
            let frames = try await Self.rowFrames(
                tab: tab, count: rows, store: SettingsStore(defaults: defaults), panel: Self.panel())
            #expect(frames.count == rows)
            for frame in frames {
                #expect(frame.height == SettingsMetrics.rowHeight, "\(frame)")
                #expect(frame.minX == SettingsMetrics.labelX, "\(frame)")
                #expect(frame.maxX == SettingsMetrics.trailingX, "\(frame)")
            }
        }
    }

    @Test func theWindowFitsEachTabsContentUnderTheHeader() async throws {
        try await onMain("settings window height") {
            let (defaults, name) = SettingsStoreTests.suite()
            defer { defaults.removePersistentDomain(forName: name) }
            let store = SettingsStore(defaults: defaults)
            let controller = SettingsWindowController(store: store, panel: Self.panel(), actions: .none)
            let window = controller.prepareWindow()
            defer { window.contentViewController = nil }
            // The title bar and header (84) and the gap (8) over each tab's sections. No scroll view.
            for (tab, height) in [(SettingsTab.general, 627.5), (.permissions, 196.5), (.agents, 306.5)] {
                controller.select(tab)
                window.contentView?.layoutSubtreeIfNeeded()
                controller.fitWindow(animated: false)
                #expect(abs(window.frame.height - height) <= 4, "\(tab) is \(window.frame.height)")
                #expect(window.frame.width == SettingsMetrics.width)
            }
        }
    }

    @MainActor
    private static func arrow(right: Bool) -> NSEvent {
        let key = String(UnicodeScalar(UInt16(right ? NSRightArrowFunctionKey : NSLeftArrowFunctionKey))!)
        return NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function], timestamp: 0, windowNumber: 0,
            context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false,
            keyCode: right ? 124 : 123)!
    }

    @MainActor
    private static func panel() -> SettingsPanelState {
        let defaults = UserDefaults(suiteName: "skreenrek.tests.\(UUID().uuidString)")!
        let updates = UpdateChecker(
            feed: StaticReleaseFeed(), installer: StaticReleaseFeed(), method: .homebrew, defaults: defaults,
            openURL: { _ in }, relaunch: {})
        // An empty home folder: the installer only reads it, and every agent shows as not installed.
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("skreenrek-settings-\(UUID().uuidString)")
        let agents = AgentsPanelState(installer: AgentInstaller(home: home, executablePath: "/unused/skreenrek", path: ""))
        return SettingsPanelState(
            permissions: FakePermissions(), loginItem: FailingLoginItem(), agents: agents, updates: updates)
    }

    /// Hosts a tab in an offscreen window and waits for its rows to report where they landed.
    @MainActor
    private static func rowFrames(
        tab: SettingsTab, count: Int, store: SettingsStore, panel: SettingsPanelState
    ) async throws -> [CGRect] {
        var frames: [CGRect] = []
        var window: NSWindow?
        let result: [CGRect] = await withCheckedContinuation { continuation in
            var finished = false
            let view = SettingsView(tab: tab, store: store, panel: panel, actions: .none)
                .environment(\.settingsRowProbe) { frame in
                    frames.append(frame)
                    if frames.count == count, !finished {
                        finished = true
                        continuation.resume(returning: frames)
                    }
                }
            let hosting = NSHostingView(rootView: view)
            let host = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 700), styleMask: .borderless, backing: .buffered,
                defer: false)
            host.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            window = host
        }
        window?.contentView = nil
        return result
    }
}
