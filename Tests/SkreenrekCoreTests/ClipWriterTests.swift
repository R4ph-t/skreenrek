import AVFoundation
import Foundation
import SkreenrekCore
import Testing
import VideoToolbox

extension RecorderSuites {
    @Suite struct ClipWriterTests {
        @Test func theBitRateIsPointZeroEightBitsPerPixelPerFrameClamped() {
            #expect(ClipWriterSettings.averageBitRate(size: PixelSize(width: 1920, height: 1080), fps: .fps60) == 9_953_280)
            #expect(ClipWriterSettings.averageBitRate(size: PixelSize(width: 1280, height: 800), fps: .fps30) == 4_000_000)
            #expect(ClipWriterSettings.averageBitRate(size: PixelSize(width: 2560, height: 1600), fps: .fps60) == 19_660_800)
            #expect(ClipWriterSettings.averageBitRate(size: PixelSize(width: 640, height: 400), fps: .fps30) == 4_000_000)
            #expect(ClipWriterSettings.averageBitRate(size: PixelSize(width: 8000, height: 8000), fps: .fps60) == 80_000_000)
        }

        @Test func outputSettingsAskForH264HighRec709AndAKeyframeEveryTwoSeconds() throws {
            let settings = ClipWriterSettings(
                url: URL(fileURLWithPath: "/tmp/clip.mp4"), size: PixelSize(width: 1920, height: 1080), fps: .fps60)
            let output = ClipWriter.outputSettings(settings, hardware: true)
            #expect(output[AVVideoCodecKey] as? AVVideoCodecType == .h264)
            #expect(output[AVVideoWidthKey] as? Int == 1920)
            #expect(output[AVVideoHeightKey] as? Int == 1080)
            let compression = try #require(output[AVVideoCompressionPropertiesKey] as? [String: Any])
            #expect(compression[AVVideoProfileLevelKey] as? String == AVVideoProfileLevelH264HighAutoLevel)
            #expect(compression[AVVideoAverageBitRateKey] as? Int == 9_953_280)
            #expect(compression[AVVideoMaxKeyFrameIntervalKey] as? Int == 120)
            #expect(compression[AVVideoMaxKeyFrameIntervalDurationKey] as? Int == 2)
            let color = try #require(output[AVVideoColorPropertiesKey] as? [String: String])
            #expect(color[AVVideoColorPrimariesKey] == AVVideoColorPrimaries_ITU_R_709_2)
            #expect(color[AVVideoTransferFunctionKey] == AVVideoTransferFunction_ITU_R_709_2)
            #expect(color[AVVideoYCbCrMatrixKey] == AVVideoYCbCrMatrix_ITU_R_709_2)
            let hardware = try #require(output[AVVideoEncoderSpecificationKey] as? [String: Bool])
            #expect(hardware[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String] == true)
            let software = try #require(
                ClipWriter.outputSettings(settings, hardware: false)[AVVideoEncoderSpecificationKey] as? [String: Bool])
            #expect(software[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String] == false)
        }

        @Test func hevcSettingsUseTheHEVCCodec() {
            var settings = ClipWriterSettings(
                url: URL(fileURLWithPath: "/tmp/clip.mp4"), size: PixelSize(width: 1280, height: 800), fps: .fps30)
            settings.codec = .hevc
            let output = ClipWriter.outputSettings(settings, hardware: true)
            #expect(output[AVVideoCodecKey] as? AVVideoCodecType == .hevc)
        }

        @Test func theSoftwarePolicyReportsSoftware() throws {
            let temp = try TempFolder("writer")
            defer { temp.cleanUp() }
            let writer = try ClipWriter(
                settings: ClipWriterSettings(
                    url: temp.url.appendingPathComponent("clip.mp4"), size: PixelSize(width: 320, height: 200),
                    fps: .fps30, encoder: .software))
            #expect(writer.encoder == .software)
            #expect(writer.isReady)
        }

        @Test func theHardwarePolicyNeverFailsTheRecording() throws {
            let temp = try TempFolder("writer-hw")
            defer { temp.cleanUp() }
            let writer = try ClipWriter(
                settings: ClipWriterSettings(
                    url: temp.url.appendingPathComponent("clip.mp4"), size: PixelSize(width: 320, height: 200),
                    fps: .fps30, encoder: .requireHardware))
            print("ClipWriterTests: .requireHardware gave the \(writer.encoder.rawValue) encoder")
            #expect(EncoderKind.allCases.contains(writer.encoder))
        }
    }
}
