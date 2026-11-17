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
    func copy(_ text: String)
    func openSettings()
    /// Opens onboarding on step 1 (the permissions), even after onboarding was completed.
    func showPermissions()
    /// The "Discard this recording?" alert; true for Discard.
    func confirmDiscard() async -> Bool
    func chooseFolder(current: URL) async -> URL?
    /// The custom size panel; nil when cancelled. `scale` is the display's, for the points caption.
    func askCustomSize(current: PixelSize?, scale: Double) async -> PixelSize?
    /// The backing scale of a display (the main one when nil).
    func scale(of display: DisplayID?) -> Double
    func quit()
}

/// The System Settings panes the Privacy fix items open. Opening a pane is not a permission prompt.
public enum PrivacyPane {
    public static func url(_ permission: Permission) -> URL {
        switch permission {
        case .screenRecording:
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
            sizeChoice: settings.sizeChoice, cursor: settings.cursor, events: settings.events,
            permissionsMissing: permissions.map { $0.screenRecording != .allowed || $0.accessibility != .allowed }
                ?? false)
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
            await run { _ = try await self.controller.pick() }
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
        case .chooseSize(let choice):
            await clearErrors()
            await chooseSize(choice)
        case .customSize:
            await clearErrors()
            let scale = effects.scale(of: snapshot.displayId)
            guard let size = await effects.askCustomSize(current: settings.sizeChoice.pixelSize, scale: scale) else {
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

    /// Records the picked window, resizing it first to the chosen size unless it already has that read-back.
    private func record() async {
        var params = StartParams()
        if snapshot.window != nil, let size = settings.sizeChoice.pixelSize, snapshot.readback?.requested != size {
            params.width = size.width
            params.height = size.height
        }
        await run { _ = try await self.controller.start(params, startedBy: .menu) }
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
