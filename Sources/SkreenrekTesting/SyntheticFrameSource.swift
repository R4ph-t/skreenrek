import CoreVideo
import Foundation
import SkreenrekCore

/// Makes IOSurface-backed `420v` pixel buffers, the kind ScreenCaptureKit delivers, whose luma encodes a frame index.
public enum SyntheticFrames {
    /// `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange` (`420v`).
    public static let pixelFormat: OSType = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

    /// Distinct luma levels before the index wraps. Levels are 4 apart inside video range (16…235), so a decoded
    /// frame read back from H.264 still maps to its index.
    public static let lumaLevels = 55

    public static func luma(forIndex index: Int) -> UInt8 {
        UInt8(16 + (index % lumaLevels) * 4)
    }

    /// The frame index (modulo `lumaLevels`) a luma value stands for.
    public static func index(forLuma luma: UInt8) -> Int {
        let level = ((Double(luma) - 16) / 4).rounded()
        return min(max(Int(level), 0), lumaLevels - 1)
    }

    /// A new IOSurface-backed `420v` buffer filled with the luma for `index` and neutral chroma.
    public static func makeBuffer(size: PixelSize, index: Int) throws -> CVPixelBuffer {
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any]() as CFDictionary,
            kCVPixelBufferPixelFormatTypeKey: pixelFormat,
            kCVPixelBufferWidthKey: size.width,
            kCVPixelBufferHeightKey: size.height,
        ]
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, size.width, size.height, pixelFormat, attributes as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else {
            throw SkreenrekError.internal(
                message: "Couldn't make a synthetic frame (CVReturn \(status)).", hint: "Check the test setup.")
        }
        fill(buffer, luma: luma(forIndex: index))
        return buffer
    }

    /// Reads the luma of the buffer's top-left pixel and maps it back to a frame index.
    public static func index(of buffer: CVPixelBuffer) -> Int {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return 0 }
        return index(forLuma: base.load(as: UInt8.self))
    }

    private static func fill(_ buffer: CVPixelBuffer, luma: UInt8) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        for (plane, value) in [(0, luma), (1, UInt8(128))] {
            guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, plane) else { continue }
            let bytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, plane) * CVPixelBufferGetHeightOfPlane(buffer, plane)
            memset(base, Int32(value), bytes)
        }
    }
}

/// A frame source that makes synthetic frames instead of capturing the screen.
///
/// Timing:
/// - `.realTime(interval:)`: frame n is due at `start + n × interval` on the given clock and stamped with the
///   clock's time when delivered. With a `ManualClock` the test drives it; with a real clock it runs in real time.
/// - `.scripted(times)`: frame n is stamped `times[n]` (irregular gaps allowed). With `waitForClock`, delivery
///   waits until the clock reaches each time; otherwise all frames are delivered at once.
public final class SyntheticFrameSource: FrameSource, @unchecked Sendable {
    public enum Timing: Sendable {
        case realTime(interval: TimeInterval)
        case scripted([TimeInterval], waitForClock: Bool)
    }

    public struct StartCall: Sendable, Hashable {
        public var target: CaptureTarget
        public var size: PixelSize
        public var fps: FrameRate
        public var showsCursor: Bool
    }

    private struct State {
        var task: Task<Void, Never>?
        var continuation: AsyncThrowingStream<CapturedFrame, Error>.Continuation?
        var starts: [StartCall] = []
        var delivered = 0
        var stopped = 0
    }

    private let clock: any HostClock
    private let timing: Timing
    private let frameCount: Int?
    private let endError: SkreenrekError?
    private let startError: SkreenrekError?
    private let frameSize: PixelSize?
    private let state = Locked(State())

    /// - Parameters:
    ///   - frameCount: frames to deliver before ending; `nil` keeps going until `stop()` (real-time only; scripted
    ///     timing delivers one frame per time).
    ///   - endError: when set, the stream ends with this error after the last frame (for example "window closed").
    ///   - startError: when set, `start` throws it (for example a permission failure).
    ///   - frameSize: overrides the delivered buffer size (to simulate wrong-size frames); defaults to the
    ///     requested size.
    public init(
        clock: any HostClock, timing: Timing = .realTime(interval: 1.0 / 60), frameCount: Int? = nil,
        endError: SkreenrekError? = nil, startError: SkreenrekError? = nil, frameSize: PixelSize? = nil
    ) {
        self.clock = clock
        self.timing = timing
        self.frameCount = frameCount
        self.endError = endError
        self.startError = startError
        self.frameSize = frameSize
    }

    /// Every `start` call, in order.
    public var starts: [StartCall] { state.withLock { $0.starts } }
    /// Frames delivered so far.
    public var deliveredCount: Int { state.withLock { $0.delivered } }
    /// How many times `stop()` was called.
    public var stopCount: Int { state.withLock { $0.stopped } }

    public func start(target: CaptureTarget, size: PixelSize, fps: FrameRate, showsCursor: Bool) async throws
        -> AsyncThrowingStream<CapturedFrame, Error>
    {
        state.withLock {
            $0.starts.append(StartCall(target: target, size: size, fps: fps, showsCursor: showsCursor))
        }
        if let startError { throw startError }

        let (stream, continuation) = AsyncThrowingStream.makeStream(of: CapturedFrame.self)
        let bufferSize = frameSize ?? size
        let clock = clock
        let timing = timing
        let frameCount = frameCount
        let endError = endError
        let task = Task { [state] in
            do {
                let start = clock.now()
                let limit: Int
                switch timing {
                case .realTime: limit = frameCount ?? .max
                case .scripted(let times, _): limit = min(times.count, frameCount ?? .max)
                }
                var index = 0
                while index < limit, !Task.isCancelled {
                    let hostTime: TimeInterval
                    switch timing {
                    case .realTime(let interval):
                        try await clock.sleep(until: start + Double(index) * interval)
                        hostTime = clock.now()
                    case .scripted(let times, let waitForClock):
                        if waitForClock { try await clock.sleep(until: times[index]) }
                        hostTime = times[index]
                    }
                    let buffer = try SyntheticFrames.makeBuffer(size: bufferSize, index: index)
                    continuation.yield(CapturedFrame(pixelBuffer: buffer, hostTime: hostTime))
                    state.withLock { $0.delivered += 1 }
                    index += 1
                }
                if Task.isCancelled {
                    continuation.finish()
                } else {
                    continuation.finish(throwing: endError)
                }
            } catch {
                continuation.finish(throwing: error is CancellationError ? nil : error)
            }
        }
        let previous = state.withLock { s -> Task<Void, Never>? in
            let previous = s.task
            s.task = task
            s.continuation = continuation
            return previous
        }
        previous?.cancel()
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    public func stop() async {
        let (task, continuation) = state.withLock { s in
            s.stopped += 1
            defer {
                s.task = nil
                s.continuation = nil
            }
            return (s.task, s.continuation)
        }
        task?.cancel()
        continuation?.finish()
    }
}
