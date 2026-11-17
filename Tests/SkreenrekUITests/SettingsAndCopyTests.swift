import Foundation
import SkreenrekControl
import SkreenrekCore
import SkreenrekUI
import Testing

@MainActor
@Suite struct SettingsStoreTests {
    static func suite() -> (UserDefaults, String) {
        let name = "skreenrek.tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func defaultsMatchTheController() {
        let (defaults, name) = Self.suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        let store = SettingsStore(defaults: defaults, home: home)
        #expect(
            store.controllerSettings
                == ControllerSettings(outputFolder: OutputFolder.defaultParent(home: home)))
        #expect(store.sizeChoice == .default)
        #expect(store.outputFolderDisplayPath == "~/Movies/Skreenrek")
    }

    @Test func valuesRoundTrip() {
        let (defaults, name) = Self.suite()
        defer { defaults.removePersistentDomain(forName: name) }
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

    @Test func badStoredValuesFallBack() {
        let (defaults, name) = Self.suite()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(45, forKey: SettingsStore.Key.fps)
        defaults.set("wide", forKey: SettingsStore.Key.size)
        let store = SettingsStore(defaults: defaults)
        #expect(store.fps == .fps60)
        #expect(store.sizeChoice == .default)
    }

    @Test func sizeChoiceStorage() {
        #expect(SizeChoice(storageValue: "keep") == .keepCurrent)
        #expect(SizeChoice(storageValue: "1280x720") == .size(PixelSize(width: 1280, height: 720)))
        #expect(SizeChoice(storageValue: "0x720") == nil)
        #expect(SizeChoice.default.storageValue == "1280x800")
    }

    @Test func openAtLoginFailureShowsInline() {
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

    @Test func permissionRowsReadTheProbe() {
        let probe = FakePermissions()
        probe.accessibility = .missing
        let panel = SettingsPanelState(permissions: probe, loginItem: FailingLoginItem())
        #expect(panel.screenRecording == .allowed)
        #expect(panel.accessibility == .missing)
        probe.accessibility = .allowed
        panel.refresh()
        #expect(panel.accessibility == .allowed)
    }

    @Test func privacyPaneURLs() {
        #expect(
            PrivacyPane.url(.screenRecording).absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        #expect(
            PrivacyPane.url(.accessibility).absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }
}

final class FakePermissions: PermissionProbe, @unchecked Sendable {
    var screenRecording: PermissionStatus = .allowed
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
    @Test func pointsCaption() {
        let model = CustomSizeModel(current: PixelSize(width: 1280, height: 800), scale: 2)
        #expect(model.caption == "640 × 400 pt at 2×")
        #expect(model.size == PixelSize(width: 1280, height: 800))
        #expect(CustomSizeModel(widthText: "1280", heightText: "800", scale: 1).caption == "1280 × 800 pt at 1×")
    }

    @Test func oddSizeOnRetinaIsRejected() {
        let model = CustomSizeModel(widthText: "1281", heightText: "800", scale: 2)
        #expect(model.size == nil)
        #expect(!model.isValid)
        #expect(model.caption == "Width 1281 px is odd. On a 2× display sizes must be even.")
    }

    @Test func emptyFieldsAskForASize() {
        let model = CustomSizeModel(widthText: "", heightText: "800", scale: 2)
        #expect(model.size == nil)
        #expect(model.caption == "Enter a width and height in px.")
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
                #expect(text[match.range] == "Skreenrek", "\(text)")
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
