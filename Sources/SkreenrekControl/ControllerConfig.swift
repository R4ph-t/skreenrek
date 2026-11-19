import Foundation
import SkreenrekCore

/// Everything the controller touches outside itself. The app passes the real ones; tests pass the fakes.
public struct ControllerSeams: Sendable {
    public var catalog: any WindowCatalog
    public var resizer: any WindowResizer
    public var frameSource: any FrameSource
    public var mouse: any MouseEventSource
    public var clock: any HostClock
    public var permissions: any PermissionProbe
    public var disk: any DiskSpaceProbe
    public var picker: any WindowPicker
    /// Brings a just-picked window to the front. The app wires `SystemWindowFront`; tests use `FakeWindowFront`.
    public var front: any WindowFront
    /// Skreenrek's own pid: its windows are never listed.
    public var ownPid: Int32
    /// `.requireHardware` in the app; `.software` in tests on the CI virtual machine.
    public var encoder: EncoderPolicy
    /// False only for offline tests that need every slot to get its frame.
    public var realTimeWriter: Bool
    /// Makes the clip writer; nil means `ClipWriter`. Tests wrap it to time the first append.
    public var makeSink: RecordingSession.SinkFactory?

    public init(
        catalog: any WindowCatalog, resizer: any WindowResizer, frameSource: any FrameSource,
        mouse: any MouseEventSource, clock: any HostClock, permissions: any PermissionProbe, disk: any DiskSpaceProbe,
        picker: any WindowPicker = UnavailableWindowPicker(), front: any WindowFront = NoOpWindowFront(),
        ownPid: Int32 = ProcessInfo.processInfo.processIdentifier,
        encoder: EncoderPolicy = .requireHardware, realTimeWriter: Bool = true,
        makeSink: RecordingSession.SinkFactory? = nil
    ) {
        self.catalog = catalog
        self.resizer = resizer
        self.frameSource = frameSource
        self.mouse = mouse
        self.clock = clock
        self.permissions = permissions
        self.disk = disk
        self.picker = picker
        self.front = front
        self.ownPid = ownPid
        self.encoder = encoder
        self.realTimeWriter = realTimeWriter
        self.makeSink = makeSink
    }
}

/// The defaults a recording takes when a request leaves them out (Settings, 08).
public struct ControllerSettings: Sendable, Hashable, Codable {
    /// The parent of the clip folders; `~/Movies/Skreenrek/` by default.
    public var outputFolder: URL
    public var fps: FrameRate
    public var cursor: Bool
    public var events: Bool
    public var hud: Bool

    public init(
        outputFolder: URL = OutputFolder.defaultParent(), fps: FrameRate = .fps60, cursor: Bool = true,
        events: Bool = true, hud: Bool = true
    ) {
        self.outputFolder = outputFolder
        self.fps = fps
        self.cursor = cursor
        self.events = events
        self.hud = hud
    }
}

/// The picker until the overlay arrives in 10: every pick fails with `internal`.
public struct UnavailableWindowPicker: WindowPicker {
    public static let error = SkreenrekError.internal(message: "The window picker isn't available yet.")

    public init() {}

    public func pick(timeout: TimeInterval) async throws -> PickResult {
        throw Self.error
    }
}

/// What the UI (08, 10) shows: one value per state change, in order.
public struct ControllerSnapshot: Sendable, Hashable {
    public var state: ControllerState
    /// Seconds since the recording started; nil unless recording or writing.
    public var elapsed: TimeInterval?
    /// The armed or recorded window; nil for regions and when idle.
    public var window: WindowInfo?
    /// The armed or recorded region, in pixels of `displayId`.
    public var region: PixelRect?
    public var displayId: DisplayID?
    /// The display of the armed or recorded target, for sizing (its visible frame and scale).
    public var display: DisplayInfo?
    /// The armed window's size, or the recording's output size.
    public var size: PixelSize?
    /// The armed window's last read-back.
    public var readback: Readback?
    /// The recording's frame rate, or the default for the next one.
    public var fps: FrameRate
    public var startedBy: StartedBy?
    /// The MCP client name, e.g. "Claude Code".
    public var client: String?
    public var lastClip: StopBody?
    /// The failure the error state holds.
    public var error: SkreenrekError?
    /// Effective HUD option of the active recording (including CLI/MCP overrides).
    public var hud: Bool
    /// The picker overlay is on screen.
    public var picking: Bool
    /// Windows picked so far. It moves on every pick, including a second pick of the same window.
    public var pickCount: Int
    /// While recording or writing: the recorded window stays picked after a saved clip (a menu or control-bar
    /// recording with the control bar on). False for agent recordings, which drop the pick, and when idle.
    public var keepsWindowPicked: Bool

    public init(
        state: ControllerState, elapsed: TimeInterval? = nil, window: WindowInfo? = nil, region: PixelRect? = nil,
        displayId: DisplayID? = nil, size: PixelSize? = nil, readback: Readback? = nil, fps: FrameRate,
        startedBy: StartedBy? = nil, client: String? = nil, lastClip: StopBody? = nil, error: SkreenrekError? = nil,
        hud: Bool = true, display: DisplayInfo? = nil, picking: Bool = false, pickCount: Int = 0,
        keepsWindowPicked: Bool = false
    ) {
        self.state = state
        self.elapsed = elapsed
        self.window = window
        self.region = region
        self.displayId = displayId
        self.size = size
        self.readback = readback
        self.fps = fps
        self.startedBy = startedBy
        self.client = client
        self.lastClip = lastClip
        self.error = error
        self.hud = hud
        self.display = display
        self.picking = picking
        self.pickCount = pickCount
        self.keepsWindowPicked = keepsWindowPicked
    }
}
