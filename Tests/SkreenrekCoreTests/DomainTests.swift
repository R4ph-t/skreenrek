import Foundation
import SkreenrekCore
import Testing

@Suite struct DomainTests {
    static let display = DisplayInfo(
        id: 1, name: "Built-in Retina Display", scale: 2,
        frame: PointRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: PointRect(x: 0, y: 33, width: 1512, height: 949))

    static let safari = WindowInfo(
        id: 4521, app: "Safari", bundleId: "com.apple.Safari", title: "localhost:3000", pid: 812,
        frame: PointRect(x: 100, y: 80, width: 640, height: 400), displayId: 1, onScreen: true)

    @Test func versionIsInOnePlace() {
        #expect(SkreenrekVersion.current == "0.1.0")
    }

    @Test func pixelSizeRoundsPointsTimesScale() {
        #expect(Self.safari.pixelSize(on: Self.display) == PixelSize(width: 1280, height: 800))
        let oneX = DisplayInfo(id: 2, name: "External", scale: 1, frame: Self.display.frame, visibleFrame: Self.display.frame)
        #expect(Self.safari.pixelSize(on: oneX) == PixelSize(width: 640, height: 400))
        #expect(PointRect(x: 0, y: 0, width: 640.3, height: 399.8).pixelSize(scale: 2) == PixelSize(width: 1281, height: 800))
    }

    @Test func controllerStateRawValuesAreStatusWords() {
        #expect(ControllerState.allCases.map(\.rawValue) == ["idle", "armed", "recording", "writing", "error"])
    }

    @Test func windowInfoJSONIsStable() throws {
        let json = try SkreenrekJSON.string(Self.safari)
        #expect(
            json
                == #"{"app":"Safari","bundleId":"com.apple.Safari","displayId":1,"frame":{"height":400,"width":640,"x":100,"y":80},"id":4521,"onScreen":true,"pid":812,"title":"localhost:3000"}"#
        )
        let decoded = try SkreenrekJSON.decoder().decode(WindowInfo.self, from: Data(json.utf8))
        #expect(decoded == Self.safari)
    }

    @Test func readbackJSONHasUnitsAndExactness() throws {
        let readback = Readback(
            window: .init(Self.safari), display: .init(id: 1, scale: 2),
            requested: PixelSize(width: 1280, height: 800), actual: PixelSize(width: 1280, height: 800),
            frame: PointRect(x: 100, y: 80, width: 640, height: 400), attempts: 1)
        #expect(readback.exact)
        let json = try SkreenrekJSON.string(readback)
        #expect(
            json
                == #"{"actual":{"height":800,"unit":"px","width":1280},"attempts":1,"display":{"id":1,"scale":2},"exact":true,"frame":{"height":400,"unit":"pt","width":640,"x":100,"y":80},"requested":{"height":800,"unit":"px","width":1280},"window":{"app":"Safari","id":4521,"title":"localhost:3000"}}"#
        )
        let inexact = Readback(
            window: .init(Self.safari), display: .init(id: 1, scale: 2),
            requested: PixelSize(width: 1280, height: 800), actual: PixelSize(width: 1286, height: 800),
            frame: PointRect(x: 100, y: 80, width: 643, height: 400), attempts: 3)
        #expect(!inexact.exact)
        let decoded = try SkreenrekJSON.decoder().decode(Readback.self, from: SkreenrekJSON.encode(inexact))
        #expect(decoded == inexact)
    }

    @Test func jsonDoesNotEscapeSlashes() throws {
        let options = RecordingOptions(outDir: "/tmp/clips")
        #expect(try SkreenrekJSON.string(options).contains(#""outDir":"/tmp/clips""#))
    }

    @Test func recordingOptionsRoundTrip() throws {
        let options = RecordingOptions(
            fps: .fps30, cursor: false, events: false, hud: false, outDir: "/tmp", name: "demo", assetsDir: "/a",
            codec: .hevc, duration: 12.5, allowInexact: true)
        let decoded = try SkreenrekJSON.decoder().decode(RecordingOptions.self, from: SkreenrekJSON.encode(options))
        #expect(decoded == options)
        #expect(try SkreenrekJSON.string(options).contains(#""fps":30"#))
        #expect(try SkreenrekJSON.string(StartedBy(.mcp, client: "claude-code")) == #"{"client":"claude-code","source":"mcp"}"#)
    }

    @Test func recordingStatsCleanness() throws {
        var stats = RecordingStats(slotsWritten: 60, framesFresh: 58, framesRepeatedIdle: 2, encoder: .software, pixelFormat: "420v")
        #expect(stats.isClean)
        stats.framesDropped = 1
        #expect(!stats.isClean)
        stats.framesDropped = 0
        stats.sourceFramesSkipped = 1
        #expect(!stats.isClean)
        let decoded = try SkreenrekJSON.decoder().decode(RecordingStats.self, from: SkreenrekJSON.encode(stats))
        #expect(decoded == stats)
        #expect(try SkreenrekJSON.string(stats).contains(#""encoder":"software""#))
    }
}

@Suite struct SkreenrekErrorTests {
    static let candidates = [
        WindowCandidate(
            window: WindowInfo(
                id: 4521, app: "Safari", bundleId: "com.apple.Safari", title: "localhost:3000", pid: 1,
                frame: PointRect(x: 0, y: 0, width: 640, height: 400), displayId: 1, onScreen: true),
            pixelSize: PixelSize(width: 1280, height: 800)),
        WindowCandidate(
            window: WindowInfo(
                id: 4533, app: "Safari", bundleId: "com.apple.Safari", title: "Docs", pid: 1,
                frame: PointRect(x: 0, y: 0, width: 720, height: 450), displayId: 1, onScreen: true),
            pixelSize: PixelSize(width: 1440, height: 900)),
    ]

    static let all: [SkreenrekError] = [
        .internal(message: "Something went wrong.", hint: "Run: skreenrek doctor"),
        .usage(message: "Width 1281 px is odd. On a 2× display sizes must be even.", hint: "Use 1280 or 1282 px."),
        .permissionDenied(.screenRecording),
        .permissionDenied(.accessibility),
        .notExact(
            message: "Safari can't be narrower than 1286 px. It is 1286 × 800 px now.",
            hint: "Pick a width of 1286 px or more, or pass --allow-inexact."),
        .windowNotFound(query: "--app Safari"),
        .windowAmbiguous(query: "--app Safari", candidates: candidates),
        .wrongState(message: "Skreenrek is already recording.", hint: "Stop it with: skreenrek stop"),
        .recordingFailed(
            message: "The window closed at 0:31. The clip up to that point was saved.", hint: "Run: skreenrek last"),
    ]

    @Test func exitCodesAndCodesMatchTheTable() {
        let table = Self.all.map { "\($0.code)=\($0.exitCode.rawValue)" }
        #expect(
            table == [
                "internal=1", "usage=2", "permission_denied=3", "permission_denied=3", "not_exact=4",
                "window_not_found=5", "window_ambiguous=5", "wrong_state=6", "recording_failed=7",
            ])
        #expect(SkreenrekExitCode.success.rawValue == 0)
        #expect(SkreenrekExitCode.interrupted.rawValue == 130)
    }

    @Test func everyErrorHasAMessageAndHint() {
        for error in Self.all {
            #expect(!error.message.isEmpty)
            #expect(!error.hint.isEmpty)
        }
    }

    @Test func ambiguousListsCandidatesFrontToBack() {
        let error = SkreenrekError.windowAmbiguous(query: "--app Safari", candidates: Self.candidates)
        #expect(
            error.message
                == """
                2 windows match --app Safari. Pass a window ID:
                4521  Safari  localhost:3000  1280 × 800 px
                4533  Safari  Docs  1440 × 900 px
                """)
    }

    @Test func encodesAsErrorObject() throws {
        let error = SkreenrekError.notExact(
            message: "Safari can't be narrower than 1286 px. It is 1286 × 800 px now.",
            hint: "Pick a width of 1286 px or more, or pass --allow-inexact.")
        #expect(
            try SkreenrekJSON.string(error)
                == #"{"error":{"code":"not_exact","exit":4,"hint":"Pick a width of 1286 px or more, or pass --allow-inexact.","message":"Safari can't be narrower than 1286 px. It is 1286 × 800 px now."}}"#
        )
    }

    @Test func copyNeverNamesPeople() {
        for error in Self.all {
            for text in [error.message, error.hint] {
                #expect(!text.contains("Raph"))
                #expect(!text.contains("CTO"))
            }
        }
    }
}
