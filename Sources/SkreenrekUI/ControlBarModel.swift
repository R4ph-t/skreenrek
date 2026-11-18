import Foundation
import SkreenrekControl
import SkreenrekCore

/// The bar's measurements (control bar spec §2 and §5), in points.
public enum ControlBarMetrics {
    public static let height: CGFloat = 36
    public static let regularWidth: CGFloat = 300
    public static let compactWidth: CGFloat = 192
    public static let padding: CGFloat = 6
    public static let slotGap: CGFloat = 12
    public static let sizeSlotWidth: CGFloat = 84
    public static let readoutWidth: CGFloat = 96
    public static let readoutHeight: CGFloat = 15
    public static let actionWidth: CGFloat = 84
    public static let controlHeight: CGFloat = 24
    /// From the slot's edge to the value, the chevron's end, and the status dot (bar x 14).
    public static let slotInset: CGFloat = 8
    public static let statusDot: CGFloat = 8
    public static let statusGap: CGFloat = 8
    public static let stopSquare: CGFloat = 10
    public static let stopSquareRadius: CGFloat = 2
    public static let markSize: CGFloat = 16
    public static let labelGap: CGFloat = 6
    public static let warningSize: CGFloat = 12
    public static let warningGap: CGFloat = 4
    /// Between the window's edge and the bar, and between the bar and the screen's edge.
    public static let windowGap: Double = 8
    public static let screenMargin: Double = 8
    /// From the window's bottom edge to a docked bar.
    public static let dockInset: Double = 12
    public static let fadeSeconds: TimeInterval = 0.15
    /// How long a refused resize keeps its triangle.
    public static let refusalSeconds: TimeInterval = 4
    /// How often the screens and permissions are read again while the window is tracked.
    public static let systemReadInterval: TimeInterval = 1
}

public enum ControlBarPlacement: Sendable, Hashable {
    case below
    case above
    case docked
}

public enum ControlBarWidth: Sendable, Hashable {
    case regular
    /// No readout: a window narrower than the full bar.
    case compact

    public var points: CGFloat {
        self == .regular ? ControlBarMetrics.regularWidth : ControlBarMetrics.compactWidth
    }

    /// The space left of Record: Size and the readout, or Size alone on the compact bar.
    public var leadingAreaWidth: CGFloat {
        points - ControlBarMetrics.padding * 2 - ControlBarMetrics.slotGap - ControlBarMetrics.actionWidth
    }
}

/// Where the bar goes for one window frame. Everything is in top-left global points.
public struct ControlBarLayout: Sendable, Hashable {
    public var frame: PointRect
    public var placement: ControlBarPlacement
    public var width: ControlBarWidth
    public var display: DisplayInfo

    /// The screen holding the largest part of the window, or `fallback` when the window is on none of them.
    public static func display(
        for window: PointRect, among displays: [DisplayInfo], fallback: DisplayInfo? = nil
    ) -> DisplayInfo? {
        var best: (display: DisplayInfo, area: Double)?
        for display in displays {
            let overlap = window.cgRect.intersection(display.frame.cgRect)
            guard !overlap.isNull else { continue }
            let area = Double(overlap.width * overlap.height)
            if area > 0, area > (best?.area ?? 0) { best = (display, area) }
        }
        return best?.display ?? fallback ?? displays.first
    }

    /// Below the window, else above it, else inside its bottom edge. Centred and always on the window's display.
    public static func place(window: PointRect, on display: DisplayInfo) -> ControlBarLayout {
        let metrics = ControlBarMetrics.self
        let visible = display.visibleFrame.cgRect
        let bounds = window.cgRect
        let width: ControlBarWidth = window.width < Double(metrics.regularWidth) ? .compact : .regular
        let barWidth = Double(width.points)
        let barHeight = Double(metrics.height)
        let margin = metrics.screenMargin
        let gap = metrics.windowGap

        let placement: ControlBarPlacement
        var y: Double
        if bounds.maxY + gap + barHeight + margin <= visible.maxY {
            placement = .below
            y = bounds.maxY + gap
        } else if bounds.minY - gap - barHeight - margin >= visible.minY {
            placement = .above
            y = bounds.minY - gap - barHeight
        } else {
            placement = .docked
            y = bounds.maxY - metrics.dockInset - barHeight
        }
        // A window hanging off the screen must not take the bar with it.
        y = clamp(y.rounded(), low: visible.minY + margin, high: visible.maxY - margin - barHeight)
        let x = clamp(
            (bounds.midX - barWidth / 2).rounded(), low: visible.minX + margin,
            high: visible.maxX - margin - barWidth)
        return ControlBarLayout(
            frame: PointRect(x: x, y: y, width: barWidth, height: barHeight), placement: placement, width: width,
            display: display)
    }

    /// The low bound wins on a screen too small for the bar.
    private static func clamp(_ value: Double, low: Double, high: Double) -> Double {
        max(low, min(value, high))
    }
}

/// A preset chosen from the bar, on its way through the exact resize.
public enum ControlBarResize: Sendable, Hashable {
    case none
    case resizing
    /// The window kept its size. `sequence` tells two refusals in a row apart.
    case refused(sequence: Int, reason: String)
}

public struct ControlBarPermissions: Sendable, Hashable {
    public var screenRecording: PermissionStatus
    public var directCapture: PermissionStatus
    public var accessibility: PermissionStatus

    public init(
        screenRecording: PermissionStatus = .allowed, directCapture: PermissionStatus = .allowed,
        accessibility: PermissionStatus = .allowed
    ) {
        self.screenRecording = screenRecording
        self.directCapture = directCapture
        self.accessibility = accessibility
    }

    public init(_ probe: any PermissionProbe) {
        self.init(
            screenRecording: probe.screenRecording, directCapture: probe.directCapture,
            accessibility: probe.accessibility)
    }
}

/// Why Record is unavailable. `ControlBarModel.block` picks the first that applies, in this order.
public enum ControlBarBlock: Sendable, Hashable {
    case screenRecording
    case directCapture
    case presetDoesNotFit(tooltip: String)
    case outputFolder

    public var sentence: String {
        switch self {
        case .screenRecording: UIStrings.Settings.screenRecordingNotAllowed
        case .directCapture: UIStrings.ControlBar.directCaptureBlocked
        case .presetDoesNotFit(let tooltip): tooltip
        case .outputFolder: UIStrings.ControlBar.outputFolderNotWritable
        }
    }
}

/// What the app is doing with the bar's window.
public enum ControlBarActivity: Sendable, Hashable {
    case idle
    /// Record was clicked and the recorder isn't running yet.
    case starting
    case recording(seconds: Int)
    case saving
}

/// Everything outside the bar that decides what it shows.
public struct ControlBarInput: Sendable, Hashable {
    public var target: SelectionOutlineTarget?
    /// The Show Control Bar switch.
    public var enabled: Bool
    /// False in the headless host, which never shows the bar.
    public var menuBarApp: Bool
    public var pickerOpen: Bool
    public var windowClosed: Bool
    public var activity: ControlBarActivity
    public var sizeChoice: SizeChoice
    public var readback: Readback?
    /// The recording's output size.
    public var clipSize: PixelSize?
    /// The target's display as the controller knows it, for a window on no current screen.
    public var knownDisplay: DisplayInfo?
    public var outputWritable: Bool
    public var resize: ControlBarResize
    public var reduceMotion: Bool
    /// On-screen chrome is allowed during a recording: the HUD's rule (Settings and `--no-hud`).
    public var recordingChrome: Bool

    public init(
        target: SelectionOutlineTarget?, enabled: Bool = true, menuBarApp: Bool = true, pickerOpen: Bool = false,
        windowClosed: Bool = false, activity: ControlBarActivity = .idle, sizeChoice: SizeChoice = .default,
        readback: Readback? = nil, clipSize: PixelSize? = nil, knownDisplay: DisplayInfo? = nil,
        outputWritable: Bool = true, resize: ControlBarResize = .none, reduceMotion: Bool = false,
        recordingChrome: Bool = true
    ) {
        self.target = target
        self.enabled = enabled
        self.menuBarApp = menuBarApp
        self.pickerOpen = pickerOpen
        self.windowClosed = windowClosed
        self.activity = activity
        self.sizeChoice = sizeChoice
        self.readback = readback
        self.clipSize = clipSize
        self.knownDisplay = knownDisplay
        self.outputWritable = outputWritable
        self.resize = resize
        self.reduceMotion = reduceMotion
        self.recordingChrome = recordingChrome
    }

    /// While recording or saving, `snapshot.window` is the recorded window, picked first or not.
    public init(
        context: MenuContext, windowClosed: Bool, outputWritable: Bool, resize: ControlBarResize,
        recordStarting: Bool, reduceMotion: Bool
    ) {
        let snapshot = context.snapshot
        let activity: ControlBarActivity =
            switch snapshot.state {
            case .recording: .recording(seconds: context.elapsedSeconds)
            case .writing: .saving
            default: recordStarting ? .starting : .idle
            }
        self.init(
            target: snapshot.window.map(SelectionOutlineTarget.init(window:)), enabled: context.showControlBar,
            pickerOpen: snapshot.picking, windowClosed: windowClosed, activity: activity,
            sizeChoice: context.sizeChoice, readback: snapshot.readback, clipSize: snapshot.size,
            knownDisplay: snapshot.display, outputWritable: outputWritable, resize: resize,
            reduceMotion: reduceMotion, recordingChrome: context.recordingIndicator && snapshot.hud)
    }
}

/// The Size pop-up.
public struct ControlBarSizeControl: Sendable, Hashable {
    public var value: String
    /// The six presets and the separator between their groups.
    public var entries: [MenuEntry]
    public var enabled: Bool
    public var help: String
    public var accessibilityLabel: String
}

/// What sits left of the readout, or for `saving` everything left of Record.
public enum ControlBarLeading: Sendable, Hashable {
    case size(ControlBarSizeControl)
    case timer(String)
    /// The indicator and "Saving clip…", centred together. The compact bar has no room for the text, so it draws the
    /// indicator alone and keeps `text` for the tooltip and VoiceOver.
    case saving(spinner: Bool, text: String, showsText: Bool)
}

/// The middle slot. The compact bar has none, and saving uses its space.
public struct ControlBarReadout: Sendable, Hashable {
    public var text: String
    /// The previous size, while a resize is waiting for its read-back.
    public var dimmed: Bool
    /// The orange triangle: the size isn't exact, or the window refused.
    public var warning: Bool
    public var help: String?
    public var accessibilityLabel: String
}

/// The third slot.
public struct ControlBarAction: Sendable, Hashable {
    public enum Style: Sendable, Hashable {
        case record
        /// Disabled for a moment: resizing, starting or saving. No triangle.
        case recordBusy
        case recordBlocked(ControlBarBlock)
        case stop
    }

    public var style: Style
    public var help: String
    public var accessibilityLabel: String
    public var accessibilityHint: String?

    public var action: MenuAction? {
        switch style {
        case .record: .record
        case .stop: .stop
        case .recordBusy, .recordBlocked: nil
        }
    }
}

public struct ControlBarContent: Sendable, Hashable {
    public var width: ControlBarWidth
    public var groupLabel: String
    public var leading: ControlBarLeading
    public var readout: ControlBarReadout?
    public var action: ControlBarAction
}

/// The bar for one moment: where it goes and what it holds.
public struct ControlBarDisplay: Sendable, Hashable {
    public var windowID: WindowID
    public var frame: PointRect
    public var placement: ControlBarPlacement
    public var content: ControlBarContent

    public var width: ControlBarWidth { content.width }
}

/// When the bar shows, where, and what's in it. Pure: time, the window's position, the screens and the permissions
/// are passed in.
public struct ControlBarModel: Sendable {
    public private(set) var input = ControlBarInput(target: nil)
    public private(set) var permissions = ControlBarPermissions()
    private var displays: [DisplayInfo] = []
    private var presence: WindowPresence?
    /// The size on show when a resize began. It stays until the read-back.
    private var sizeBeforeResize: PixelSize?
    private var refusal: (size: PixelSize, reason: String, until: TimeInterval)?
    private var seenRefusal: Int?

    public init() {}

    /// Applies new conditions. Returns the sentence to announce when this update is a new refusal.
    @discardableResult
    public mutating func update(_ new: ControlBarInput, now: TimeInterval) -> String? {
        let shownBefore = shownSize()
        let windowChanged = input.target?.window.id != new.target?.window.id
        input = new
        if windowChanged {
            presence = nil
            sizeBeforeResize = nil
            refusal = nil
        }
        var announcement: String?
        switch new.resize {
        case .none:
            sizeBeforeResize = nil
        case .resizing:
            sizeBeforeResize = sizeBeforeResize ?? shownBefore
            refusal = nil
        case .refused(let sequence, let reason):
            if sequence != seenRefusal, !windowChanged, let size = sizeBeforeResize ?? shownBefore {
                refusal = (size, reason, now + ControlBarMetrics.refusalSeconds)
                announcement = reason
            }
            seenRefusal = sequence
            sizeBeforeResize = nil
        }
        return announcement
    }

    public mutating func update(presence: WindowPresence) { self.presence = presence }
    public mutating func update(displays: [DisplayInfo]) { self.displays = displays }
    public mutating func update(permissions: ControlBarPermissions) { self.permissions = permissions }

    /// Nothing about the app rules the bar out. The window itself may still be out of sight.
    private var eligible: Bool {
        input.enabled && input.menuBarApp && input.target != nil && !input.pickerOpen && !input.windowClosed
            && !hiddenAsChrome
    }

    /// A recording that asked for no on-screen chrome gets no bar. Idle and starting aren't chrome.
    private var hiddenAsChrome: Bool {
        switch input.activity {
        case .recording, .saving: !input.recordingChrome
        case .idle, .starting: false
        }
    }

    /// The tracker keeps running while the window is out of sight, so the bar comes back with it.
    public var wantsTracking: Bool { eligible }

    public var fadeSeconds: TimeInterval { input.reduceMotion ? 0 : ControlBarMetrics.fadeSeconds }

    /// The window's frame right now, as far as the bar knows.
    public var windowFrame: PointRect? {
        guard let target = input.target else { return nil }
        switch presence {
        case .notVisible: return nil
        case .onScreen(let frame): return frame
        case nil: return target.window.frame
        }
    }

    private var layout: ControlBarLayout? {
        guard let frame = windowFrame,
            let display = ControlBarLayout.display(for: frame, among: displays, fallback: input.knownDisplay)
        else { return nil }
        return ControlBarLayout.place(window: frame, on: display)
    }

    public func display(at now: TimeInterval) -> ControlBarDisplay? {
        guard eligible, let target = input.target, let frame = windowFrame, let layout else { return nil }
        return ControlBarDisplay(
            windowID: target.window.id, frame: layout.frame, placement: layout.placement,
            content: content(target: target, window: frame, layout: layout, now: now))
    }

    /// The next time `display` changes by itself: the end of a refusal.
    public func nextDeadline(after now: TimeInterval) -> TimeInterval? {
        guard let until = refusal?.until, now < until else { return nil }
        return until
    }

    /// The first reason Record can't run, in the spec's order. Without Accessibility the preset isn't applied, so it
    /// can't stand in the way: the window records at its current size.
    public static func block(
        permissions: ControlBarPermissions, sizeChoice: SizeChoice, display: DisplayInfo, outputWritable: Bool
    ) -> ControlBarBlock? {
        if permissions.screenRecording != .allowed { return .screenRecording }
        if permissions.directCapture != .allowed { return .directCapture }
        if permissions.accessibility == .allowed, let size = sizeChoice.pixelSize,
            case .failure(let failure) = WindowFit.plan(clip: size, on: display)
        {
            return .presetDoesNotFit(tooltip: failure.tooltip)
        }
        return outputWritable ? nil : .outputFolder
    }

    // MARK: - Sizes

    private func shownSize() -> PixelSize? {
        guard let frame = windowFrame, let layout else { return nil }
        return clipSize(window: frame, display: layout.display)
    }

    /// What the clip will be. A preset is the size the next recording gets, and a window that can't be resized
    /// records as it is.
    private func clipSize(window: PointRect, display: DisplayInfo) -> PixelSize {
        let current = window.pixelSize(scale: display.scale)
        switch input.activity {
        case .recording, .saving:
            return input.clipSize ?? current
        case .idle, .starting:
            guard permissions.accessibility == .allowed, let size = input.sizeChoice.pixelSize else { return current }
            if let readback = input.readback, readback.requested == size { return readback.actual }
            return size
        }
    }

    /// The reason a read-back differs from the chosen preset. Nil when it matches.
    private var notExactReason: String? {
        guard permissions.accessibility == .allowed, let size = input.sizeChoice.pixelSize,
            let readback = input.readback, readback.requested == size, !readback.exact
        else { return nil }
        return UIStrings.Menu.notExactReason(
            app: readback.window.app, requested: readback.requested, actual: readback.actual,
            reason: ExactResizer.reason(requested: readback.requested, actuals: [readback.actual]))
    }

    private func activeRefusal(at now: TimeInterval) -> (size: PixelSize, reason: String)? {
        guard let refusal, now < refusal.until else { return nil }
        return (refusal.size, refusal.reason)
    }

    // MARK: - Content

    private func content(
        target: SelectionOutlineTarget, window: PointRect, layout: ControlBarLayout, now: TimeInterval
    ) -> ControlBarContent {
        let compact = layout.width == .compact
        let readout = self.readout(window: window, display: layout.display, now: now)
        return ControlBarContent(
            width: layout.width, groupLabel: UIStrings.ControlBar.group(target.title),
            leading: leading(readout: readout, display: layout.display, compact: compact),
            readout: compact || input.activity == .saving ? nil : readout,
            action: action(title: target.title, display: layout.display))
    }

    private func readout(window: PointRect, display: DisplayInfo, now: TimeInterval) -> ControlBarReadout {
        let idle = input.activity == .idle || input.activity == .starting
        if idle, permissions.accessibility != .allowed {
            return warning(clipSize(window: window, display: display), reason: UIStrings.ControlBar.accessibilityOff)
        }
        if idle, let refusal = activeRefusal(at: now) {
            return warning(refusal.size, reason: refusal.reason)
        }
        if idle, input.resize == .resizing, let previous = sizeBeforeResize {
            return plain(previous, window: window, dimmed: true)
        }
        let size = clipSize(window: window, display: display)
        if idle, let reason = notExactReason { return warning(size, reason: reason) }
        return plain(size, window: window, dimmed: false)
    }

    private func plain(_ size: PixelSize, window: PointRect, dimmed: Bool) -> ControlBarReadout {
        let points = WindowPoints(width: Int(window.width.rounded()), height: Int(window.height.rounded()))
        return ControlBarReadout(
            text: size.description, dimmed: dimmed, warning: false,
            help: UIStrings.ControlBar.readoutHelp(clip: size, window: points),
            accessibilityLabel: UIStrings.ControlBar.spokenSize(size))
    }

    /// The triangle's layout: the size without " px".
    private func warning(_ size: PixelSize, reason: String) -> ControlBarReadout {
        ControlBarReadout(
            text: UIStrings.Menu.dimensions(size), dimmed: false, warning: true, help: reason,
            accessibilityLabel: UIStrings.ControlBar.spokenSize(size))
    }

    private func leading(readout: ControlBarReadout, display: DisplayInfo, compact: Bool) -> ControlBarLeading {
        switch input.activity {
        case .recording(let seconds):
            return .timer(TimeFormat.elapsed(Double(seconds)))
        case .saving:
            return .saving(spinner: !input.reduceMotion, text: UIStrings.Menu.savingClip, showsText: !compact)
        case .idle, .starting:
            return .size(sizeControl(readout: readout, display: display, compact: compact))
        }
    }

    private func sizeControl(
        readout: ControlBarReadout, display: DisplayInfo, compact: Bool
    ) -> ControlBarSizeControl {
        let value = PanelModel.sizeName(input.sizeChoice)
        let enabled = permissions.accessibility == .allowed
        var help = enabled ? UIStrings.ControlBar.sizeHelp : UIStrings.ControlBar.accessibilityOff
        var label = UIStrings.Panel.popupLabel(title: UIStrings.Menu.size, value: value)
        if compact {
            // No readout here, so the pop-up carries the size. Disabled, its tooltip already says the same thing.
            if enabled, let detail = readout.help { help += " " + detail }
            label += ", " + readout.accessibilityLabel
        }
        return ControlBarSizeControl(
            value: value, entries: MenuModel.sizePresetEntries(input.sizeChoice, display: display), enabled: enabled,
            help: help, accessibilityLabel: label)
    }

    private func action(title: String, display: DisplayInfo) -> ControlBarAction {
        let record = UIStrings.Brand.record
        switch input.activity {
        case .recording(let seconds):
            return ControlBarAction(
                style: .stop, help: UIStrings.Panel.stopHelp,
                accessibilityLabel: UIStrings.Brand.stopLabel(seconds: seconds), accessibilityHint: nil)
        case .saving, .starting:
            return ControlBarAction(
                style: .recordBusy, help: UIStrings.ControlBar.recordHelp, accessibilityLabel: record,
                accessibilityHint: nil)
        case .idle:
            if let block = Self.block(
                permissions: permissions, sizeChoice: input.sizeChoice, display: display,
                outputWritable: input.outputWritable)
            {
                return ControlBarAction(
                    style: .recordBlocked(block), help: block.sentence, accessibilityLabel: record,
                    accessibilityHint: block.sentence)
            }
            return ControlBarAction(
                style: input.resize == .resizing ? .recordBusy : .record, help: UIStrings.ControlBar.recordHelp,
                accessibilityLabel: record, accessibilityHint: UIStrings.ControlBar.recordHint(title))
        }
    }
}

/// The bar's window, as the controller drives it.
@MainActor
public protocol ControlBarSurface: AnyObject {
    func show(_ display: ControlBarDisplay, fade: TimeInterval)
    /// New content or a new place. Never animated.
    func update(_ display: ControlBarDisplay)
    func hide(fade: TimeInterval)
    /// Puts the bar back directly above the window, which may have come forward.
    func keepAbove(_ window: WindowID)
    func announce(_ text: String)
}

/// Connects the model to the window, the tracker and the clock. It holds no rules of its own.
@MainActor
public final class ControlBarController {
    private let surface: any ControlBarSurface
    private let tracker: any WindowFrameTracking
    private let clock: any HostClock
    private let permissions: any PermissionProbe
    private let displays: @MainActor () -> [DisplayInfo]
    private var model = ControlBarModel()
    private var tracked: WindowID?
    private var shown: ControlBarDisplay?
    private var systemReadAt: TimeInterval?
    private var timer: Task<Void, Never>?
    /// Called when the bar appears or goes away, for the HUD.
    public var onVisibilityChange: (() -> Void)?

    public init(
        surface: any ControlBarSurface, tracker: any WindowFrameTracking, clock: any HostClock,
        permissions: any PermissionProbe, displays: @escaping @MainActor () -> [DisplayInfo]
    ) {
        self.surface = surface
        self.tracker = tracker
        self.clock = clock
        self.permissions = permissions
        self.displays = displays
    }

    public var isVisible: Bool { shown != nil }

    /// Where the window is now, so a resize can tell whether it changed anything.
    public var windowFrame: PointRect? { model.windowFrame }

    public func update(_ input: ControlBarInput) {
        let now = clock.now()
        readSystem(now: now, force: true)
        if let announcement = model.update(input, now: now) { surface.announce(announcement) }
        updateTracking()
        publish(now: now, tick: false)
        schedule(after: now)
    }

    /// Neither changes while a window is dragged, so the 100 ms tracking tick doesn't need to read them.
    private func readSystem(now: TimeInterval, force: Bool) {
        let due = systemReadAt.map { now - $0 >= ControlBarMetrics.systemReadInterval } ?? true
        guard force || due else { return }
        systemReadAt = now
        model.update(displays: displays())
        model.update(permissions: ControlBarPermissions(permissions))
    }

    private func updateTracking() {
        guard model.wantsTracking, let window = model.input.target?.window else {
            if tracked != nil { tracker.stop() }
            tracked = nil
            return
        }
        guard tracked != window.id else { return }
        if tracked != nil { tracker.stop() }
        tracked = window.id
        tracker.start(window) { [weak self] presence in
            guard let self else { return }
            let now = self.clock.now()
            self.model.update(presence: presence)
            self.readSystem(now: now, force: false)
            self.publish(now: now, tick: true)
        }
    }

    private func publish(now: TimeInterval, tick: Bool) {
        let display = model.display(at: now)
        let wasVisible = shown != nil
        switch (shown, display) {
        case (nil, nil):
            break
        case (nil, let display?):
            surface.show(display, fade: model.fadeSeconds)
        case (_?, nil):
            surface.hide(fade: model.fadeSeconds)
        case (let old?, let display?):
            if old != display {
                surface.update(display)
            } else if tick {
                surface.keepAbove(display.windowID)
            }
        }
        shown = display
        if wasVisible != (display != nil) { onVisibilityChange?() }
    }

    private func schedule(after now: TimeInterval) {
        timer?.cancel()
        timer = nil
        guard let deadline = model.nextDeadline(after: now) else { return }
        let clock = clock
        timer = Task { [weak self] in
            do { try await clock.sleep(until: deadline) } catch { return }
            guard let self else { return }
            self.publish(now: deadline, tick: false)
        }
    }
}

/// One window tracker shared by the outline and the bar. It runs while either of them needs it, so the bar keeps
/// following the window after the outline's flash ends.
@MainActor
public final class SharedWindowFrameTracker {
    private final class Client: WindowFrameTracking {
        weak var owner: SharedWindowFrameTracker?
        var window: WindowInfo?
        var onChange: (@MainActor (WindowPresence) -> Void)?

        init(owner: SharedWindowFrameTracker) { self.owner = owner }

        func start(_ window: WindowInfo, onChange: @escaping @MainActor (WindowPresence) -> Void) {
            owner?.start(self, window: window, onChange: onChange)
        }

        func stop() { owner?.stop(self) }
    }

    private let source: any WindowFrameTracking
    /// The clients that are tracking, oldest first. The newest decides the window.
    private var active: [Client] = []
    private var running: WindowID?
    private var latest: WindowPresence?

    public init(source: any WindowFrameTracking) {
        self.source = source
    }

    public func makeClient() -> any WindowFrameTracking { Client(owner: self) }

    private func start(
        _ client: Client, window: WindowInfo, onChange: @escaping @MainActor (WindowPresence) -> Void
    ) {
        active.removeAll { $0 === client }
        client.window = window
        client.onChange = onChange
        active.append(client)
        if running == window.id {
            // The tracker promises one report right away.
            if let latest { onChange(latest) }
        } else {
            reconcile()
        }
    }

    private func stop(_ client: Client) {
        active.removeAll { $0 === client }
        client.window = nil
        client.onChange = nil
        reconcile()
    }

    private func reconcile() {
        let wanted = active.last?.window
        guard wanted?.id != running else { return }
        if running != nil { source.stop() }
        running = wanted?.id
        latest = nil
        guard let wanted else { return }
        source.start(wanted) { [weak self] presence in self?.deliver(presence) }
    }

    private func deliver(_ presence: WindowPresence) {
        latest = presence
        for client in active where client.window?.id == running {
            client.onChange?(presence)
        }
    }
}
