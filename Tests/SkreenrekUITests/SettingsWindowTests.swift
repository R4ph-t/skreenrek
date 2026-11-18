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

    @Test func theWindowHasToolbarTabsOpeningOnTheLastOneUsed() async throws {
        try await onMain("settings tabs") {
            let (defaults, name) = SettingsStoreTests.suite()
            defer { defaults.removePersistentDomain(forName: name) }
            let store = SettingsStore(defaults: defaults)
            store.settingsTab = .agents
            let tabs = SettingsTabsController(
                store: store, panel: Self.panel(), actions: .none)
            #expect(tabs.tabStyle == .toolbar)
            #expect(tabs.tabViewItems.map(\.label) == ["General", "Agents", "Permissions"])
            #expect(tabs.tabViewItems.allSatisfy { $0.image != nil })
            #expect(tabs.selectedTabViewItemIndex == 1)
            tabs.select(.general)
            #expect(tabs.selectedTabViewItemIndex == 0)
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

    @Test func theWindowFitsEachTabsContent() async throws {
        try await onMain("settings window height") {
            let (defaults, name) = SettingsStoreTests.suite()
            defer { defaults.removePersistentDomain(forName: name) }
            let tabs = SettingsTabsController(
                store: SettingsStore(defaults: defaults), panel: Self.panel(), actions: .none)
            let window = NSWindow(contentViewController: tabs)
            defer { window.contentViewController = nil }
            for (tab, height) in [(SettingsTab.general, 508.0), (.permissions, 120.0)] {
                tabs.select(tab)
                tabs.view.layoutSubtreeIfNeeded()
                let child = try #require(tabs.tabViewItems[tabs.selectedTabViewItemIndex].viewController)
                child.view.layoutSubtreeIfNeeded()
                tabs.fitWindow()
                let content = window.contentLayoutRect.height
                #expect(abs(content - height) <= 4, "\(tab) is \(content)")
            }
        }
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
