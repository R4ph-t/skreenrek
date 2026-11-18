import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit
import SkreenrekCore
import Synchronization

/// The real `FrameSource`: ScreenCaptureKit, delivering its own IOSurface-backed `420v` buffers with no copy.
///
/// Windows use `SCContentFilter(desktopIndependentWindow:)`; regions use the display minus Skreenrek's own windows,
/// cropped with `sourceRect`. Scaling to the output size happens on the GPU inside ScreenCaptureKit. Only `.complete`
/// frames are delivered. The stream ends with `FrameSourceError.windowClosed` when the window goes away, and a
/// permission failure throws `permission_denied` (Screen Recording).
public final class SCStreamFrameSource: FrameSource {
    /// How often to check that a recorded window still exists.
    public static let windowCheckInterval: Duration = .milliseconds(500)

    private struct Running: @unchecked Sendable {
        var stream: SCStream
        var output: StreamOutput
        var watcher: Task<Void, Never>?
    }

    private let filterPlan: CaptureFilterPlan
    private let running = Mutex<Running?>(nil)
    /// The latest start's stream, kept after stop so the recorder can read its drop count.
    private let lastFeed = Mutex<FrameStreamFeed?>(nil)
    private let sampleQueue = DispatchQueue(label: "\(SkreenrekIdentity.bundleID).capture", qos: .userInteractive)

    /// - Parameter excludedBundleID: the app left out of region captures (Skreenrek itself).
    public init(excludedBundleID: String? = Bundle.main.bundleIdentifier ?? SkreenrekIdentity.bundleID,
                ownPid: Int32 = ProcessInfo.processInfo.processIdentifier) {
        self.filterPlan = CaptureFilterPlan(ownPid: ownPid, bundleID: excludedBundleID)
    }

    /// Whether Screen Recording is already allowed. Never prompts.
    public static var screenRecordingAllowed: Bool { CGPreflightScreenCaptureAccess() }

    public var droppedFrameCount: Int { lastFeed.withLock { $0?.droppedCount ?? 0 } }

    public func start(target: CaptureTarget, size: PixelSize, fps: FrameRate, showsCursor: Bool) async throws
        -> AsyncThrowingStream<CapturedFrame, any Error>
    {
        await stop()
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw Self.mapStartError(error)
        }

        let filter: SCContentFilter
        var sourceRect: CGRect?
        switch target {
        case .window(let info):
            guard let window = content.windows.first(where: { $0.windowID == info.id.rawValue }) else {
                throw SkreenrekError.windowNotFound(query: String(info.id.rawValue))
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            // A clip of a slightly different aspect crops the window (centred, at most 1 px); never letterboxes.
            sourceRect = WindowFit.sourceRect(
                window: CGSize(width: info.frame.width, height: info.frame.height), clip: size)
        case .region(let rect, let displayId):
            guard let display = content.displays.first(where: { $0.displayID == displayId }) else {
                throw SkreenrekError.recordingFailed(.other("The display for this region isn't connected."))
            }
            let excluded = content.applications.filter { filterPlan.excludes(pid: $0.processID, bundleID: $0.bundleIdentifier) }
            filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
            let scale = Double(filter.pointPixelScale)
            sourceRect = CGRect(
                x: Double(rect.x) / scale, y: Double(rect.y) / scale, width: Double(rect.width) / scale,
                height: Double(rect.height) / scale)
        }

        let configuration = SCStreamConfiguration()
        configuration.width = size.width
        configuration.height = size.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps.framesPerSecond))
        configuration.showsCursor = showsCursor
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.colorMatrix = CGDisplayStream.yCbCrMatrix_ITU_R_709_2
        configuration.queueDepth = 6
        configuration.capturesAudio = false
        if let sourceRect { configuration.sourceRect = sourceRect }

        let feed = FrameStreamFeed()
        lastFeed.withLock { $0 = feed }
        let windowID: CGWindowID? = if case .window(let info) = target { CGWindowID(info.id.rawValue) } else { nil }
        let output = StreamOutput(feed: feed, windowID: windowID)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
        do {
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: sampleQueue)
            try await stream.startCapture()
        } catch {
            feed.finish()
            throw Self.mapStartError(error)
        }

        var watcher: Task<Void, Never>?
        if case .window(let info) = target {
            let windowID = CGWindowID(info.id.rawValue)
            watcher = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.windowCheckInterval)
                    guard !Task.isCancelled else { return }
                    if !Self.windowExists(windowID) {
                        output.end(throwing: FrameSourceError.windowClosed)
                        await self?.stop()
                        return
                    }
                }
            }
        }
        running.withLock { $0 = Running(stream: stream, output: output, watcher: watcher) }
        let streamID = ObjectIdentifier(stream)
        feed.onTermination { [weak self] in
            Task { await self?.stop(only: streamID) }
        }
        return feed.stream
    }

    public func stop() async {
        await stop(only: nil)
    }

    /// Stops the running stream; with `only`, only when that stream is still the running one.
    private func stop(only streamID: ObjectIdentifier?) async {
        guard let current = running.withLock({ state -> Running? in
            guard let running = state, streamID == nil || ObjectIdentifier(running.stream) == streamID else {
                return nil
            }
            state = nil
            return running
        }) else { return }
        current.watcher?.cancel()
        try? await current.stream.stopCapture()
        current.output.end(throwing: nil)
    }

    /// Whether the window is still in the window list (no permission needed for the ID alone).
    public static func windowExists(_ windowID: CGWindowID) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[CFString: Any]] else {
            return false
        }
        return list.contains { ($0[kCGWindowNumber] as? NSNumber)?.uint32Value == windowID }
    }

    static func isPermissionError(_ error: any Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == SCStreamErrorDomain else { return false }
        return nsError.code == SCStreamError.Code.userDeclined.rawValue
            || nsError.code == SCStreamError.Code.missingEntitlements.rawValue
    }

    /// How a stream that stopped on its own ends: `permission_denied` for a permission error; for a window,
    /// "window closed" only when the window is really gone; otherwise `recording_failed` with the reason.
    public static func endError(
        stoppedWith error: (any Error)?, windowID: CGWindowID?,
        windowExists: (CGWindowID) -> Bool = SCStreamFrameSource.windowExists
    ) -> any Error {
        if let error, isPermissionError(error) { return SkreenrekError.permissionDenied(.screenRecording) }
        if let windowID, !windowExists(windowID) { return FrameSourceError.windowClosed }
        let reason = error.map { "Screen capture stopped: \($0.localizedDescription)" } ?? "Screen capture stopped."
        return SkreenrekError.recordingFailed(.other(reason))
    }

    static func mapStartError(_ error: any Error) -> any Error {
        if error is SkreenrekError { return error }
        if isPermissionError(error) { return SkreenrekError.permissionDenied(.screenRecording) }
        return SkreenrekError.recordingFailed(.other("Screen capture couldn't start: \(error.localizedDescription)"))
    }
}

/// Receives ScreenCaptureKit's sample buffers on the capture queue and yields the original pixel buffers.
private final class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let feed: FrameStreamFeed
    private let windowID: CGWindowID?

    init(feed: FrameStreamFeed, windowID: CGWindowID?) {
        self.feed = feed
        self.windowID = windowID
    }

    func end(throwing error: (any Error)?) {
        feed.finish(throwing: error)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
            let rawStatus = attachments.first?[.status] as? Int,
            let status = SCFrameStatus(rawValue: rawStatus)
        else { return }
        switch status {
        case .complete:
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let hostTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            feed.yield(CapturedFrame(pixelBuffer: pixelBuffer, hostTime: hostTime))
        case .stopped:
            end(throwing: SCStreamFrameSource.endError(stoppedWith: nil, windowID: windowID))
        default:
            // Idle, blank, suspended or started: nothing new to show; the recorder repeats the last frame.
            return
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        end(throwing: SCStreamFrameSource.endError(stoppedWith: error, windowID: windowID))
    }
}
