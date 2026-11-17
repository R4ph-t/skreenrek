import AVFoundation
import Darwin
import Foundation
import SkreenrekControl
import SkreenrekCore
import SkreenrekTesting
import Synchronization
import Testing

/// The whole flow over a real Unix socket against a `HeadlessHost` with fakes.
@Suite(.timeLimit(.minutes(2))) struct ControlFlowTests {
    @Test func windowsThenStartWithASizeThenStopWritesTheThreeFiles() async throws {
        let h = try Harness(encode: true).start()
        defer { h.stop() }
        let client = try await h.client(.mcp, name: "Claude Code")

        let windows = try await client.call(.windows, params: WindowsParams(), as: WindowsBody.self)
        #expect(windows.windows.map(\.id) == [WindowID(4127), WindowID(5001)])
        let safari = try #require(windows.windows.first)
        #expect(safari.width == 1280 && safari.height == 800 && safari.unit == "px" && safari.displayId == 1)

        let start = try await client.call(
            .recordStart, params: StartParams(windowId: 4127, width: 1280, height: 720, fps: 30), as: StartBody.self)
        let readback = try #require(start.readback)
        // 720p on the 2× display: a 1280 × 720 pt window, recorded natively and scaled down to 1280 × 720 px.
        #expect(readback.exact)
        #expect(readback.actual == PixelSize(width: 1280, height: 720))
        #expect(readback.frame == PointRect(x: 120, y: 80, width: 1280, height: 720))
        #expect(start.fps == 30)
        #expect(start.recordingId.hasSuffix("_safari"))
        #expect(h.source.startCalls.map(\.size) == [PixelSize(width: 1280, height: 720)])

        try await h.waitForSlots(15)
        h.mouse.send(MouseEvent(type: .down, button: 0, clickCount: 1, location: CGPoint(x: 760, y: 440), hostTime: 0.5))
        h.mouse.send(MouseEvent(type: .up, button: 0, clickCount: 1, location: CGPoint(x: 760, y: 440), hostTime: 0.6))
        try await h.waitForSlots(30)

        let reply = try await client.send(.recordStop)
        let stop = try reply.decode(StopBody.self)
        #expect(stop.recording.id == start.recordingId)
        #expect(stop.recording.width == 1280 && stop.recording.height == 720)
        // Spec 13: the window in points next to the video, whose scale is native-to-clip.
        #expect(stop.recording.window == WindowPoints(width: 1280, height: 720))
        #expect(stop.recording.video.scale == 2)
        #expect(stop.recording.fps == 30)
        #expect(stop.recording.codec == .h264)
        #expect(stop.recording.startedBy == .mcp)
        #expect(stop.recording.startedAt == start.startedAt)
        #expect(stop.recording.duration == Double(stop.recording.stats.slotsWritten) / 30)
        #expect(stop.recording.stats.stopToFinalizedMs != nil)
        #expect(stop.readback == readback)

        // The design spec's `stop --json` keys, plus 03's stats.
        let object = try jsonObject(reply.line)
        let result = try #require(object["result"] as? [String: Any])
        #expect(Set(result.keys) == ["recording", "files", "snippet", "readback"])
        let recording = try #require(result["recording"] as? [String: Any])
        #expect(
            Set(recording.keys)
                == [
                    "id", "duration", "fps", "width", "height", "codec", "startedAt", "startedBy", "stats", "video",
                    "window",
                ])
        #expect(try #require(recording["window"] as? [String: Int]) == ["width": 1280, "height": 720])
        #expect(Set(try #require(result["files"] as? [String: Any]).keys) == ["clip", "events", "snippet"])

        let fm = FileManager.default
        let folder = h.temp.output.appendingPathComponent(start.recordingId)
        #expect(stop.files.clip == folder.appendingPathComponent("clip.mp4").path)
        #expect(stop.files.events == folder.appendingPathComponent("events.json").path)
        #expect(stop.files.snippet == folder.appendingPathComponent("hyperframes.html").path)
        for path in [stop.files.clip, stop.files.events!, stop.files.snippet] {
            #expect(fm.fileExists(atPath: path), "\(path)")
        }
        #expect(try String(contentsOfFile: stop.files.snippet, encoding: .utf8) == stop.snippet)
        #expect(stop.snippet.hasPrefix("<!-- Skreenrek · Safari — localhost:3000 · 1280×720 px · 30 fps"))

        let clip = stop.files.clip
        let size = try await within("the clip's video size") {
            try await AVURLAsset(url: URL(fileURLWithPath: clip)).loadTracks(withMediaType: .video).first?
                .load(.naturalSize)
        }
        #expect(size == CGSize(width: 1280, height: 720))

        let events = try JSONDecoder().decode(
            EventsFile.self, from: Data(contentsOf: URL(fileURLWithPath: stop.files.events!)))
        #expect(events.complete)
        #expect(events.recording.id == start.recordingId)
        #expect(events.recording.client == "Claude Code")
        #expect(events.recording.startedBy == .mcp)
        #expect(events.recording.video.width == 1280 && events.recording.video.scale == 2)
        // The frame is fixed at start: the one read back after the resize.
        #expect(events.recording.source == .window(
            app: "Safari", bundleId: "com.apple.Safari", title: "localhost:3000", windowId: WindowID(4127),
            frame: readback.frame))
        // (760, 440) pt is (640, 360) pt inside the frame: (640, 360) px in the 1:1 pt-to-clip video, its middle.
        #expect(events.clicks.map { [$0.x, $0.y] } == [[640, 360]])
        #expect(events.events.map(\.type) == [.down, .up])
        #expect(events.cursor.samples.count == stop.recording.stats.slotsWritten)

        let last = try await client.call(.last, as: StopBody.self)
        #expect(last == stop)
        let status = try await client.call(.status, as: StatusBody.self)
        #expect(status.state == .idle)
        #expect(status.lastClip == stop)
    }

    @Test func twoClientsStartingAtOnceGetOneRecordingAndOneWrongState() async throws {
        let h = try Harness().start()
        defer { h.stop() }
        let a = try await h.client()
        let b = try await h.client()
        let params = StartParams(app: "Safari")
        async let first = a.send(.recordStart, params: params)
        async let second = b.send(.recordStart, params: params)
        let replies = try await [first, second]
        var started = 0
        var refused: [ErrorBody] = []
        for reply in replies {
            do {
                _ = try reply.decode(StartBody.self)
                started += 1
            } catch let error as ControlRemoteError {
                refused.append(error.body)
            }
        }
        #expect(started == 1)
        #expect(refused.count == 1)
        #expect(refused.first?.exit == 6)
        #expect(refused.first?.code == "wrong_state")
        #expect(refused.first?.message == "Skreenrek is already recording Safari.")
        #expect(refused.first?.hint == "Run: skreenrek stop")
        #expect(h.source.startCalls.count == 1)
        try await h.waitForSlots(1)
        _ = try await a.call(.recordStop, as: StopBody.self)
    }

    @Test func stopAndDiscardWhileIdleAreWrongState() async throws {
        let h = try Harness().start()
        defer { h.stop() }
        let client = try await h.client()
        for method in [ControlProtocol.Method.recordStop, .recordDiscard, .recordWait] {
            let error = try await client.expectError(method)
            #expect(error.code == "wrong_state")
            #expect(error.exit == 6)
            #expect(error.message == "Nothing is recording.")
        }
        let last = try await client.expectError(.last)
        #expect(last.code == "wrong_state")
    }

    @Test func aSizeThatIsNotExactFailsWithExit4UnlessAllowInexact() async throws {
        let h = try Harness().start()
        defer { h.stop() }
        // 1280 × 800 asks for a 1280 × 800 pt window; Safari won't go narrower than 1286 pt (a 1286 px clip).
        h.resizer.rules = ResizeRules(minimumSize: CGSize(width: 1286, height: 100))
        let client = try await h.client()

        let error = try await client.expectError(
            .recordStart, params: StartParams(app: "Safari", width: 1280, height: 800))
        #expect(error.exit == 4)
        #expect(error.code == "not_exact")
        #expect(error.message == "Safari can't be narrower than 1286 px. It is 1286 × 800 px now.")
        #expect(h.source.startCalls.isEmpty)
        #expect((try? FileManager.default.contentsOfDirectory(atPath: h.temp.output.path))?.isEmpty ?? true)
        #expect(try await client.call(.status, as: StatusBody.self).state == .idle)

        let start = try await client.call(
            .recordStart, params: StartParams(app: "Safari", width: 1280, height: 800, allowInexact: true),
            as: StartBody.self)
        let readback = try #require(start.readback)
        #expect(!readback.exact)
        #expect(readback.actual == PixelSize(width: 1286, height: 800))
        #expect(readback.attempts == 3)
        // The recording is the size the window really has.
        #expect(h.source.startCalls.map(\.size) == [PixelSize(width: 1286, height: 800)])
        _ = try await client.call(.recordDiscard, as: DiscardBody.self)
    }

    /// The capture permissions are checked first: a missing one never resizes the window or touches capture, so
    /// recording is never where a macOS prompt first appears.
    @Test func startWithoutScreenRecordingFailsWithExit3BeforeTheResize() async throws {
        let h = try Harness().start()
        defer { h.stop() }
        h.permissions.screenRecording = .missing
        let client = try await h.client()
        let error = try await client.expectError(
            .recordStart, params: StartParams(app: "Safari", width: 1440, height: 900))
        #expect(error.exit == 3)
        #expect(error.code == "permission_denied")
        #expect(error.message == "Screen Recording isn't allowed for Skreenrek.")
        #expect(h.resizer.calls.isEmpty)
        #expect(h.source.startCalls.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: h.temp.output.path))
        #expect(try await client.call(.status, as: StatusBody.self).state == .idle)
    }

    @Test func resizeWithoutAccessibilityFailsWithExit3AndNothingChanges() async throws {
        let h = try Harness(picker: FakeWindowPicker(result: .window(WindowID(4127)))).start()
        defer { h.stop() }
        h.permissions.accessibility = .missing
        let client = try await h.client()
        _ = try await client.call(.pick, params: PickParams(), as: PickBody.self, timeout: 30)
        let before = try await client.call(.status, as: StatusBody.self)

        let error = try await client.expectError(.resize, params: ResizeParams(app: "Safari", width: 1440, height: 900))
        #expect(error.exit == 3)
        #expect(error.code == "permission_denied")
        #expect(error.message == "Accessibility isn't allowed for Skreenrek.")
        #expect(h.resizer.calls.isEmpty)
        #expect(try await client.call(.status, as: StatusBody.self) == before)

        // A start with a size needs Accessibility too.
        let start = try await client.expectError(.recordStart, params: StartParams(width: 1440, height: 900))
        #expect(start.exit == 3)
        #expect(start.message == "Accessibility isn't allowed for Skreenrek.")
        #expect(h.source.startCalls.isEmpty)
    }

    @Test func resizeReturnsTheReadBackAndUpdatesTheArmedWindow() async throws {
        let h = try Harness(picker: FakeWindowPicker(result: .window(WindowID(4127)))).start()
        defer { h.stop() }
        let client = try await h.client()
        let picked = try await client.call(.pick, params: PickParams(timeoutSeconds: 5), as: PickBody.self, timeout: 30)
        #expect(picked == .window(WindowEntry(ResolvedWindow(window: ControlFixtures.safari, display: ControlFixtures.retina))))
        #expect(h.picker.timeouts == [5])
        #expect(try await client.call(.status, as: StatusBody.self).state == .armed)

        // No window named: the armed one.
        let readback = try await client.call(.resize, params: ResizeParams(width: 1920, height: 1080), as: Readback.self)
        #expect(readback.exact)
        #expect(readback.window.id == WindowID(4127))
        let status = try await client.call(.status, as: StatusBody.self)
        #expect(status.state == .armed)
        #expect(status.readback == readback)
        #expect(status.window?.width == 1920)
    }

    @Test func startPickOrResizeDuringAResizeIsWrongState() async throws {
        let h = try Harness(picker: FakeWindowPicker(result: .window(WindowID(4127)))).start()
        defer { h.stop() }
        let resizer = try await h.client()
        let other = try await h.client()
        h.resizeGate.close()
        async let resized = resizer.call(
            .resize, params: ResizeParams(app: "Safari", width: 1440, height: 900), as: Readback.self)
        try await within("the held resize") { await h.resizeGate.waitForHeldCall() }

        let start = try await other.expectError(.recordStart, params: StartParams(app: "Terminal"))
        #expect(start.exit == 6)
        #expect(start.code == "wrong_state")
        #expect(start.message == "Skreenrek is resizing a window.")
        let second = try await other.expectError(
            .resize, params: ResizeParams(app: "Terminal", width: 1280, height: 800))
        #expect(second.exit == 6)
        let pick = try await other.expectError(.pick, params: PickParams())
        #expect(pick.exit == 6)
        #expect(h.source.startCalls.isEmpty)
        #expect(h.picker.timeouts.isEmpty)

        h.resizeGate.open()
        #expect(try await resized.exact)
        #expect(h.resizer.calls.count == 1)
        // Once the resize is done, a start goes through.
        _ = try await other.call(.recordStart, params: StartParams(app: "Terminal"), as: StartBody.self)
        _ = try await other.call(.recordDiscard, as: DiscardBody.self)
    }

    @Test func aStartThatFailsInTheRecorderLeavesNoClipFolder() async throws {
        let source = SyntheticFrameSource(
            timing: .scripted([]), startError: SkreenrekError.permissionDenied(.screenRecording))
        let h = try Harness(source: source).start()
        defer { h.stop() }
        let client = try await h.client()
        let error = try await client.expectError(.recordStart, params: StartParams(app: "Safari"))
        #expect(error.exit == 3)
        let left = (try? FileManager.default.contentsOfDirectory(atPath: h.temp.output.path)) ?? []
        #expect(left.isEmpty)
        #expect(try await client.call(.status, as: StatusBody.self).state == .idle)
    }

    @Test func resizeWhileRecordingIsWrongState() async throws {
        let h = try Harness().start()
        defer { h.stop() }
        let client = try await h.client()
        _ = try await client.call(.recordStart, params: StartParams(app: "Safari"), as: StartBody.self)
        let error = try await client.expectError(.resize, params: ResizeParams(app: "Safari", width: 1440, height: 900))
        #expect(error.code == "wrong_state")
        #expect(error.message == "Skreenrek is already recording Safari.")
        #expect(h.resizer.calls.isEmpty)
        _ = try await client.call(.recordDiscard, as: DiscardBody.self)
    }

    @Test func recordWaitReturnsTheStopBodyWhenTheDurationEnds() async throws {
        // 1 s at 30 fps: frames arrive as the manual clock reaches them, and the 31st reaches the slot limit.
        let clock = ManualClock()
        let source = SyntheticFrameSource(timing: .onClock(clock, (0...30).map { Double($0) / 30 }))
        let h = try Harness(source: source, clock: clock).start()
        defer { h.stop() }
        let starter = try await h.client()
        let waiter = try await h.client()
        let start = try await starter.call(
            .recordStart, params: StartParams(app: "Safari", durationSeconds: 1), as: StartBody.self)
        async let wait = waiter.call(.recordWait, as: EndBody.self, timeout: 30)
        try await h.waitForEndWaiters(1)
        clock.advance(to: 1 + RecordingSession.defaultTickGrace)
        let ended = try await wait
        guard case .saved(let body) = ended else {
            Issue.record("record.wait returned \(ended)")
            return
        }
        #expect(body.recording.id == start.recordingId)
        #expect(body.recording.duration == 1)
        #expect(body.recording.stats.slotsWritten == 30)
        #expect(body.readback == nil)
        #expect(try await starter.call(.last, as: StopBody.self) == body)
    }

    @Test func discardDeletesTheClipAndWaitSaysDiscarded() async throws {
        let h = try Harness().start()
        defer { h.stop() }
        let client = try await h.client()
        let waiter = try await h.client()
        let start = try await client.call(.recordStart, params: StartParams(app: "Safari"), as: StartBody.self)
        try await h.waitForSlots(5)
        async let wait = waiter.call(.recordWait, as: EndBody.self, timeout: 30)
        // record.wait is waiting before the discard goes out.
        try await h.waitForEndWaiters(1)
        let discarded = try await client.call(.recordDiscard, as: DiscardBody.self)
        #expect(discarded.discarded)
        #expect(try await wait == .discarded)
        let folder = h.temp.output.appendingPathComponent(start.recordingId)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        let status = try await client.call(.status, as: StatusBody.self)
        #expect(status.state == .idle)
        #expect(status.lastClip == nil)
    }

    @Test func aClosedWindowEndsInTheErrorStateWithAPartialClip() async throws {
        let source = SyntheticFrameSource(count: 20, fps: 30, endError: FrameSourceError.windowClosed)
        let h = try Harness(source: source).start()
        defer { h.stop() }
        let client = try await h.client()
        _ = try await client.call(.recordStart, params: StartParams(app: "Safari"), as: StartBody.self)
        // The source ends on its own; the recording may be over before any request gets there.
        try await h.waitForState(.error)
        let error = try #require(try await client.call(.status, as: StatusBody.self).error)
        #expect(error.exit == 7)
        #expect(error.code == "recording_failed")
        #expect(error.message == "The window closed at 0:00. The clip up to that point was saved.")

        let status = try await client.call(.status, as: StatusBody.self)
        #expect(status.state == .error)
        #expect(status.error == error)
        let last = try await client.call(.last, as: StopBody.self)
        #expect(last.recording.stats.slotsWritten == 20)
        let events = try JSONDecoder().decode(
            EventsFile.self, from: Data(contentsOf: URL(fileURLWithPath: try #require(last.files.events))))
        #expect(!events.complete)

        // The error clears on the next action.
        _ = try? await client.send(.recordStop)
        #expect(try await client.call(.status, as: StatusBody.self).state == .idle)
    }

    @Test func eventsOffWritesNoEventsFile() async throws {
        let h = try Harness().start()
        defer { h.stop() }
        let client = try await h.client()
        _ = try await client.call(.recordStart, params: StartParams(app: "Terminal", events: false), as: StartBody.self)
        try await h.waitForSlots(10)
        let stop = try await client.call(.recordStop, as: StopBody.self)
        #expect(stop.files.events == nil)
        #expect(!stop.snippet.contains("events.json"))
        #expect(h.mouse.startCount == 0)
    }

    @Test func pickArmsAWindowAndStartRecordsIt() async throws {
        let picker = FakeWindowPicker(result: nil)
        let h = try Harness(picker: picker).start()
        defer { h.stop() }
        let client = try await h.client(.menu)
        async let picked = client.call(.pick, params: PickParams(), as: PickBody.self, timeout: 30)
        try await within("a pick") { await picker.waitForPick() }
        picker.answer(.window(WindowID(5001)))
        guard case .window(let entry) = try await picked else {
            Issue.record("not a window")
            return
        }
        #expect(entry.app == "Terminal")
        #expect(picker.timeouts == [60])

        let other = try await h.client()
        let status = try await other.call(.status, as: StatusBody.self)
        #expect(status.state == .armed)
        #expect(status.window?.id == WindowID(5001))

        let start = try await other.call(.recordStart, params: StartParams(), as: StartBody.self)
        #expect(start.recordingId.hasSuffix("_terminal"))
        #expect(h.source.startCalls.first?.target == .window(ControlFixtures.terminal))
        _ = try await other.call(.recordDiscard, as: DiscardBody.self)
    }

    @Test func aCancelledPickChangesNothingAndStartWithNothingPickedIsUsage() async throws {
        let h = try Harness(picker: FakeWindowPicker(result: .cancelled)).start()
        defer { h.stop() }
        let client = try await h.client()
        #expect(try await client.call(.pick, params: PickParams(), as: PickBody.self, timeout: 30) == .cancelled)
        let reply = try await client.send(.pick, params: PickParams(), timeout: 30)
        #expect(String(decoding: reply.line, as: UTF8.self).contains(#""result":{"cancelled":true}"#))
        #expect(try await client.call(.status, as: StatusBody.self).state == .idle)
        let error = try await client.expectError(.recordStart, params: StartParams())
        #expect(error.code == "usage")
        #expect(error.exit == 2)
    }

    @Test func theDefaultPickerSaysItIsNotAvailableYet() async throws {
        let h = try Harness().start()
        defer { h.stop() }
        let controller = SkreenrekController(
            seams: ControllerSeams(
                catalog: h.catalog, resizer: h.resizer, frameSource: h.source, mouse: h.mouse, clock: h.clock,
                permissions: h.permissions, disk: h.disk))
        await #expect(throws: UnavailableWindowPicker.error) { try await controller.pick() }
    }

    @Test func aRegionRecordsAtItsOwnSize() async throws {
        let h = try Harness().start()
        defer { h.stop() }
        let client = try await h.client()
        let start = try await client.call(
            .recordStart, params: StartParams(region: RegionParams(x: 100, y: 200, width: 640, height: 360)),
            as: StartBody.self)
        #expect(start.recordingId.hasSuffix("_region"))
        #expect(
            h.source.startCalls.first?.target
                == .region(PixelRect(x: 100, y: 200, width: 640, height: 360), displayId: 1))
        #expect(h.source.startCalls.first?.size == PixelSize(width: 640, height: 360))
        _ = try await client.call(.recordDiscard, as: DiscardBody.self)

        let outside = try await client.expectError(
            .recordStart, params: StartParams(region: RegionParams(x: 3000, y: 0, width: 640, height: 360)))
        #expect(outside.code == "usage")
        let both = try await client.expectError(
            .recordStart, params: StartParams(app: "Safari", region: RegionParams(x: 0, y: 0, width: 64, height: 64)))
        #expect(both.code == "usage")
    }

    @Test func badStartOptionsAreUsageErrors() async throws {
        let h = try Harness().start()
        defer { h.stop() }
        let client = try await h.client()
        let cases: [StartParams] = [
            StartParams(app: "Safari", fps: 24),
            StartParams(app: "Safari", codec: "av1"),
            StartParams(app: "Safari", durationSeconds: 0),
            StartParams(app: "Safari", width: 1280),
            StartParams(app: "Safari", width: 1281, height: 800),
        ]
        for params in cases {
            let error = try await client.expectError(.recordStart, params: params)
            #expect(error.code == "usage", "\(params)")
            #expect(error.exit == 2)
        }
        #expect(h.source.startCalls.isEmpty)
    }

    @Test func anUnknownWindowIsExit5() async throws {
        let h = try Harness().start()
        defer { h.stop() }
        let client = try await h.client()
        let error = try await client.expectError(.recordStart, params: StartParams(app: "Xcode"))
        #expect(error.exit == 5)
        #expect(error.code == "window_not_found")
    }

    @Test func statusDuringARecordingShowsWhoStartedIt() async throws {
        let clock = ManualClock(now: 100)
        let source = SyntheticFrameSource(timing: .scripted((0..<31).map { 100 + Double($0) / 30 }))
        let h = try Harness(source: source, clock: clock).start()
        defer { h.stop() }
        let mcp = try await h.client(.mcp, name: "Claude Code")
        let start = try await mcp.call(.recordStart, params: StartParams(app: "Safari"), as: StartBody.self)
        clock.advance(by: 12.3456)
        let status = try await (try await h.client()).call(.status, as: StatusBody.self)
        #expect(status.state == .recording)
        #expect(status.window?.app == "Safari")
        let recording = try #require(status.recording)
        #expect(recording.id == start.recordingId)
        #expect(recording.elapsed == 12.346)
        #expect(recording.startedBy == .mcp)
        #expect(recording.client == "Claude Code")
        #expect(recording.width == 1280 && recording.height == 800)
        _ = try await mcp.call(.recordDiscard, as: DiscardBody.self)
    }

    @Test func doctorReportsPermissionsVersionFolderAndSocket() async throws {
        let h = try Harness().start()
        defer { h.stop() }
        h.permissions.accessibility = .missing
        let doctor = try await (try await h.client()).call(.doctor, as: DoctorBody.self)
        #expect(doctor.version == SkreenrekVersion.current)
        #expect(doctor.permissions == .init(screenRecording: .allowed, directCapture: .allowed, accessibility: .missing))
        #expect(doctor.outputFolder.path == h.temp.output.path)
        #expect(doctor.outputFolder.writable)
        #expect(doctor.socket == h.temp.socket.path)
    }

    @Test func helloSaysVersionProtocolAndPid() async throws {
        let h = try Harness().start()
        defer { h.stop() }
        let hello = try await (try await h.client()).call(.hello, as: HelloBody.self)
        #expect(hello == HelloBody(pid: getpid()))
        #expect(hello.protocol == 1)
    }
}

/// The controller's snapshot stream, for the UI.
@Suite(.timeLimit(.minutes(2))) struct ControllerSnapshotTests {
    @Test func clientHUDOptionReachesTheAppSnapshot() async throws {
        let h = try Harness().start()
        defer { h.stop() }
        let client = try await h.client(.mcp)
        _ = try await client.call(.recordStart, params: StartParams(app: "Safari", hud: false), as: StartBody.self)
        #expect(await h.controller.snapshot().hud == false)
        _ = try await client.call(.recordDiscard, as: DiscardBody.self)
    }

    @Test func permissionRejectionNotifiesTheAppAndStillReturnsExitThree() async throws {
        let h = try Harness().start()
        defer { h.stop() }
        let reported = Mutex<[Permission]>([])
        await h.controller.setPermissionFailureHandler { permission in reported.withLock { $0.append(permission) } }
        h.permissions.screenRecording = .missing
        let client = try await h.client(.cli)
        let error = try await client.expectError(.recordStart, params: StartParams(app: "Safari"))
        #expect(error.exit == 3)
        #expect(reported.withLock { $0 } == [.screenRecording])
    }

    @Test func snapshotsGoIdleRecordingWritingIdle() async throws {
        let h = try Harness().start()
        defer { h.stop() }
        let stream = await h.controller.snapshots()
        let collector = Task {
            var states: [ControllerState] = []
            for await snapshot in stream {
                if states.last != snapshot.state { states.append(snapshot.state) }
                if snapshot.state == .idle, snapshot.lastClip != nil { break }
            }
            return states
        }
        let client = try await h.client(.mcp, name: "Codex")
        _ = try await client.call(.recordStart, params: StartParams(app: "Safari"), as: StartBody.self)
        let recording = await h.controller.snapshot()
        #expect(recording.state == .recording)
        #expect(recording.startedBy == .mcp)
        #expect(recording.client == "Codex")
        #expect(recording.window?.id == WindowID(4127))
        #expect(recording.size == PixelSize(width: 1280, height: 800))
        #expect(recording.fps == .fps30)
        try await h.waitForSlots(10)
        _ = try await client.call(.recordStop, as: StopBody.self)
        let states = try await within("the snapshot stream") { await collector.value }
        #expect(states == [.idle, .recording, .writing, .idle])
    }
}

/// The wire protocol's error paths.
@Suite(.timeLimit(.minutes(2))) struct ControlProtocolTests {
    @Test func malformedJSONIsUsageAndTheConnectionStaysUsable() async throws {
        let h = try Harness().start()
        defer { h.stop() }
        let client = try await h.client()
        let reply = try await client.sendRaw(Data("{not json\n".utf8))
        let object = try jsonObject(reply.line)
        #expect(object["v"] as? Int == 1)
        #expect(object["id"] is NSNull)
        let error = try #require(object["error"] as? [String: Any])
        #expect(error["code"] as? String == "usage")
        #expect(error["exit"] as? Int == 2)
        #expect(try await client.call(.hello, as: HelloBody.self).protocol == 1)
    }

    @Test func anotherProtocolVersionIsInternalWithTheReopenHint() async throws {
        let h = try Harness().start()
        defer { h.stop() }
        let client = try await h.client()
        let reply = try await client.sendRaw(Data(#"{"v":2,"id":9,"method":"status"}"#.utf8 + [0x0A]))
        let object = try jsonObject(reply.line)
        #expect(object["id"] as? Int == 9)
        let error = try #require(object["error"] as? [String: Any])
        #expect(error["code"] as? String == "internal")
        #expect(error["exit"] as? Int == 1)
        #expect(error["hint"] as? String == "Quit and reopen Skreenrek so the app and the command match.")
    }

    @Test func unknownMethodsAndBadParamsAreUsage() async throws {
        let h = try Harness().start()
        defer { h.stop() }
        let client = try await h.client()
        let unknown = try await client.send("record.pause", params: NoParams(), timeout: 5)
        #expect(throws: ControlRemoteError.self) { try unknown.decode(NoParams.self) }
        #expect(String(decoding: unknown.line, as: UTF8.self).contains(#""code":"usage""#))

        let bad = try await client.sendRaw(
            Data(#"{"v":1,"id":3,"method":"record.start","params":{"fps":"sixty"}}"#.utf8 + [0x0A]))
        let error = try #require(try jsonObject(bad.line)["error"] as? [String: Any])
        #expect(error["code"] as? String == "usage")
        #expect(error["message"] as? String == "The params for record.start aren't valid: fps has the wrong type.")

        let missing = try await client.sendRaw(
            Data(#"{"v":1,"id":4,"method":"resize","params":{"width":1280}}"#.utf8 + [0x0A]))
        let missingError = try #require(try jsonObject(missing.line)["error"] as? [String: Any])
        #expect(missingError["message"] as? String == "The params for resize aren't valid: height is missing.")
    }

    @Test func aLineOverOneMebibyteIsUsageAndClosesTheConnection() async throws {
        let h = try Harness().start()
        defer { h.stop() }
        let client = try await h.client()
        // No newline: the server stops reading once the buffer passes 1 MiB.
        let huge = Data(repeating: UInt8(ascii: "a"), count: ControlServer.maxLineBytes + 70_000)
        let reply = try await client.sendRaw(huge, timeout: 10)
        let error = try #require(try jsonObject(reply.line)["error"] as? [String: Any])
        #expect(error["code"] as? String == "usage")
        #expect(error["message"] as? String == "The request is longer than 1 MiB.")
        await #expect(throws: ControlClientError.self) { _ = try await client.send(.hello) }
        // Other connections still work.
        #expect(try await (try await h.client()).call(.hello, as: HelloBody.self).protocol == 1)
    }

    @Test func requestsOnOneConnectionAreAnsweredInOrder() async throws {
        let h = try Harness().start()
        defer { h.stop() }
        let client = try await h.client()
        let lines = (1...5).map { #"{"v":1,"id":\#($0),"method":"status"}"# }.joined(separator: "\n") + "\n"
        let first = try await client.sendRaw(Data(lines.utf8))
        #expect(try jsonObject(first.line)["id"] as? Int == 1)
        for id in 2...5 {
            let next = try await client.sendRaw(Data(), timeout: 5)
            #expect(try jsonObject(next.line)["id"] as? Int == id)
        }
    }
}

/// The socket file, its folder, stale sockets and peers.
@Suite(.timeLimit(.minutes(2))) struct ControlServerTests {
    @Test func theFolderIs0700AndTheSocket0600() throws {
        let h = try Harness().start()
        defer { h.stop() }
        var info = stat()
        #expect(stat(h.temp.socket.path, &info) == 0)
        #expect(info.st_mode & S_IFMT == S_IFSOCK)
        #expect(info.st_mode & 0o777 == 0o600)
        #expect(stat(h.temp.socket.deletingLastPathComponent().path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o700)
    }

    @Test func aStaleSocketIsReplacedAndALiveOneMeansAlreadyRunning() async throws {
        let temp = ShortTemp()
        defer { temp.cleanUp() }
        // A socket file nobody listens on, left by a crashed app.
        try FileManager.default.createDirectory(
            at: temp.socket.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(temp.socket.path.utf8)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        #expect(bound == 0)
        close(fd)
        #expect(FileManager.default.fileExists(atPath: temp.socket.path))

        let server = ControlServer(path: temp.socket) { _ in Data() }
        try server.start()
        defer { server.stop() }
        #expect(server.isRunning)

        let second = ControlServer(path: temp.socket) { _ in Data() }
        #expect(throws: ControlServer.StartError.alreadyRunning(path: temp.socket.path)) { try second.start() }
        #expect(server.isRunning)
    }

    @Test func stoppingRemovesTheSocketAndClientsSeeNotRunning() async throws {
        let h = try Harness().start()
        let path = h.temp.socket
        h.host.stop()
        #expect(!FileManager.default.fileExists(atPath: path.path))
        await #expect(throws: ControlClientError.notRunning(path: path.path)) {
            _ = try await ControlClient.connect(path: path, client: ClientInfo(kind: .cli))
        }
        h.temp.cleanUp()
    }

    @Test func aPeerWithAnotherUidIsRefused() async throws {
        let temp = ShortTemp()
        defer { temp.cleanUp() }
        let server = ControlServer(path: temp.socket, allowedUID: geteuid() &+ 1) { line in line + [0x0A] }
        try server.start()
        defer { server.stop() }
        let client = try await ControlClient.connect(path: temp.socket, client: ClientInfo(kind: .cli))
        await #expect(throws: ControlClientError.connectionClosed) {
            _ = try await client.send(.hello)
        }
        #expect(server.rejectedPeerCount == 1)
    }

    @Test func aPathTooLongForAUnixSocketIsRefused() {
        let long = URL(fileURLWithPath: "/tmp/" + String(repeating: "x", count: 120) + "/c.sock")
        let server = ControlServer(path: long) { _ in Data() }
        #expect(throws: ControlServer.StartError.pathTooLong(path: long.path)) { try server.start() }
    }

    @Test func severalClientsAreServedAtOnce() async throws {
        let h = try Harness().start()
        defer { h.stop() }
        let clients = try await withThrowingTaskGroup(of: ControlClient.self) { group in
            for _ in 0..<6 { group.addTask { try await h.client() } }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        try await withThrowingTaskGroup(of: StatusBody.self) { group in
            for client in clients { group.addTask { try await client.call(.status, as: StatusBody.self) } }
            for try await status in group { #expect(status.state == .idle) }
        }
        #expect(h.host.server.connectionCount == 6)
    }
}

@Suite(.timeLimit(.minutes(2))) struct ControlPathsTests {
    @Test func theDefaultIsInApplicationSupportAndTheEnvironmentOverridesIt() {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        #expect(
            ControlPaths.socketURL(environment: [:], home: home).path
                == "/Users/someone/Library/Application Support/skreenrek/control.sock")
        #expect(
            ControlPaths.socketURL(environment: ["SKREENREK_SOCKET": "/tmp/s.sock"], home: home).path == "/tmp/s.sock")
        #expect(ControlPaths.socketURL(environment: ["SKREENREK_SOCKET": ""], home: home).lastPathComponent == "control.sock")
    }
}
