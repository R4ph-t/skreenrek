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

    private let excludedBundleID: String?
    private let running = Mutex<Running?>(nil)
    private let sampleQueue = DispatchQueue(label: "it.fraime.skreenrek.capture", qos: .userInteractive)

    /// - Parameter excludedBundleID: the app left out of region captures (Skreenrek itself).
    public init(excludedBundleID: String? = Bundle.main.bundleIdentifier) {
        self.excludedBundleID = excludedBundleID
    }

    /// Whether Screen Recording is already allowed. Never prompts.
    public static var screenRecordingAllowed: Bool { CGPreflightScreenCaptureAccess() }

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
        case .region(let rect, let displayId):
            guard let display = content.displays.first(where: { $0.displayID == displayId }) else {
                throw SkreenrekError.recordingFailed(.other("The display for this region isn't connected."))
            }
            let excluded = content.applications.filter { $0.bundleIdentifier == excludedBundleID }
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

        let (frames, continuation) = AsyncThrowingStream<CapturedFrame, any Error>.makeStream()
        let isWindow = if case .window = target { true } else { false }
        let output = StreamOutput(continuation: continuation, isWindow: isWindow)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
        do {
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: sampleQueue)
            try await stream.startCapture()
        } catch {
            continuation.finish()
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
        continuation.onTermination = { [weak self] _ in
            Task { await self?.stop(only: streamID) }
        }
        return frames
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
    static func windowExists(_ windowID: CGWindowID) -> Bool {
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

    static func mapStartError(_ error: any Error) -> any Error {
        if error is SkreenrekError { return error }
        if isPermissionError(error) { return SkreenrekError.permissionDenied(.screenRecording) }
        return SkreenrekError.recordingFailed(.other("Screen capture couldn't start: \(error.localizedDescription)"))
    }
}

/// Receives ScreenCaptureKit's sample buffers on the capture queue and yields the original pixel buffers.
private final class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let continuation: AsyncThrowingStream<CapturedFrame, any Error>.Continuation
    private let isWindow: Bool

    init(continuation: AsyncThrowingStream<CapturedFrame, any Error>.Continuation, isWindow: Bool) {
        self.continuation = continuation
        self.isWindow = isWindow
    }

    func end(throwing error: (any Error)?) {
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
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
            continuation.yield(CapturedFrame(pixelBuffer: pixelBuffer, hostTime: hostTime))
        case .stopped:
            if isWindow { end(throwing: FrameSourceError.windowClosed) }
        default:
            // Idle, blank, suspended or started: nothing new to show; the recorder repeats the last frame.
            return
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        if SCStreamFrameSource.isPermissionError(error) {
            end(throwing: SkreenrekError.permissionDenied(.screenRecording))
        } else if isWindow {
            end(throwing: FrameSourceError.windowClosed)
        } else {
            end(throwing: SkreenrekError.recordingFailed(.other("Screen capture stopped: \(error.localizedDescription)")))
        }
    }
}
