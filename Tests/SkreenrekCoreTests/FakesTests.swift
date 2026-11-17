import CoreGraphics
import CoreVideo
import Foundation
import SkreenrekCore
import SkreenrekTesting
import Testing

@Suite struct ManualClockTests {
    @Test func onlyAdvancesWhenTold() {
        let clock = ManualClock(now: 10)
        #expect(clock.now() == 10)
        clock.advance(by: 0.5)
        #expect(clock.now() == 10.5)
        clock.advance(to: 3)
        #expect(clock.now() == 10.5)
    }

    @Test func sleepResumesWhenClockReachesDeadline() async throws {
        let clock = ManualClock()
        let woke = Locked<TimeInterval?>(nil)
        let sleeper = Task {
            try await clock.sleep(until: 2)
            woke.withLock { $0 = clock.now() }
        }
        await clock.waitForSleepers(1)
        #expect(clock.nextDeadline == 2)
        clock.advance(to: 1.9)
        #expect(clock.sleeperCount == 1)
        clock.advance(to: 2.5)
        try await sleeper.value
        #expect(woke.current == 2.5)
    }

    @Test func sleepInThePastReturnsAtOnce() async throws {
        let clock = ManualClock(now: 5)
        try await clock.sleep(until: 4)
        try await clock.sleep(until: 5)
        #expect(clock.sleeperCount == 0)
    }

    @Test func cancellationEndsTheSleep() async {
        let clock = ManualClock()
        let sleeper = Task { try await clock.sleep(until: 100) }
        await clock.waitForSleepers(1)
        sleeper.cancel()
        let result = await sleeper.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(clock.sleeperCount == 0)
    }
}

@Suite struct FakeWindowResizerTests {
    static let window = WindowInfo(
        id: 7, app: "Safari", bundleId: "com.apple.Safari", title: "Docs", pid: 1,
        frame: PointRect(x: 10, y: 20, width: 500, height: 300), displayId: 1, onScreen: true)

    @Test func appliesRequestedFrame() async throws {
        let resizer = FakeWindowResizer(windows: [Self.window])
        try await resizer.setFrame(PointRect(x: 0, y: 30, width: 640, height: 400), of: Self.window)
        #expect(try await resizer.readFrame(of: Self.window) == PointRect(x: 0, y: 30, width: 640, height: 400))
        #expect(resizer.calls.count == 1)
    }

    @Test func minimumAndMaximumSizes() async throws {
        let resizer = FakeWindowResizer(
            windows: [Self.window], rules: ResizeRules(minimumSize: (643, 200), maximumSize: (2000, 450)))
        try await resizer.setFrame(PointRect(x: 0, y: 0, width: 640, height: 500), of: Self.window)
        #expect(try await resizer.readFrame(of: Self.window) == PointRect(x: 0, y: 0, width: 643, height: 450))
    }

    @Test func sizeStepsSnapToNearestStep() async throws {
        let resizer = FakeWindowResizer(windows: [Self.window])
        resizer.setRules(ResizeRules(sizeStep: (3.5, 7)), for: Self.window.id)
        try await resizer.setFrame(PointRect(x: 0, y: 0, width: 640, height: 400), of: Self.window)
        let frame = try await resizer.readFrame(of: Self.window)
        #expect(frame.pixelSize(scale: 2) == PixelSize(width: 1281, height: 798))
    }

    @Test func ignoredAttemptLeavesFrameUnchanged() async throws {
        let resizer = FakeWindowResizer(windows: [Self.window], rules: ResizeRules(ignoredAttempts: [1]))
        let target = PointRect(x: 10, y: 20, width: 640, height: 400)
        try await resizer.setFrame(target, of: Self.window)
        #expect(try await resizer.readFrame(of: Self.window) == Self.window.frame)
        try await resizer.setFrame(target, of: Self.window)
        #expect(try await resizer.readFrame(of: Self.window) == target)
    }

    @Test func injectedErrorIsThrown() async {
        let resizer = FakeWindowResizer(windows: [Self.window])
        resizer.error = .permissionDenied(.accessibility)
        await #expect(throws: SkreenrekError.permissionDenied(.accessibility)) {
            try await resizer.setFrame(Self.window.frame, of: Self.window)
        }
    }
}

@Suite struct FakeCatalogAndProbesTests {
    @Test func catalogReturnsWhatTheTestSets() async throws {
        let display = DisplayInfo(
            id: 1, name: "Main", scale: 2, frame: PointRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: PointRect(x: 0, y: 33, width: 1512, height: 949))
        let catalog = FakeWindowCatalog(windows: [FakeWindowResizerTests.window], displays: [display])
        #expect(try await catalog.windows() == [FakeWindowResizerTests.window])
        #expect(try await catalog.displays() == [display])
        catalog.error = .permissionDenied(.screenRecording)
        await #expect(throws: SkreenrekError.permissionDenied(.screenRecording)) { try await catalog.windows() }
    }

    @Test func probesReturnWhatTheTestSets() throws {
        let permissions = FakePermissionProbe(screenRecording: .missing)
        #expect(permissions.status(of: .screenRecording) == .missing)
        #expect(permissions.status(of: .accessibility) == .allowed)
        permissions.screenRecording = .allowed
        #expect(permissions.screenRecording == .allowed)

        let disk = FakeDiskSpaceProbe(freeBytes: 1_000)
        let url = URL(fileURLWithPath: "/tmp")
        #expect(try disk.freeBytes(at: url) == 1_000)
        disk.error = .recordingFailed(message: "The output folder isn't writable.", hint: "Pick another folder.")
        #expect(throws: SkreenrekError.self) { try disk.freeBytes(at: url) }
        #expect(disk.queries == [url, url])
    }

    @Test func mouseSourceDeliversEventsWhileStarted() async {
        let mouse = FakeMouseEventSource(cursor: CGPoint(x: 5, y: 6))
        #expect(mouse.cursorLocation() == CGPoint(x: 5, y: 6))
        let stream = await mouse.start()
        let down = MouseEvent(type: .down, button: 0, clickCount: 1, location: CGPoint(x: 1, y: 2), hostTime: 1)
        let up = MouseEvent(type: .up, button: 0, clickCount: 1, location: CGPoint(x: 1, y: 2), hostTime: 1.1)
        mouse.send(down)
        mouse.send(up)
        await mouse.stop()
        mouse.send(down)
        var received: [MouseEvent] = []
        for await event in stream { received.append(event) }
        #expect(received == [down, up])
    }
}

@Suite struct SyntheticFrameSourceTests {
    static let target = CaptureTarget.region(PixelRect(x: 0, y: 0, width: 64, height: 48), displayId: 1)
    static let size = PixelSize(width: 64, height: 48)

    @Test func buffersAreIOSurfaceBacked420vWithIndexInLuma() throws {
        for index in [0, 1, 17, 54, 55] {
            let buffer = try SyntheticFrames.makeBuffer(size: Self.size, index: index)
            #expect(CVPixelBufferGetIOSurface(buffer) != nil)
            #expect(CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
            #expect(CVPixelBufferGetWidth(buffer) == 64)
            #expect(CVPixelBufferGetHeight(buffer) == 48)
            #expect(SyntheticFrames.index(of: buffer) == index % SyntheticFrames.lumaLevels)
        }
        #expect(SyntheticFrames.index(forLuma: SyntheticFrames.luma(forIndex: 9) + 1) == 9)
    }

    @Test func scriptedTimestampsAreDeliveredInOrder() async throws {
        let clock = ManualClock()
        let times: [TimeInterval] = [0, 0.016, 0.05, 0.051, 0.2]
        let source = SyntheticFrameSource(clock: clock, timing: .scripted(times, waitForClock: false))
        let stream = try await source.start(target: Self.target, size: Self.size, fps: .fps60, showsCursor: true)
        var seen: [(TimeInterval, Int)] = []
        for try await frame in stream {
            seen.append((frame.hostTime, SyntheticFrames.index(of: frame.pixelBuffer)))
        }
        #expect(seen.map(\.0) == times)
        #expect(seen.map(\.1) == [0, 1, 2, 3, 4])
        #expect(source.starts.first?.fps == .fps60)
    }

    @Test func realTimeFollowsTheManualClock() async throws {
        let clock = ManualClock()
        let source = SyntheticFrameSource(clock: clock, timing: .realTime(interval: 0.5), frameCount: 3)
        let stream = try await source.start(target: Self.target, size: Self.size, fps: .fps30, showsCursor: false)
        let collected = Task {
            var times: [TimeInterval] = []
            for try await frame in stream { times.append(frame.hostTime) }
            return times
        }
        for _ in 0..<2 {
            await clock.waitForSleepers(1)
            clock.advance(by: 0.5)
        }
        #expect(try await collected.value == [0, 0.5, 1.0])
    }

    @Test func canEndWithAnError() async throws {
        let clock = ManualClock()
        let source = SyntheticFrameSource(
            clock: clock, timing: .scripted([0, 0.1], waitForClock: false),
            endError: .recordingFailed(message: "window closed", hint: "Run: skreenrek last"))
        let stream = try await source.start(target: Self.target, size: Self.size, fps: .fps30, showsCursor: true)
        var count = 0
        var ended: Error?
        do {
            for try await _ in stream { count += 1 }
        } catch {
            ended = error
        }
        #expect(count == 2)
        #expect(ended is SkreenrekError)
    }

    @Test func wrongSizeFramesCanBeSimulated() async throws {
        let source = SyntheticFrameSource(
            clock: ManualClock(), timing: .scripted([0], waitForClock: false),
            frameSize: PixelSize(width: 32, height: 24))
        let stream = try await source.start(target: Self.target, size: Self.size, fps: .fps30, showsCursor: true)
        for try await frame in stream {
            #expect(CVPixelBufferGetWidth(frame.pixelBuffer) == 32)
        }
    }

    @Test func stopEndsTheStream() async throws {
        let clock = ManualClock()
        let source = SyntheticFrameSource(clock: clock, timing: .realTime(interval: 1))
        let stream = try await source.start(target: Self.target, size: Self.size, fps: .fps30, showsCursor: true)
        let collected = Task {
            var count = 0
            for try await _ in stream { count += 1 }
            return count
        }
        await clock.waitForSleepers(1)
        await source.stop()
        #expect(try await collected.value <= 1)
        #expect(source.stopCount == 1)
    }

    @Test func startErrorIsThrown() async {
        let source = SyntheticFrameSource(clock: ManualClock(), startError: .permissionDenied(.screenRecording))
        await #expect(throws: SkreenrekError.permissionDenied(.screenRecording)) {
            _ = try await source.start(target: Self.target, size: Self.size, fps: .fps30, showsCursor: true)
        }
    }
}
