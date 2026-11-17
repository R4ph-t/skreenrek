import CoreGraphics
import Foundation
import SkreenrekCore
import SkreenrekTesting
import Testing

enum EventFixtures {
    /// An external 1× display left of the main one.
    static let leftDisplay = DisplayInfo(
        id: 2, name: "External", scale: 1,
        frame: PointRect(x: -1920, y: 0, width: 1920, height: 1080),
        visibleFrame: PointRect(x: -1920, y: 25, width: 1920, height: 1055))

    static let stats = RecordingStats(
        slotsWritten: 2520, framesFresh: 2400, framesRepeatedIdle: 118, framesDropped: 2, sourceFramesSkipped: 1,
        startToFirstFrameMs: 84.5, stopToFinalizedMs: 41.25, encoder: .hardware, pixelFormat: "420v")

    static func recording(
        target: CaptureTarget = .window(Fixtures.safari), display: DisplayInfo = Fixtures.retina,
        duration: Double = 42.0, client: String? = "Claude Code"
    ) -> EventsFile.Recording {
        let size: PixelSize
        switch target {
        case .window(let w): size = w.pixelSize(on: display)
        case .region(let rect, _): size = rect.size
        }
        return EventsFile.Recording(
            id: "2026-11-17_104207_safari", startedAt: "2026-11-17T10:42:07.120+01:00", duration: duration, fps: 60,
            video: EventsFile.Video(width: size.width, height: size.height, scale: display.scale, codec: .h264),
            source: EventsFile.Source(target: target), startedBy: .mcp, client: client, stats: stats)
    }

    static func down(_ x: Double, _ y: Double, at t: TimeInterval, button: Int = 0, clicks: Int = 1) -> MouseEvent {
        MouseEvent(type: .down, button: button, clickCount: clicks, location: CGPoint(x: x, y: y), hostTime: t)
    }

    static func up(_ x: Double, _ y: Double, at t: TimeInterval, button: Int = 0, clicks: Int = 1) -> MouseEvent {
        MouseEvent(type: .up, button: button, clickCount: clicks, location: CGPoint(x: x, y: y), hostTime: t)
    }

    static func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("skreenrek-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@Suite struct EventRecorderTests {
    typealias F = EventFixtures

    /// Runs a recorder over the fake source: events are sent, then t = 0 is set at `firstFrame`, then the cursor is
    /// sampled once per slot at the given host times.
    func record(
        target: CaptureTarget = .window(Fixtures.safari), display: DisplayInfo = Fixtures.retina,
        events: [MouseEvent], firstFrame: TimeInterval? = 100, cursor: [(TimeInterval, CGPoint)] = []
    ) async throws -> EventLog {
        let source = FakeMouseEventSource()
        let recorder = EventRecorder(source: source, target: target, display: display, fps: .fps60)
        try await recorder.start()
        #expect(source.isRunning)
        for event in events { source.send(event) }
        if let firstFrame { recorder.firstFrame(hostTime: firstFrame) }
        for (t, point) in cursor {
            source.cursor = point
            recorder.sample(hostTime: t)
        }
        let log = await recorder.stop()
        #expect(!source.isRunning)
        return log
    }

    @Test func retinaWindowNotAtTheOrigin() async throws {
        // Safari at (120, 80) pt, 2×: (440, 106) pt → ((440 − 120) × 2, (106 − 80) × 2) = (640, 52) px.
        let log = try await record(events: [F.down(440, 106, at: 101.234), F.up(440, 106, at: 101.310)])
        #expect(log.events == [
            EventsFile.Event(t: 1.234, type: .down, button: .left, clickCount: 1, x: 640, y: 52),
            EventsFile.Event(t: 1.31, type: .up, button: .left, clickCount: 1, x: 640, y: 52),
        ])
    }

    @Test func oneXWindowOnASecondDisplayAtNegativeX() async throws {
        var window = Fixtures.safari
        window.frame = PointRect(x: -1500, y: 200, width: 1280, height: 800)
        window.displayId = 2
        let log = try await record(
            target: .window(window), display: F.leftDisplay, events: [F.down(-1000.4, 250.6, at: 100.5)])
        #expect(log.events.map { [$0.x, $0.y] } == [[500, 51]])
    }

    @Test func regionOnADisplayAtNegativeX() async throws {
        // Region (200, 100) px on the 1× display at x = −1920 pt: global (−1620, 150) → (300, 150) − (200, 100).
        let region = CaptureTarget.region(PixelRect(x: 200, y: 100, width: 1280, height: 800), displayId: 2)
        let log = try await record(target: region, display: F.leftDisplay, events: [F.down(-1620, 150, at: 100)])
        #expect(log.events.map { [$0.x, $0.y] } == [[100, 50]])
    }

    @Test func regionOnARetinaDisplay() async throws {
        let region = CaptureTarget.region(PixelRect(x: 400, y: 200, width: 1280, height: 800), displayId: 1)
        let log = try await record(target: region, display: Fixtures.retina, events: [F.down(300, 150, at: 100)])
        #expect(log.events.map { [$0.x, $0.y] } == [[200, 100]])
    }

    @Test func pointsOutsideTheVideoKeepTheirRealValues() async throws {
        let log = try await record(events: [F.down(100, 70, at: 100), F.down(900, 600, at: 100.1)])
        #expect(log.events.map { [$0.x, $0.y] } == [[-40, -20], [1560, 1040]])
    }

    @Test func coordinatesRoundToWholePixels() {
        let mapping = VideoMapping(target: .window(Fixtures.safari), display: Fixtures.retina)
        let p = mapping.pixel(CGPoint(x: 120.26, y: 80.24))
        #expect(p.x == 1 && p.y == 0)
    }

    @Test func appKitPointsFlipToTopLeft() {
        let p = ScreenGeometry(primaryHeight: 982).topLeft(fromAppKit: CGPoint(x: -300, y: 900))
        #expect(p == CGPoint(x: -300, y: 82))
    }

    @Test func tIsAlignedToTheFirstFrameAndEarlierEventsAreDropped() async throws {
        let log = try await record(
            events: [F.down(440, 106, at: 99.9), F.up(440, 106, at: 99.99), F.down(440, 106, at: 100.0004)],
            firstFrame: 100,
            cursor: [(99.98, CGPoint(x: 120, y: 80)), (100, CGPoint(x: 326, y: 233)), (100 + 1.0 / 60, CGPoint(x: 327, y: 232.5))])
        #expect(log.events.count == 1)
        #expect(log.events.first?.t == 0)
        #expect(log.samples == [CursorSample(t: 0, x: 412, y: 306), CursorSample(t: 0.017, x: 414, y: 305)])
    }

    @Test func withoutAFirstFrameTheLogIsEmpty() async throws {
        let log = try await record(events: [F.down(440, 106, at: 101)], firstFrame: nil, cursor: [(101, .zero)])
        #expect(log == EventLog())
    }

    @Test func buttonsAndClickCounts() async throws {
        let log = try await record(events: [
            F.down(440, 106, at: 101, button: 1), F.down(440, 106, at: 102, button: 2),
            F.down(440, 106, at: 103, button: 3), F.down(440, 106, at: 104, button: 0, clicks: 2),
        ])
        #expect(log.events.map(\.button) == [.right, .middle, .other, .left])
        #expect(log.events.map(\.clickCount) == [1, 1, 1, 2])
        #expect(MouseButton(index: 7) == .other)
    }

    @Test func cursorSamplesRunAtTheClipFps() async throws {
        let ticks = (0..<60).map { (100 + Double($0) / 60, CGPoint(x: 200, y: 200)) }
        let log = try await record(events: [], cursor: ticks)
        #expect(log.samples.count == 60)
        #expect(log.samples.last?.t == 0.983)
    }

    @Test func driveWithTheManualClock() async throws {
        let clock = ManualClock(now: 500)
        let source = FakeMouseEventSource(cursor: CGPoint(x: 120, y: 80))
        let recorder = EventRecorder(source: source, target: .window(Fixtures.safari), display: Fixtures.retina, fps: .fps30)
        try await recorder.start()
        recorder.firstFrame(hostTime: clock.now())
        for _ in 0..<3 {
            recorder.sample(hostTime: clock.now())
            clock.advance(by: 1.0 / 30)
        }
        source.send(F.down(440, 106, at: clock.now()))
        let log = await recorder.stop()
        #expect(log.samples.map(\.t) == [0, 0.033, 0.067])
        #expect(log.events.map(\.t) == [0.1])
    }
}

@Suite struct EventsFileTests {
    typealias F = EventFixtures

    static let log = EventLog(
        samples: [CursorSample(t: 0, x: 412, y: 306), CursorSample(t: 0.017, x: 414, y: 305)],
        events: [
            EventsFile.Event(t: 1.234, type: .down, button: .left, clickCount: 1, x: 640, y: 52),
            EventsFile.Event(t: 1.31, type: .up, button: .left, clickCount: 1, x: 640, y: 52),
            EventsFile.Event(t: 2.5, type: .down, button: .right, clickCount: 1, x: 1, y: 799),
            EventsFile.Event(t: 2.6, type: .up, button: .right, clickCount: 1, x: 1, y: 799),
        ])

    static let golden = """
        {"clicks":[{"button":"left","t":1.234,"x":640,"xPct":50,"y":52,"yPct":6.5},\
        {"button":"right","t":2.5,"x":1,"xPct":0.1,"y":799,"yPct":99.9}],\
        "complete":true,\
        "coordinates":{"origin":"top-left","space":"video","unit":"px"},\
        "cursor":{"sampleRate":60,"samples":[[0,412,306],[0.017,414,305]]},\
        "events":[{"button":"left","clickCount":1,"t":1.234,"type":"down","x":640,"y":52},\
        {"button":"left","clickCount":1,"t":1.31,"type":"up","x":640,"y":52},\
        {"button":"right","clickCount":1,"t":2.5,"type":"down","x":1,"y":799},\
        {"button":"right","clickCount":1,"t":2.6,"type":"up","x":1,"y":799}],\
        "recording":{"client":"Claude Code","duration":42,"fps":60,"id":"2026-11-17_104207_safari",\
        "source":{"app":"Safari","bundleId":"com.apple.Safari","frame":{"height":400,"unit":"pt","width":640,"x":120,"y":80},\
        "kind":"window","title":"localhost:3000","windowId":4127},\
        "startedAt":"2026-11-17T10:42:07.120+01:00","startedBy":"mcp",\
        "stats":{"encoder":"hardware","framesDropped":2,"framesFresh":2400,"framesRepeatedIdle":118,\
        "pixelFormat":"420v","slotsWritten":2520,"sourceFramesSkipped":1,"startToFirstFrameMs":84.5,"stopToFinalizedMs":41.25},\
        "video":{"codec":"h264","file":"clip.mp4","height":800,"scale":2,"width":1280}},\
        "schema":"skreenrek.events/1"}

        """

    @Test func goldenWindowFile() throws {
        let file = EventsFile(recording: F.recording(), complete: true, log: Self.log)
        #expect(String(decoding: try file.data(), as: UTF8.self) == Self.golden)
    }

    @Test func goldenRegionSource() throws {
        let region = CaptureTarget.region(PixelRect(x: 200, y: 100, width: 1280, height: 800), displayId: 2)
        let file = EventsFile(
            recording: F.recording(target: region, display: F.leftDisplay, client: nil), complete: false,
            log: EventLog())
        let json = try SkreenrekJSON.string(file)
        #expect(json.contains(#""source":{"displayId":2,"kind":"region","rect":{"height":800,"unit":"px","width":1280,"x":200,"y":100}}"#))
        #expect(json.contains(#""client":null"#))
        #expect(json.contains(#""complete":false"#))
        #expect(json.contains(#""clicks":[]"#) && json.contains(#""events":[]"#))
        #expect(json.contains(#""video":{"codec":"h264","file":"clip.mp4","height":800,"scale":1,"width":1280}"#))
    }

    @Test func roundTrips() throws {
        let file = EventsFile(recording: F.recording(), complete: true, log: Self.log)
        let decoded = try SkreenrekJSON.decoder().decode(EventsFile.self, from: try file.data())
        #expect(decoded == file)
        let region = EventsFile(
            recording: F.recording(target: .region(PixelRect(x: 0, y: 0, width: 640, height: 480), displayId: 1)),
            complete: true, log: EventLog())
        #expect(try SkreenrekJSON.decoder().decode(EventsFile.self, from: try region.data()) == region)
    }

    @Test func clickPercentages() {
        let events = [
            EventsFile.Event(t: 0, type: .down, button: .left, clickCount: 1, x: 640, y: 52),
            EventsFile.Event(t: 0.1, type: .up, button: .left, clickCount: 1, x: 640, y: 52),
            EventsFile.Event(t: 1, type: .down, button: .middle, clickCount: 1, x: -128, y: 1200),
            EventsFile.Event(t: 2, type: .down, button: .other, clickCount: 3, x: 427, y: 267),
        ]
        let clicks = EventsFile.Click.derive(from: events, width: 1280, height: 800)
        #expect(clicks.map(\.xPct) == [50.0, -10.0, 33.4])
        #expect(clicks.map(\.yPct) == [6.5, 150.0, 33.4])
        #expect(clicks.map(\.button) == [.left, .middle, .other])
        #expect(EventsFile.Click.derive(from: events, width: 0, height: 0).map(\.xPct) == [0, 0, 0])
    }

    @Test func statsCarryEveryRecordingStatsField() throws {
        let file = EventsFile(recording: F.recording(), complete: true, log: EventLog())
        let object = try #require(
            try JSONSerialization.jsonObject(with: try file.data()) as? [String: Any])
        let recording = try #require(object["recording"] as? [String: Any])
        let stats = try #require(recording["stats"] as? [String: Any])
        let expected: Set = [
            "slotsWritten", "framesFresh", "framesRepeatedIdle", "framesDropped", "sourceFramesSkipped",
            "startToFirstFrameMs", "stopToFinalizedMs", "encoder", "pixelFormat",
        ]
        #expect(Set(stats.keys) == expected)
        #expect(Set(Mirror(reflecting: F.stats).children.compactMap(\.label)) == expected)
    }

    @Test func noKeystrokeFieldAnywhere() throws {
        let forbidden: Set = ["key", "keyCode", "characters", "modifiers"]
        var log = Self.log
        log.events.append(EventsFile.Event(t: 3, type: .down, button: .other, clickCount: 2, x: 5, y: 5))
        let file = EventsFile(recording: F.recording(), complete: true, log: log)
        var keys: [String] = []
        func walk(_ value: Any) {
            if let dict = value as? [String: Any] {
                for (k, v) in dict {
                    keys.append(k)
                    walk(v)
                }
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }
        walk(try JSONSerialization.jsonObject(with: try file.data()))
        #expect(!keys.isEmpty)
        for key in keys {
            #expect(!forbidden.contains(key), "events.json has a keystroke field: \(key)")
            #expect(!key.lowercased().contains("key"), "events.json has a keystroke-like field: \(key)")
        }
    }

    @Test func timestampIsLocalTimeWithOffsetAndMilliseconds() throws {
        let date = Date(timeIntervalSince1970: 1_763_372_527.12)  // 2025-11-17T09:42:07.120Z
        let paris = try #require(TimeZone(identifier: "Europe/Paris"))
        #expect(EventsFile.timestamp(date, timeZone: paris) == "2025-11-17T10:42:07.120+01:00")
        #expect(EventsFile.timestamp(date, timeZone: try #require(TimeZone(secondsFromGMT: 0))) == "2025-11-17T09:42:07.120+00:00")
    }

    @Test func writesAtomicallyIntoTheClipFolder() throws {
        let folder = try F.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = EventsFile(recording: F.recording(), complete: true, log: Self.log)
        let url = try file.write(to: folder)
        #expect(url.lastPathComponent == "events.json")
        #expect(try Data(contentsOf: url) == file.data())
        // Rewriting replaces the file and leaves no temp file behind.
        try file.write(to: folder)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["events.json"])
    }
}

@Suite struct SnippetBuilderTests {
    typealias F = EventFixtures

    static let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
    static let clipFolder = URL(fileURLWithPath: "/Users/someone/Movies/Skreenrek/2026-11-17_104207_safari", isDirectory: true)

    static let golden = """
        <!-- Skreenrek · Safari — localhost:3000 · 1280×800 px · 60 fps · 42.0 s · clicks: events.json -->
        <!-- Copy the clip first: cp ~/Movies/Skreenrek/2026-11-17_104207_safari/clip.mp4 assets/2026-11-17_104207_safari.mp4 -->
        <video class="clip" src="assets/2026-11-17_104207_safari.mp4"
               data-start="0" data-duration="42.0" data-track-index="0" muted playsinline></video>

        """

    static let goldenWithAssets = """
        <!-- Skreenrek · Safari — localhost:3000 · 1280×800 px · 60 fps · 42.0 s · clicks: events.json -->
        <video class="clip" src="assets/2026-11-17_104207_safari.mp4"
               data-start="0" data-duration="42.0" data-track-index="0" muted playsinline></video>

        """

    func input(source: EventsFile.Source? = nil, duration: Double = 42.0, hasEvents: Bool = true) -> SnippetBuilder.Input {
        var recording = F.recording(duration: duration)
        if let source { recording.source = source }
        return SnippetBuilder.Input(recording: recording, hasEvents: hasEvents)
    }

    @Test func goldenWithCopyCommand() {
        let text = SnippetBuilder.text(input(), copy: .copyCommand(clipFolder: Self.clipFolder, homeDirectory: Self.home))
        #expect(text == Self.golden)
    }

    @Test func goldenWithAssetsFolder() {
        #expect(SnippetBuilder.text(input(), copy: .none) == Self.goldenWithAssets)
    }

    @Test func withoutEventsTheClicksPartIsLeftOut() {
        let text = SnippetBuilder.text(input(hasEvents: false), copy: .none)
        #expect(text.hasPrefix("<!-- Skreenrek · Safari — localhost:3000 · 1280×800 px · 60 fps · 42.0 s -->\n"))
        #expect(!text.contains("clicks"))
    }

    @Test func durationHasOneDecimal() {
        #expect(SnippetBuilder.text(input(duration: 7.24), copy: .none).contains("· 7.2 s ·"))
        #expect(SnippetBuilder.text(input(duration: 7.26), copy: .none).contains("· 7.3 s ·"))
        #expect(SnippetBuilder.text(input(duration: 3.96), copy: .none).contains(#"data-duration="4.0""#))
    }

    @Test func regionWording() {
        let region = EventsFile.Source.region(displayId: 1, rect: PixelRect(x: 0, y: 0, width: 1280, height: 800))
        let text = SnippetBuilder.text(input(source: region), copy: .none)
        #expect(text.hasPrefix("<!-- Skreenrek · Region 1280×800 px · 1280×800 px · 60 fps · 42.0 s · clicks: events.json -->"))
    }

    @Test func titlesCannotBreakTheComment() {
        let source = EventsFile.Source.window(
            app: "Te<rm>", bundleId: nil, title: "a -- b ---> c\n<!-- d -->", windowId: WindowID(1),
            frame: Fixtures.safari.frame)
        let text = SnippetBuilder.text(input(source: source), copy: .none)
        let first = String(text.split(separator: "\n")[0])
        #expect(first == "<!-- Skreenrek · Te‹rm› — a — b —-› c ‹!— d —› · 1280×800 px · 60 fps · 42.0 s · clicks: events.json -->")
        let inner = first.dropFirst(4).dropLast(3)
        #expect(!inner.contains("--") && !inner.contains(">") && !inner.contains("<"))
    }

    @Test func windowWithoutATitleShowsTheAppOnly() {
        let source = EventsFile.Source.window(
            app: "Finder", bundleId: nil, title: "", windowId: WindowID(1), frame: Fixtures.safari.frame)
        #expect(SnippetBuilder.text(input(source: source), copy: .none).hasPrefix("<!-- Skreenrek · Finder · 1280×800"))
    }

    @Test func neverAnAbsolutePathOrAUserName() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folder = home.appendingPathComponent("Movies/Skreenrek/2026-11-17_104207_safari")
        let text = SnippetBuilder.text(input(), copy: .copyCommand(clipFolder: folder, homeDirectory: home))
        #expect(!text.contains(home.path))
        #expect(!text.contains(NSUserName()))
        #expect(!text.contains(" /"))
        #expect(!text.contains("\"/"))
        #expect(text.contains("cp ~/Movies/Skreenrek/2026-11-17_104207_safari/clip.mp4 "))
    }

    @Test func writesTheSnippetAndCopiesIntoTheAssetsFolder() throws {
        let root = try F.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let clipFolder = root.appendingPathComponent("2026-11-17_104207_safari")
        try FileManager.default.createDirectory(at: clipFolder, withIntermediateDirectories: true)
        try Data("not really a movie".utf8).write(to: clipFolder.appendingPathComponent("clip.mp4"))
        let assets = root.appendingPathComponent("project/assets")

        let text = try SnippetBuilder.write(input(), clipFolder: clipFolder, assetsDir: assets, homeDirectory: root)
        #expect(text == Self.goldenWithAssets)
        #expect(try String(contentsOf: clipFolder.appendingPathComponent("hyperframes.html"), encoding: .utf8) == text)
        let copy = assets.appendingPathComponent("2026-11-17_104207_safari.mp4")
        #expect(try Data(contentsOf: copy) == Data("not really a movie".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: assets.path) == ["2026-11-17_104207_safari.mp4"])

        // A second write replaces the older copy.
        try Data("newer".utf8).write(to: clipFolder.appendingPathComponent("clip.mp4"))
        try SnippetBuilder.write(input(), clipFolder: clipFolder, assetsDir: assets, homeDirectory: root)
        #expect(try Data(contentsOf: copy) == Data("newer".utf8))
    }

    @Test func writesTheCopyCommandWithoutAnAssetsFolder() throws {
        let home = try F.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        let clipFolder = home.appendingPathComponent("Movies/Skreenrek/2026-11-17_104207_safari")
        try FileManager.default.createDirectory(at: clipFolder, withIntermediateDirectories: true)
        let text = try SnippetBuilder.write(input(), clipFolder: clipFolder, assetsDir: nil, homeDirectory: home)
        #expect(text == Self.golden)
        #expect(try FileManager.default.contentsOfDirectory(atPath: clipFolder.path) == ["hyperframes.html"])
    }
}

@Suite struct ClipArtifactsTests {
    typealias F = EventFixtures

    func clipFolder() throws -> (root: URL, folder: URL) {
        let root = try F.temporaryFolder()
        let folder = root.appendingPathComponent("Movies/Skreenrek/2026-11-17_104207_safari")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("mp4".utf8).write(to: folder.appendingPathComponent("clip.mp4"))
        return (root, folder)
    }

    @Test func writesEventsAndSnippet() throws {
        let (root, folder) = try clipFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let written = try ClipArtifacts.write(
            recording: F.recording(), complete: true, log: EventsFileTests.log, events: true, assetsDir: nil,
            clipFolder: folder, homeDirectory: root)
        #expect(written.eventsFile == folder.appendingPathComponent("events.json"))
        #expect(written.snippet == SnippetBuilderTests.golden)
        #expect(written.assetCopy == nil)
        let data = try Data(contentsOf: try #require(written.eventsFile))
        #expect(String(decoding: data, as: UTF8.self) == EventsFileTests.golden)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
            == ["clip.mp4", "events.json", "hyperframes.html"])
    }

    @Test func eventsOffWritesNoEventsFile() throws {
        let (root, folder) = try clipFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let written = try ClipArtifacts.write(
            recording: F.recording(), complete: true, log: EventsFileTests.log, events: false, assetsDir: nil,
            clipFolder: folder, homeDirectory: root)
        #expect(written.eventsFile == nil)
        #expect(!written.snippet.contains("clicks"))
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)) == ["clip.mp4", "hyperframes.html"])
    }

    @Test func partialClipIsMarkedIncomplete() throws {
        let (root, folder) = try clipFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let assets = root.appendingPathComponent("site/assets")
        let written = try ClipArtifacts.write(
            recording: F.recording(), complete: false, log: EventLog(), events: true, assetsDir: assets,
            clipFolder: folder, homeDirectory: root)
        let file = try SkreenrekJSON.decoder().decode(
            EventsFile.self, from: try Data(contentsOf: try #require(written.eventsFile)))
        #expect(file.complete == false)
        #expect(file.events.isEmpty && file.clicks.isEmpty && file.cursor.samples.isEmpty)
        #expect(written.assetCopy == assets.appendingPathComponent("2026-11-17_104207_safari.mp4"))
        #expect(FileManager.default.fileExists(atPath: try #require(written.assetCopy).path))
        #expect(!written.snippet.contains("cp "))
    }
}
