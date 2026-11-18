import Foundation
import Observation
import SkreenrekControl
import SkreenrekCore

/// The values Settings and the dropdown change, kept in `UserDefaults` (injectable, so tests use their own suite).
/// They feed the controller's defaults through `controllerSettings`.
@MainActor
@Observable
public final class SettingsStore {
    public enum Key {
        public static let outputFolder = "outputFolder"
        public static let fps = "defaultFrameRate"
        public static let cursor = "showCursor"
        public static let events = "writeClickEvents"
        public static let hud = "showRecordingIndicator"
        public static let size = "nextSize"
        public static let settingsTab = "settingsTab"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let home: URL

    public var outputFolder: URL {
        didSet { defaults.set(outputFolder.path, forKey: Key.outputFolder) }
    }

    public var fps: FrameRate {
        didSet { defaults.set(fps.rawValue, forKey: Key.fps) }
    }

    public var cursor: Bool {
        didSet { defaults.set(cursor, forKey: Key.cursor) }
    }

    public var events: Bool {
        didSet { defaults.set(events, forKey: Key.events) }
    }

    public var hud: Bool {
        didSet { defaults.set(hud, forKey: Key.hud) }
    }

    /// The size the next recording (or the armed window) gets, from the Size submenu.
    public var sizeChoice: SizeChoice {
        didSet { defaults.set(sizeChoice.storageValue, forKey: Key.size) }
    }

    /// The Settings tab used last, so Settings reopens there.
    public var settingsTab: SettingsTab {
        didSet { defaults.set(settingsTab.rawValue, forKey: Key.settingsTab) }
    }

    public init(defaults: UserDefaults = .standard, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.defaults = defaults
        self.home = home
        let fallback = ControllerSettings(outputFolder: OutputFolder.defaultParent(home: home))
        if let path = defaults.string(forKey: Key.outputFolder), !path.isEmpty {
            outputFolder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            outputFolder = fallback.outputFolder
        }
        fps = FrameRate(rawValue: defaults.integer(forKey: Key.fps)) ?? fallback.fps
        cursor = defaults.object(forKey: Key.cursor) as? Bool ?? fallback.cursor
        events = defaults.object(forKey: Key.events) as? Bool ?? fallback.events
        hud = defaults.object(forKey: Key.hud) as? Bool ?? fallback.hud
        sizeChoice = defaults.string(forKey: Key.size).flatMap(SizeChoice.init(storageValue:)) ?? .default
        settingsTab = defaults.string(forKey: Key.settingsTab).flatMap(SettingsTab.init(rawValue:)) ?? .general
    }

    /// The controller's defaults for requests that leave them out.
    public var controllerSettings: ControllerSettings {
        ControllerSettings(outputFolder: outputFolder, fps: fps, cursor: cursor, events: events, hud: hud)
    }

    /// `~/Movies/Skreenrek` with the home folder written as `~`.
    public var outputFolderDisplayPath: String {
        let path = outputFolder.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") { return "~" + path.dropFirst(homePath.count) }
        return path
    }
}
