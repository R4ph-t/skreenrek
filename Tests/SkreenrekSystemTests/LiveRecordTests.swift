import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import SkreenrekCore
import SkreenrekSystem
import Testing

extension LiveGate {
    /// `SKREENREK_LIVE=1` and Screen Recording already allowed for the test runner (checked without prompting).
    static var recordEnabled: Bool {
        ProcessInfo.processInfo.environment["SKREENREK_LIVE"] == "1" && SCStreamFrameSource.screenRecordingAllowed
    }
}

/// Opt-in: records a window the test opens for 2 s at 60 fps through ScreenCaptureKit and the real writer, and checks
/// 120 frames and a clean recording. Never prompts. Run with `SKREENREK_LIVE=1 swift test --filter Live`.
@Suite(.enabled(if: LiveGate.recordEnabled, "Set SKREENREK_LIVE=1 and allow Screen Recording for the test runner"))
struct LiveRecordTests {
    static let title = "skreenrek live record"

    /// A window in its own process (osascript with the Cocoa bridge). It prints `ready <window number>` once on screen.
    static let script = """
        ObjC.import('Cocoa');
        var app = $.NSApplication.sharedApplication;
        app.setActivationPolicy($.NSApplicationActivationPolicyRegular);
        var w = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer(
            $.NSMakeRect(240, 240, 640, 400), 15, $.NSBackingStoreBuffered, false);
        w.title = '\(title)';
        w.makeKeyAndOrderFront(null);
        console.log('ready ' + w.windowNumber);
        app.run;
        """

    @Test func recordsTwoSecondsAt60FpsClean() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", Self.script]
        let output = Pipe()
        process.standardError = output
        try process.run()
        defer { process.terminate() }

        var windowNumber: UInt32?
        for try await line in output.fileHandleForReading.bytes.lines where line.hasPrefix("ready ") {
            windowNumber = UInt32(line.dropFirst("ready ".count))
            break
        }
        let id = try #require(windowNumber)
        let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(id)) as? [[String: Any]] ?? []
        let bounds = try #require(list.first?[kCGWindowBounds as String] as? NSDictionary)
        let rect = try #require(CGRect(dictionaryRepresentation: bounds))
        let window = WindowInfo(
            id: WindowID(id), app: "osascript", bundleId: nil, title: Self.title, pid: process.processIdentifier,
            frame: PointRect(rect), displayId: 0, onScreen: true)
        let displays = await AppKitDisplays.current()
        let display = try #require(WindowDirectory.display(for: window.frame, in: displays))
        let size = window.pixelSize(on: display)

        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("skreenrek-live-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let folder = try OutputFolder.create(
            in: parent, target: .window(window), name: "live", date: Date())

        let session = RecordingSession(
            source: SCStreamFrameSource(), clock: HostTimeClock(), disk: VolumeDiskSpaceProbe(),
            encoder: .requireHardware)
        try await session.start(
            target: .window(window), size: size, options: RecordingOptions(fps: .fps60, duration: 2), folder: folder)
        let result = await session.waitForEnd()
        print("LiveRecordTests: \(size) \(result.stats)")

        #expect(result.stopReason == .duration)
        #expect(result.stats.slotsWritten == 120)
        #expect(result.stats.isClean)
        let asset = AVURLAsset(url: result.clipURL)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(trackOutput)
        #expect(reader.startReading())
        var samples = 0
        while let buffer = trackOutput.copyNextSampleBuffer() { samples += CMSampleBufferGetNumSamples(buffer) }
        #expect(samples == 120)
    }
}
