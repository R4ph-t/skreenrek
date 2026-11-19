import Foundation
import SkreenrekCore
import Testing

@Suite struct DomainTests {
    static let readback = Readback(
        window: Readback.Window(Fixtures.safari), display: Readback.Display(Fixtures.retina),
        requested: PixelSize(width: 1280, height: 800), actual: PixelSize(width: 1280, height: 800),
        frame: PointRect(x: 120, y: 80, width: 640, height: 400), exact: true, attempts: 1)

    @Test func readbackEncodesTheDesignSpecShape() throws {
        let json = try SkreenrekJSON.string(Self.readback)
        #expect(
            json == #"{"actual":{"height":800,"unit":"px","width":1280},"attempts":1,"#
                + #""display":{"id":1,"name":"Built-in Retina Display","scale":2},"exact":true,"#
                + #""frame":{"height":400,"unit":"pt","width":640,"x":120,"y":80},"#
                + #""requested":{"height":800,"unit":"px","width":1280},"#
                + #""window":{"app":"Safari","bundleId":"com.apple.Safari","id":4127,"pid":812,"title":"localhost:3000"}}"#)
    }

    @Test func readbackDecodesTheDesignSpecBlockVerbatim() throws {
        let block = """
            {
              "window": { "id": 4127, "app": "Safari", "bundleId": "com.apple.Safari", "title": "localhost:3000", "pid": 812 },
              "display": { "id": 1, "name": "Built-in Retina Display", "scale": 2 },
              "requested": { "width": 1280, "height": 800, "unit": "px" },
              "actual":    { "width": 1280, "height": 800, "unit": "px" },
              "frame":     { "x": 120, "y": 80, "width": 640, "height": 400, "unit": "pt" },
              "exact": true,
              "attempts": 1
            }
            """
        let decoded = try SkreenrekJSON.decoder().decode(Readback.self, from: Data(block.utf8))
        #expect(decoded == Self.readback)
    }

    @Test func missingBundleIdStaysInTheJSONAsNull() throws {
        var readback = Self.readback
        readback.window.bundleId = nil
        let json = try SkreenrekJSON.string(readback)
        #expect(json.contains(#""bundleId":null"#))
        #expect(try SkreenrekJSON.decoder().decode(Readback.self, from: Data(json.utf8)) == readback)
    }

    @Test func aWrongUnitIsADecodingError() {
        let json = #"{"width":1280,"height":800,"unit":"pt"}"#
        #expect(throws: DecodingError.self) {
            try SkreenrekJSON.decoder().decode(PixelSize.self, from: Data(json.utf8))
        }
    }

    @Test func slashesAreNotEscaped() throws {
        let options = RecordingOptions(outDir: URL(fileURLWithPath: "/tmp/clips"))
        #expect(try SkreenrekJSON.string(options).contains("file:///tmp/clips"))
    }

    @Test func windowPixelSizeUsesTheDisplayScale() {
        #expect(Fixtures.safari.pixelSize(on: Fixtures.retina) == PixelSize(width: 1280, height: 800))
        var external = Fixtures.retina
        external.scale = 1
        #expect(Fixtures.safari.pixelSize(on: external) == PixelSize(width: 640, height: 400))
        #expect(PointRect(x: 0, y: 0, width: 640.4, height: 399.6).pixelSize(scale: 2)
            == PixelSize(width: 1281, height: 799))
    }

    @Test func sizesPrintTheDesignSpecWay() {
        let size = PixelSize(width: 1280, height: 800)
        #expect(size.description == "1280 × 800 px")
        #expect(size.flagValue == "1280x800")
    }

    @Test func windowIDEncodesAsABareNumber() throws {
        #expect(try SkreenrekJSON.string([WindowID(4127)]) == "[4127]")
    }

    @Test func controllerStateRawValuesAreTheStatusWords() {
        #expect(ControllerState.allCases.map(\.rawValue) == ["idle", "armed", "recording", "writing", "error"])
    }

    @Test func startedByRawValues() throws {
        #expect(StartedBy.allCases.map(\.rawValue) == ["cli", "mcp", "menu"])
        let origin = RecordingOrigin(startedBy: .mcp, client: "Claude Code")
        #expect(try SkreenrekJSON.string(origin) == #"{"client":"Claude Code","startedBy":"mcp"}"#)
    }

    @Test func recordingOptionDefaults() {
        let options = RecordingOptions()
        #expect(options.fps == .fps60)
        #expect(options.fps.framesPerSecond == 60)
        #expect(options.cursor && options.events && options.hud)
        #expect(options.codec == .h264)
        #expect(options.duration == nil)
        #expect(!options.allowInexact)
        #expect(options.outDir == nil && options.assetsDir == nil && options.name == nil)
    }

    @Test func statsAreCleanOnlyWithoutDropsOrSkips() {
        let clean = RecordingStats(slotsWritten: 60, framesFresh: 40, framesRepeatedIdle: 20, encoder: .software)
        #expect(clean.isClean)
        #expect(clean.pixelFormat == "420v")
        var dropped = clean
        dropped.framesDropped = 1
        #expect(!dropped.isClean)
        var skipped = clean
        skipped.sourceFramesSkipped = 1
        #expect(!skipped.isClean)
    }

    @Test func statsJSONUsesTheFieldNames() throws {
        let stats = RecordingStats(
            slotsWritten: 2, framesFresh: 1, framesRepeatedIdle: 1, startToFirstFrameMs: 12.5,
            stopToFinalizedMs: 40, encoder: .hardware)
        #expect(
            try SkreenrekJSON.string(stats)
                == #"{"encoder":"hardware","framesDropped":0,"framesFresh":1,"framesRepeatedIdle":1,"#
                + #""pixelFormat":"420v","slotsWritten":2,"sourceFramesSkipped":0,"startToFirstFrameMs":12.5,"#
                + #""stopToFinalizedMs":40}"#)
    }

    @Test(arguments: [(0.0, "0:00"), (12.9, "0:12"), (31, "0:31"), (252, "4:12"), (3665, "61:05"), (-3, "0:00")])
    func minutesSeconds(seconds: Double, expected: String) {
        #expect(TimeFormat.minutesSeconds(seconds) == expected)
    }

    @Test(arguments: [
        (0.0, "0:00"), (12.0, "0:12"), (12.9, "0:12"), (3599.0, "59:59"), (3599.9, "59:59"), (3600.0, "1:00:00"),
        (3723.0, "1:02:03"), (36_000.0, "10:00:00"), (-3.0, "0:00"), (.nan, "0:00"), (.infinity, "0:00"),
        (-.infinity, "0:00"),
    ])
    func elapsed(seconds: Double, expected: String) {
        #expect(TimeFormat.elapsed(seconds) == expected)
    }

    @Test func version() {
        #expect(SkreenrekVersion.current == "1.0.9")
    }
}
