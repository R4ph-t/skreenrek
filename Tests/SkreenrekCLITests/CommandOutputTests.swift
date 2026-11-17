import CoreGraphics
import Foundation
import SkreenrekCLI
import SkreenrekControl
import SkreenrekCore
import SkreenrekTesting
import Testing

/// Golden human and JSON output for every command, run in process against a real socket.
@Suite(.timeLimit(.minutes(2))) struct CommandOutputTests {
    @Test func windowsPrintsOneAlignedRowPerWindow() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        let human = try await h.run(["windows"])
        #expect(human.code == 0)
        #expect(human.out == """
            4127  Safari    localhost:3000  1280 × 800 px
            5001  Terminal  zsh             640 × 400 px

            """)
        #expect(human.err.isEmpty)

        let json = try await h.run(["windows", "--app", "Terminal", "--json"])
        #expect(json.code == 0)
        #expect(json.out == """
            {"windows":[{"app":"Terminal","bundleId":"com.apple.Terminal","displayId":1,"height":400,"id":5001,\
            "onScreen":true,"title":"zsh","unit":"px","width":640}]}

            """)
    }

    @Test func resizePrintsTheReadBackInPixelsAndPoints() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        let human = try await h.run(["resize", "--app", "Safari", "--size", "1440x900"])
        #expect(human.code == 0, "\(human)")
        #expect(human.out == "✓ Safari — localhost:3000 is 1440 × 900 px (720 × 450 pt at 2×)\n")

        let json = try await h.run(["resize", "4127", "--size", "1280x800", "--json"])
        #expect(json.code == 0, "\(json)")
        #expect(json.out == """
            {"actual":{"height":800,"unit":"px","width":1280},"attempts":1,"display":{"id":1,\
            "name":"Built-in Retina Display","scale":2},"exact":true,"frame":{"height":400,"unit":"pt","width":640,\
            "x":120,"y":80},"requested":{"height":800,"unit":"px","width":1280},"window":{"app":"Safari",\
            "bundleId":"com.apple.Safari","id":4127,"pid":812,"title":"localhost:3000"}}

            """)
    }

    @Test func resizeWithAllowInexactSaysItIsNotExact() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        h.resizer.rules = ResizeRules(minimumSize: CGSize(width: 643, height: 100))
        let result = try await h.run(["resize", "--app", "Safari", "--size", "1280x800", "--allow-inexact"])
        #expect(result.code == 0, "\(result)")
        #expect(result.out == """
            ✓ Safari — localhost:3000 is 1286 × 800 px (643 × 400 pt at 2×)
              note    not exact: 1280 × 800 px was asked for

            """)
    }

    @Test func recordWithASizePrintsTheReadBackThenTheRecordingLine() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        let result = try await h.run(["record", "--app", "Safari", "--size", "1280x800", "--fps", "60"])
        #expect(result.code == 0, "\(result)")
        #expect(result.out == """
            ✓ Safari — localhost:3000 is 1280 × 800 px
            ● Recording at 60 fps. Stop with: skreenrek stop

            """)
        #expect(result.err.isEmpty)
        let status = try await h.client().call(.status, as: StatusBody.self)
        #expect(status.recording?.startedBy == .cli)
        _ = try await h.client().call(.recordDiscard, as: DiscardBody.self)
    }

    @Test func recordWithoutASizePrintsOnlyTheRecordingLineAndJSONIsTheStartBody() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        let human = try await h.run(["record", "5001", "--fps", "30"])
        #expect(human.code == 0, "\(human)")
        #expect(human.out == "● Recording at 30 fps. Stop with: skreenrek stop\n")
        _ = try await h.client().call(.recordDiscard, as: DiscardBody.self)

        let json = try await h.run(["record", "--app", "Safari", "--json"])
        #expect(json.code == 0, "\(json)")
        let object = try json.json()
        #expect(Set(object.keys) == ["recordingId", "startedAt", "readback", "fps", "video"])
        #expect(object["fps"] as? Int == 60)
        #expect(object["readback"] is NSNull)
        #expect(json.out.hasSuffix("}\n") && json.out.split(separator: "\n").count == 1)
        _ = try await h.client().call(.recordDiscard, as: DiscardBody.self)
    }

    @Test func recordPassesEveryFlagToTheApp() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        let result = try await h.run([
            "record", "--app", "Safari", "--no-cursor", "--no-events", "--no-hud", "--out", "clips", "--name", "demo",
            "--codec", "hevc", "--duration", "1m30s",
        ])
        #expect(result.code == 0, "\(result)")
        let call = try #require(h.source.startCalls.first)
        #expect(call.showsCursor == false)
        #expect(h.mouse.startCount == 0)
        let status = try await h.client().call(.status, as: StatusBody.self)
        #expect(status.recording?.id.hasSuffix("_demo") == true)
        // `--out` is relative to the shell's folder, not the app's.
        let folder = h.temp.root.appendingPathComponent("work/clips/\(try #require(status.recording?.id))")
        #expect(FileManager.default.fileExists(atPath: folder.path))
        _ = try await h.client().call(.recordDiscard, as: DiscardBody.self)
    }

    @Test func stopPrintsTheSavedLineThePathsAndTheEncoderNote() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        _ = try await h.run(["record", "--app", "Safari"])
        try await h.waitForSlots(5)
        let stop = try await h.run(["stop"])
        #expect(stop.code == 0, "\(stop)")
        let body = try await h.client().call(.last, as: StopBody.self)
        let folder = h.tildeFolder(body.recording.id)
        #expect(stop.out == """
            ✓ Saved \(TimeFormat.minutesSeconds(body.recording.duration)) · 1280 × 800 px · 60 fps
              clip    \(folder)/clip.mp4
              events  \(folder)/events.json
              snippet \(folder)/hyperframes.html
              note    software encoder

            """)

        let last = try await h.run(["last"])
        #expect(last.out == stop.out)
        let lastJSON = try await h.run(["last", "--json"])
        #expect(try lastJSON.decode(StopBody.self) == body)
        let object = try lastJSON.json()
        #expect(Set(object.keys) == ["recording", "files", "snippet", "readback"])
        let recording = try #require(object["recording"] as? [String: Any])
        #expect(recording["stats"] != nil)
    }

    @Test func stopJSONIsTheStopBodyWithStats() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        _ = try await h.run(["record", "--app", "Terminal", "--no-events"])
        try await h.waitForSlots(5)
        let stop = try await h.run(["stop", "--json"])
        #expect(stop.code == 0, "\(stop)")
        let body = try stop.decode(StopBody.self)
        #expect(body.files.events == nil)
        #expect(body.recording.stats.slotsWritten > 0)
        let files = try #require(try stop.json()["files"] as? [String: Any])
        #expect(files["events"] is NSNull)
        // Human output leaves out the events line when there is none.
        let last = try await h.run(["last"])
        #expect(!last.out.contains("events"))
    }

    @Test func discardPrintsOneLineAndJSONSaysDiscarded() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        _ = try await h.run(["record", "--app", "Safari"])
        let human = try await h.run(["discard"])
        #expect(human.code == 0, "\(human)")
        #expect(human.out == "✓ Discarded the recording.\n")
        _ = try await h.run(["record", "--app", "Safari"])
        let json = try await h.run(["discard", "--json"])
        #expect(json.out == "{\"discarded\":true}\n")
    }

    @Test func statusPrintsTheStateWordAndWhileRecordingTheWindowAndElapsedTime() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        let idle = try await h.run(["status"])
        #expect(idle.out == "idle\n")
        _ = try await h.run(["record", "--app", "Safari"])
        h.clock.advance(by: 12.4)
        let recording = try await h.run(["status"])
        #expect(recording.out == "recording · Safari — localhost:3000 · 0:12\n")
        let json = try await h.run(["status", "--json"])
        let object = try json.json()
        #expect(Set(object.keys) == ["state", "window", "readback", "recording", "lastClip", "error"])
        #expect(object["state"] as? String == "recording")
        _ = try await h.client().call(.recordDiscard, as: DiscardBody.self)
    }

    @Test func pickPrintsTheChosenWindowAndStatusShowsItArmed() async throws {
        let h = try CLIHarness(picker: FakeWindowPicker(result: .window(WindowID(5001)))).start()
        defer { h.stop() }
        let pick = try await h.run(["pick"])
        #expect(pick.code == 0, "\(pick)")
        #expect(pick.out == "5001  Terminal  zsh  640 × 400 px\n")
        let status = try await h.run(["status"])
        #expect(status.out == "armed · Terminal — zsh · 640 × 400 px\n")
        let json = try await h.run(["pick", "--json"])
        #expect(try json.json()["id"] as? Int == 5001)
    }

    @Test func aCancelledPickSaysSo() async throws {
        let h = try CLIHarness(picker: FakeWindowPicker(result: .cancelled)).start()
        defer { h.stop() }
        let pick = try await h.run(["pick"])
        #expect(pick.code == 0)
        #expect(pick.out == "Pick cancelled.\n")
        #expect(try await h.run(["pick", "--json"]).out == "{\"cancelled\":true}\n")
    }

    @Test func theDefaultPickerIsAnInternalError() async throws {
        let h = CLIHarness()
        // The app's own picker until 10: a host built without one.
        let controller = HeadlessHost(
            seams: ControllerSeams(
                catalog: h.catalog, resizer: h.resizer, frameSource: h.source, mouse: h.mouse, clock: h.clock,
                permissions: h.permissions, disk: h.disk),
            socketPath: h.temp.socket)
        try controller.start()
        defer {
            controller.stop()
            h.temp.cleanUp()
        }
        let pick = try await h.run(["pick"])
        #expect(pick.code == 1)
        #expect(pick.err == "error: The window picker isn't available yet.\nhint:  Run: skreenrek doctor\n")
    }

    @Test func doctorPrintsOneLinePerCheck() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        // `skreenrek` on PATH is this executable, through a symlink.
        let bin = h.temp.root.appendingPathComponent("bin", isDirectory: true)
        let real = h.temp.root.appendingPathComponent("real-skreenrek")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: real.path, contents: Data(), attributes: [.posixPermissions: 0o755])
        try FileManager.default.createSymbolicLink(
            at: bin.appendingPathComponent("skreenrek"), withDestinationURL: real)
        let result = try await h.run(
            ["doctor"], variables: ["PATH": "/nowhere:\(bin.path)"], executablePath: real.path)
        #expect(result.code == 0, "\(result)")
        #expect(result.out == """
            ✓ Screen Recording   Allowed
            ✓ Accessibility      Allowed
            ✓ Skreenrek app      \(SkreenrekVersion.current), running
            ✓ Output folder      ~/out
            ✓ Command-line tool  ~/bin/skreenrek
            ✓ Socket             ~/s/c.sock

            """)
    }

    @Test func doctorExits3WithoutScreenRecordingAndShowsTheFixes() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        h.permissions.screenRecording = .missing
        h.permissions.accessibility = .missing
        let result = try await h.run(["doctor"], variables: ["PATH": "/nowhere"])
        #expect(result.code == 3, "\(result)")
        let lines = result.out.split(separator: "\n").map(String.init)
        #expect(lines.count == 6)
        #expect(lines[0] == "✗ Screen Recording   Not allowed. Allow it in System Settings › Privacy & Security › "
            + "Screen & System Audio Recording, then quit and reopen Skreenrek.")
        #expect(lines[1] == "✗ Accessibility      Not allowed. Allow it in System Settings › Privacy & Security › "
            + "Accessibility for exact sizes.")
        #expect(lines[4].hasPrefix("✗ Command-line tool  /usr/local/bin/skreenrek isn't on your PATH as skreenrek."))

        let json = try await h.run(["doctor", "--json"])
        #expect(json.code == 3)
        let body = try json.decode(DoctorBody.self)
        #expect(body.permissions.screenRecording == .missing)
        #expect(json.err.isEmpty)
    }

    @Test func quietPrintsNothingOnSuccessButStillPrintsErrors() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        let ok = try await h.run(["record", "--app", "Safari", "--quiet"])
        #expect(ok.code == 0)
        #expect(ok.out.isEmpty && ok.err.isEmpty)
        let json = try await h.run(["status", "--quiet", "--json"])
        #expect(json.out.isEmpty)
        let failed = try await h.run(["record", "--app", "Safari", "--quiet"])
        #expect(failed.code == 6)
        #expect(failed.out.isEmpty)
        #expect(failed.err == "error: Skreenrek is already recording Safari.\nhint:  Run: skreenrek stop\n")
        _ = try await h.client().call(.recordDiscard, as: DiscardBody.self)
    }

    @Test func globalFlagsWorkBeforeTheCommand() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        let result = try await h.run(["--json", "status"])
        #expect(result.code == 0, "\(result)")
        #expect(try result.json()["state"] as? String == "idle")
    }

    @Test func helpAndVersionPrintOnStdoutAndExit0() async throws {
        let h = CLIHarness()
        defer { h.temp.cleanUp() }
        let version = try await h.run(["--version"])
        #expect(version.code == 0)
        #expect(version.out == "skreenrek \(SkreenrekVersion.current)\n")
        let help = try await h.run(["--help"])
        #expect(help.code == 0)
        for command in ["windows", "pick", "resize", "record", "stop", "discard", "status", "last", "doctor"] {
            #expect(help.out.contains("  \(command) "), "\(command)")
        }
        #expect(!help.out.contains("debug"))
        let record = try await h.run(["record", "--help"])
        #expect(record.code == 0)
        #expect(record.out.contains("--allow-inexact") && record.out.contains("--wait"))
        #expect(try await h.run(["help", "stop"]).code == 0)
    }
}
