import Foundation
import Observation
import SkreenrekControl
import SkreenrekCore
import os

/// What the menu needs from the system: Finder, the pasteboard, panels and alerts. The app passes `SystemEffects`;
/// tests pass a recorder.
@MainActor
public protocol UIEffects: AnyObject {
    func revealInFinder(_ path: String)
    func open(_ url: URL)
    /// Opens a clip in the default player. The panel injects this; tests record the URL.
    func openClip(at url: URL)
    func copy(_ text: String)
    func openSettings()
    /// Opens Settings on General, where the Updates row is.
    func showUpdates()
    /// Opens onboarding on step 1 (the permissions), even after onboarding was completed.
    func showPermissions()
    /// The "Discard this recording?" alert; true for Discard.
    func confirmDiscard() async -> Bool
    func chooseFolder(current: URL) async -> URL?
    /// The Custom Size panel; nil when cancelled. `display` is where the window would go, for the live line.
    func askCustomSize(current: PixelSize?, display: DisplayInfo?) async -> PixelSize?
    /// The main display, for checking sizes when nothing is picked.
    func mainDisplay() -> DisplayInfo?
    func quit()
}

/// The System Settings panes the Privacy fix items open. Opening a pane is not a permission prompt.
public enum PrivacyPane {
    public static func url(_ permission: Permission) -> URL {
        switch permission {
        // macOS 15 lists the private window picker bypass in the same Screen & System Audio Recording pane.
        case .screenRecording, .directCapture:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        }
    }
}

/// Remembers the target of the recording that produced the last clip, for the Last Clip row's title.
public struct LastClipTracker: Sendable, Hashable {
    private var recordingTitle: String?
    public private(set) var clipId: String?
    public private(set) var title: String?

    public init() {}

    public mutating func observe(_ snapshot: ControllerSnapshot) {
        let context = MenuContext(snapshot: snapshot)
        if snapshot.state == .recording || snapshot.state == .writing, let target = context.targetTitle {
            recordingTitle = target
        }
        guard let clip = snapshot.lastClip else { return }
        if clip.recording.id != clipId {
            clipId = clip.recording.id
            title = recordingTitle
            recordingTitle = nil
        }
    }
}

/// The menu bar's state and actions. It owns no capture: every action goes through the controller.
@MainActor
@Observable
public final class AppModel {
    private static let log = Logger(subsystem: "it.fraime.skreenrek", category: "menu")

    @ObservationIgnored public let controller: SkreenrekController
    @ObservationIgnored public let settings: SettingsStore
    @ObservationIgnored private let effects: any UIEffects
    @ObservationIgnored private let permissions: (any PermissionProbe)?
    @ObservationIgnored private var tracker = LastClipTracker()
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var errorShownWhenOpened = false
    /// Called on the main actor after every change the menu or the icon shows.
    @ObservationIgnored public var onChange: (() -> Void)?

    public private(set) var snapshot: ControllerSnapshot
    public private(set) var actionError: SkreenrekError?
    public private(set) var menuOpen = false
    /// A preset chosen from the control bar, while it resizes and after a refusal.
    public private(set) var barResize = ControlBarResize.none
    /// Record was clicked and the recorder isn't running yet.
    public private(set) var recordStarting = false
    @ObservationIgnored private var refusals = 0
    /// A newer release's version, from `UpdateChecker`, for the dropdown's footer line.
    public var updateAvailable: String? {
        didSet { if updateAvailable != oldValue { onChange?() } }
    }

    public init(
        controller: SkreenrekController, settings: SettingsStore, effects: any UIEffects,
        permissions: (any PermissionProbe)? = nil
    ) {
        self.controller = controller
        self.settings = settings
        self.effects = effects
        self.permissions = permissions
        self.snapshot = ControllerSnapshot(state: .idle, fps: settings.fps)
    }

    public var context: MenuContext {
        MenuContext(
            snapshot: snapshot, actionError: actionError, lastClipTitle: tracker.title,
            sizeChoice: settings.sizeChoice, display: snapshot.display ?? effects.mainDisplay(),
            cursor: settings.cursor, events: settings.events, showControlBar: settings.showControlBar,
            permissionsMissing: permissions.map { !$0.canCapture || $0.accessibility != .allowed }
                ?? false,
            updateAvailable: updateAvailable)
    }

    public var icon: StatusIcon { StatusIconModel.icon(for: context) }
    public var entries: [MenuEntry] { MenuModel.entries(for: context) }

    /// The ⌃⌘⎋ hot key is registered only while a recording runs.
    public var wantsStopHotKey: Bool { snapshot.state == .recording }

    /// Pushes the settings to the controller and follows its snapshots until `stop()`.
    public func start() async {
        await controller.updateSettings(settings.controllerSettings)
        let stream = await controller.snapshots()
        tasks.append(
            Task { [weak self] in
                for await snapshot in stream {
                    guard let self else { return }
                    self.apply(snapshot)
                }
            })
    }

    public func stop() {
        for task in tasks { task.cancel() }
        tasks = []
    }

    public func apply(_ snapshot: ControllerSnapshot) {
        tracker.observe(snapshot)
        self.snapshot = snapshot
        onChange?()
    }

    /// Refreshes the elapsed time while recording (once a second, from the menu's timer).
    public func tick() async {
        let fresh = await controller.snapshot()
        guard fresh.state == snapshot.state else { return }
        apply(fresh)
    }

    // MARK: - Menu open and close

    public func menuWillOpen() {
        menuOpen = true
        errorShownWhenOpened = context.error != nil
    }

    /// The error state clears after the menu is opened and closed once.
    public func menuDidClose() async {
        menuOpen = false
        guard errorShownWhenOpened else { return }
        errorShownWhenOpened = false
        await clearErrors()
    }

    private func clearErrors() async {
        let hadControllerError = snapshot.error != nil
        if actionError != nil {
            actionError = nil
            onChange?()
        }
        if hadControllerError { await controller.dismissError() }
    }

    // MARK: - Actions

    public func perform(_ action: MenuAction) async {
        switch action {
        case .pickWindow:
            await clearErrors()
            await run {
                // Spec 13: a picked window keeps its current size until a preset is chosen.
                if case .window = try await self.controller.pick() { self.settings.sizeChoice = .keepCurrent }
            }
        case .clearWindow:
            // Size and Frame Rate keep their values, and the window keeps its current size.
            await clearErrors()
            await run { try await self.controller.forgetTarget() }
        case .record:
            await clearErrors()
            await record()
        case .stop:
            // A failed recording keeps its error in the controller, which the menu shows; nothing else to do here.
            _ = try? await controller.stop()
        case .discard:
            guard await effects.confirmDiscard() else { return }
            _ = try? await controller.discard()
        case .openOutputFolder:
            try? FileManager.default.createDirectory(at: settings.outputFolder, withIntermediateDirectories: true)
            effects.open(settings.outputFolder)
        case .openSettings:
            effects.openSettings()
        case .showUpdate:
            effects.showUpdates()
        case .showPermissions:
            effects.showPermissions()
        case .quit:
            effects.quit()
        case .toggleCursor:
            settings.cursor.toggle()
            await pushSettings()
        case .toggleEvents:
            settings.events.toggle()
            await pushSettings()
        case .toggleControlBar:
            settings.showControlBar.toggle()
            onChange?()
        case .chooseSize(let choice):
            await clearErrors()
            await chooseSize(choice)
        case .customSize:
            await clearErrors()
            let display = snapshot.display ?? effects.mainDisplay()
            guard let size = await effects.askCustomSize(current: settings.sizeChoice.pixelSize, display: display)
            else {
                return
            }
            await chooseSize(.size(size))
        case .chooseFrameRate(let rate):
            settings.fps = rate
            await pushSettings()
        case .showInFinder(let path):
            effects.revealInFinder(path)
        case .copyFilePath(let path):
            effects.copy(path)
        case .copySnippet(let snippet):
            effects.copy(snippet)
        case .openClip(let path):
            effects.openClip(at: URL(fileURLWithPath: path))
        case .copyErrorDetails(let details):
            effects.copy(details)
        case .openPrivacySettings(let permission):
            effects.open(PrivacyPane.url(permission))
        case .chooseOutputFolder:
            await clearErrors()
            guard let folder = await effects.chooseFolder(current: settings.outputFolder) else { return }
            settings.outputFolder = folder
            await pushSettings()
        }
    }

    /// Choosing a size while a window is picked resizes it now and reads it back; otherwise it's the size for the
    /// next recording.
    private func chooseSize(_ choice: SizeChoice) async {
        settings.sizeChoice = choice
        onChange?()
        guard let size = choice.pixelSize, snapshot.window != nil, context.isArmed else { return }
        await run { _ = try await self.controller.resize(query: nil, size: size, allowInexact: true) }
    }

    /// A preset from the control bar: the same exact resize as the CLI. A window that keeps its size puts the previous
    /// choice back, and the bar shows why instead of the menu's error state. `currentFrame` is where the window is now.
    public func chooseBarSize(_ size: PixelSize, currentFrame: PointRect?) async {
        guard barResize != .resizing, snapshot.window != nil, context.isArmed else { return }
        let previous = settings.sizeChoice
        settings.sizeChoice = .size(size)
        barResize = .resizing
        onChange?()
        await clearErrors()
        var refusal: String?
        do {
            let readback = try await controller.resize(query: nil, size: size, allowInexact: true)
            if !readback.exact, let currentFrame, readback.frame.width == currentFrame.width,
                readback.frame.height == currentFrame.height
            {
                refusal = UIStrings.Menu.notExactReason(
                    app: readback.window.app, requested: readback.requested, actual: readback.actual,
                    reason: ExactResizer.reason(requested: readback.requested, actuals: [readback.actual]))
            }
        } catch {
            let failure = error as? SkreenrekError ?? .internal(message: error.localizedDescription)
            await controller.reportActionFailure(failure)
            Self.log.info("Control bar resize failed: \(failure.code, privacy: .public)")
            refusal = ErrorPresentation(failure, lastClip: nil).row.detail
        }
        apply(await controller.snapshot())
        if let refusal {
            settings.sizeChoice = previous
            refusals += 1
            barResize = .refused(sequence: refusals, reason: refusal)
        } else {
            barResize = .none
        }
        onChange?()
    }

    /// Records the picked window, resizing it first to the chosen size unless it already has that read-back. With the
    /// control bar on, the window stays picked afterwards, so the bar goes back to Record.
    private func record() async {
        var params = StartParams()
        if snapshot.window != nil, let size = settings.sizeChoice.pixelSize, snapshot.readback?.requested != size {
            params.width = size.width
            params.height = size.height
        }
        let keepPicked = settings.showControlBar && snapshot.window != nil
        recordStarting = true
        onChange?()
        await run {
            _ = try await self.controller.start(params, startedBy: .menu, keepWindowPicked: keepPicked)
        }
        recordStarting = false
        onChange?()
    }

    /// Settings changed in the Settings window or the menu: the controller takes the new defaults.
    public func pushSettings() async {
        await controller.updateSettings(settings.controllerSettings)
        onChange?()
    }

    private func run(_ body: () async throws -> Void) async {
        do {
            try await body()
        } catch let error as SkreenrekError {
            await controller.reportActionFailure(error)
            Self.log.info("Menu action failed: \(error.code, privacy: .public)")
            actionError = error
            onChange?()
        } catch {
            actionError = .internal(message: error.localizedDescription)
            onChange?()
        }
    }

    // MARK: - Quit

    public enum QuitDecision: Sendable, Equatable {
        case now
        /// "Stop and save the recording before quitting?"
        case askToStop
        /// The clip is being written: wait for it, then quit.
        case afterWriting
    }

    public var quitDecision: QuitDecision {
        switch snapshot.state {
        case .recording: .askToStop
        case .writing: .afterWriting
        default: .now
        }
    }

    /// Stops and saves (or waits for the clip being written), for Stop and Quit.
    public func finishForQuit() async {
        switch snapshot.state {
        case .recording: _ = try? await controller.stop()
        case .writing: _ = try? await controller.waitForEnd()
        default: break
        }
    }
}
