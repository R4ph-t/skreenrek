import Foundation

public enum VideoContainer: String, Sendable, Hashable, Codable, CaseIterable {
    case mp4, mov
    public var fileName: String { "clip.\(rawValue)" }
}

public enum QualityPreset: String, Sendable, Hashable, Codable, CaseIterable {
    case low, medium, high, max
}

/// Validated before any side effect. Preset bitrates are resolved for the actual output size by the writer.
public struct OutputSettings: Sendable, Hashable, Codable {
    public static let defaults = OutputSettings(container: .mp4, codec: .h264, profile: "high", quality: .high,
        requestedBitrateMbps: nil)
    public let container: VideoContainer
    public let codec: VideoCodec
    public let profile: String
    public let quality: QualityPreset?
    public let requestedBitrateMbps: Double?

    private init(container: VideoContainer, codec: VideoCodec, profile: String, quality: QualityPreset?,
        requestedBitrateMbps: Double?) {
        self.container = container
        self.codec = codec
        self.profile = profile
        self.quality = quality
        self.requestedBitrateMbps = requestedBitrateMbps
    }

    public static func resolve(
        container: String? = nil, codec: String? = nil, quality: String? = nil, bitrateMbps: Double? = nil,
        surface: StartedBy = .cli
    ) throws -> Self {
        func usage(_ message: String, _ cli: String, _ mcp: String) -> SkreenrekError {
            .usage(message: message, hint: surface == .mcp ? mcp : cli)
        }
        guard let containerValue = VideoContainer(rawValue: (container ?? "mp4").lowercased()) else {
            throw usage("\"\(container!)\" isn't a format Skreenrek can save.",
                "Use --format mp4 or mov.", "Use format: \"mp4\" or \"mov\".")
        }
        guard let codecValue = VideoCodec(rawValue: (codec ?? "h264").lowercased()) else {
            throw usage("\"\(codec!)\" isn't a codec Skreenrek can record.",
                "Use --codec h264, hevc or prores.", "Use codec: \"h264\", \"hevc\" or \"prores\".")
        }
        guard let preset = QualityPreset(rawValue: (quality ?? "high").lowercased()) else {
            throw usage("\"\(quality!)\" isn't a quality preset.",
                "Use --quality low, medium, high or max, or set --bitrate in Mbps.",
                "Use quality: \"low\", \"medium\", \"high\" or \"max\", or set bitrateMbps in Mbps.")
        }
        if quality != nil, bitrateMbps != nil {
            throw usage("Use either --quality or --bitrate, not both.",
                "Drop one. --bitrate sets an exact target; --quality picks one for the window size.",
                "Drop one. bitrateMbps sets an exact target; quality picks one for the window size.")
        }
        if let bitrateMbps, !bitrateMbps.isFinite || !(1...200).contains(bitrateMbps) {
            let passed = String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), bitrateMbps)
            throw usage("Bitrate must be between 1 and 200 Mbps. You passed \(passed).",
                "Pass a --bitrate from 1 to 200, or use --quality high.",
                "Pass a bitrateMbps from 1 to 200, or use quality: \"high\".")
        }
        if codecValue == .prores, containerValue != .mov {
            throw usage("ProRes can only be saved as a .mov file.",
                "Add --format mov, or use --codec h264 or --codec hevc.",
                "Add format: \"mov\", or use codec: \"h264\" or codec: \"hevc\".")
        }
        if codecValue == .prores, bitrateMbps != nil {
            throw usage("ProRes doesn't take a bitrate. Its quality comes from --quality.",
                "Replace --bitrate with --quality low, medium, high or max.",
                "Replace bitrateMbps with quality: \"low\", \"medium\", \"high\" or \"max\".")
        }
        let profile: String
        switch codecValue {
        case .h264: profile = "high"
        case .hevc: profile = "main"
        case .prores:
            profile = switch preset { case .low: "proxy"; case .medium: "lt"; case .high: "422"; case .max: "422hq" }
        }
        return Self(container: containerValue, codec: codecValue, profile: profile,
            quality: bitrateMbps == nil ? preset : nil, requestedBitrateMbps: bitrateMbps)
    }

    public var isDefault: Bool {
        container == .mp4 && codec == .h264 && quality == .high && requestedBitrateMbps == nil
    }

    private enum CodingKeys: String, CodingKey { case container, codec, profile, quality, requestedBitrateMbps, bitrateMbps }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self = try Self.resolve(container: c.decode(String.self, forKey: .container),
            codec: c.decode(String.self, forKey: .codec), quality: c.decodeIfPresent(String.self, forKey: .quality),
            bitrateMbps: c.decodeIfPresent(Double.self, forKey: .requestedBitrateMbps))
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(container, forKey: .container)
        try c.encode(codec, forKey: .codec)
        try c.encode(profile, forKey: .profile)
        try c.encode(quality, forKey: .quality)
        try c.encode(requestedBitrateMbps, forKey: .requestedBitrateMbps)
        try c.encodeNil(forKey: .bitrateMbps)
    }

    public func targetBitrate(size: PixelSize, fps: FrameRate) -> Int? {
        guard codec != .prores else { return nil }
        if let requestedBitrateMbps { return Int((requestedBitrateMbps * 1_000_000).rounded()) }
        let multiplier: Double = switch quality ?? .high {
        case .low: 0.25; case .medium: 0.5; case .high: 1; case .max: 2
        }
        let raw = Double(size.width) * Double(size.height) * Double(fps.framesPerSecond) * 0.08 * multiplier
        return Int(min(max(raw, 4_000_000 * multiplier), 80_000_000 * multiplier).rounded())
    }
}

extension RecordingOptions {
    public func resolvedOutput(surface: StartedBy = .cli) throws -> OutputSettings {
        try .resolve(container: container.rawValue, codec: codec.rawValue, quality: quality?.rawValue,
            bitrateMbps: bitrateMbps, surface: surface)
    }
}

extension VideoCodec {
    public var displayName: String {
        switch self { case .h264: "H.264"; case .hevc: "HEVC"; case .prores: "ProRes" }
    }
}
