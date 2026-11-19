import Foundation
import SkreenrekCore
@testable import SkreenrekUI
import Testing

/// Sparkle runs only in a release bundle, and the dropdown's Check for Updates… item follows it. Nothing here starts
/// Sparkle: the updater is built only from an unconfigured info dictionary, which returns nil.
@Suite struct SparkleUpdaterTests {
    static let feed = "https://github.com/R4ph-t/skreenrek/releases/latest/download/appcast.xml"
    static let key = "7uv/ca5Plq03VT5kH490hKhCBcLKCsr7rofoiAhLHI8="

    @Test func sparkleRunsOnlyWithAFeedAndAPublicKey() {
        #expect(SparkleUpdater.isConfigured(["SUFeedURL": Self.feed, "SUPublicEDKey": Self.key]))
        #expect(!SparkleUpdater.isConfigured(nil))
        #expect(!SparkleUpdater.isConfigured([:]))
        #expect(!SparkleUpdater.isConfigured(["SUFeedURL": Self.feed]))
        #expect(!SparkleUpdater.isConfigured(["SUPublicEDKey": Self.key]))
        #expect(!SparkleUpdater.isConfigured(["SUFeedURL": " ", "SUPublicEDKey": Self.key]))
        #expect(!SparkleUpdater.isConfigured(["SUFeedURL": Self.feed, "SUPublicEDKey": ""]))
        #expect(!SparkleUpdater.isConfigured(["SUFeedURL": 1, "SUPublicEDKey": Self.key]))
    }

    /// `swift test` runs outside a bundle, and an ad-hoc bundle has the keys removed: no updater, so no UI.
    @Test func anUnconfiguredBundleGetsNoUpdater() async throws {
        try await onMain("no updater") {
            #expect(SparkleUpdater(info: [:]) == nil)
            #expect(SparkleUpdater(info: ["CFBundleIdentifier": SkreenrekIdentity.bundleID]) == nil)
            #expect(!SparkleUpdater.isConfigured(Bundle.main.infoDictionary))
        }
    }

    // MARK: - Dropdown footer

    private static func footer(_ item: CheckForUpdatesItem, state: String = "idle") throws -> [MenuItemModel] {
        var context = try #require(RenderSamples.states.first { $0.name == state }).context
        context.checkForUpdates = item
        return MenuModel.entries(for: context).compactMap { entry -> MenuItemModel? in
            if case .item(let item) = entry { return item }
            return nil
        }
    }

    @Test func checkForUpdatesSitsJustBeforeSettingsAndHidesWithoutSparkle() throws {
        let hidden = try Self.footer(.hidden)
        #expect(!hidden.contains { $0.action == .checkForUpdates })
        #expect(hidden.map(\.title).suffix(3) == ["Open Output Folder", "Settings…", "Quit Skreenrek"])

        let shown = try Self.footer(.enabled)
        #expect(
            shown.map(\.title).suffix(4) == ["Open Output Folder", "Check for Updates…", "Settings…", "Quit Skreenrek"])
        let item = try #require(shown.first { $0.action == .checkForUpdates })
        #expect(item.enabled)
        #expect(DropdownModel.symbol(for: .checkForUpdates) == "arrow.triangle.2.circlepath")
        let context = try #require(RenderSamples.states.first { $0.name == "checkforupdates" }).context
        #expect(DropdownModel.iconTint(for: item, context: context) == .neutral)

        let busy = try #require(try Self.footer(.disabled).first { $0.action == .checkForUpdates })
        #expect(!busy.enabled)
        // While recording too.
        #expect(try Self.footer(.enabled, state: "recording").contains { $0.action == .checkForUpdates })
    }

    @Test func thePanelFooterHasTheSameItem() throws {
        var context = try #require(RenderSamples.states.first { $0.name == "idle" }).context
        context.checkForUpdates = .disabled
        let footer = PanelModel.content(for: context, preview: .noWindow).footer
        #expect(
            footer.map(\.title) == ["Open Output Folder", "Check for Updates…", "Settings…", "Quit Skreenrek"])
        let item = try #require(footer.first { $0.action == .checkForUpdates })
        #expect(!item.enabled)
        #expect(item.symbol == "arrow.triangle.2.circlepath")
        #expect(item.tint == .neutral)
        context.checkForUpdates = .hidden
        #expect(!PanelModel.content(for: context, preview: .noWindow).footer.contains { $0.action == .checkForUpdates })
    }

    @Test func theItemAsksSparkleToCheck() async throws {
        try await onMain("check for updates") {
            let h = MenuHarness()
            defer { h.cleanUp() }
            var changes = 0
            h.model.onChange = { changes += 1 }
            h.model.checkForUpdates = .enabled
            #expect(changes == 1)
            #expect(h.model.context.checkForUpdates == .enabled)
            h.model.checkForUpdates = .enabled
            #expect(changes == 1)
            await h.model.perform(.checkForUpdates)
            #expect(h.effects.updateChecks == 1)
        }
    }

    @Test func theStandInCountsChecks() async throws {
        try await onMain("static updater") {
            let updater = StaticUpdater(canCheckForUpdates: false)
            #expect(!updater.canCheckForUpdates)
            updater.checkForUpdates()
            #expect(updater.checks == 1)
        }
    }
}
