import Foundation
@testable import SkreenrekCLI
import SkreenrekControl
import SkreenrekCore
import SkreenrekTesting
import Testing

@Suite struct FormatUsageGuardTests {
    static let invalid: [([String], String, String)] = [
        (["--codec", "prores"], "ProRes can only be saved as a .mov file.",
            "Add --format mov, or use --codec h264 or --codec hevc."),
        (["--bitrate", "500"], "Bitrate must be between 1 and 200 Mbps. You passed 500.",
            "Pass a --bitrate from 1 to 200, or use --quality high."),
        (["--quality", "high", "--bitrate", "8"], "Use either --quality or --bitrate, not both.",
            "Drop one. --bitrate sets an exact target; --quality picks one for the window size."),
        (["--format", "mov", "--codec", "prores", "--bitrate", "8"],
            "ProRes doesn't take a bitrate. Its quality comes from --quality.",
            "Replace --bitrate with --quality low, medium, high or max."),
        (["--codec", "av1"], "\"av1\" isn't a codec Skreenrek can record.", "Use --codec h264, hevc or prores."),
        (["--format", "webm"], "\"webm\" isn't a format Skreenrek can save.", "Use --format mp4 or mov."),
        (["--quality", "ultra"], "\"ultra\" isn't a quality preset.",
            "Use --quality low, medium, high or max, or set --bitrate in Mbps."),
    ]

    @Test func sevenCLIUsageErrorsPrecedeResizeAndFolderCreation() async throws {
        try await withTestDeadline {
            let h = try CLIHarness().start()
            defer { h.stop() }
            for (flags, message, hint) in Self.invalid {
                let result = try await h.run(["record", "--app", "Safari", "--size", "1280x800"] + flags)
                #expect(result.code == 2)
                #expect(result.err == "error: \(message)\nhint:  \(hint)\n")
                #expect(h.resizer.calls.isEmpty && h.source.startCalls.isEmpty && h.sinks.all.isEmpty)
                #expect(!FileManager.default.fileExists(atPath: h.temp.output.path))
            }
        }
    }

    @Test func controllerValidatesEvenWithoutTheCLIParser() async throws {
        try await withTestDeadline {
            let h = try CLIHarness().start()
            defer { h.stop() }
            let params = [
                StartParams(codec: "prores"), StartParams(bitrateMbps: 500),
                StartParams(quality: "high", bitrateMbps: 8), StartParams(codec: "prores", format: "mov", bitrateMbps: 8),
                StartParams(codec: "av1"), StartParams(format: "webm"), StartParams(quality: "ultra"),
            ]
            for var p in params {
                p.app = "Safari"; p.width = 1280; p.height = 800
                do { _ = try await h.controller.start(p, startedBy: .cli); Issue.record("Accepted invalid format") }
                catch let error as SkreenrekError { #expect(error.exitCode == 2) }
                #expect(h.resizer.calls.isEmpty && h.source.startCalls.isEmpty && h.sinks.all.isEmpty)
                #expect(!FileManager.default.fileExists(atPath: h.temp.output.path))
            }
        }
    }
}

@Suite struct DefaultOutputUnchangedTests {
    @Test func defaultAndExplicitDefaultsHaveTheSameHumanLineAndJSONCodecString() async throws {
        let format = HumanFormat(style: Style(enabled: false), home: "/Users/someone")
        let body = FormatTests.body(stats: RecordingStats(encoder: .hardware))
        #expect(format.saved(body).split(separator: "\n").first == "✓ Saved 0:42 · 1280 × 800 px · 60 fps")
        try await withTestDeadline {
            for flags in [[], ["--format", "MP4", "--codec", "H264", "--quality", "HIGH"]] {
                let h = try CLIHarness(encode: true).start()
                defer { h.stop() }
                let start = try await h.run(["record", "--app", "Safari", "--fps", "30", "--json"] + flags)
                #expect(start.code == 0)
                let started = try start.json()
                let settings = try #require(started["video"] as? [String: Any])
                #expect(settings["codec"] as? String == "h264" && settings["quality"] as? String == "high")
                #expect(settings["bitrateMbps"] is NSNull && settings["requestedBitrateMbps"] is NSNull)
                try await h.waitForSlots(30)
                let stopped = try await h.run(["stop", "--json"])
                let recording = try #require(try stopped.json()["recording"] as? [String: Any])
                let video = try #require(recording["video"] as? [String: Any])
                #expect(recording["codec"] as? String == "h264")
                let id = try #require(recording["id"] as? String)
                #expect(video["file"] as? String == "\(id).mp4" && video["profile"] as? String == "high")
                #expect(video["quality"] as? String == "high" && video["bitrateMbps"] is Double)
                let human = try await h.run(["last"])
                #expect(!human.out.contains("H.264 MP4"))
            }
        }
    }

    @Test func movReadbackSurvivesStopWaitLastAndArtifacts() async throws {
        try await withTestDeadline {
            let h = try CLIHarness(encode: true).start()
            defer { h.stop() }
            let start = try await h.run(["record", "--app", "Safari", "--fps", "30", "--format", "MOV", "--bitrate", "7.5", "--json"])
            #expect(start.code == 0)
            let settings = try #require(try start.json()["video"] as? [String: Any])
            #expect(settings["container"] as? String == "mov" && settings["quality"] is NSNull)
            #expect(settings["requestedBitrateMbps"] as? Double == 7.5)
            try await h.waitForSlots(30)
            let client = try await h.client()
            async let waited = client.call(.recordWait, as: EndBody.self, timeout: 20)
            await h.controller.waitForEndWaiters()
            let stop = try await h.run(["stop", "--json"])
            let last = try await h.run(["last", "--json"])
            #expect(stop.out == last.out)
            let end = try await waited
            guard case .saved(let saved) = end else { Issue.record("Expected a saved clip"); return }
            #expect(saved.recording.video.container == .mov && saved.recording.video.bitrateMbps != nil)
            #expect(saved.recording.codec == saved.recording.video.codec)
            #expect(saved.files.clip.hasSuffix("/\(saved.recording.id)/\(saved.recording.id).mov") && saved.snippet.contains(".mov\""))
            let events = try JSONDecoder().decode(EventsFile.self, from: Data(contentsOf: URL(fileURLWithPath: saved.files.events!)))
            #expect(events.recording.video == saved.recording.video)
            let human = try await h.run(["last"])
            #expect(human.out.contains(" · H.264 MOV · "))
        }
    }
}

@Suite struct ProResNoteTests {
    static let note = "note:  ProRes doesn't play in Chrome or Firefox. Use --codec h264 for web pages."

    @Test func humanAddsTheExactNoteImmediatelyAfterSaved() {
        var body = FormatTests.body(stats: RecordingStats(encoder: .hardware))
        body.recording.codec = .prores
        body.recording.video = VideoReadback(file: "2026-11-17_104207_safari.mov", width: 1280, height: 800, scale: 2, codec: .prores,
            container: .mov, bitrateMbps: 9.8)
        let output = HumanFormat(style: Style(enabled: false), home: "/").saved(body).split(separator: "\n")
        #expect(output[0] == "✓ Saved 0:42 · 1280 × 800 px · 60 fps · ProRes MOV · 9.8 Mbps")
        #expect(output[1] == Substring(Self.note))
    }

    @Test func quietAndJSONSuppressTheProResNote() async throws {
        try await withTestDeadline {
            let h = try CLIHarness().start()
            defer { h.stop() }
            let start = try await h.run(["record", "--app", "Safari", "--codec", "prores", "--format", "mov"])
            #expect(start.code == 0)
            try await h.waitForSlots(30)
            let human = try await h.run(["stop"])
            #expect(human.out.split(separator: "\n")[1] == Substring(Self.note))
            let json = try await h.run(["last", "--json"])
            #expect(json.code == 0 && !json.out.contains(Self.note))
            let quiet = try await h.run(["last", "--quiet"])
            #expect(quiet.code == 0 && quiet.out.isEmpty && quiet.err.isEmpty)
        }
    }
}
