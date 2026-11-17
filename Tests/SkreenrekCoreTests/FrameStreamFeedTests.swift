import CoreVideo
import Foundation
import SkreenrekCore
import SkreenrekTesting
import Synchronization
import Testing

/// A pool that refuses to allocate more than `threshold` live buffers, like ScreenCaptureKit's `queueDepth` pool:
/// if anything downstream kept buffers, allocation would fail.
final class CapturePool: @unchecked Sendable {
    let size: PixelSize
    let threshold: Int
    private let pool: CVPixelBufferPool
    private let failures = Mutex(0)

    init(size: PixelSize = PixelSize(width: 64, height: 32), threshold: Int) {
        self.size = size
        self.threshold = threshold
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        self.pool = pool!
    }

    /// Allocations refused because too many buffers were still alive.
    var refused: Int { failures.withLock { $0 } }

    func frame(at hostTime: TimeInterval) -> CapturedFrame? {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            nil, pool, [kCVPixelBufferPoolAllocationThresholdKey as String: threshold] as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else {
            failures.withLock { $0 += 1 }
            return nil
        }
        return CapturedFrame(pixelBuffer: buffer, hostTime: hostTime)
    }
}

/// A source that delivers exactly the frames the test pushes, through the same bounded feed as ScreenCaptureKit's.
final class PushFrameSource: FrameSource {
    private let current = Mutex<FrameStreamFeed?>(nil)

    var droppedFrameCount: Int { current.withLock { $0?.droppedCount ?? 0 } }

    func start(target: CaptureTarget, size: PixelSize, fps: FrameRate, showsCursor: Bool) async throws
        -> AsyncThrowingStream<CapturedFrame, any Error>
    {
        let feed = FrameStreamFeed()
        current.withLock { $0 = feed }
        return feed.stream
    }

    func push(_ frame: CapturedFrame) {
        current.withLock { $0 }?.yield(frame)
    }

    func stop() async {
        current.withLock { $0 }?.finish()
    }
}

/// A sink whose first append blocks until released, to hold the recorder's consumer.
final class GateSink: PixelBufferSink, @unchecked Sendable {
    private let gate = DispatchSemaphore(value: 0)
    private let state = Mutex((entered: false, appends: 0))
    let encoder: EncoderKind = .software
    var isReady: Bool { true }

    var isHolding: Bool { state.withLock { $0.entered } }
    var appendCount: Int { state.withLock { $0.appends } }

    func release() { gate.signal() }

    func append(_ pixelBuffer: CVPixelBuffer, slot: Int) -> Bool {
        let first = state.withLock { s -> Bool in
            s.appends += 1
            if s.entered { return false }
            s.entered = true
            return true
        }
        if first { gate.wait() }
        return true
    }

    func waitUntilReady(timeout: TimeInterval) async -> Bool { true }
    func finish(slotCount: Int) async throws {}
    func cancel() async {}
}

@Suite struct FrameStreamFeedTests {
    @Test func aFloodKeepsOnlyTheNewestFrameAndCountsEveryDrop() async throws {
        let pool = CapturePool(threshold: 3)
        let feed = FrameStreamFeed()
        for n in 0..<100 {
            feed.yield(try #require(pool.frame(at: Double(n) / 60)))
        }
        // Dropped frames went back to the pool: it never ran dry.
        #expect(pool.refused == 0)
        #expect(feed.droppedCount == 99)
        feed.finish()
        var delivered: [CapturedFrame] = []
        for try await frame in feed.stream { delivered.append(frame) }
        #expect(delivered.map(\.hostTime) == [99.0 / 60])
    }

    @Test func framesTheConsumerKeepsUpWithAreNeverDropped() async throws {
        let feed = FrameStreamFeed()
        var iterator = feed.stream.makeAsyncIterator()
        for n in 0..<20 {
            feed.yield(TestFrames.frame(PixelSize(width: 8, height: 8), at: Double(n)))
            #expect(try await iterator.next()?.hostTime == Double(n))
        }
        #expect(feed.droppedCount == 0)
    }

    @Test func fakesWithoutABoundedStreamReportNoDrops() {
        #expect(SyntheticFrameSource(count: 1, fps: 60).droppedFrameCount == 0)
    }
}

extension RecorderSuites {
    @Suite struct SourceFloodTests {
        /// While the recorder's consumer is held, a flood of capture frames stays bounded (the pool never runs dry)
        /// and every frame the stream dropped is counted in `sourceFramesSkipped`, so the recording isn't clean.
        @Test func aFloodWhileTheConsumerIsHeldStaysBoundedAndIsCounted() async throws {
            let pool = CapturePool(threshold: 6)
            let source = PushFrameSource()
            let sink = GateSink()
            let session = RecordingSession(
                source: source, clock: ManualClock(), disk: FakeDiskSpaceProbe(), encoder: .software,
                makeSink: { _ in sink })
            try await session.start(
                target: .window(Fixtures.safari), size: pool.size, options: RecordingOptions(fps: .fps60),
                folder: Fixtures.unusedFolder)

            source.push(try #require(pool.frame(at: 0)))
            await eventually { sink.isHolding }
            for n in 1...50 {
                if let frame = pool.frame(at: Double(n) / 60) { source.push(frame) }
            }
            #expect(pool.refused == 0, "capture buffers piled up")
            #expect(source.droppedFrameCount == 49)
            sink.release()

            await eventually { await session.framesReceived == 2 }
            #expect(await session.heldBufferCount <= 2)
            let result = try await session.stop()
            print("SourceFloodTests: \(result.stats)")
            #expect(result.stats.sourceFramesSkipped == 49)
            #expect(!result.stats.isClean)
            #expect(result.stats.framesFresh == 2)
            #expect(result.stats.slotsWritten == 51)
        }
    }
}
