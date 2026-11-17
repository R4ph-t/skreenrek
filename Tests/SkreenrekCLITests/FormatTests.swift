import Foundation
@testable import SkreenrekCLI
import SkreenrekControl
import SkreenrekCore
import SkreenrekTesting
import Testing

/// Flag values, colour rules and the `stop` note line.
@Suite(.timeLimit(.minutes(2))) struct FormatTests {
    @Test func durationsParse() throws {
        let cases: [(String, Double)] = [
            ("30s", 30), ("2m", 120), ("1m30s", 90), ("45", 45), ("2.5", 2.5), ("1.5m", 90), ("0.5s", 0.5),
            ("90S", 90),
        ]
        for (text, seconds) in cases {
            #expect(try Values.duration(text) == seconds, "\(text)")
        }
        for bad in ["", "s", "m", "1h", "30 s", "-5", "abc", "1s30m", "1m30"] {
            #expect(throws: SkreenrekError.self, "\(bad)") { try Values.duration(bad) }
        }
        #expect(throws: SkreenrekError.usage(
            message: "The duration must be more than 0 seconds.", hint: "Pass a --duration such as 30s.")
        ) { try Values.duration("0s") }
    }

    @Test func sizesAndRegionsParse() throws {
        #expect(try Values.size("1280x800") == PixelSize(width: 1280, height: 800))
        #expect(try Values.size("1920X1080") == PixelSize(width: 1920, height: 1080))
        #expect(try Values.size("1080×1920") == PixelSize(width: 1080, height: 1920))
        for bad in ["1280", "x800", "0x800", "-1x800", "1280x800x2", "wide"] {
            #expect(throws: SkreenrekError.self, "\(bad)") { try Values.size(bad) }
        }
        #expect(try Values.region("100,200,640,360") == RegionParams(x: 100, y: 200, width: 640, height: 360))
        #expect(try Values.region("0, 0, 64, 64") == RegionParams(x: 0, y: 0, width: 64, height: 64))
        for bad in ["1,2,3", "1,2,3,4,5", "a,b,c,d", "0,0,0,10", "0,0,10,-1"] {
            #expect(throws: SkreenrekError.self, "\(bad)") { try Values.region(bad) }
        }
    }

    @Test func foldersResolveAgainstTheShellsFolder() {
        let home = URL(fileURLWithPath: "/Users/someone")
        let cwd = URL(fileURLWithPath: "/Users/someone/project")
        #expect(Values.folder("clips", home: home, base: cwd) == "/Users/someone/project/clips")
        #expect(Values.folder("../out", home: home, base: cwd) == "/Users/someone/out")
        #expect(Values.folder("~/Movies", home: home, base: cwd) == "/Users/someone/Movies")
        #expect(Values.folder("~", home: home, base: cwd) == "/Users/someone")
        #expect(Values.folder("/tmp/x/", home: home, base: cwd) == "/tmp/x")
    }

    @Test func aRegionGoesToTheAppInPixelsOfTheDisplay() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        let result = try await h.run(["record", "--region", "100,200,640,360", "--display", "1"])
        #expect(result.code == 0, "\(result)")
        #expect(result.out == "● Recording at 60 fps. Stop with: skreenrek stop\n")
        #expect(
            h.source.startCalls.first?.target == .region(PixelRect(x: 100, y: 200, width: 640, height: 360), displayId: 1))
        #expect(h.source.startCalls.first?.size == PixelSize(width: 640, height: 360))
        let status = try await h.run(["status"])
        #expect(status.out == "recording · region 640 × 360 px · 0:00\n")
        _ = try await h.client().call(.recordDiscard, as: DiscardBody.self)

        let outside = try await h.run(["record", "--region", "3000,0,640,360"])
        #expect(outside.code == 2)
        let noDisplay = try await h.run(["record", "--region", "0,0,640,360", "--display", "7"])
        #expect(noDisplay.code == 2)
    }

    @Test func colourOnlyOnATTYWithoutNoColorOrNO_COLOR() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        let green = "\u{1B}[32m✓\u{1B}[0m"
        let red = "\u{1B}[31m●\u{1B}[0m"
        let tty = try await h.run(["resize", "--app", "Safari", "--size", "1280x800"], tty: true)
        #expect(tty.out == "\(green) Safari — localhost:3000 is 1280 × 800 px (640 × 400 pt at 2×)\n")
        for (arguments, tty, variables) in [
            (["resize", "--app", "Safari", "--size", "1280x800"], false, [String: String]()),
            (["resize", "--app", "Safari", "--size", "1280x800", "--no-color"], true, [:]),
            (["resize", "--app", "Safari", "--size", "1280x800"], true, ["NO_COLOR": "1"]),
            (["resize", "--app", "Safari", "--size", "1280x800"], true, ["NO_COLOR": ""]),
        ] {
            let result = try await h.run(arguments, tty: tty, variables: variables)
            #expect(!result.out.contains("\u{1B}["), "\(arguments) tty \(tty) \(variables)")
            #expect(result.out.hasPrefix("✓ Safari"))
        }
        let recording = try await h.run(["record", "--app", "Safari"], tty: true)
        #expect(recording.out == "\(red) Recording at 60 fps. Stop with: skreenrek stop\n")
        let error = try await h.run(["record", "--app", "Safari"], tty: true)
        #expect(error.err.hasPrefix("\u{1B}[31merror:\u{1B}[0m Skreenrek is already recording Safari.\n"))
        let plainError = try await h.run(["record", "--app", "Safari"], tty: true, variables: ["NO_COLOR": "1"])
        #expect(plainError.err.hasPrefix("error: "))
        _ = try await h.client().call(.recordDiscard, as: DiscardBody.self)
    }

    static func body(stats: RecordingStats, events: Bool = true) -> StopBody {
        let folder = "/Users/someone/Movies/Skreenrek/2026-11-17_104207_safari"
        return StopBody(
            recording: StopBody.Recording(
                id: "2026-11-17_104207_safari", duration: 42, fps: 60, width: 1280, height: 800, codec: .h264,
                startedAt: "2026-11-17T10:42:07.120+01:00", startedBy: .cli, stats: stats),
            files: StopBody.Files(
                clip: "\(folder)/clip.mp4", events: events ? "\(folder)/events.json" : nil,
                snippet: "\(folder)/hyperframes.html"),
            snippet: "<video>", readback: nil)
    }

    @Test func theSavedBlockMatchesTheDesignSpecAndAddsNoNoteWhenCleanAndHardware() {
        let format = HumanFormat(style: Style(enabled: false), home: "/Users/someone")
        let clean = Self.body(stats: RecordingStats(slotsWritten: 2520, framesFresh: 2520, encoder: .hardware))
        #expect(format.saved(clean) == """
            ✓ Saved 0:42 · 1280 × 800 px · 60 fps
              clip    ~/Movies/Skreenrek/2026-11-17_104207_safari/clip.mp4
              events  ~/Movies/Skreenrek/2026-11-17_104207_safari/events.json
              snippet ~/Movies/Skreenrek/2026-11-17_104207_safari/hyperframes.html

            """)
        let dropped = Self.body(stats: RecordingStats(slotsWritten: 2520, framesDropped: 3, encoder: .software))
        #expect(format.saved(dropped).hasSuffix("  note    3 dropped frames · software encoder\n"))
    }

    @Test func theNoteLineCountsWhatWentWrong() {
        #expect(HumanFormat.statsNote(RecordingStats(encoder: .hardware)) == nil)
        #expect(HumanFormat.statsNote(RecordingStats(framesDropped: 3, encoder: .software))
            == "3 dropped frames · software encoder")
        #expect(HumanFormat.statsNote(RecordingStats(framesDropped: 1, encoder: .hardware)) == "1 dropped frame")
        #expect(HumanFormat.statsNote(RecordingStats(sourceFramesSkipped: 2, encoder: .hardware))
            == "2 skipped frames")
        #expect(HumanFormat.statsNote(RecordingStats(encoder: .software)) == "software encoder")
    }

    @Test func pointsAndScalesPrintWithoutTrailingZeros() {
        #expect(HumanFormat.number(640) == "640")
        #expect(HumanFormat.number(472.5) == "472.5")
        #expect(HumanFormat.scale(2) == "2×")
        #expect(HumanFormat.scale(1.5) == "1.5×")
        let format = HumanFormat(style: Style(enabled: false), home: "/Users/someone")
        #expect(format.tilde("/Users/someone/Movies") == "~/Movies")
        #expect(format.tilde("/Users/someoneelse/x") == "/Users/someoneelse/x")
        #expect(format.tilde("/Users/someone") == "~")
    }

    @Test func globalFlagsHoistAfterTheCommand() {
        #expect(CLI.hoistGlobalFlags(["--json", "status"]) == ["status", "--json"])
        #expect(CLI.hoistGlobalFlags(["--quiet", "--no-color", "debug", "perf", "--app", "X"])
            == ["debug", "perf", "--quiet", "--no-color", "--app", "X"])
        #expect(CLI.hoistGlobalFlags(["status", "--json"]) == ["status", "--json"])
        #expect(CLI.hoistGlobalFlags(["--json"]) == ["--json"])
    }
}
