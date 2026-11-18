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
            case .permissionDenied(.directCapture): "direct capture isn't approved"
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
        public static let showControlBar = "Show Control Bar"
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

        public static let currentSize = "Current Size"
        public static let customSize = "Custom…"

        /// The Size submenu's trailing values and the custom Size row: `1920 × 1080` (no unit).
        public static func dimensions(_ size: PixelSize) -> String { "\(size.width) × \(size.height)" }

        /// Shown whenever Screen Recording or Accessibility is missing, even after onboarding; opens onboarding step 1.
        public static let permissionsNeeded = "Permissions needed…"

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

        /// The detail lines join their parts with a middle dot.
        public static let separator = " · "
    }

    /// Copy the menu panel adds. Everything else is reused from the menu strings above.
    public enum Panel {
        /// A size that isn't a spec 13 preset. The exact px stays on the caption line.
        public static let custom = "Custom"
        public static let previewUnavailable = "Preview unavailable"
        public static let openSettings = "Open Settings…"
        public static let windowClosed = "Window closed"
        public static let clipMissing = "Clip moved or deleted"
        /// VoiceOver when the clip file is gone.
        public static let clipMissingLabel = "Last clip, moved or deleted"
        /// Tooltip on the Last Clip main area.
        public static let openClip = "Open Clip"
        /// The compact header when nothing is picked.
        public static let noWindow = "No window"
        public static let pickWindowToRecord = "Pick a window to record"
        /// The Clear button's tooltip.
        public static let clearWindow = "Clear Window"
        /// The Clear button for VoiceOver.
        public static let clearPickedWindow = "Clear picked window"
        /// Tooltip and VoiceOver on the failed preview. Recording still works.
        public static let previewFailedHelp =
            "Skreenrek couldn't take a preview of this window. Recording still works."
        /// The Stop button's tooltip. ⌃⌘⎋ stays the global stop.
        public static let stopHelp = "Stop Recording (⌃⌘⎋)"

        /// The compact header for VoiceOver.
        public static var noWindowLabel: String { "\(Menu.noWindowPicked). \(pickWindowToRecord)." }

        /// `Picked Safari — localhost:3000`: VoiceOver, after a pick.
        public static func picked(_ title: String) -> String { "Picked \(title)" }

        /// `Open last clip, Safari — localhost:3000, 42 seconds`.
        public static func openLastClip(title: String, seconds: Int) -> String {
            "Open last clip, \(title), \(Icon.spokenDuration(seconds))"
        }

        /// `Safari — localhost:3000, 1920 by 1080 pixels, 60 frames per second`.
        public static func spokenCaption(title: String, size: PixelSize, fps: FrameRate) -> String {
            "\(title), \(size.width) by \(size.height) pixels, \(fps.framesPerSecond) frames per second"
        }

        /// `Size, 1080p`. VoiceOver adds "pop-up button".
        public static func popupLabel(title: String, value: String) -> String {
            "\(title), \(value)"
        }
    }

    /// Copy for the bar under the picked window. Everything else it shows is reused.
    public enum ControlBar {
        public static let sizeHelp = "Clip size. Skreenrek resizes the window to fit."
        public static let recordHelp = "Record this window."
        public static let outputFolderNotWritable =
            "The output folder isn't writable. Choose another folder in Settings."
        public static let accessibilityOff =
            "Skreenrek can't resize windows without Accessibility. Recording at the current size."
        public static var directCaptureBlocked: String {
            "\(Errors.directCaptureOff). \(Errors.directCaptureDetail)"
        }

        /// `Skreenrek controls for Safari — localhost:3000`: VoiceOver, for the whole bar.
        public static func group(_ title: String) -> String { "Skreenrek controls for \(title)" }

        /// `Records Safari — localhost:3000.`
        public static func recordHint(_ title: String) -> String { "Records \(title)." }

        /// `The clip will be 1920 × 1080 px. The window is 1440 × 810 pt on screen.`
        public static func readoutHelp(clip: PixelSize, window: WindowPoints) -> String {
            "The clip will be \(clip). The window is \(window) pt on screen."
        }

        /// `1920 by 1080 pixels`.
        public static func spokenSize(_ size: PixelSize) -> String { "\(size.width) by \(size.height) pixels" }
    }

    // MARK: - Error rows (the design spec's error-copy table)

    public enum Errors {
        public static let recordingStopped = "Recording stopped"
        public static let screenRecordingOff = "Screen Recording is off"
        public static let screenRecordingDetail =
            "Allow Skreenrek in System Settings › Privacy & Security, then reopen it."
        public static let directCaptureOff = "Direct capture isn't approved"
        public static let directCaptureDetail = "Finish setup so macOS asks about its private window picker first."
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
        public static let tooLarge = "Too large for this display."

        /// `Window on screen: 1440 × 810`.
        public static func windowOnScreen(_ window: WindowPoints) -> String { "Window on screen: \(window)" }
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
        public static let introduction = "Skreenrek records windows for your coding agents. It needs three permissions. Everything stays on this Mac."
        public static let accessibilityNote = "Without Accessibility you can still record, but windows keep their current size."
        public static let continueButton = "Continue"
        public static let done = "Done"
        public static let quitAndReopen = "Quit & Reopen"
        /// macOS applies a Screen Recording grant only to a new process, so the running app keeps reading "missing".
        public static let relaunchNote =
            "After you allow Skreenrek in System Settings, quit and reopen it so macOS applies the change."

        /// The direct-capture step: macOS 15's "bypass the system private window picker" prompt.
        public static let directCapture = "Direct Capture"
        public static let directCaptureDetail = "Required. Skips the system window picker."

        /// What each step's button asks macOS for, and the sentence under the row.
        public static func allow(_ permission: Permission) -> String {
            switch permission {
            case .screenRecording: "Allow Screen Recording"
            case .directCapture: "Allow Direct Capture"
            case .accessibility: "Allow Accessibility"
            }
        }
        public static let askAgain = "Ask Again"
        /// VoiceOver, for a permission in the step progress that isn't allowed yet.
        public static let notAllowed = "Not allowed"
        public static func explanation(_ permission: Permission) -> String {
            switch permission {
            case .screenRecording:
                "macOS asks once. Turn on Skreenrek in System Settings, then quit and reopen it."
            case .directCapture:
                "macOS asks if Skreenrek can skip its private window picker. Click Allow. It asks again about once a month."
            case .accessibility:
                accessibilityNote
            }
        }
        /// The direct-capture step before Screen Recording is in effect.
        public static let directCaptureWaiting = "Allow Screen Recording first."

        public static let agentsTitle = "Connect your agents"
        public static let agentsIntroduction = "Adds the Skreenrek MCP server and the record-window skill to each agent you pick. You can change this later in Settings."
        public static let skip = "Skip"
        public static let connect = "Connect"
        public static let cliDetail = "Links skreenrek into ~/.local/bin"
        public static let notInstalled = "Not installed"
        public static func found(_ agent: AgentClient) -> String { "Found ~/.\(agent.rawValue)" }
        public static func step(_ number: Int, of total: Int) -> String { "Step \(number) of \(total)" }
    }

    // MARK: - Settings

    public enum Agents {
        public static let title = "Agents"
        public static let connect = "Connect"
        public static let remove = "Remove"
        public static let footer = "Connect adds the Skreenrek MCP server and the record-window skill."

        /// `Install Cursor first.`
        public static func installFirst(_ agent: String) -> String { "Install \(agent) first." }
    }

    public enum Settings {
        public static let outputFolder = "Output folder"
        public static let choose = "Choose…"
        public static let defaultFrameRate = "Default frame rate"
        public static let showCursor = "Show cursor in video"
        public static let writeClickEvents = "Write click events"
        public static let showRecordingIndicator = "Show recording indicator"
        public static let showControlBar = "Show control bar"
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
        public static let general = "General"
        public static let recording = "Recording"
        public static let about = "About"
        public static let viewOnGitHub = "View on GitHub"
        public static let screenRecordingNotAllowed = "Screen Recording isn't allowed. Skreenrek can't record until you allow it."
        public static let accessibilityNotAllowed =
            "Accessibility isn't allowed. Skreenrek can record, but windows keep their current size."

        /// `Updates, Skreenrek 1.0.5 is up to date.`
        public static func updatesLabel(_ detail: String) -> String { "\(Updates.title), \(detail)" }
        /// `Screen Recording, allowed.`
        public static func permissionAllowedLabel(_ title: String) -> String { "\(title), allowed." }
        /// `Accessibility, required for exact window sizes, not allowed, Open System Settings…`. VoiceOver adds
        /// "button".
        public static func permissionMissingLabel(_ title: String, detail: String) -> String {
            var requirement = detail.replacingOccurrences(of: "Required. ", with: "")
            requirement = requirement.replacingOccurrences(of: "Required for", with: "required for")
            while requirement.hasSuffix(".") { requirement.removeLast() }
            return "\(title), \(requirement), not allowed, \(openSystemSettings)"
        }
    }

    // MARK: - Updates

    public enum Updates {
        public static let title = "Updates"
        public static let checkForUpdates = "Check for Updates"
        public static let checking = "Checking…"
        public static let update = "Update"
        public static let download = "Download…"
        public static let retry = "Retry"
        public static let relaunch = "Relaunch"
        public static let openReleasePage = "Open Release Page"
        public static let failed = "Couldn't check for updates."
        public static let installing = "Updating with Homebrew…"
        public static let installFailed = "Homebrew couldn't update Skreenrek."
        /// The dropdown's footer line while a newer release waits.
        public static let menuAvailable = "Update available"
        /// The Settings disclosure that shows the newer release's notes.
        public static let whatsNew = "What's new"

        /// `Skreenrek 1.0.2`, before the first check.
        public static func currentVersion(_ version: String) -> String { "Skreenrek \(version)" }
        /// `Skreenrek 1.0.2 is up to date.`
        public static func upToDate(_ version: String) -> String { "Skreenrek \(version) is up to date." }
        /// `Skreenrek 1.0.3 is available. You have 1.0.2.`
        public static func available(_ version: String, current: String) -> String {
            "Skreenrek \(version) is available. You have \(current)."
        }
        /// `Skreenrek 1.0.3 is installed. Relaunch to use it.`
        public static func installed(_ version: String) -> String {
            "Skreenrek \(version) is installed. Relaunch to use it."
        }
    }

    // MARK: - Dropdown header, Last Clip row and the project link

    /// Copy the branded dropdown and Settings add. The menu and Settings copy above is reused unchanged.
    public enum Brand {
        public static let repoURL = "https://github.com/R4ph-t/skreenrek"
        public static let repoHelp = "Open the Skreenrek project on GitHub."
        public static let thumbnailLabel = "The first frame of the last clip."
        /// The header's compact controls.
        public static let record = "Record"
        public static let stop = "Stop"

        /// `Stop Recording, 12 seconds`: the header's Stop button for VoiceOver.
        public static func stopLabel(seconds: Int) -> String {
            "\(Menu.stopRecording), \(Icon.spokenDuration(seconds))"
        }

        /// `Not exact: Safari won't go narrower than 1286 px, so the clip is 1286 × 800 instead of 1280 × 800.`
        public static func notExactReason(
            app: String, reason: NotExactReason, requested: PixelSize, actual: PixelSize
        ) -> String {
            let limit: String
            switch reason {
            case .minWidth(let px): limit = "won't go narrower than \(px) px"
            case .minHeight(let px): limit = "won't go shorter than \(px) px"
            case .maxWidth(let px): limit = "won't go wider than \(px) px"
            case .maxHeight(let px): limit = "won't go taller than \(px) px"
            case .steps: limit = "resizes in steps"
            }
            return "Not exact: \(app) \(limit), so the clip is \(actual.width) × \(actual.height) instead of "
                + "\(requested.width) × \(requested.height)."
        }

        /// `Recording Safari — localhost:3000, 12 seconds`: the header's VoiceOver label while recording.
        public static func recordingLabel(target: String, seconds: Int) -> String {
            "Recording \(target), \(Icon.spokenDuration(seconds))"
        }
    }

    /// Every fixed string above, for the copy audit.
    public static let allFixed: [String] = [
        Picker.pick, Picker.alreadyOpen, Picker.hint, Picker.escape, Picker.cancel, HUD.stop, HUD.showDetails, HUD.dismiss,
        Onboarding.title, Onboarding.introduction, Onboarding.accessibilityNote, Onboarding.continueButton,
        Onboarding.quitAndReopen, Onboarding.relaunchNote, Onboarding.done, Onboarding.directCapture,
        Onboarding.directCaptureDetail, Onboarding.directCaptureWaiting,
        Onboarding.allow(.screenRecording), Onboarding.allow(.directCapture), Onboarding.allow(.accessibility),
        Onboarding.askAgain, Onboarding.notAllowed, Onboarding.explanation(.screenRecording),
        Onboarding.explanation(.directCapture),
        Onboarding.agentsTitle, Onboarding.agentsIntroduction, Onboarding.skip, Onboarding.connect,
        Onboarding.cliDetail, Onboarding.notInstalled,
        Agents.title, Agents.connect, Agents.remove, Agents.footer,
        productName, Icon.idle, Icon.writing, Icon.regionTarget,
        Menu.ready, Menu.noWindowPicked, Menu.pickWindow, Menu.pickAnotherWindow, Menu.size, Menu.frameRate,
        Menu.showCursor, Menu.writeClickEvents, Menu.recordWindow, Menu.lastClip, Menu.showInFinder,
        Menu.copyFilePath, Menu.copySnippet, Menu.openOutputFolder, Menu.settings, Menu.quit, Menu.stopRecording,
        Menu.discardRecording, Menu.savingClip, Menu.region, Menu.currentSize, Menu.customSize,
        Menu.notExact, Menu.permissionsNeeded,
        Menu.startedFromMenu, Menu.startedFromCommandLine, Menu.startedOverMCP,
        Errors.recordingStopped, Errors.screenRecordingOff, Errors.screenRecordingDetail, Errors.cantResize,
        Errors.cantResizeDetail, Errors.notExact, Errors.couldntSave, Errors.somethingWentWrong,
        Errors.copyErrorDetails, Errors.openPrivacySettings, Errors.openAccessibilitySettings, Errors.pickAnotherSize,
        Errors.chooseOutputFolder, Errors.directCaptureOff, Errors.directCaptureDetail,
        Alerts.discardTitle, Alerts.discardMessage, Alerts.discard, Alerts.cancel, Alerts.quitTitle,
        Alerts.stopAndQuit,
        CustomSize.title, CustomSize.width, CustomSize.height, CustomSize.px, CustomSize.times, CustomSize.setSize,
        CustomSize.cancel,
        CustomSize.enterSize, CustomSize.tooLarge,
        Settings.outputFolder, Settings.choose, Settings.defaultFrameRate, Settings.showCursor,
        Settings.writeClickEvents, Settings.showRecordingIndicator, Settings.openAtLogin, Settings.stopShortcut,
        Settings.stopShortcutKeys, Settings.permissions, Settings.screenRecording, Settings.screenRecordingDetail,
        Settings.accessibility, Settings.accessibilityDetail, Settings.allowed, Settings.openSystemSettings,
        Settings.loginItemOnFailed, Settings.loginItemOffFailed, Settings.chooseFolderPrompt, Settings.general,
        Settings.recording, Settings.about, Settings.viewOnGitHub,
        Settings.screenRecordingNotAllowed, Settings.accessibilityNotAllowed,
        Brand.repoHelp, Brand.thumbnailLabel, Brand.record, Brand.stop,
        Panel.custom, Panel.previewUnavailable, Panel.openSettings, Panel.windowClosed, Panel.clipMissing,
        Panel.clipMissingLabel, Panel.openClip, Panel.previewFailedHelp, Panel.stopHelp, Panel.noWindow,
        Panel.pickWindowToRecord, Panel.clearWindow, Panel.clearPickedWindow, Panel.noWindowLabel,
        Updates.title, Updates.checkForUpdates, Updates.checking, Updates.update, Updates.download, Updates.retry,
        Updates.relaunch, Updates.openReleasePage, Updates.failed, Updates.installing, Updates.installFailed,
        Updates.menuAvailable, Updates.whatsNew,
        Menu.showControlBar, Settings.showControlBar, ControlBar.sizeHelp, ControlBar.recordHelp,
        ControlBar.outputFolderNotWritable, ControlBar.directCaptureBlocked, ControlBar.accessibilityOff,
    ]
}
