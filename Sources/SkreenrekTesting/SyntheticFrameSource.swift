import CoreVideo
import Foundation
import SkreenrekCore
import Synchronization

/// A frame source that makes IOSurface-backed `420v` buffers, the same kind ScreenCaptureKit delivers. Each frame is
/// flat grey whose luma encodes its index (`luma(forFrameIndex:)`), so a test can tell frames apart after encoding.
public final class SyntheticFrameSource: FrameSource {
    /// When frames are delivered and which host time each one carries.
    public enum Timing: Sendable {
        /// Every frame is delivered at once, carrying these host times (irregular gaps allowed).
        case scripted([TimeInterval])
        /// Each frame waits until `clock` reaches its host time (irregular gaps allowed).
        case onClock(any HostClock, [TimeInterval])
        /// A frame every `1 / fps` seconds of `clock` time from the start call; `count` nil runs until `stop()`.
        case realTime(any HostClock, fps: Double, count: Int?)
    }

    /// One `start` call, as received.
    public struct StartCall: Sendable, Hashable {
        public var target: CaptureTarget
        public var size: PixelSize
        public var fps: FrameRate
        public var showsCursor: Bool

        public init(target: CaptureTarget, size: PixelSize, fps: FrameRate, showsCursor: Bool) {
            self.target = target
            self.size = size
            self.fps = fps
            self.showsCursor = showsCursor
        }
    }

    private struct State {
        var task: Task<Void, Never>?
        var continuation: AsyncThrowingStream<CapturedFrame, any Error>.Continuation?
        var startCalls: [StartCall] = []
        var stopCount = 0
        var delivered = 0
    }

    private let timing: Timing
    private let endError: (any Error)?
    private let startError: (any Error)?
    private let frameSizes: [Int: PixelSize]
    private let motion: Bool
    private let state = Mutex(State())

    /// - Parameters:
    ///   - endError: thrown after the last frame (e.g. "window closed"). Ignored for an endless `.realTime`.
    ///   - startError: thrown by `start` (e.g. `SkreenrekError.permissionDenied(.screenRecording)`).
    ///   - frameSizes: frames (by index) made at another size than the one `start` asked for.
    public init(
        timing: Timing, endError: (any Error)? = nil, startError: (any Error)? = nil,
        frameSizes: [Int: PixelSize] = [:], motion: Bool = false
    ) {
        self.timing = timing
        self.endError = endError
        self.startError = startError
        self.frameSizes = frameSizes
        self.motion = motion
    }

    /// `count` frames at `fps`, host times `start + n / fps`, delivered at once.
    public convenience init(count: Int, fps: Double, start: TimeInterval = 0, endError: (any Error)? = nil) {
        self.init(timing: .scripted((0..<count).map { start + Double($0) / fps }), endError: endError)
    }

    public var startCalls: [StartCall] { state.withLock { $0.startCalls } }
    public var stopCount: Int { state.withLock { $0.stopCount } }
    /// Frames yielded so far.
    public var framesDelivered: Int { state.withLock { $0.delivered } }

    public func start(target: CaptureTarget, size: PixelSize, fps: FrameRate, showsCursor: Bool) async throws
        -> AsyncThrowingStream<CapturedFrame, any Error>
    {
        if let startError { throw startError }
        let (stream, continuation) = AsyncThrowingStream<CapturedFrame, any Error>.makeStream()
        let timing = timing
        let endError = endError
        let frameSizes = frameSizes
        let motion = motion
        let startTime: TimeInterval? = if case .realTime(let clock, _, _) = timing { clock.now() } else { nil }

        let task = Task { [weak self] in
            let factory = PixelBufferFactory()
            var index = 0
            do {
                produce: while true {
                    let hostTime: TimeInterval
                    switch timing {
                    case .scripted(let times):
                        guard index < times.count else { break produce }
                        hostTime = times[index]
                    case .onClock(let clock, let times):
                        guard index < times.count else { break produce }
                        hostTime = times[index]
                        try await clock.sleep(until: hostTime)
                    case .realTime(let clock, let fps, let count):
                        if let count, index >= count { break produce }
                        hostTime = (startTime ?? 0) + Double(index) / fps
                        try await clock.sleep(until: hostTime)
                    }
                    try Task.checkCancellation()
                    let buffer = try factory.make(
                        size: frameSizes[index] ?? size, luma: Self.luma(forFrameIndex: index), motionIndex: motion ? index : nil)
                    continuation.yield(CapturedFrame(pixelBuffer: buffer, hostTime: hostTime))
                    self?.state.withLock { $0.delivered += 1 }
                    index += 1
                }
                if let endError {
                    continuation.finish(throwing: endError)
                } else {
                    continuation.finish()
                }
            } catch is CancellationError {
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        let previous = state.withLock { s in
            s.startCalls.append(StartCall(target: target, size: size, fps: fps, showsCursor: showsCursor))
            let previous = (s.task, s.continuation)
            s.task = task
            s.continuation = continuation
            return previous
        }
        previous.0?.cancel()
        previous.1?.finish()
        return stream
    }

    public func stop() async {
        let (task, continuation) = state.withLock { s in
            s.stopCount += 1
            let current = (s.task, s.continuation)
            s.task = nil
            s.continuation = nil
            return current
        }
        task?.cancel()
        continuation?.finish()
    }

    /// Ends the running stream now with `error`, like ScreenCaptureKit when the window closes.
    public func fail(with error: any Error) {
        let (task, continuation) = state.withLock { s in
            let current = (s.task, s.continuation)
            s.task = nil
            s.continuation = nil
            return current
        }
        task?.cancel()
        continuation?.finish(throwing: error)
    }

    // MARK: - Frame index ↔ luma

    /// Distinct luma levels used. Indices repeat every `lumaCycle` frames.
    public static let lumaCycle = 55
    /// Gap between levels, so a lossy encode still decodes to the right index.
    public static let lumaStep = 4

    /// The luma of frame `index`: `16 + (index mod 55) × 4`, inside video range (16–235).
    public static func luma(forFrameIndex index: Int) -> UInt8 {
        UInt8(16 + (index % lumaCycle) * lumaStep)
    }

    /// The frame index (mod 55) for a measured luma value.
    public static func frameIndex(forLuma luma: Double) -> Int {
        let level = Int(((luma - 16) / Double(lumaStep)).rounded())
        return min(max(level, 0), lumaCycle - 1)
    }

    /// The mean luma of a `420v` buffer's Y plane.
    public static func meanLuma(of buffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return 0 }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0
        for y in 0..<height {
            let row = bytes + y * stride
            for x in 0..<width { sum += Int(row[x]) }
        }
        return Double(sum) / Double(max(1, width * height))
    }
}

/// Makes flat `420v` IOSurface-backed buffers from a pool per size. Lives inside one producer task.
private final class PixelBufferFactory {
    private var pool: CVPixelBufferPool?
    private var poolSize: PixelSize?

    struct Failure: Error, CustomStringConvertible {
        var status: CVReturn
        var description: String { "Couldn't make a synthetic pixel buffer (CVReturn \(status))." }
    }

    func make(size: PixelSize, luma: UInt8, motionIndex: Int? = nil) throws -> CVPixelBuffer {
        if poolSize != size {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferWidthKey as String: size.width,
                kCVPixelBufferHeightKey as String: size.height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            ]
            var newPool: CVPixelBufferPool?
            let status = CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &newPool)
            guard status == kCVReturnSuccess, let newPool else { throw Failure(status: status) }
            pool = newPool
            poolSize = size
        }
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool!, &buffer)
        guard status == kCVReturnSuccess, let buffer else { throw Failure(status: status) }
        fill(buffer, luma: luma)
        if let motionIndex { fillMotion(buffer, index: motionIndex) }
        return buffer
    }

    /// Moving textured tiles, deterministic and different on every frame. Enough detail for bitrate tests.
    private func fillMotion(_ buffer: CVPixelBuffer, index: Int) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return }
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let tx = (x + index * 7) / 24
                let ty = (y + index * 3) / 24
                var hash = UInt32(truncatingIfNeeded: tx &* 374761393 &+ ty &* 668265263 &+ index &* 1442695041)
                hash = (hash ^ (hash >> 13)) &* 1274126177
                bytes[y * stride + x] = UInt8(16 + (hash ^ (hash >> 16)) % 220)
            }
        }
    }

    private func fill(_ buffer: CVPixelBuffer, luma: UInt8) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        for (plane, value) in [(0, luma), (1, UInt8(128))] {
            guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, plane) else { continue }
            let bytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, plane) * CVPixelBufferGetHeightOfPlane(buffer, plane)
            memset(base, Int32(value), bytes)
        }
    }
}
