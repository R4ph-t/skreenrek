import Foundation
import SkreenrekCore

/// Every string the menu bar, the dropdown, the alerts and Settings show, from the design spec. One file, so a test can
/// audit the copy: no person's name or role, no placeholder, and the product spelled Skreenrek everywhere.
public enum UIStrings {
    public static let productName = "Skreenrek"

    // MARK: - Menu-bar icon (tooltip and VoiceOver)

    public enum Icon {
        public static let idle = "Skreenrek is ready. No window picked."
        public static let writing = "Skreenrek is saving the clip."
        public static let regionTarget = "a screen region"

        /// `Skreenrek is ready to record Safari at 1280 × 800 pixels.`
        public static func armed(target: String, size: PixelSize?) -> String {
            guard let size else { return "Skreenrek is ready to record \(target)." }
            return "Skreenrek is ready to record \(target) at \(size.width) × \(size.height) pixels."
        }

        /// `Skreenrek is recording Safari. 12 seconds.`
        public static func recording(target: String, seconds: Int) -> String {
            "Skreenrek is recording \(target). \(spokenDuration(seconds))."
        }

        /// `Skreenrek stopped recording: the window closed.`
        public static func error(reason: String) -> String {
            "Skreenrek stopped recording: \(reason)."
        }

        /// `12 seconds`, `1 second`, `1 minute 5 seconds`, `2 minutes`.
        public static func spokenDuration(_ seconds: Int) -> String {
            let total = max(0, seconds)
            let minutes = total / 60
            let rest = total % 60
            let secondsText = "\(rest) \(rest == 1 ? "second" : "seconds")"
            guard minutes > 0 else { return secondsText }
            let minutesText = "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
            return rest == 0 ? minutesText : "\(minutesText) \(secondsText)"
        }

        /// What the error sentence names as the reason, lower case after the colon.
        public static func reason(_ error: SkreenrekError) -> String {
            switch error {
            case .recordingFailed(.windowClosed): "the window closed"
            case .recordingFailed(.diskLow): "less than 2 GB free"
            case .recordingFailed(.notWritable): "the output folder isn't writable"
            case .permissionDenied(.screenRecording): "Screen Recording is off"
            case .permissionDenied(.accessibility): "Accessibility is off"
            case .notExact: "the size isn't exact"
            default: sentenceFragment(error.message)
            }
        }

        /// A message as a fragment after a colon: its first line without the final period, and the first letter in
        /// lower case when it starts a plain word (names such as Skreenrek or Safari keep their capital).
        static func sentenceFragment(_ message: String) -> String {
            var text = message.split(separator: "\n").first.map(String.init) ?? message
            while text.hasSuffix(".") { text.removeLast() }
            let firstWord = String(text.prefix { $0 != " " })
            guard plainSentenceStarts.contains(firstWord), let first = text.first else { return text }
            return first.lowercased() + text.dropFirst()
        }

        static let plainSentenceStarts: Set<String> = [
            "The", "A", "An", "No", "Less", "Nothing", "Couldn't", "Can't", "This", "There",
        ]
    }

    // MARK: - Dropdown

    public enum Menu {
        public static let ready = "Ready"
        public static let noWindowPicked = "No window picked"
        public static let pickWindow = "Pick Window…"
        public static let pickAnotherWindow = "Pick Another Window…"
        public static let size = "Size"
        public static let frameRate = "Frame Rate"
        public static let showCursor = "Show Cursor"
        public static let writeClickEvents = "Write Click Events"
        public static let recordWindow = "Record Window"
        public static let lastClip = "Last Clip"
        public static let showInFinder = "Show in Finder"
        public static let copyFilePath = "Copy File Path"
        public static let copySnippet = "Copy HyperFrames Snippet"
        public static let openOutputFolder = "Open Output Folder"
        public static let settings = "Settings…"
        public static let quit = "Quit Skreenrek"
        public static let stopRecording = "Stop Recording"
        public static let discardRecording = "Discard Recording…"
        public static let savingClip = "Saving clip…"
        public static let region = "Screen region"

        public static let keepCurrentSize = "Keep Current Size"
        public static let customSize = "Custom Size…"
        public static let portrait = "portrait"
        public static let square = "square"

        public static let exactSize = "exact size"

        public static let startedFromMenu = "Started from the menu"
        public static let startedFromCommandLine = "Started from the command line"
        public static let startedOverMCP = "Started over MCP"

        /// `Started by Claude Code over MCP`.
        public static func startedBy(client: String) -> String { "Started by \(client) over MCP" }

        /// `Recording Safari — localhost:3000`.
        public static func recording(_ target: String) -> String { "Recording \(target)" }

        /// `Safari — localhost:3000`, or the app alone when the title is empty.
        public static func windowTitle(app: String, title: String) -> String {
            title.isEmpty ? app : "\(app) — \(title)"
        }

        /// `30 fps`.
        public static func fps(_ rate: FrameRate) -> String { "\(rate.framesPerSecond) fps" }

        /// `not exact`: the short note on the armed row. The reason goes to the tooltip and VoiceOver
        /// (`notExactReason`), so the detail stays on one line.
        public static let notExact = "not exact"

        /// `Safari won't go narrower than 1286 px, so the clip is 1286 × 800 instead of 1280 × 800.`
        public static func notExactReason(
            app: String, requested: PixelSize, actual: PixelSize, reason: NotExactReason
        ) -> String {
            let limit: String
            switch reason {
            case .minWidth(let px): limit = "\(app) won't go narrower than \(px) px"
            case .minHeight(let px): limit = "\(app) won't go shorter than \(px) px"
            case .maxWidth(let px): limit = "\(app) won't go wider than \(px) px"
            case .maxHeight(let px): limit = "\(app) won't go taller than \(px) px"
            case .steps: limit = "\(app) resizes in steps"
            }
            return "\(limit), so the clip is \(dimensions(actual)) instead of \(dimensions(requested))."
        }

        /// `1280 × 800`, without the unit.
        static func dimensions(_ size: PixelSize) -> String { "\(size.width) × \(size.height)" }

        /// The detail lines join their parts with a middle dot.
        public static let separator = " · "
    }

    // MARK: - Error rows (the design spec's error-copy table)

    public enum Errors {
        public static let recordingStopped = "Recording stopped"
        public static let screenRecordingOff = "Screen Recording is off"
        public static let screenRecordingDetail =
            "Allow Skreenrek in System Settings › Privacy & Security, then reopen it."
        public static let cantResize = "Can't resize windows"
        public static let cantResizeDetail = "Allow Skreenrek in Accessibility settings to set exact sizes."
        public static let notExact = "Size isn't exact"
        public static let couldntSave = "Couldn't save the clip"
        public static let somethingWentWrong = "Something went wrong"

        public static let copyErrorDetails = "Copy Error Details"
        public static let openPrivacySettings = "Open Privacy Settings…"
        public static let openAccessibilitySettings = "Open Accessibility Settings…"
        public static let pickAnotherSize = "Pick Another Size…"
        public static let chooseOutputFolder = "Choose Output Folder…"

        /// What Copy Error Details puts on the pasteboard: the CLI's `error:` / `hint:` lines.
        public static func details(_ error: SkreenrekError) -> String {
            "error: \(error.message)\nhint:  \(error.hint)"
        }
    }

    // MARK: - Alerts

    public enum Alerts {
        public static let discardTitle = "Discard this recording?"
        public static let discardMessage = "The clip and its events will be deleted."
        public static let discard = "Discard"
        public static let cancel = "Cancel"
        public static let quitTitle = "Stop and save the recording before quitting?"
        public static let stopAndQuit = "Stop and Quit"
    }

    // MARK: - Custom size

    public enum CustomSize {
        public static let title = "Custom Size"
        public static let width = "Width"
        public static let height = "Height"
        public static let px = "px"
        public static let times = "×"
        public static let setSize = "Set Size"
        public static let cancel = "Cancel"
        public static let enterSize = "Enter a width and height in px."

        /// `640 × 400 pt at 2×`.
        public static func points(width: Double, height: Double, scale: Double) -> String {
            "\(number(width)) × \(number(height)) pt at \(SizeRequest.scaleLabel(scale))"
        }

        static func number(_ value: Double) -> String {
            value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        }
    }

    public enum Picker {
        public static let pick = "Pick"
        public static let alreadyOpen = "The window picker is already open."
        public static let hint = "Click a window, or drag to pick a region."
        public static let escape = "Esc to cancel"
        public static let cancel = "Cancel"
        public static func detail(_ size: PixelSize) -> String { "\(size) · Click to pick" }
        public static func voiceOver(app: String, title: String, size: PixelSize) -> String {
            "\(app), \(title), \(size.width) by \(size.height) pixels. Press Return to pick."
        }
    }

    public enum HUD {
        public static let dismiss = "Dismiss"
        public static let stop = "Stop"
        public static let showDetails = "Show Details"
        public static func saved(_ duration: Double) -> String { "Saved · \(TimeFormat.minutesSeconds(duration))" }
        public static func stopped(_ reason: String) -> String { "Stopped: \(reason)" }
        public static func voiceOver(target: String, seconds: Int) -> String {
            "Recording \(target), \(Icon.spokenDuration(seconds))"
        }
    }

    public enum Onboarding {
        public static let title = "Set up Skreenrek"
        public static let introduction = "Skreenrek records windows for your coding agents. It needs two permissions. Everything stays on this Mac."
        public static let accessibilityNote = "Without Accessibility you can still record, but windows keep their current size."
        public static let continueButton = "Continue"
        public static let agentsTitle = "Connect your agents"
        public static let agentsIntroduction = "Adds the Skreenrek MCP server and the record-window skill to each agent you pick. You can change this later in Settings."
        public static let skip = "Skip"
        public static let connect = "Connect"
        public static let cliDetail = "Links skreenrek into ~/.local/bin"
        public static let notInstalled = "Not installed"
        public static func found(_ agent: AgentClient) -> String { "Found ~/.\(agent.rawValue)" }
        public static func step(_ number: Int) -> String { "Step \(number) of 2" }
    }

    // MARK: - Settings

    public enum Agents {
        public static let title = "Agents"
        public static let connect = "Connect"
        public static let remove = "Remove"
    }

    public enum Settings {
        public static let windowTitle = "Skreenrek Settings"
        public static let outputFolder = "Output folder"
        public static let choose = "Choose…"
        public static let defaultFrameRate = "Default frame rate"
        public static let showCursor = "Show cursor in video"
        public static let writeClickEvents = "Write click events"
        public static let showRecordingIndicator = "Show recording indicator"
        public static let openAtLogin = "Open at login"
        public static let stopShortcut = "Stop shortcut"
        public static let stopShortcutKeys = "⌃⌘⎋"
        public static let permissions = "Permissions"
        public static let screenRecording = "Screen Recording"
        public static let screenRecordingDetail = "Required. Records the window you pick."
        public static let accessibility = "Accessibility"
        public static let accessibilityDetail = "Required for exact window sizes."
        public static let allowed = "Allowed"
        public static let openSystemSettings = "Open System Settings…"
        public static let loginItemOnFailed = "Skreenrek couldn't be added to your login items."
        public static let loginItemOffFailed = "Skreenrek couldn't be removed from your login items."
        public static let chooseFolderPrompt = "Choose"

        /// `Skreenrek 0.1.0`.
        public static func version(_ version: String) -> String { "Skreenrek \(version)" }
    }

    /// Every fixed string above, for the copy audit.
    public static let allFixed: [String] = [
        Picker.pick, Picker.alreadyOpen, Picker.hint, Picker.escape, Picker.cancel, HUD.stop, HUD.showDetails, HUD.dismiss,
        Onboarding.title, Onboarding.introduction, Onboarding.accessibilityNote, Onboarding.continueButton,
        Onboarding.agentsTitle, Onboarding.agentsIntroduction, Onboarding.skip, Onboarding.connect,
        Onboarding.cliDetail, Onboarding.notInstalled,
        Agents.title, Agents.connect, Agents.remove,
        productName, Icon.idle, Icon.writing, Icon.regionTarget,
        Menu.ready, Menu.noWindowPicked, Menu.pickWindow, Menu.pickAnotherWindow, Menu.size, Menu.frameRate,
        Menu.showCursor, Menu.writeClickEvents, Menu.recordWindow, Menu.lastClip, Menu.showInFinder,
        Menu.copyFilePath, Menu.copySnippet, Menu.openOutputFolder, Menu.settings, Menu.quit, Menu.stopRecording,
        Menu.discardRecording, Menu.savingClip, Menu.region, Menu.keepCurrentSize, Menu.customSize, Menu.portrait,
        Menu.square, Menu.exactSize, Menu.notExact,
        Menu.startedFromMenu, Menu.startedFromCommandLine, Menu.startedOverMCP,
        Errors.recordingStopped, Errors.screenRecordingOff, Errors.screenRecordingDetail, Errors.cantResize,
        Errors.cantResizeDetail, Errors.notExact, Errors.couldntSave, Errors.somethingWentWrong,
        Errors.copyErrorDetails, Errors.openPrivacySettings, Errors.openAccessibilitySettings, Errors.pickAnotherSize,
        Errors.chooseOutputFolder,
        Alerts.discardTitle, Alerts.discardMessage, Alerts.discard, Alerts.cancel, Alerts.quitTitle,
        Alerts.stopAndQuit,
        CustomSize.title, CustomSize.width, CustomSize.height, CustomSize.px, CustomSize.times, CustomSize.setSize,
        CustomSize.cancel,
        CustomSize.enterSize,
        Settings.windowTitle, Settings.outputFolder, Settings.choose, Settings.defaultFrameRate, Settings.showCursor,
        Settings.writeClickEvents, Settings.showRecordingIndicator, Settings.openAtLogin, Settings.stopShortcut,
        Settings.stopShortcutKeys, Settings.permissions, Settings.screenRecording, Settings.screenRecordingDetail,
        Settings.accessibility, Settings.accessibilityDetail, Settings.allowed, Settings.openSystemSettings,
        Settings.loginItemOnFailed, Settings.loginItemOffFailed, Settings.chooseFolderPrompt,
    ]
}
