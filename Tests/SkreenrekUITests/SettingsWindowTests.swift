import AppKit
import Foundation
import SkreenrekCore
import SkreenrekTesting
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

    @Test func theWindowHasStandardToolbarTabsOnTheSolidSurfaceAndTheTabsNameAsItsTitle() async throws {
        try await onMain("settings window") {
            let (defaults, name) = SettingsStoreTests.suite()
            defer { defaults.removePersistentDomain(forName: name) }
            let store = SettingsStore(defaults: defaults)
            store.settingsTab = .agents
            let controller = SettingsWindowController(store: store, panel: Self.panel(), actions: .none)
            let window = controller.prepareWindow()
            defer { window.contentViewController = nil }
            let tabs = try #require(window.contentViewController as? NSTabViewController)
            #expect(tabs.tabStyle == .toolbar)
            #expect(tabs.tabViewItems.map(\.label) == ["General", "Agents", "Permissions"])
            #expect(tabs.tabViewItems.map { $0.image != nil } == [true, true, true])
            #expect(window.toolbarStyle == .preference)
            #expect(window.titlebarAppearsTransparent)
            #expect(window.backgroundColor == SkreenrekSurface.baseColor)
            // It opens on the tab used last, and the title is the selected tab's name.
            #expect(store.settingsTab == .agents)
            #expect(window.title == "Agents")
            for tab in SettingsTab.allCases.reversed() + SettingsTab.allCases {
                controller.select(tab)
                #expect(store.settingsTab == tab)
                #expect(window.title == tab.title, "\(tab)")
            }
        }
    }

    /// One fixed content height, the tallest tab's (General with the identity row). Switching tabs, quickly and
    /// repeatedly, never resizes the window, and laying a tab out again doesn't either: nothing reports a height back.
    @Test func switchingTabsNeverResizesTheWindow() async throws {
        try await onMain("settings tab switch") {
            let (defaults, name) = SettingsStoreTests.suite()
            defer { defaults.removePersistentDomain(forName: name) }
            let store = SettingsStore(defaults: defaults)
            store.settingsTab = .permissions
            let controller = SettingsWindowController(store: store, panel: Self.panel(), actions: .none)
            let window = controller.prepareWindow()
            defer { window.contentViewController = nil }
            let general = NSHostingView(
                rootView: SettingsView(tab: .general, store: store, panel: Self.panel(), actions: .none))
            #expect(controller.contentHeight == general.fittingSize.height + SettingsChromeMetrics.contentTopGap)
            #expect(window.contentLayoutRect.height == controller.contentHeight, "\(window.contentLayoutRect)")
            #expect(window.contentLayoutRect.width == SettingsMetrics.width)
            let frame = window.frame
            for tab in Array(repeating: SettingsTab.allCases, count: 5).flatMap({ $0 }) + [.permissions, .agents] {
                controller.select(tab)
                window.contentView?.layoutSubtreeIfNeeded()
                #expect(window.frame == frame, "\(tab)")
            }
            window.contentView?.needsLayout = true
            window.contentView?.layoutSubtreeIfNeeded()
            #expect(window.frame == frame)
        }
    }

    /// Release notes found after the window was built (the launch or hourly check) make General taller: the window
    /// grows once to fit them, keeping its top edge, and tab switches still never resize it.
    @Test func notesThatArriveAfterTheWindowIsBuiltGrowItOnceAndNothingClips() async throws {
        try await onMain("settings notes refit") {
            let (defaults, name) = SettingsStoreTests.suite()
            defer { defaults.removePersistentDomain(forName: name) }
            let store = SettingsStore(defaults: defaults)
            let feed = FakeReleaseFeed(latest: "99.0.0", notes: RenderSamples.releaseNotes)
            let updates = UpdateChecker(
                feed: feed, installer: nil, method: .releasePage, defaults: defaults, openURL: { _ in }, relaunch: {})
            let panel = Self.panel(updates: updates)
            let controller = SettingsWindowController(store: store, panel: panel, actions: .none)
            let window = controller.prepareWindow()
            defer { window.contentViewController = nil }
            let before = controller.contentHeight
            let top = window.frame.maxY
            await updates.checkNow()
            // The refit runs on the main actor right after the state change; yield until it has (no clock involved).
            for _ in 0..<100 where controller.contentHeight == before { await Task.yield() }
            let needed = SettingsWindowController.tallestTabHeight(store: store, panel: panel, actions: .none)
            #expect(needed > before + WhatsNewNotes.maxHeight)
            #expect(controller.contentHeight == needed)
            #expect(window.contentLayoutRect.height == needed, "\(window.contentLayoutRect)")
            #expect(window.frame.maxY == top)
            let frame = window.frame
            for tab in SettingsTab.allCases + SettingsTab.allCases {
                controller.select(tab)
                window.contentView?.layoutSubtreeIfNeeded()
                #expect(window.frame == frame, "\(tab)")
            }
            // Measuring again with nothing new changes nothing.
            controller.fitHeight(allowShrink: true)
            #expect(window.frame == frame)
        }
    }

    @Test func theIdentityRowShowsTheNameAndTheCurrentVersion() {
        let header = SettingsHeaderModel()
        #expect(header.name == "Skreenrek")
        #expect(header.version == "Version \(SkreenrekVersion.current)")
        #expect(header.accessibilityLabel == "Skreenrek, version \(SkreenrekVersion.current)")
        #expect(SettingsHeaderModel(version: "2.0.0").version == "Version 2.0.0")
        #expect(SettingsChromeMetrics.identityHeight == 48)
        #expect(SettingsChromeMetrics.iconSize == 32)
        #expect(SettingsChromeMetrics.textGap == 12)
        #expect(SettingsChromeMetrics.contentTopGap == 8)
    }

    /// The identity row is on General only, above the first section; the other tabs start with their sections.
    @Test func theIdentityRowIsOnGeneralOnly() async throws {
        try await onMain("settings identity row") {
            let (defaults, name) = SettingsStoreTests.suite()
            defer { defaults.removePersistentDomain(forName: name) }
            let store = SettingsStore(defaults: defaults)
            let panel = Self.panel()
            @MainActor func height(_ tab: SettingsTab) -> CGFloat {
                NSHostingView(rootView: SettingsView(tab: tab, store: store, panel: panel, actions: .none)).fittingSize.height
            }
            let withRow = height(.general)
            let row = NSHostingView(rootView: SettingsIdentityRow()).fittingSize
            #expect(row.height == 48)
            #expect(withRow > row.height)
            #expect(withRow > height(.agents))
            #expect(withRow > height(.permissions))
        }
    }

    @Test func theHeaderIconIsTheDocksIconInTheBundleAndTheV1ArtworkOutside() {
        let dock = NSImage(size: NSSize(width: 1, height: 1))
        let brand = NSImage(size: NSSize(width: 2, height: 2))
        let bundled = SettingsHeaderIcon.image(isAppBundle: true, applicationIcon: { dock }, fallback: { brand })
        let unbundled = SettingsHeaderIcon.image(isAppBundle: false, applicationIcon: { dock }, fallback: { brand })
        #expect(bundled === dock)
        #expect(unbundled === brand)
        #expect(SettingsHeaderIcon.isAppBundle(Bundle(path: "/System/Applications/Calculator.app") ?? .main))
        // swift test runs from an .xctest bundle, not an app.
        #expect(!SettingsHeaderIcon.isAppBundle(.main))
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

    @MainActor
    private static func panel(updates: UpdateChecker? = nil) -> SettingsPanelState {
        let defaults = UserDefaults(suiteName: "skreenrek.tests.\(UUID().uuidString)")!
        let updates = updates ?? UpdateChecker(
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
