import Foundation
import SkreenrekCore
import os
import Synchronization

/// The one owner of capture state in the app: one recording at a time, no pause.
///
/// States: `idle` → `armed` (a picked target and its last read-back) → `recording` → `writing` → `idle` (with the
/// last clip). `error` holds the last recording failure and clears on the next action (pick, resize, start, stop,
/// discard, or `dismissError()`). Every capture and resize goes through here; the CLI, MCP and menu only call it.
///
/// It is an actor off the main thread, so a busy UI never delays recording (the mouse monitors stamp clicks with
/// `clock.now()` on the main thread, so the main actor must stay free while recording).
public actor SkreenrekController {
    private static let log = Logger(subsystem: "it.fraime.skreenrek", category: "controller")

    private enum Armed: Sendable {
        case window(ResolvedWindow, readback: Readback?)
        case region(PixelRect, display: DisplayInfo)
    }

    private enum Outcome: Sendable {
        case saved(StopBody)
        case failed(SkreenrekError)
        case discarded
    }

    /// One recording, from a successful start until its outcome is known.
    private final class Active: Sendable {
        let session: RecordingSession
        let events: EventRecorder?
        let target: CaptureTarget
        let display: DisplayInfo
        let size: PixelSize
        let options: RecordingOptions
        let origin: RecordingOrigin
        let readback: Readback?
        let recordingId: String
        let startedAt: Date
        let startHostTime: TimeInterval
        private let endTask = Mutex<Task<Outcome, Never>?>(nil)

        init(
            session: RecordingSession, events: EventRecorder?, target: CaptureTarget, display: DisplayInfo,
            size: PixelSize, options: RecordingOptions, origin: RecordingOrigin, readback: Readback?,
            recordingId: String, startedAt: Date, startHostTime: TimeInterval
        ) {
            self.session = session
            self.events = events
            self.target = target
            self.display = display
            self.size = size
            self.options = options
            self.origin = origin
            self.readback = readback
            self.recordingId = recordingId
            self.startedAt = startedAt
            self.startHostTime = startHostTime
        }

        var app: String? {
            if case .window(let window) = target { return window.app }
            return nil
        }

        func setEndTask(_ task: Task<Outcome, Never>) { endTask.withLock { $0 = task } }

        var outcome: Outcome {
            get async {
                guard let task = endTask.withLock({ $0 }) else { return .discarded }
                return await task.value
            }
        }
    }

    private enum Phase {
        case idle
        case armed(Armed)
        /// Between a start request and the recorder running; `app` is the window being started, when known.
        case starting(app: String?, previous: Armed?)
        case recording(Active)
        case writing(Active)
    }

    private let seams: ControllerSeams
    private let directory: WindowDirectory
    private let socketPath: String?
    private var settings: ControllerSettings
    private var phase = Phase.idle
    private var error: SkreenrekError?
    private var lastClip: StopBody?
    private var subscribers: [UUID: AsyncStream<ControllerSnapshot>.Continuation] = [:]
    private var lastPublished: ControllerSnapshot?
    private var endWaiters = 0
    /// True while `resize` waits on the window: the actor is reentrant, so this keeps a start, pick or second resize
    /// from slipping in mid-resize.
    private var resizing = false
    private var endWaiterWatchers: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    /// - Parameter socketPath: reported by `doctor`.
    public init(seams: ControllerSeams, settings: ControllerSettings = ControllerSettings(), socketPath: String? = nil) {
        self.seams = seams
        self.directory = WindowDirectory(catalog: seams.catalog, ownPid: seams.ownPid)
        self.settings = settings
        self.socketPath = socketPath
    }

    // MARK: - Settings and snapshots

    public var currentSettings: ControllerSettings { settings }

    public func updateSettings(_ settings: ControllerSettings) {
        self.settings = settings
        publish()
    }

    /// Clears the error state without another action (the menu opened and closed once).
    public func dismissError() {
        error = nil
        publish()
    }

    /// A stream of snapshots: the current one first, then one per change, in order.
    public func snapshots() -> AsyncStream<ControllerSnapshot> {
        let (stream, continuation) = AsyncStream<ControllerSnapshot>.makeStream(bufferingPolicy: .unbounded)
        let id = UUID()
        subscribers[id] = continuation
        continuation.yield(snapshot())
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribe(id) }
        }
        return stream
    }

    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }

    /// The state right now.
    public func snapshot() -> ControllerSnapshot {
        var s = ControllerSnapshot(state: state, fps: settings.fps, lastClip: lastClip, error: error)
        switch phase {
        case .idle:
            break
        case .armed(let armed), .starting(_, let armed?):
            switch armed {
            case .window(let resolved, let readback):
                s.window = resolved.window
                s.displayId = resolved.display.id
                s.size = readback?.actual ?? resolved.pixelSize
                s.readback = readback
            case .region(let rect, let display):
                s.region = rect
                s.displayId = display.id
                s.size = rect.size
            }
        case .starting:
            break
        case .recording(let active), .writing(let active):
            s.elapsed = seams.clock.now() - active.startHostTime
            switch active.target {
            case .window(let window): s.window = window
            case .region(let rect, _): s.region = rect
            }
            s.displayId = active.display.id
            s.size = active.size
            s.readback = active.readback
            s.fps = active.options.fps
            s.startedBy = active.origin.startedBy
            s.client = active.origin.client
        }
        return s
    }

    private var state: ControllerState {
        switch phase {
        case .recording: return .recording
        case .writing: return .writing
        case .armed, .starting(_, _?): return error == nil ? .armed : .error
        case .idle, .starting: return error == nil ? .idle : .error
        }
    }

    private func publish() {
        let snapshot = snapshot()
        var comparable = snapshot
        comparable.elapsed = nil
        var previous = lastPublished
        previous?.elapsed = nil
        guard comparable != previous else { return }
        lastPublished = snapshot
        for continuation in subscribers.values { continuation.yield(snapshot) }
    }

    // MARK: - Windows, pick, resize

    /// Recordable windows, front to back. `app` matches the app name or bundle ID.
    public func windows(app: String? = nil) async throws -> WindowsBody {
        WindowsBody(windows: try await directory.resolvedWindows(app: app).map(WindowEntry.init))
    }

    /// Opens the picker for a human and arms what they pick. Cancelling changes nothing.
    public func pick(timeout: TimeInterval = PickParams.defaultTimeout) async throws -> PickBody {
        clearError()
        try ensureNotBusy()
        let result = try await seams.picker.pick(timeout: timeout)
        switch result {
        case .cancelled:
            return .cancelled
        case .window(let id):
            let resolved = try await directory.resolve(.id(id))
            try ensureNotBusy()
            phase = .armed(.window(resolved, readback: nil))
            publish()
            return .window(WindowEntry(resolved))
        case .region(let rect, let displayId):
            let display = try await regionDisplay(rect, displayId: displayId)
            try ensureNotBusy()
            phase = .armed(.region(rect, display: display))
            publish()
            return .region(PickedRegion(region: rect, displayId: display.id))
        }
    }

    /// Resizes a window to exact pixels and reads it back. `query` nil means the armed window. Without Accessibility
    /// it fails with `permission_denied` and nothing changes.
    public func resize(query: WindowQuery?, size: PixelSize, allowInexact: Bool = false) async throws -> Readback {
        clearError()
        try ensureNotBusy()
        guard seams.permissions.accessibility == .allowed else {
            throw SkreenrekError.permissionDenied(.accessibility)
        }
        resizing = true
        defer { resizing = false }
        let resolved = try await resolveWindow(query)
        let readback = try await ExactResizer(resizer: seams.resizer).resize(
            resolved, to: size, allowInexact: allowInexact)
        if case .armed(.window(let armed, _)) = phase, armed.window.id == resolved.window.id {
            var window = resolved.window
            window.frame = readback.frame
            phase = .armed(.window(ResolvedWindow(window: window, display: resolved.display), readback: readback))
            publish()
        }
        return readback
    }

    // MARK: - Recording

    /// Starts recording: resolve the target → resize first when a size is given (exit 4 unless `allowInexact`) →
    /// Screen Recording check → output folder → recorder with events. Returns once the recorder runs, never waiting
    /// for a frame to be encoded.
    public func start(_ params: StartParams, startedBy: StartedBy, client: String? = nil) async throws -> StartBody {
        clearError()
        try ensureNotBusy()
        let previous: Armed? = if case .armed(let armed) = phase { armed } else { nil }
        let app: String? = params.app ?? {
            if case .window(let resolved, _)? = previous, params.windowQuery == nil, params.region == nil {
                return resolved.window.app
            }
            return nil
        }()
        phase = .starting(app: app, previous: previous)
        do {
            let body = try await performStart(params, previous: previous, startedBy: startedBy, client: client)
            publish()
            return body
        } catch {
            if case .starting = phase { phase = previous.map(Phase.armed) ?? .idle }
            publish()
            throw error
        }
    }

    private func performStart(_ params: StartParams, previous: Armed?, startedBy: StartedBy, client: String?)
        async throws -> StartBody
    {
        let options = try recordingOptions(params, surface: startedBy)
        let size = try requestedSize(params)

        // The target, its display and, for a resize, the read-back. The window frame is fixed here: events map
        // against the frame read back at start.
        var target: CaptureTarget
        var display: DisplayInfo
        var readback: Readback?
        if let region = params.region {
            guard params.windowQuery == nil else {
                throw SkreenrekError.usage(
                    message: "Pass a window or a region, not both.", hint: "Drop windowId and app, or drop region.")
            }
            guard size == nil else {
                throw SkreenrekError.usage(
                    message: "A region already has its size, so it can't be resized.",
                    hint: "Drop width and height, or record a window.")
            }
            display = try await regionDisplay(region.rect, displayId: params.displayId)
            target = .region(region.rect, displayId: display.id)
        } else if params.windowQuery == nil, case .region(let rect, let armedDisplay)? = previous {
            guard size == nil else {
                throw SkreenrekError.usage(
                    message: "A region already has its size, so it can't be resized.",
                    hint: "Drop width and height, or record a window.")
            }
            display = armedDisplay
            target = .region(rect, displayId: armedDisplay.id)
        } else {
            var resolved = try await resolveWindow(params.windowQuery)
            if let size {
                guard seams.permissions.accessibility == .allowed else {
                    throw SkreenrekError.permissionDenied(.accessibility)
                }
                let result = try await ExactResizer(resizer: seams.resizer).resize(
                    resolved, to: size, allowInexact: params.allowInexact ?? false)
                resolved.window.frame = result.frame
                readback = result
            }
            display = resolved.display
            target = .window(resolved.window)
        }
        let outputSize: PixelSize =
            switch target {
            case .window(let window): window.pixelSize(on: display)
            case .region(let rect, _): rect.size
            }

        guard seams.permissions.screenRecording == .allowed else {
            throw SkreenrekError.permissionDenied(.screenRecording)
        }

        let startedAt = Date()
        let folder = try OutputFolder.create(
            in: options.outDir ?? settings.outputFolder, target: target, name: options.name, date: startedAt)
        let origin = RecordingOrigin(startedBy: startedBy, client: startedBy == .mcp ? client : nil)

        var events: EventRecorder?
        if options.events {
            let recorder = EventRecorder(source: seams.mouse, target: target, display: display, fps: options.fps)
            do {
                try await recorder.start()
            } catch {
                try? FileManager.default.removeItem(at: folder)
                throw (error as? SkreenrekError)
                    ?? SkreenrekError.internal(message: "Couldn't watch the mouse: \(error.localizedDescription)")
            }
            events = recorder
        }
        var onSlot: (@Sendable (SlotTick) -> Void)?
        if let recorder = events {
            onSlot = { tick in
                if tick.index == 0 { recorder.firstFrame(hostTime: tick.firstFrameHostTime) }
                recorder.sample(hostTime: tick.hostTime)
            }
        }
        let session = RecordingSession(
            source: seams.frameSource, clock: seams.clock, disk: seams.disk, encoder: seams.encoder,
            realTimeWriter: seams.realTimeWriter, makeSink: seams.makeSink, onSlot: onSlot)
        let startHostTime = seams.clock.now()
        do {
            try await session.start(
                target: target, size: outputSize, options: options, folder: folder, origin: origin,
                startedAt: startedAt)
        } catch {
            _ = await events?.stop()
            try? FileManager.default.removeItem(at: folder)
            throw error
        }

        let active = Active(
            session: session, events: events, target: target, display: display, size: outputSize, options: options,
            origin: origin, readback: readback, recordingId: folder.lastPathComponent, startedAt: startedAt,
            startHostTime: startHostTime)
        active.setEndTask(Task { await self.end(active) })
        phase = .recording(active)
        Self.log.info("Recording \(active.recordingId, privacy: .public) started by \(startedBy.rawValue, privacy: .public)")
        return StartBody(
            recordingId: active.recordingId, startedAt: EventsFile.timestamp(startedAt), readback: readback,
            fps: options.fps.framesPerSecond, video: try options.resolvedOutput())
    }

    /// Stops the recording and writes the clip, events and snippet. Stopping while the clip is being written waits for
    /// it. A recording that failed (window closed, disk low, write failed) throws `recording_failed`; its partial clip
    /// is in `last()`.
    public func stop() async throws -> StopBody {
        clearError()
        switch phase {
        case .recording(let active):
            _ = try? await active.session.stop()
            return try Self.body(await active.outcome)
        case .writing(let active):
            return try Self.body(await active.outcome)
        default:
            throw SkreenrekError.wrongState(.notRecording)
        }
    }

    /// Stops and deletes the recording.
    public func discard() async throws -> DiscardBody {
        clearError()
        switch phase {
        case .recording(let active):
            await active.session.discard()
            _ = await active.outcome
            return DiscardBody()
        case .writing:
            throw SkreenrekError.wrongState(.stillWriting)
        default:
            throw SkreenrekError.wrongState(.notRecording)
        }
    }

    /// Waits until the recording ends by any means and returns what `stop()` would (or `{ discarded: true }`).
    public func waitForEnd() async throws -> EndBody {
        switch phase {
        case .recording(let active), .writing(let active):
            endWaiters += 1
            let ready = endWaiterWatchers.filter { $0.count <= endWaiters }
            endWaiterWatchers.removeAll { $0.count <= endWaiters }
            for watcher in ready { watcher.continuation.resume() }
            let outcome = await active.outcome
            endWaiters -= 1
            switch outcome {
            case .saved(let body): return .saved(body)
            case .failed(let error): throw error
            case .discarded: return .discarded
            }
        default:
            throw SkreenrekError.wrongState(.notRecording)
        }
    }

    /// Callers waiting in `waitForEnd()` right now.
    public var endWaiterCount: Int { endWaiters }

    /// Returns once at least `count` callers wait in `waitForEnd()` (tests use it instead of polling).
    public func waitForEndWaiters(_ count: Int = 1) async {
        if endWaiters >= count { return }
        await withCheckedContinuation { endWaiterWatchers.append((count, $0)) }
    }

    private static func body(_ outcome: Outcome) throws -> StopBody {
        switch outcome {
        case .saved(let body): return body
        case .failed(let error): throw error
        case .discarded: throw SkreenrekError.wrongState(.notRecording)
        }
    }

    /// Runs once per recording: waits for the recorder to end, then writes events.json and the snippet.
    private func end(_ active: Active) async -> Outcome {
        let result = await active.session.waitForEnd()
        if result.stopReason == .discarded {
            _ = await active.events?.stop()
            phase = .idle
            publish()
            return .discarded
        }
        phase = .writing(active)
        publish()
        let log = await active.events?.stop()
        let outcome = writeArtifacts(result, active: active, log: log)
        switch outcome {
        case .saved(let body):
            lastClip = body
            error = result.error
        case .failed(let failure):
            error = failure
        case .discarded:
            break
        }
        phase = .idle
        publish()
        if let error = result.error, case .saved = outcome { return .failed(error) }
        return outcome
    }

    private func writeArtifacts(_ result: RecordingResult, active: Active, log: EventLog?) -> Outcome {
        guard result.stats.slotsWritten > 0 else {
            try? FileManager.default.removeItem(at: result.folder)
            return .failed(
                result.error
                    ?? .recordingFailed(.other("No frames arrived from the window, so no clip was saved.")))
        }
        let startedAt = EventsFile.timestamp(result.startedAt)
        var video = result.video
        video.scale = active.display.scale
        let recording = EventsFile.Recording(
            id: result.id, startedAt: startedAt, duration: result.duration, fps: result.fps.framesPerSecond,
            video: video,
            source: EventsFile.Source(target: active.target), startedBy: result.startedBy,
            client: result.origin.client, stats: result.stats)
        let written: ClipArtifacts.Written
        do {
            written = try ClipArtifacts.write(
                recording: recording, complete: result.complete, log: log ?? EventLog(),
                events: active.options.events, assetsDir: active.options.assetsDir, clipFolder: result.folder)
        } catch {
            Self.log.error("Couldn't write the clip's files: \(error.localizedDescription, privacy: .public)")
            return .failed(.recordingFailed(.notWritable))
        }
        return .saved(
            StopBody(
                recording: StopBody.Recording(
                    id: result.id, duration: result.duration, fps: result.fps.framesPerSecond, width: result.width,
                    height: result.height, codec: result.codec, startedAt: startedAt, startedBy: result.startedBy,
                    stats: result.stats, video: video),
                files: StopBody.Files(
                    clip: result.clipURL.path, events: written.eventsFile?.path, snippet: written.snippetFile.path),
                snippet: written.snippet, readback: active.readback))
    }

    // MARK: - Status, last, doctor

    public func status() -> StatusBody {
        let snapshot = snapshot()
        var window: WindowEntry?
        var recording: StatusBody.Recording?
        switch phase {
        case .armed(.window(let resolved, _)), .starting(_, .window(let resolved, _)?):
            var entry = WindowEntry(resolved)
            if let size = snapshot.size {
                entry.width = size.width
                entry.height = size.height
            }
            window = entry
        case .recording(let active), .writing(let active):
            if case .window(let w) = active.target {
                window = WindowEntry(ResolvedWindow(window: w, display: active.display))
            }
            recording = StatusBody.Recording(
                id: active.recordingId, elapsed: ((snapshot.elapsed ?? 0) * 1000).rounded() / 1000,
                fps: active.options.fps.framesPerSecond, width: active.size.width, height: active.size.height,
                startedAt: EventsFile.timestamp(active.startedAt), startedBy: active.origin.startedBy,
                client: active.origin.client)
        default:
            break
        }
        return StatusBody(
            state: snapshot.state, window: window, readback: snapshot.readback, recording: recording,
            lastClip: lastClip, error: error?.body)
    }

    /// The last clip saved (including a partial clip after a failure).
    public func last() throws -> StopBody {
        guard let lastClip else { throw SkreenrekError.wrongState(.noClip) }
        return lastClip
    }

    public func doctor() -> DoctorBody {
        let folder = settings.outputFolder
        return DoctorBody(
            version: SkreenrekVersion.current,
            permissions: DoctorBody.Permissions(
                screenRecording: seams.permissions.screenRecording, accessibility: seams.permissions.accessibility),
            outputFolder: DoctorBody.OutputFolder(path: folder.path, writable: Self.canWrite(folder)),
            socket: socketPath)
    }

    /// The folder is writable, or its nearest existing parent is (so it can be created).
    static func canWrite(_ folder: URL) -> Bool {
        let fm = FileManager.default
        var url = folder.standardizedFileURL
        while !fm.fileExists(atPath: url.path) {
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return false }
            url = parent
        }
        return fm.isWritableFile(atPath: url.path)
    }

    // MARK: - Helpers

    private func clearError() {
        guard error != nil else { return }
        error = nil
        publish()
    }

    /// `wrong_state` while a resize runs, or a recording is starting, running or being written.
    private func ensureNotBusy() throws {
        if resizing { throw SkreenrekError.wrongState(.resizing) }
        switch phase {
        case .starting(let app, _):
            throw SkreenrekError.wrongState(.alreadyRecording(app: app))
        case .recording(let active), .writing(let active):
            throw SkreenrekError.wrongState(.alreadyRecording(app: active.app))
        case .idle, .armed:
            return
        }
    }

    /// The window a query names, or the armed window (refreshed) when there is no query.
    private func resolveWindow(_ query: WindowQuery?) async throws -> ResolvedWindow {
        if let query { return try await directory.resolve(query) }
        let armed: Armed? =
            switch phase {
            case .armed(let armed), .starting(_, let armed?): armed
            default: nil
            }
        guard case .window(let resolved, _)? = armed else {
            throw SkreenrekError.usage(
                message: "No window was named, and none is picked.",
                hint: "Pass a window ID or an app. List them with: skreenrek windows")
        }
        return try await directory.resolve(.id(resolved.window.id))
    }

    /// The display for a region (default: the main display, the first one listed), with the region inside it.
    private func regionDisplay(_ rect: PixelRect, displayId: DisplayID?) async throws -> DisplayInfo {
        let displays = try await seams.catalog.displays()
        let display: DisplayInfo
        if let displayId {
            guard let match = displays.first(where: { $0.id == displayId }) else {
                throw SkreenrekError.usage(
                    message: "No display has ID \(displayId).", hint: "Leave out displayId to use the main display.")
            }
            display = match
        } else {
            guard let main = displays.first else {
                throw SkreenrekError.internal(message: "No display was found.")
            }
            display = main
        }
        let bounds = display.frame.pixelSize(scale: display.scale)
        guard rect.width > 0, rect.height > 0, rect.x >= 0, rect.y >= 0, rect.x + rect.width <= bounds.width,
            rect.y + rect.height <= bounds.height
        else {
            throw SkreenrekError.usage(
                message: "The region \(rect.x),\(rect.y),\(rect.width),\(rect.height) isn't inside the display "
                    + "(\(bounds)).",
                hint: "Pass a region inside 0,0,\(bounds.width),\(bounds.height).")
        }
        return display
    }

    private func requestedSize(_ params: StartParams) throws -> PixelSize? {
        switch (params.width, params.height) {
        case (nil, nil): return nil
        case (let width?, let height?): return PixelSize(width: width, height: height)
        default:
            throw SkreenrekError.usage(
                message: "Pass both width and height to resize, or neither.", hint: "Add the missing one, in px.")
        }
    }

    private func recordingOptions(_ params: StartParams, surface: StartedBy) throws -> RecordingOptions {
        let output = try OutputSettings.resolve(container: params.format, codec: params.codec,
            quality: params.quality, bitrateMbps: params.bitrateMbps, surface: surface)
        var fps = settings.fps
        if let value = params.fps {
            guard let rate = FrameRate(rawValue: value) else {
                throw SkreenrekError.usage(message: "Frame rate \(value) isn't offered.", hint: "Use fps 30 or 60.")
            }
            fps = rate
        }
        if let duration = params.durationSeconds, !(duration > 0) || !duration.isFinite {
            throw SkreenrekError.usage(
                message: "The duration must be more than 0 seconds.", hint: "Pass a positive durationSeconds.")
        }
        return RecordingOptions(
            fps: fps, cursor: params.cursor ?? settings.cursor, events: params.events ?? settings.events,
            hud: params.hud ?? settings.hud, outDir: params.outDir.map(Self.folderURL), name: params.name,
            assetsDir: params.assetsDir.map(Self.folderURL), codec: output.codec, duration: params.durationSeconds,
            allowInexact: params.allowInexact ?? false, container: output.container,
            quality: output.quality, bitrateMbps: output.requestedBitrateMbps)
    }

    /// A folder path from a request: `~` expands to the home folder.
    static func folderURL(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }
}
