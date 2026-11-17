import Foundation
import SkreenrekCore
import Testing

@Suite struct OutputSettingsTests {
    static let errors: [(String?, String?, String?, Double?, String, String, String)] = [
        (nil, "prores", nil, nil, "ProRes can only be saved as a .mov file.",
            "Add --format mov, or use --codec h264 or --codec hevc.",
            "Add format: \"mov\", or use codec: \"h264\" or codec: \"hevc\"."),
        (nil, nil, nil, 500, "Bitrate must be between 1 and 200 Mbps. You passed 500.",
            "Pass a --bitrate from 1 to 200, or use --quality high.",
            "Pass a bitrateMbps from 1 to 200, or use quality: \"high\"."),
        (nil, nil, "high", 8, "Use either --quality or --bitrate, not both.",
            "Drop one. --bitrate sets an exact target; --quality picks one for the window size.",
            "Drop one. bitrateMbps sets an exact target; quality picks one for the window size."),
        ("mov", "prores", nil, 8, "ProRes doesn't take a bitrate. Its quality comes from --quality.",
            "Replace --bitrate with --quality low, medium, high or max.",
            "Replace bitrateMbps with quality: \"low\", \"medium\", \"high\" or \"max\"."),
        (nil, "av1", nil, nil, "\"av1\" isn't a codec Skreenrek can record.",
            "Use --codec h264, hevc or prores.", "Use codec: \"h264\", \"hevc\" or \"prores\"."),
        ("webm", nil, nil, nil, "\"webm\" isn't a format Skreenrek can save.",
            "Use --format mp4 or mov.", "Use format: \"mp4\" or \"mov\"."),
        (nil, nil, "ultra", nil, "\"ultra\" isn't a quality preset.",
            "Use --quality low, medium, high or max, or set --bitrate in Mbps.",
            "Use quality: \"low\", \"medium\", \"high\" or \"max\", or set bitrateMbps in Mbps."),
    ]

    @Test func sevenExactErrorsOnBothSurfaces() {
        for (format, codec, quality, bitrate, message, cli, mcp) in Self.errors {
            for surface in [StartedBy.cli, .mcp] {
                #expect(throws: SkreenrekError.usage(message: message, hint: surface == .mcp ? mcp : cli)) {
                    try OutputSettings.resolve(container: format, codec: codec, quality: quality,
                        bitrateMbps: bitrate, surface: surface)
                }
            }
        }
        print("OutputSettingsTests: seven exact CLI/MCP usage errors verified")
    }

    @Test func bitrateLimitsAndFiniteValues() throws {
        for value in [500.0, 0.5, 0, 200.1, .infinity, -.infinity, .nan] {
            #expect(throws: SkreenrekError.self) { try OutputSettings.resolve(bitrateMbps: value) }
        }
        for value in [1.0, 200, 7.5] {
            let output = try OutputSettings.resolve(bitrateMbps: value)
            #expect(output.quality == nil)
            #expect(output.requestedBitrateMbps == value)
            #expect(output.targetBitrate(size: Fixtures.size1280x800, fps: .fps60) == Int(value * 1_000_000))
        }
    }

    @Test func defaultsCaseFoldingPresetsAndFlavours() throws {
        let output = try OutputSettings.resolve()
        #expect(output.isDefault && output.profile == "high")
        #expect(try OutputSettings.resolve(container: "MP4", codec: "H264", quality: "HIGH") == output)
        for (quality, multiplier, profile) in [("low", 0.25, "proxy"), ("medium", 0.5, "lt"), ("high", 1.0, "422"), ("max", 2.0, "422hq")] {
            let preset = try OutputSettings.resolve(quality: quality)
            #expect(preset.targetBitrate(size: Fixtures.size1280x800, fps: .fps30) == Int(4_000_000 * multiplier))
            #expect(preset.targetBitrate(size: PixelSize(width: 8000, height: 8000), fps: .fps60) == Int(80_000_000 * multiplier))
            let prores = try OutputSettings.resolve(container: "MOV", codec: "ProRes", quality: quality.uppercased())
            #expect(prores.profile == profile && prores.targetBitrate(size: Fixtures.size1280x800, fps: .fps60) == nil)
        }
        #expect(output.targetBitrate(size: PixelSize(width: 1920, height: 1080), fps: .fps60) == 9_953_280)
    }
}
