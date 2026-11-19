import AVFoundation
import CoreMedia
import Foundation

/// File facts come from the completed asset. Quality and requested bitrate describe the encoder request.
public struct VideoReadback: Sendable, Hashable, Codable {
    public var file: String
    public var container: VideoContainer
    public var codec: VideoCodec
    public var profile: String
    public var quality: QualityPreset?
    public var requestedBitrateMbps: Double?
    public var bitrateMbps: Double?
    public var width: Int
    public var height: Int
    public var scale: Double

    public init(file: String, width: Int, height: Int, scale: Double, codec: VideoCodec,
        container: VideoContainer = .mp4, profile: String? = nil, quality: QualityPreset? = .high,
        requestedBitrateMbps: Double? = nil, bitrateMbps: Double? = nil
    ) {
        self.file = file
        self.container = container
        self.codec = codec
        self.profile = profile ?? (codec == .h264 ? "high" : codec == .hevc ? "main" : "422")
        self.quality = quality
        self.requestedBitrateMbps = requestedBitrateMbps
        self.bitrateMbps = bitrateMbps
        self.width = width
        self.height = height
        self.scale = scale
    }

    /// `file` is the movie's name in its folder (see `VideoContainer.fileName(forFolder:)`).
    public init(settings: OutputSettings, size: PixelSize, scale: Double = 1, file: String) {
        self.init(file: file, width: size.width, height: size.height, scale: scale, codec: settings.codec,
            container: settings.container, profile: settings.profile, quality: settings.quality,
            requestedBitrateMbps: settings.requestedBitrateMbps)
    }

    public var isDefault: Bool {
        container == .mp4 && codec == .h264 && quality == .high && requestedBitrateMbps == nil
    }
    public var formatLabel: String { "\(codec.displayName) \(container.rawValue.uppercased())" }

    private enum CodingKeys: String, CodingKey {
        case file, container, codec, profile, quality, requestedBitrateMbps, bitrateMbps, width, height, scale
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(file, forKey: .file)
        try c.encode(container, forKey: .container)
        try c.encode(codec, forKey: .codec)
        try c.encode(profile, forKey: .profile)
        try c.encode(quality, forKey: .quality)
        try c.encode(requestedBitrateMbps, forKey: .requestedBitrateMbps)
        try c.encode(bitrateMbps, forKey: .bitrateMbps)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encode(scale, forKey: .scale)
    }

    public static func inspect(url: URL, settings: OutputSettings, scale: Double = 1) async throws -> Self {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first,
            let format = try await track.load(.formatDescriptions).first else { throw ReadError.noVideo }
        let subtype = CMFormatDescriptionGetMediaSubType(format)
        let atoms = CMFormatDescriptionGetExtension(format,
            extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Data] ?? [:]
        let codec: VideoCodec
        let profile: String
        switch subtype {
        case kCMVideoCodecType_H264:
            codec = .h264
            guard let config = atoms["avcC"], config.count > 1 else { throw ReadError.noProfile }
            switch config[1] {
            case 100: profile = "high"
            case 77: profile = "main"
            case 66: profile = "baseline"
            default: throw ReadError.noProfile
            }
        case kCMVideoCodecType_HEVC:
            codec = .hevc
            guard let config = atoms["hvcC"], config.count > 1 else { throw ReadError.noProfile }
            switch config[1] & 0x1f {
            case 1: profile = "main"
            case 2: profile = "main10"
            default: throw ReadError.noProfile
            }
        case kCMVideoCodecType_AppleProRes422Proxy: codec = .prores; profile = "proxy"
        case kCMVideoCodecType_AppleProRes422LT: codec = .prores; profile = "lt"
        case kCMVideoCodecType_AppleProRes422: codec = .prores; profile = "422"
        case kCMVideoCodecType_AppleProRes422HQ: codec = .prores; profile = "422hq"
        default: throw ReadError.noVideo
        }
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw ReadError.noVideo }
        let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let bitrate = (Double(bytes) * 8 / duration / 1_000_000 * 10).rounded() / 10
        return Self(file: url.lastPathComponent, width: Int(dimensions.width), height: Int(dimensions.height),
            scale: scale, codec: codec, container: try readContainer(url), profile: profile,
            quality: settings.quality, requestedBitrateMbps: settings.requestedBitrateMbps, bitrateMbps: bitrate)
    }

    /// Inspect the major brand, regardless of the URL's extension. AVAssetWriter emits ftyp first.
    private static func readContainer(_ url: URL) throws -> VideoContainer {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 32) ?? Data()
        guard header.count >= 12, String(decoding: header[4..<8], as: UTF8.self) == "ftyp" else {
            throw ReadError.noContainer
        }
        let brand = String(decoding: header[8..<12], as: UTF8.self)
        if brand == "qt  " { return .mov }
        guard ["isom", "iso2", "mp41", "mp42", "avc1", "M4V "].contains(brand) else { throw ReadError.noContainer }
        return .mp4
    }

    private enum ReadError: Error { case noVideo, noProfile, noContainer }
}
