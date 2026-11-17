import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import SkreenrekCore
import SkreenrekTesting
import Synchronization
import Testing
import VideoToolbox

/// Builds a session that writes a real MP4 with the software encoder, offline (every slot gets its frame).
private func offlineSession(
    _ source: any FrameSource, clock: any HostClock = ManualClock(), disk: any DiskSpaceProbe = FakeDiskSpaceProbe(),
    encoder: EncoderPolicy = .software, onSlot: (@Sendable (SlotTick) -> Void)? = nil
) -> RecordingSession {
    RecordingSession(
        source: source, clock: clock, disk: disk, encoder: encoder, realTimeWriter: false, onSlot: onSlot)
}

extension RecorderSuites {
    /// Real MP4s from synthetic frames, checked with AVAssetReader.
    @Suite struct RecorderVideoTests {
        /// 2 s with a 300 ms gap in source frames: every slot is written, the gap repeats the last frame before it.
        @Test(arguments: [FrameRate.fps60, .fps30])
        func aGapInSourceFramesStillGivesEveryFrame(fps: FrameRate) async throws {
            let temp = try TempFolder("gap")
            defer { temp.cleanUp() }
            let rate = fps.framesPerSecond
            let gap = (rate / 2)..<(rate / 2 + rate * 3 / 10)  // 0.5 s to 0.8 s
            let times = Fixtures.frameTimes(0..<(2 * rate), fps: rate, skipping: gap)
            let clock = ManualClock()
            let session = offlineSession(SyntheticFrameSource(timing: .scripted(times)), clock: clock)
            let folder = try temp.clipFolder()

            try await session.start(
                target: .window(Fixtures.safari), size: Fixtures.size1280x800,
                options: RecordingOptions(fps: fps, duration: 2), folder: folder)
            await eventually { await session.framesReceived == times.count }
            // The last frame waits for its slot to fall due: move the clock past it.
            clock.advance(to: 2 + RecordingSession.defaultTickGrace)
            let result = try await withTestDeadline { await session.waitForEnd() }

            #expect(result.stopReason == .duration)
            #expect(result.complete)
            #expect(result.stats.slotsWritten == 2 * rate)
            #expect(result.stats.framesFresh == times.count)
            #expect(result.stats.framesRepeatedIdle == gap.count)
            #expect(result.stats.framesDropped == 0)
            #expect(result.stats.sourceFramesSkipped == 0)
            #expect(result.stats.isClean)
            #expect(result.stats.encoder == .software)
            #expect(result.stats.pixelFormat == "420v")
            #expect(result.duration == 2)

            let samples = try await VideoFile.samples(result.clipURL)
            #expect(samples.count == 2 * rate)
            let slot = CMTime(value: 1, timescale: CMTimeScale(rate))
            for (n, sample) in samples.enumerated() {
                #expect(sample.presentationTime == CMTime(value: CMTimeValue(n), timescale: CMTimeScale(rate)))
                #expect(sample.duration == slot, "sample \(n)")
            }

            // Source frame k carries luma for index k; during the gap the frame before it repeats.
            let expected = (0..<(2 * rate)).map { n -> Int in
                let sourceIndex = n < gap.lowerBound ? n : (gap.contains(n) ? gap.lowerBound - 1 : n - gap.count)
                return sourceIndex % SyntheticFrameSource.lumaCycle
            }
            #expect(try await VideoFile.frameIndices(result.clipURL) == expected)
        }

        @Test(arguments: [
            PixelSize(width: 1280, height: 800), PixelSize(width: 1920, height: 1080), PixelSize(width: 1080, height: 1920),
        ])
        func theClipIsTheTargetsNativePixelSize(size: PixelSize) async throws {
            let temp = try TempFolder("size")
            defer { temp.cleanUp() }
            let session = offlineSession(SyntheticFrameSource(count: 20, fps: 30))
            try await session.start(
                target: .window(Fixtures.safari), size: size, options: RecordingOptions(fps: .fps30, duration: 0.5),
                folder: try temp.clipFolder())
            let result = try await withTestDeadline { await session.waitForEnd() }
            #expect(result.size == size)
            #expect(try await VideoFile.naturalSize(result.clipURL) == size)
            #expect(try await VideoFile.codec(result.clipURL) == kCMVideoCodecType_H264)
            #expect(try await VideoFile.samples(result.clipURL).count == 15)
        }

        @Test func durationGivesExactlyDurationTimesFpsFrames() async throws {
            let temp = try TempFolder("duration")
            defer { temp.cleanUp() }
            let session = offlineSession(SyntheticFrameSource(count: 200, fps: 60))
            try await session.start(
                target: .window(Fixtures.safari), size: PixelSize(width: 640, height: 400),
                options: RecordingOptions(fps: .fps60, duration: 1.5), folder: try temp.clipFolder())
            let result = try await withTestDeadline { await session.waitForEnd() }
            #expect(result.stopReason == .duration)
            #expect(result.stats.slotsWritten == 90)
            #expect(result.duration == 1.5)
            #expect(try await VideoFile.samples(result.clipURL).count == 90)
            let asset = AVURLAsset(url: result.clipURL)
            #expect(try await asset.load(.duration) == CMTime(value: 90, timescale: 60))
        }

        @Test func aClosedWindowSavesAPlayablePartialClip() async throws {
            let temp = try TempFolder("closed")
            defer { temp.cleanUp() }
            let source = SyntheticFrameSource(count: 30, fps: 60, endError: FrameSourceError.windowClosed)
            let session = offlineSession(source)
            try await session.start(
                target: .window(Fixtures.safari), size: Fixtures.size1280x800, options: RecordingOptions(fps: .fps60),
                folder: try temp.clipFolder())
            let result = try await withTestDeadline { await session.waitForEnd() }

            #expect(result.stopReason == .windowClosed(at: 0.5))
            #expect(!result.complete)
            let error = try #require(result.error)
            #expect(error.exitCode == 7)
            #expect(error.code == "recording_failed")
            #expect(error.message == "The window closed at 0:00. The clip up to that point was saved.")
            #expect(result.stats.slotsWritten == 30)
            #expect(try await VideoFile.samples(result.clipURL).count == 30)
            #expect(source.stopCount >= 1)
        }

        @Test func lowDiskStopsWithTheDiskCopy() async throws {
            let temp = try TempFolder("disk")
            defer { temp.cleanUp() }
            // The check at 0:00 sees plenty of space; the one at 0:05 sees 1 GB.
            let disk = DroppingDiskProbe(highCalls: 1)
            let session = offlineSession(
                SyntheticFrameSource(count: 400, fps: 60), disk: disk)
            let folder = try temp.clipFolder()
            try await session.start(
                target: .window(Fixtures.safari), size: PixelSize(width: 320, height: 200),
                options: RecordingOptions(fps: .fps60), folder: folder)
            let result = try await withTestDeadline { await session.waitForEnd() }

            #expect(result.stopReason == .diskLow(at: 5))
            #expect(!result.complete)
            #expect(result.error?.message == "Less than 2 GB free. The clip up to 0:05 was saved.")
            #expect(result.error?.exitCode == 7)
            #expect(disk.callCount == 2)
            #expect(try await VideoFile.samples(result.clipURL).count == result.stats.slotsWritten)
            #expect(result.stats.slotsWritten >= 300)
        }

        @Test(.enabled(if: RecorderVideoTests.hevcEncoderAvailable()))
        func anHEVCClipWhenTheMachineHasAnHEVCEncoder() async throws {
            let temp = try TempFolder("hevc")
            defer { temp.cleanUp() }
            let session = offlineSession(SyntheticFrameSource(count: 40, fps: 30), encoder: .requireHardware)
            try await session.start(
                target: .window(Fixtures.safari), size: Fixtures.size1280x800,
                options: RecordingOptions(fps: .fps30, codec: .hevc, duration: 1), folder: try temp.clipFolder())
            let result = try await withTestDeadline { await session.waitForEnd() }
            #expect(result.codec == .hevc)
            #expect(try await VideoFile.codec(result.clipURL) == kCMVideoCodecType_HEVC)
            #expect(try await VideoFile.samples(result.clipURL).count == 30)
            print("RecorderVideoTests: HEVC encoder used: \(result.stats.encoder.rawValue)")
        }

        static func hevcEncoderAvailable() -> Bool {
            var session: VTCompressionSession?
            let status = VTCompressionSessionCreate(
                allocator: nil, width: 1280, height: 800, codecType: kCMVideoCodecType_HEVC, encoderSpecification: nil,
                imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: nil, refcon: nil,
                compressionSessionOut: &session)
            if let session { VTCompressionSessionInvalidate(session) }
            return status == noErr && session != nil
        }
    }

    /// Session behaviour with fake sinks: stop, discard, failures, the tick hook, stats.
    @Suite struct RecordingSessionTests {
        private static func session(
            _ source: any FrameSource, sink: any PixelBufferSink, clock: any HostClock = ManualClock(),
            disk: any DiskSpaceProbe = FakeDiskSpaceProbe(), onSlot: (@Sendable (SlotTick) -> Void)? = nil
        ) -> RecordingSession {
            RecordingSession(
                source: source, clock: clock, disk: disk, encoder: .software, makeSink: { _ in sink }, onSlot: onSlot)
        }

        @Test func stopWritesEverySlotUpToNowAndTheResultDescribesTheClip() async throws {
            let temp = try TempFolder("stop")
            defer { temp.cleanUp() }
            let clock = ManualClock(now: 50)
            let source = SyntheticFrameSource(timing: .scripted(Fixtures.frameTimes(0..<10, fps: 30, start: 50)))
            let sink = RecordingSink()
            let session = Self.session(source, sink: sink, clock: clock)
            let folder = try temp.clipFolder("2026-11-17_104207_safari")
            let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
            try await session.start(
                target: .window(Fixtures.safari), size: Fixtures.size1280x800, options: RecordingOptions(fps: .fps30),
                folder: folder, origin: RecordingOrigin(startedBy: .mcp, client: "Claude Code"), startedAt: startedAt)

            // Ten frames, then the source goes quiet (an idle window) until 2 s.
            await eventually { await session.framesReceived == 10 }
            clock.advance(to: 52)
            await eventually { await session.stats.slotsWritten > 1 }
            let result = try await withTestDeadline { try await session.stop() }

            #expect(result.id == "2026-11-17_104207_safari")
            #expect(result.folder == folder)
            #expect(result.fps == .fps30)
            #expect(result.size == Fixtures.size1280x800)
            #expect(result.codec == .h264)
            #expect(result.startedAt == startedAt)
            #expect(result.startedBy == .mcp)
            #expect(result.origin.client == "Claude Code")
            #expect(result.complete)
            #expect(result.stopReason == .stopped)
            #expect(result.error == nil)
            #expect(result.firstFrameHostTime == 50)
            // Stop at 2.0 s: slots 0…60.
            #expect(result.stats.slotsWritten == 61)
            #expect(result.duration == 61.0 / 30)
            #expect(result.stats.framesFresh == 10)
            #expect(result.stats.framesRepeatedIdle == 51)
            #expect(result.stats.isClean)
            #expect(result.stats.startToFirstFrameMs == 0)
            #expect(result.stats.stopToFinalizedMs == 0)
            #expect(sink.finishedSlotCount == 61)
            #expect(sink.appended.map(\.slot) == Array(0..<61))
            #expect(source.stopCount >= 1)

            // Stopping again returns the same result; the stats stay final.
            #expect(try await withTestDeadline { try await session.stop() } == result)
            #expect(await session.stats == result.stats)
        }

        @Test func idleTicksCatchUpAfterALateWake() async throws {
            let clock = ManualClock()
            let sink = RecordingSink()
            let session = Self.session(SyntheticFrameSource(count: 1, fps: 60), sink: sink, clock: clock)
            try await session.start(
                target: .window(Fixtures.safari), size: Fixtures.size1280x800, options: RecordingOptions(fps: .fps60),
                folder: Fixtures.unusedFolder)
            await eventually { await session.framesReceived == 1 }
            // One big jump: the tick that wakes writes every slot that fell due, with no gap.
            clock.advance(to: 1 + RecordingSession.defaultTickGrace)
            await eventually { await session.stats.slotsWritten == 61 }
            #expect(sink.appended.map(\.slot) == Array(0..<61))
            let stats = await session.stats
            #expect(stats.framesRepeatedIdle == 60)
            #expect(stats.framesDropped == 0)
            _ = try await withTestDeadline { try await session.stop() }
        }

        @Test func theTickHookSeesEverySlotOnceInOrderWithTheFirstFrameTime() async throws {
            let ticks = Mutex<[SlotTick]>([])
            let source = SyntheticFrameSource(timing: .scripted(Fixtures.frameTimes(0..<12, fps: 60, start: 7)))
            let session = Self.session(source, sink: RecordingSink(), onSlot: { tick in ticks.withLock { $0.append(tick) } })
            try await session.start(
                target: .window(Fixtures.safari), size: Fixtures.size1280x800,
                options: RecordingOptions(fps: .fps60, duration: 0.15), folder: Fixtures.unusedFolder)
            let result = try await withTestDeadline { await session.waitForEnd() }
            let seen = ticks.withLock { $0 }
            #expect(seen.map(\.index) == Array(0..<9))
            #expect(seen.allSatisfy { $0.firstFrameHostTime == 7 })
            #expect(seen.allSatisfy { abs($0.hostTime - (7 + Double($0.index) / 60)) < 1e-9 })
            #expect(result.firstFrameHostTime == 7)
            #expect(await session.firstFrameHostTime == 7)
        }

        @Test func aWrongSizeFrameIsSkippedAndCounted() async throws {
            let source = SyntheticFrameSource(
                timing: .scripted(Fixtures.frameTimes(0..<10, fps: 30)), frameSizes: [4: PixelSize(width: 8, height: 8)])
            let sink = RecordingSink()
            let session = Self.session(source, sink: sink)
            try await session.start(
                target: .window(Fixtures.safari), size: Fixtures.size1280x800,
                options: RecordingOptions(fps: .fps30, duration: 9.0 / 30), folder: Fixtures.unusedFolder)
            let result = try await withTestDeadline { await session.waitForEnd() }
            #expect(result.stats.sourceFramesSkipped == 1)
            #expect(result.stats.framesRepeatedIdle == 1)
            #expect(!result.stats.isClean)
            #expect(sink.appended[4].frame.pixelBuffer === sink.appended[3].frame.pixelBuffer)
        }

        @Test func discardStopsAndDeletesTheClipFolder() async throws {
            let temp = try TempFolder("discard")
            defer { temp.cleanUp() }
            let folder = try temp.clipFolder()
            let clock = ManualClock()
            let source = SyntheticFrameSource(timing: .realTime(clock, fps: 60, count: nil))
            let session = RecordingSession(
                source: source, clock: clock, disk: FakeDiskSpaceProbe(), encoder: .software, realTimeWriter: false)
            try await session.start(
                target: .window(Fixtures.safari), size: PixelSize(width: 320, height: 200),
                options: RecordingOptions(fps: .fps60), folder: folder)
            clock.advance(to: 0.5)
            await eventually { await session.framesReceived >= 5 }
            #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("clip.mp4").path))
            await session.discard()
            #expect(!FileManager.default.fileExists(atPath: folder.path))
            let result = try await withTestDeadline { await session.waitForEnd() }
            #expect(result.stopReason == .discarded)
            #expect(!result.complete)
            #expect(result.error == nil)
            #expect(source.stopCount >= 1)
        }

        @Test func anUnwritableFolderFailsBeforeStartAndTheSourceNeverStarts() async throws {
            let temp = try TempFolder("readonly")
            defer { temp.cleanUp() }
            let folder = try temp.clipFolder()
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
            let source = SyntheticFrameSource(count: 10, fps: 60)
            let session = RecordingSession(source: source, clock: ManualClock(), disk: FakeDiskSpaceProbe(), encoder: .software)
            await #expect(throws: SkreenrekError.recordingFailed(.notWritable)) {
                try await session.start(
                    target: .window(Fixtures.safari), size: Fixtures.size1280x800, options: RecordingOptions(),
                    folder: folder)
            }
            #expect(source.startCalls.isEmpty)
            #expect(SkreenrekError.recordingFailed(.notWritable).message == "The output folder isn't writable.")
            await #expect(throws: SkreenrekError.wrongState(.notRecording)) { try await withTestDeadline { try await session.stop() } }
        }

        @Test func aWriteFailureStopsWithTheNotWritableCopy() async throws {
            final class FailingSink: PixelBufferSink, @unchecked Sendable {
                let encoder = EncoderKind.software
                var isReady: Bool { true }
                func append(_ pixelBuffer: CVPixelBuffer, slot: Int) -> Bool { slot < 5 }
                func waitUntilReady(timeout: TimeInterval) async -> Bool { true }
                func finish(slotCount: Int) async throws {}
                func cancel() async {}
            }
            let session = Self.session(SyntheticFrameSource(count: 20, fps: 60), sink: FailingSink())
            try await session.start(
                target: .window(Fixtures.safari), size: Fixtures.size1280x800, options: RecordingOptions(),
                folder: Fixtures.unusedFolder)
            let result = try await withTestDeadline { await session.waitForEnd() }
            #expect(result.stopReason == .writeFailed)
            #expect(!result.complete)
            #expect(result.error == .recordingFailed(.notWritable))
            #expect(result.stats.slotsWritten == 5)
        }

        @Test func aPermissionFailureAtStartIsRethrownAndTheEmptyFolderRemoved() async throws {
            let temp = try TempFolder("permission")
            defer { temp.cleanUp() }
            let folder = try temp.clipFolder()
            let sink = RecordingSink()
            let source = SyntheticFrameSource(timing: .scripted([]), startError: SkreenrekError.permissionDenied(.screenRecording))
            let session = Self.session(source, sink: sink)
            await #expect(throws: SkreenrekError.permissionDenied(.screenRecording)) {
                try await session.start(
                    target: .window(Fixtures.safari), size: Fixtures.size1280x800, options: RecordingOptions(),
                    folder: folder)
            }
            #expect(sink.cancelled)
            #expect(!FileManager.default.fileExists(atPath: folder.path))
        }

        @Test func startingTwiceIsWrongState() async throws {
            let session = Self.session(SyntheticFrameSource(count: 1, fps: 60), sink: RecordingSink())
            let folder = Fixtures.unusedFolder
            try await session.start(
                target: .window(Fixtures.safari), size: Fixtures.size1280x800, options: RecordingOptions(), folder: folder)
            await #expect(throws: SkreenrekError.wrongState(.alreadyRecording(app: nil))) {
                try await session.start(
                    target: .window(Fixtures.safari), size: Fixtures.size1280x800, options: RecordingOptions(),
                    folder: folder)
            }
            _ = try await withTestDeadline { try await session.stop() }
        }

        @Test func theSourceGetsTheTargetSizeFpsAndCursorOption() async throws {
            let source = SyntheticFrameSource(count: 1, fps: 30)
            let session = Self.session(source, sink: RecordingSink())
            let region = CaptureTarget.region(PixelRect(x: 10, y: 20, width: 800, height: 600), displayId: 1)
            try await session.start(
                target: region, size: PixelSize(width: 800, height: 600),
                options: RecordingOptions(fps: .fps30, cursor: false), folder: Fixtures.unusedFolder)
            _ = try await withTestDeadline { try await session.stop() }
            #expect(
                source.startCalls
                    == [.init(target: region, size: PixelSize(width: 800, height: 600), fps: .fps30, showsCursor: false)])
        }

        @Test func noFrameAtAllLeavesNoClipFile() async throws {
            let temp = try TempFolder("empty")
            defer { temp.cleanUp() }
            let folder = try temp.clipFolder()
            let session = RecordingSession(
                source: SyntheticFrameSource(timing: .scripted([])), clock: ManualClock(), disk: FakeDiskSpaceProbe(),
                encoder: .software)
            try await session.start(
                target: .window(Fixtures.safari), size: PixelSize(width: 320, height: 200), options: RecordingOptions(),
                folder: folder)
            let result = try await withTestDeadline { try await session.stop() }
            #expect(result.stats.slotsWritten == 0)
            #expect(result.duration == 0)
            #expect(!FileManager.default.fileExists(atPath: result.clipURL.path))
        }
    }
}
