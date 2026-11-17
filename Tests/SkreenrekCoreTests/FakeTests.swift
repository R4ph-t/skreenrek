import CoreGraphics
import CoreVideo
import Foundation
import IOSurface
import SkreenrekCore
import SkreenrekTesting
import Testing

private struct WindowClosed: Error, Equatable {}

@Suite struct FakeWindowTests {
    @Test func catalogReturnsWhatTheTestSetsAndCanFail() async throws {
        let catalog = FakeWindowCatalog(windows: [Fixtures.safari], displays: [Fixtures.retina])
        #expect(try await catalog.windows() == [Fixtures.safari])
        #expect(try await catalog.displays() == [Fixtures.retina])
        catalog.failure = SkreenrekError.permissionDenied(.screenRecording)
        await #expect(throws: SkreenrekError.permissionDenied(.screenRecording)) { try await catalog.windows() }
        #expect(catalog.windowsCalls == 2)
    }

    @Test func resizerObeysWithoutRules() async throws {
        let resizer = FakeWindowResizer()
        #expect(try await resizer.readFrame(of: Fixtures.safari) == Fixtures.safari.frame)
        let target = PointRect(x: 10, y: 20, width: 800, height: 500)
        try await resizer.setFrame(target, of: Fixtures.safari)
        #expect(try await resizer.readFrame(of: Fixtures.safari) == target)
        #expect(resizer.calls.map(\.requested) == [target])
    }

    @Test func resizerKeepsAMinimumAndMaximumSize() async throws {
        let resizer = FakeWindowResizer(
            rules: ResizeRules(minimumSize: CGSize(width: 643, height: 300), maximumSize: CGSize(width: 1000, height: 700)))
        try await resizer.setFrame(PointRect(x: 0, y: 0, width: 640, height: 900), of: Fixtures.safari)
        let frame = try await resizer.readFrame(of: Fixtures.safari)
        #expect(frame.width == 643 && frame.height == 700)
        #expect(frame.pixelSize(scale: 2) == PixelSize(width: 1286, height: 1400))
    }

    @Test func resizerSnapsToSizeSteps() async throws {
        let rules = ResizeRules(minimumSize: CGSize(width: 100, height: 50), sizeStep: CGSize(width: 7, height: 15))
        #expect(rules.apply(to: PointRect(x: 0, y: 0, width: 640, height: 400))
            == PointRect(x: 0, y: 0, width: 639, height: 395))
    }

    @Test func resizerIgnoresTheChosenAttempts() async throws {
        let resizer = FakeWindowResizer(rules: ResizeRules(ignoredAttempts: [1]))
        let target = PointRect(x: 120, y: 80, width: 700, height: 400)
        try await resizer.setFrame(target, of: Fixtures.safari)
        #expect(try await resizer.readFrame(of: Fixtures.safari) == Fixtures.safari.frame)
        try await resizer.setFrame(target, of: Fixtures.safari)
        #expect(try await resizer.readFrame(of: Fixtures.safari) == target)
        #expect(resizer.readCount == 2)
    }

    @Test func resizerHasPerWindowRulesAndFailures() async throws {
        let resizer = FakeWindowResizer()
        resizer.setRules(ResizeRules(maximumSize: CGSize(width: 500, height: 500)), for: Fixtures.safari.id)
        try await resizer.setFrame(PointRect(x: 0, y: 0, width: 640, height: 400), of: Fixtures.safari)
        #expect(resizer.currentFrame(of: Fixtures.safari).width == 500)
        resizer.failure = SkreenrekError.permissionDenied(.accessibility)
        await #expect(throws: SkreenrekError.permissionDenied(.accessibility)) {
            try await resizer.readFrame(of: Fixtures.safari)
        }
    }
}

@Suite struct ManualClockTests {
    @Test func sleepResumesOnlyWhenTheClockReachesTheDeadline() async throws {
        let clock = ManualClock(now: 10)
        let task = Task { try await clock.sleep(until: 11); return clock.now() }
        await clock.waitForSleepers(1)
        clock.advance(by: 0.5)
        #expect(clock.sleeperCount == 1)
        #expect(clock.nextDeadline == 11)
        clock.advance(by: 0.5)
        #expect(try await task.value == 11)
        #expect(clock.sleeperCount == 0)
    }

    @Test func aPastDeadlineReturnsAtOnce() async throws {
        let clock = ManualClock(now: 5)
        try await clock.sleep(until: 4)
        try await clock.sleep(until: 5)
        #expect(clock.now() == 5)
    }

    @Test func sleepersWakeInDeadlineOrder() async throws {
        let clock = ManualClock()
        let order = Order()
        let late = Task { try await clock.sleep(until: 2); await order.append(2) }
        await clock.waitForSleepers(1)
        let early = Task { try await clock.sleep(until: 1); await order.append(1) }
        await clock.waitForSleepers(2)
        clock.advance(to: 1)
        try await early.value
        clock.advance(to: 3)
        try await late.value
        #expect(await order.values == [1, 2])
        clock.advance(to: 0)
        #expect(clock.now() == 3)
    }

    @Test func cancellingASleeperThrows() async {
        let clock = ManualClock()
        let task = Task { try await clock.sleep(until: 100) }
        await clock.waitForSleepers(1)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(clock.sleeperCount == 0)
    }

    actor Order {
        var values: [Int] = []
        func append(_ value: Int) { values.append(value) }
    }
}

@Suite struct SyntheticFrameSourceTests {
    static let target = CaptureTarget.window(Fixtures.safari)
    static let size = PixelSize(width: 1280, height: 800)

    static func collect(_ stream: AsyncThrowingStream<CapturedFrame, any Error>) async throws -> [CapturedFrame] {
        var frames: [CapturedFrame] = []
        for try await frame in stream { frames.append(frame) }
        return frames
    }

    @Test func framesAreIOSurfaceBacked420vAtTheRequestedSize() async throws {
        let source = SyntheticFrameSource(count: 3, fps: 30)
        let frames = try await Self.collect(
            try await source.start(target: Self.target, size: Self.size, fps: .fps30, showsCursor: true))
        #expect(frames.count == 3)
        for frame in frames {
            let buffer = frame.pixelBuffer
            #expect(CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
            #expect(CVPixelBufferGetWidth(buffer) == 1280 && CVPixelBufferGetHeight(buffer) == 800)
            #expect(CVPixelBufferGetIOSurface(buffer) != nil)
        }
        #expect(source.startCalls == [.init(target: Self.target, size: Self.size, fps: .fps30, showsCursor: true)])
    }

    @Test func lumaEncodesTheFrameIndex() async throws {
        let source = SyntheticFrameSource(count: 60, fps: 60)
        let frames = try await Self.collect(
            try await source.start(target: Self.target, size: PixelSize(width: 64, height: 32), fps: .fps60,
                                   showsCursor: false))
        for (index, frame) in frames.enumerated() {
            let luma = SyntheticFrameSource.meanLuma(of: frame.pixelBuffer)
            #expect(luma == Double(SyntheticFrameSource.luma(forFrameIndex: index)))
            #expect(SyntheticFrameSource.frameIndex(forLuma: luma) == index % SyntheticFrameSource.lumaCycle)
            #expect(SyntheticFrameSource.frameIndex(forLuma: luma + 1.5) == index % SyntheticFrameSource.lumaCycle)
        }
        #expect((0..<1000).allSatisfy { (16...235).contains(SyntheticFrameSource.luma(forFrameIndex: $0)) })
    }

    @Test func scriptedTimestampsMayBeIrregular() async throws {
        let times: [TimeInterval] = [5.0, 5.01, 5.2, 5.21, 7]
        let source = SyntheticFrameSource(timing: .scripted(times))
        let frames = try await Self.collect(
            try await source.start(target: Self.target, size: Self.size, fps: .fps60, showsCursor: true))
        #expect(frames.map(\.hostTime) == times)
    }

    @Test func theStreamCanEndWithAnError() async throws {
        let source = SyntheticFrameSource(count: 2, fps: 30, endError: WindowClosed())
        let stream = try await source.start(target: Self.target, size: Self.size, fps: .fps30, showsCursor: true)
        var received = 0
        await #expect(throws: WindowClosed.self) {
            for try await _ in stream { received += 1 }
        }
        #expect(received == 2)
    }

    @Test func startCanFail() async {
        let source = SyntheticFrameSource(
            timing: .scripted([0]), startError: SkreenrekError.permissionDenied(.screenRecording))
        await #expect(throws: SkreenrekError.permissionDenied(.screenRecording)) {
            _ = try await source.start(target: Self.target, size: Self.size, fps: .fps30, showsCursor: true)
        }
    }

    @Test func frameSizesCanDifferPerFrame() async throws {
        let source = SyntheticFrameSource(
            timing: .scripted([0, 1, 2]), frameSizes: [1: PixelSize(width: 1282, height: 800)])
        let frames = try await Self.collect(
            try await source.start(target: Self.target, size: Self.size, fps: .fps30, showsCursor: true))
        #expect(frames.map { CVPixelBufferGetWidth($0.pixelBuffer) } == [1280, 1282, 1280])
    }

    @Test func onClockFramesWaitForTheManualClock() async throws {
        let clock = ManualClock()
        let source = SyntheticFrameSource(timing: .onClock(clock, [0.5, 0.7, 1.5]))
        let stream = try await source.start(target: Self.target, size: Self.size, fps: .fps30, showsCursor: true)
        let collector = Task { try await Self.collect(stream) }
        await clock.waitForSleepers(1)
        #expect(source.framesDelivered == 0)
        clock.advance(to: 0.7)
        await clock.waitForSleepers(1)
        #expect(source.framesDelivered == 2)
        clock.advance(to: 2)
        #expect(try await collector.value.map(\.hostTime) == [0.5, 0.7, 1.5])
    }

    @Test func realTimeRunsUntilStop() async throws {
        let clock = ManualClock(now: 100)
        let source = SyntheticFrameSource(timing: .realTime(clock, fps: 10, count: nil))
        let stream = try await source.start(target: Self.target, size: Self.size, fps: .fps30, showsCursor: true)
        let collector = Task { try await Self.collect(stream) }
        // Frame 0 is due at the start time, so it is delivered without advancing.
        await clock.waitForSleepers(1)
        clock.advance(by: 0.1)
        await clock.waitForSleepers(1)
        #expect(source.framesDelivered == 2)
        await source.stop()
        let frames = try await collector.value
        #expect(frames.map(\.hostTime) == [100, 100.1])
        #expect(source.stopCount == 1)
    }

    @Test func failEndsTheRunningStreamWithTheError() async throws {
        let clock = ManualClock()
        let source = SyntheticFrameSource(timing: .realTime(clock, fps: 30, count: nil))
        let stream = try await source.start(target: Self.target, size: Self.size, fps: .fps30, showsCursor: true)
        let collector = Task { try await Self.collect(stream) }
        await clock.waitForSleepers(1)
        source.fail(with: WindowClosed())
        await #expect(throws: WindowClosed.self) { try await collector.value }
    }
}

@Suite struct FakeMouseAndProbeTests {
    @Test func mouseEventsReachTheStreamUntilStop() async throws {
        let mouse = FakeMouseEventSource(cursor: CGPoint(x: 1, y: 2))
        #expect(mouse.cursorLocation() == CGPoint(x: 1, y: 2))
        let stream = try await mouse.start()
        let down = MouseEvent(type: .down, button: 0, clickCount: 1, location: CGPoint(x: 440, y: 106), hostTime: 1.2)
        let up = MouseEvent(type: .up, button: 0, clickCount: 1, location: CGPoint(x: 440, y: 106), hostTime: 1.3)
        mouse.send(down)
        mouse.send(up)
        #expect(mouse.cursorLocation() == CGPoint(x: 440, y: 106))
        await mouse.stop()
        var events: [MouseEvent] = []
        for await event in stream { events.append(event) }
        #expect(events == [down, up])
        #expect(!mouse.isRunning)
    }

    @Test func permissionProbeIsWhatTheTestSays() {
        let probe = FakePermissionProbe(screenRecording: .missing)
        #expect(probe.status(of: .screenRecording) == .missing)
        #expect(probe.status(of: .accessibility) == .allowed)
        probe.screenRecording = .allowed
        #expect(probe.screenRecording == .allowed)
    }

    @Test func diskProbeReportsAndRecordsPaths() throws {
        let disk = FakeDiskSpaceProbe(freeBytes: 3 * FakeDiskSpaceProbe.gigabyte)
        let url = URL(fileURLWithPath: "/tmp")
        #expect(try disk.freeBytes(at: url) == 3_000_000_000)
        disk.failure = SkreenrekError.recordingFailed(.notWritable)
        #expect(throws: SkreenrekError.self) { try disk.freeBytes(at: url) }
        #expect(disk.queried == [url, url])
    }
}
