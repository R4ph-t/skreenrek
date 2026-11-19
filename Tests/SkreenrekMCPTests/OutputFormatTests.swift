import Foundation
import SkreenrekControl
import SkreenrekCore
@testable import SkreenrekMCP
import SkreenrekTesting
import Testing

@Suite struct MCPOutputFormatTests {
    @Test func sevenUsageErrorsHaveParameterHintsAndNoSideEffects() async throws {
        try await withTestDeadline {
            let h = try MCPHarness().start()
            defer { h.stop() }
            try await h.initialize()
            let cases: [(JSONValue, String, String)] = [
                (["codec": "prores"], "ProRes can only be saved as a .mov file.",
                    "Add format: \"mov\", or use codec: \"h264\" or codec: \"hevc\"."),
                (["bitrateMbps": 500], "Bitrate must be between 1 and 200 Mbps. You passed 500.",
                    "Pass a bitrateMbps from 1 to 200, or use quality: \"high\"."),
                (["quality": "high", "bitrateMbps": 8], "Use either --quality or --bitrate, not both.",
                    "Drop one. bitrateMbps sets an exact target; quality picks one for the window size."),
                (["format": "mov", "codec": "prores", "bitrateMbps": 8],
                    "ProRes doesn't take a bitrate. Its quality comes from --quality.",
                    "Replace bitrateMbps with quality: \"low\", \"medium\", \"high\" or \"max\"."),
                (["codec": "av1"], "\"av1\" isn't a codec Skreenrek can record.",
                    "Use codec: \"h264\", \"hevc\" or \"prores\"."),
                (["format": "webm"], "\"webm\" isn't a format Skreenrek can save.", "Use format: \"mp4\" or \"mov\"."),
                (["quality": "ultra"], "\"ultra\" isn't a quality preset.",
                    "Use quality: \"low\", \"medium\", \"high\" or \"max\", or set bitrateMbps in Mbps."),
            ]
            for (flags, message, hint) in cases {
                var args = try #require(flags.objectValue)
                args["app"] = "Safari"; args["width"] = 1280; args["height"] = 800
                let response = try await h.call("skreenrek_start_recording", .object(args))
                #expect(response["isError"] == true)
                let body = try response.structured()
                #expect(body["error"]?["code"] == "usage")
                #expect(body["error"]?["message"] == .string(message) && body["error"]?["hint"] == .string(hint))
                #expect(h.resizer.calls.isEmpty && h.source.startCalls.isEmpty && h.sinks.all.isEmpty)
                #expect(!FileManager.default.fileExists(atPath: h.temp.output.path))
            }
        }
    }

    @Test func movSettingsAndReadbackReachMCPClients() async throws {
        try await withTestDeadline {
            let h = try MCPHarness(encode: true).start()
            defer { h.stop() }
            try await h.initialize()
            let start = try await h.call("skreenrek_start_recording", ["app": "Safari", "fps": 30,
                "codec": "H264", "format": "MOV", "bitrateMbps": 7.5])
            #expect(start["isError"] == false)
            let started = try start.structured()
            #expect(started["video"]?["container"] == "mov" && started["video"]?["codec"] == "h264")
            #expect(started["video"]?["quality"] == .null && started["video"]?["bitrateMbps"] == .null)
            #expect(started["video"]?["requestedBitrateMbps"] == 7.5)
            try await h.waitForSlots(30)
            let stop = try await h.call("skreenrek_stop_recording")
            #expect(stop["isError"] == false)
            let stopped = try stop.structured()
            #expect(stopped["recording"]?["codec"] == "h264")
            #expect(stopped["recording"]?["video"]?["container"] == "mov")
            #expect(stopped["recording"]?["video"]?["profile"] == "high")
            #expect(stopped["recording"]?["video"]?["bitrateMbps"] != .null)
            let id = try #require(stopped["recording"]?["id"]?.stringValue)
            #expect(stopped["files"]?["clip"]?.stringValue?.hasSuffix("/\(id)/\(id).mov") == true)
            #expect(stopped["recording"]?["video"]?["file"]?.stringValue == "\(id).mov")
            let status = try await h.call("skreenrek_status").structured()
            #expect(status["lastClip"] == stopped)
        }
    }
}
