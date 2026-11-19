import Foundation
import SkreenrekControl
import SkreenrekCore
import SkreenrekUI
import Testing

/// Each test runs its body on the main actor under a hard timeout.
@Suite struct SettingsStoreTests {
    @Test func defaultsMatchTheController() async throws {
        try await onMain("defaultsMatchTheController") {
            let scratch = ScratchDefaults()
            defer { scratch.remove() }
            let defaults = scratch.defaults
            let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
            let store = SettingsStore(defaults: defaults, home: home)
            #expect(
                store.controllerSettings
                    == ControllerSettings(outputFolder: OutputFolder.defaultParent(home: home)))
            #expect(store.sizeChoice == .default)
            #expect(store.outputFolderDisplayPath == "~/Movies/Skreenrek")
        }
    }

    @Test func valuesRoundTrip() async throws {
        try await onMain("valuesRoundTrip") {
            let scratch = ScratchDefaults()
            defer { scratch.remove() }
            let defaults = scratch.defaults
            let store = SettingsStore(defaults: defaults)
            store.outputFolder = URL(fileURLWithPath: "/tmp/clips", isDirectory: true)
            store.fps = .fps30
            store.cursor = false
            store.events = false
            store.hud = false
            store.sizeChoice = .keepCurrent

            let reloaded = SettingsStore(defaults: defaults)
            #expect(reloaded.outputFolder.path == "/tmp/clips")
            #expect(reloaded.fps == .fps30)
            #expect(!reloaded.cursor)
            #expect(!reloaded.events)
            #expect(!reloaded.hud)
            #expect(reloaded.sizeChoice == .keepCurrent)
            #expect(
                reloaded.controllerSettings
                    == ControllerSettings(
                        outputFolder: URL(fileURLWithPath: "/tmp/clips", isDirectory: true), fps: .fps30, cursor: false,
                        events: false, hud: false))

            store.sizeChoice = .size(PixelSize(width: 1080, height: 1920))
            #expect(SettingsStore(defaults: defaults).sizeChoice == .size(PixelSize(width: 1080, height: 1920)))
        }
    }

    @Test func badStoredValuesFallBack() async throws {
        try await onMain("badStoredValuesFallBack") {
            let scratch = ScratchDefaults()
            defer { scratch.remove() }
            let defaults = scratch.defaults
            defaults.set(45, forKey: SettingsStore.Key.fps)
            defaults.set("wide", forKey: SettingsStore.Key.size)
            let store = SettingsStore(defaults: defaults)
            #expect(store.fps == .fps60)
            #expect(store.sizeChoice == .default)
        }
    }

    @Test func sizeChoiceStorage() async throws {
        try await onMain("sizeChoiceStorage") {
            #expect(SizeChoice(storageValue: "keep") == .keepCurrent)
            #expect(SizeChoice(storageValue: "1280x720") == .size(PixelSize(width: 1280, height: 720)))
            #expect(SizeChoice(storageValue: "0x720") == nil)
            // Spec 13: a picked window keeps its current size until a preset is chosen.
            #expect(SizeChoice.default.storageValue == "keep")
        }
    }

    @Test func openAtLoginFailureShowsInline() async throws {
        try await onMain("openAtLoginFailureShowsInline") {
            let login = FailingLoginItem()
            let panel = SettingsPanelState(permissions: FakePermissions(), loginItem: login)
            panel.setOpenAtLogin(true)
            #expect(!panel.openAtLogin)
            #expect(panel.loginError == "Skreenrek couldn't be added to your login items.")
            login.fails = false
            panel.setOpenAtLogin(true)
            #expect(panel.openAtLogin)
            #expect(panel.loginError == nil)
        }
    }

    @Test func permissionRowsReadTheProbe() async throws {
        try await onMain("permissionRowsReadTheProbe") {
            let probe = FakePermissions()
            probe.accessibility = .missing
            let panel = SettingsPanelState(permissions: probe, loginItem: FailingLoginItem())
            #expect(panel.screenRecording == .allowed)
            #expect(panel.accessibility == .missing)
            probe.accessibility = .allowed
            panel.refresh()
            #expect(panel.accessibility == .allowed)
        }
    }

    @Test func privacyPaneURLs() async throws {
        try await onMain("privacyPaneURLs") {
            #expect(
                PrivacyPane.url(.screenRecording).absoluteString
                    == "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
            #expect(
                PrivacyPane.url(.accessibility).absoluteString
                    == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }
}

final class FakePermissions: PermissionProbe, @unchecked Sendable {
    var screenRecording: PermissionStatus = .allowed
    var directCapture: PermissionStatus = .allowed
    var accessibility: PermissionStatus = .allowed
}

@MainActor
final class FailingLoginItem: LoginItemService {
    struct Failure: Error {}
    var fails = true
    var isEnabled = false

    func setEnabled(_ enabled: Bool) throws {
        if fails { throw Failure() }
        isEnabled = enabled
    }
}

@Suite struct CustomSizeModelTests {
    /// Spec 13's laptop: usable ~1448 × 870 pt.
    static let laptop = DisplayInfo(
        id: 1, name: "Built-in Retina Display", scale: 2, frame: PointRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: PointRect(x: 0, y: 33, width: 1512, height: 934))

    @Test func liveLineShowsTheWindowOnScreen() {
        let model = CustomSizeModel(current: PixelSize(width: 1920, height: 1080), display: Self.laptop)
        #expect(model.line == .quiet("Window on screen: 1440 × 810"))
        #expect(model.size == PixelSize(width: 1920, height: 1080))
    }

    @Test func tooLargeSaysSoInRed() {
        let model = CustomSizeModel(widthText: "3840", heightText: "2160", display: Self.laptop)
        #expect(model.line == .problem("Too large for this display."))
        #expect(model.size == nil)
        #expect(!model.isValid)
    }

    @Test func oddNumbersSnapDownToEvenOnReturn() {
        var model = CustomSizeModel(widthText: "1721", heightText: "1081", display: Self.laptop)
        #expect(model.snapped == PixelSize(width: 1720, height: 1080))
        #expect(model.size == PixelSize(width: 1720, height: 1080))
        model.snap()
        #expect(model.widthText == "1720")
        #expect(model.heightText == "1080")
    }

    @Test func emptyFieldsAskForASize() {
        let model = CustomSizeModel(widthText: "", heightText: "800", display: Self.laptop)
        #expect(model.size == nil)
        #expect(model.line == .quiet("Enter a width and height in px."))
    }
}

/// The copy audit: every string the UI shows comes from `UIStrings.swift`, with no person's name or role, no
/// placeholder, and the product spelled Skreenrek.
@Suite struct CopyAuditTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let uiFolder = root.appendingPathComponent("Sources/SkreenrekUI")

    static func sources() throws -> [(name: String, text: String)] {
        try FileManager.default.contentsOfDirectory(at: uiFolder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    static var samples: [String] {
        var strings = UIStrings.allFixed
        for sample in RenderSamples.states {
            strings.append(StatusIconModel.icon(for: sample.context).sentence)
            for entry in MenuModel.entries(for: sample.context) { strings.append(entry.line) }
        }
        return strings
    }

    @Test func theNewPanelAndSettingsCopyIsInTheAudit() {
        for text in [
            "No window", "Pick a window to record", "Clear Window", "Clear picked window", "About", "View on GitHub",
            "Connect adds the Skreenrek MCP server and the record-window skill.",
            "Accessibility isn't allowed. Skreenrek can record, but windows keep their current size.",
            "Screen Recording isn't allowed. Skreenrek can't record until you allow it.",
        ] {
            #expect(UIStrings.allFixed.contains(text), "\(text)")
        }
        #expect(UIStrings.Panel.picked("Safari — localhost:3000") == "Picked Safari — localhost:3000")
        #expect(UIStrings.Agents.installFirst("Cursor") == "Install Cursor first.")
        #expect(!UIStrings.allFixed.contains("Pick a window first."))
        #expect(UIStrings.Menu.noWindowPicked == "No window picked")
    }

    @Test func noNamesRolesOrPlaceholders() throws {
        let strings = try #require(try Self.sources().first { $0.name == "UIStrings.swift" }).text
        for text in [strings] + Self.samples {
            for banned in ["Raph", "CTO", "<name>", "TODO", "FIXME", "Lorem"] {
                #expect(!text.contains(banned), "\(banned) in \(text.prefix(60))")
            }
        }
    }

    @Test func productIsSpelledSkreenrek() throws {
        let anySpelling = try Regex("(?i)s[ck]reen ?rec?k")
        for text in Self.samples {
            for match in text.matches(of: anySpelling) {
                // A path (the repository link, github.com/R4ph-t/skreenrek) uses the command's lower-case name.
                if match.range.lowerBound > text.startIndex, text[text.index(before: match.range.lowerBound)] == "/",
                    text[match.range] == "skreenrek"
                {
                    continue
                }
                let commandReference = text == UIStrings.Onboarding.cliDetail && text[match.range] == "skreenrek"
                #expect(text[match.range] == "Skreenrek" || commandReference, "\(text)")
            }
        }
    }

    @Test func copyLivesInTheStringsFile() throws {
        // A SwiftUI control, menu item or alert built with a string literal outside UIStrings.swift.
        let literalCopy = try Regex(
            #"(Text|Button|Toggle|Label|LabeledContent|Picker|Section|NSMenuItem)\(\s*(title:\s*)?"[A-Za-z]"#
                + #"|(messageText|informativeText|title|toolTip)\s*=\s*"[A-Za-z]"#)
        for file in try Self.sources() where file.name != "UIStrings.swift" {
            #expect(file.text.firstMatch(of: literalCopy) == nil, "\(file.name) has copy outside UIStrings")
        }
    }

    @Test func noPermissionPromptFromTheUI() throws {
        for file in try Self.sources() {
            // Split so the repo-wide test guardrail doesn't read this test as calling them.
            for api in [
                "CGRequest" + "ScreenCaptureAccess", "AXIsProcess" + "TrustedWithOptions", "ScreenCapture" + "Kit",
            ] {
                #expect(!file.text.contains(api), "\(file.name) uses \(api)")
            }
        }
    }
}
