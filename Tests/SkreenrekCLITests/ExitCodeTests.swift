import CoreGraphics
import Foundation
import SkreenrekCLI
import SkreenrekControl
import SkreenrekCore
import SkreenrekTesting
import Testing

/// Every exit code from the design spec's table, with its stderr shape.
@Suite(.timeLimit(.minutes(2))) struct ExitCodeTests {
    @Test func parseAndValidationErrorsExit2NotArgumentParsers64() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        let cases: [([String], String)] = [
            (["resize", "--app", "Safari"], "error: Missing expected argument '--size <WxH>'.\nhint:  Run: skreenrek resize --help\n"),
            (["record", "--bogus"], "error: Unknown option '--bogus'. Did you mean '--out'?\nhint:  Run: skreenrek record --help\n"),
            (["frobnicate"], "error: Unexpected argument 'frobnicate'.\nhint:  Run: skreenrek --help\n"),
            (["record", "--app", "Safari", "--fps", "45"], "error: Frame rate 45 isn't offered.\nhint:  Pass --fps 30 or --fps 60.\n"),
            (["record", "--app", "Safari", "--fps", "sixty"], ""),
            (["resize", "--app", "Safari", "--size", "1280"], "error: \"1280\" isn't a size.\nhint:  Pass --size WxH in pixels, e.g. --size 1280x800.\n"),
            (["record", "--app", "Safari", "--codec", "av1"], "error: \"av1\" isn't a codec Skreenrek can record.\nhint:  Use --codec h264, hevc or prores.\n"),
            (["record", "--app", "Safari", "--duration", "soon"], "error: \"soon\" isn't a duration.\nhint:  Pass --duration as 30s, 2m, 1m30s or plain seconds.\n"),
            (["record", "abc"], "error: \"abc\" isn't a window ID.\nhint:  Pass a numeric ID from: skreenrek windows, or use --app NAME.\n"),
            (["record", "4127", "--app", "Safari"], "error: Pass a window ID or --app, not both.\nhint:  Drop the window ID, or drop --app.\n"),
            (["record", "--title", "x"], "error: --title only works with --app.\nhint:  Add --app NAME.\n"),
            (["record", "--app", "Safari", "--region", "0,0,10,10"], "error: Pass a window or --region, not both.\nhint:  Drop the window, or drop --region.\n"),
            (["record", "--region", "0,0,640,360", "--size", "1280x800"], "error: A region already has its size, so it can't be resized.\nhint:  Drop --size, or record a window.\n"),
            (["record", "--app", "Safari", "--display", "2"], "error: --display only works with --region.\nhint:  Add --region X,Y,W,H.\n"),
            // The app's own check: an odd width on a 2× display.
            (["resize", "--app", "Safari", "--size", "1281x800"], ""),
        ]
        for (arguments, stderr) in cases {
            let result = try await h.run(arguments)
            #expect(result.code == 2, "\(arguments): \(result)")
            #expect(result.out.isEmpty, "\(arguments)")
            if !stderr.isEmpty { #expect(result.err == stderr, "\(arguments)") }
            #expect(result.err.hasPrefix("error: ") && result.err.contains("\nhint:  "), "\(arguments)")
        }
        #expect(h.source.startCalls.isEmpty)
        #expect(h.resizer.calls.isEmpty)
    }

    @Test func usageErrorsWithJSONAreTheErrorEnvelopeOnStderr() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        let result = try await h.run(["record", "--app", "Safari", "--fps", "45", "--json"])
        #expect(result.code == 2)
        #expect(result.out.isEmpty)
        #expect(result.err == """
            {"error":{"code":"usage","exit":2,"hint":"Pass --fps 30 or --fps 60.","message":"Frame rate 45 isn't offered."}}

            """)
        let parse = try await h.run(["--json", "record", "--bogus"])
        #expect(parse.code == 2)
        let error = try parse.jsonError()
        #expect(error["code"] as? String == "usage")
        #expect(error["exit"] as? Int == 2)
    }

    @Test func screenRecordingMissingExits3() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        h.permissions.screenRecording = .missing
        let result = try await h.run(["record", "--app", "Safari"])
        #expect(result.code == 3)
        #expect(result.err == """
            error: Screen Recording isn't allowed for Skreenrek.
            hint:  Allow it in System Settings › Privacy & Security › Screen & System Audio Recording, then run: \
            skreenrek doctor

            """)
        let json = try await h.run(["record", "--app", "Safari", "--json"])
        #expect(json.code == 3)
        let error = try json.jsonError()
        #expect(error["code"] as? String == "permission_denied")
        #expect(error["exit"] as? Int == 3)
        #expect(Set(error.keys) == ["code", "message", "hint", "exit"])
    }

    @Test func accessibilityMissingExits3OnResize() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        h.permissions.accessibility = .missing
        let result = try await h.run(["resize", "--app", "Safari", "--size", "1280x800"])
        #expect(result.code == 3)
        #expect(result.err.hasPrefix("error: Accessibility isn't allowed for Skreenrek.\n"))
    }

    @Test func aSizeThatIsNotExactExits4() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        h.resizer.rules = ResizeRules(minimumSize: CGSize(width: 643, height: 100))
        let resize = try await h.run(["resize", "--app", "Safari", "--size", "1280x800"])
        #expect(resize.code == 4)
        #expect(resize.out.isEmpty)
        #expect(resize.err == """
            error: Safari can't be narrower than 1286 px. It is 1286 × 800 px now.
            hint:  Pick a width of 1286 px or more, or pass --allow-inexact.

            """)
        let record = try await h.run(["record", "--app", "Safari", "--size", "1280x800"])
        #expect(record.code == 4)
        #expect(h.source.startCalls.isEmpty)
    }

    @Test func anUnknownOrAmbiguousWindowExits5WithTheCandidates() async throws {
        let h = try CLIHarness(windows: [CLIFixtures.safari, CLIFixtures.github, CLIFixtures.terminal]).start()
        defer { h.stop() }
        let ambiguous = try await h.run(["record", "--app", "Safari"])
        #expect(ambiguous.code == 5)
        #expect(ambiguous.err == """
            error: 2 windows match --app Safari. Pass a window ID:
              4127  Safari  localhost:3000  1280 × 800 px
              4133  Safari  GitHub          1512 × 945 px
            hint:  Pass one of the IDs above, e.g. skreenrek record 4127

            """)
        let missing = try await h.run(["resize", "--app", "Xcode", "--size", "1280x800"])
        #expect(missing.code == 5)
        #expect(missing.err == """
            error: No window matches --app Xcode.
            hint:  List the windows you can record with: skreenrek windows

            """)
        let json = try await h.run(["record", "999", "--json"])
        #expect(json.code == 5)
        #expect(try json.jsonError()["code"] as? String == "window_not_found")
    }

    @Test func wrongStateExits6() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        let stop = try await h.run(["stop"])
        #expect(stop.code == 6)
        #expect(stop.err == "error: Nothing is recording.\nhint:  Start one with: skreenrek record <window>\n")
        #expect(try await h.run(["discard"]).code == 6)
        let last = try await h.run(["last"])
        #expect(last.code == 6)
        #expect(last.err == "error: No clip has been saved yet.\nhint:  Record one with: skreenrek record <window>\n")
    }

    @Test func aFailedRecordingExits7WithThePartialClip() async throws {
        let source = SyntheticFrameSource(count: 20, fps: 30, endError: FrameSourceError.windowClosed)
        let h = try CLIHarness(source: source).start()
        defer { h.stop() }
        let result = try await h.run(["record", "--app", "Safari", "--wait"])
        #expect(result.code == 7, "\(result)")
        #expect(result.out == "● Recording at 60 fps. Stop with: skreenrek stop\n")
        #expect(result.err == """
            error: The window closed at 0:00. The clip up to that point was saved.
            hint:  Find the partial clip with: skreenrek last

            """)
        let last = try await h.run(["last", "--json"])
        let body = try last.decode(StopBody.self)
        #expect(body.recording.stats.slotsWritten > 0)
        let events = try JSONDecoder().decode(
            EventsFile.self, from: Data(contentsOf: URL(fileURLWithPath: try #require(body.files.events))))
        #expect(!events.complete)
    }

    @Test func theAppNotAnsweringOutsideABundleExits1() async throws {
        let h = CLIHarness()
        defer { h.temp.cleanUp() }
        let launcher = FakeAppLauncher()
        let result = try await h.run(["status"], launcher: launcher)
        #expect(result.code == 1)
        #expect(result.out.isEmpty)
        #expect(result.err == "error: Skreenrek isn't running.\nhint:  Open Skreenrek.app, or run: skreenrek app\n")
        #expect(launcher.launches.isEmpty)
        let json = try await h.run(["status", "--json"])
        #expect(try json.jsonError()["code"] as? String == "internal")
        #expect(try json.jsonError()["exit"] as? Int == 1)
    }

    @Test func doctorWithoutTheAppPrintsWhatItCanAndExits1() async throws {
        let h = CLIHarness()
        defer { h.temp.cleanUp() }
        let result = try await h.run(["doctor"], variables: ["PATH": "/nowhere"])
        #expect(result.code == 1)
        #expect(result.out == """
            ✗ Skreenrek app      Skreenrek isn't running. Open Skreenrek.app, or run: skreenrek app
            ✗ Command-line tool  /usr/local/bin/skreenrek isn't on your PATH as skreenrek. Link it: \
            ln -s "/usr/local/bin/skreenrek" ~/.local/bin/skreenrek
            ✗ Socket             Nothing answers at ~/s/c.sock.

            """)
        let json = try await h.run(["doctor", "--json"])
        #expect(json.code == 1)
        #expect(json.out.isEmpty)
        #expect(try json.jsonError()["code"] as? String == "internal")
    }
}
