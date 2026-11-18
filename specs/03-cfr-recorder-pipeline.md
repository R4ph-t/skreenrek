# 03: Constant-frame-rate recorder pipeline and ScreenCaptureKit frame source

Status: Done · Branch: `lane/03-cfr-recorder-pipeline` · Depends on: 01 (scaffold) · Estimate: 6–8 h agent run + 0 h Raph review (no hand test) · Risk: high
Source: Designer's spec (Notion "Agent capture tool — design spec v1 (2026-11-17)", 2026-11-17), from CPO's brief (Notion "Fraime — Agent-controlled capture — brief — 2026-11-17"). Plan: Fraime Lead's "Skreenrek v1 implementation plan (2026-11-17)".

Note: the bundle ID was `it.fraime.skreenrek` before the switch to `com.raphaelterrier.skreenrek`.

## Goal

Turn a stream of captured frames into a smooth H.264 MP4 at exactly 30 or 60 fps at native resolution, with no time
or size cap, written into one folder per clip, and stop cleanly on stop, duration, window close, low disk or a write
failure. The path is zero-copy (ScreenCaptureKit's IOSurface-backed buffers go straight into AVAssetWriter) and uses
the hardware H.264 encoder, with measured start, drop and finalize numbers. Risk is high because the real frame
source is ScreenCaptureKit (Screen Recording permission).

## Behaviour

1. `CFRScheduler` (Core, pure): slot n has time `t0 + n / fps`, where t0 is the host time of the first frame. Each slot
   takes the newest frame whose host time is ≤ the slot time; when no new frame arrived, it repeats the previous one.
   It holds at most one pending frame besides the last written one (memory stays flat for any length, and the
   capture stream is never starved of buffers).
2. `ClipWriter` (Core): `AVAssetWriter` to `clip.mp4` (`.mp4`, `shouldOptimizeForNetworkUse = false`, so stopping
   never rewrites the file), one video input through an `AVAssetWriterInputPixelBufferAdaptor`, presentation time
   exactly `CMTime(value: n, timescale: fps)`. H.264 High profile by default, HEVC when `codec == .hevc`. Average bit
   rate `width × height × fps × 0.08` bits/s, clamped to 4–80 Mbit/s. Keyframe at least every 2 s. Rec. 709 colour
   properties. Output size = the target's native pixel size (window px from 02, or the region px).
3. **Zero-copy.** Frames are IOSurface-backed `420v` (`kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange`)
   `CVPixelBuffer`s. The exact buffer object the source delivered is the one appended (a repeat re-appends the same
   object with the next timestamp). Nothing in the capture-to-writer path locks base addresses, copies pixels, or
   renders through Core Image, Core Graphics or vImage. All writes go through a `PixelBufferSink` seam (real: the
   adaptor; test: a recording sink) so tests can check buffer identity.
4. **Hardware encoder.** `EncoderPolicy` (from 01): the app uses `.requireHardware`
   (`AVVideoEncoderSpecificationKey` with `kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder`).
   If the writer can't start with it, the session falls back to software and says so in the stats
   (`encoder: "software"`) and in the log; it never fails a recording for this. Tests on the CI virtual machine use
   `.software`.
5. `RecordingSession` (Core) ties `FrameSource`, `CFRScheduler`, `ClipWriter`, `HostClock` and `DiskSpaceProbe`:
   - `start(target, options, folder)` starts the source and a tick loop that writes every due slot per `1 / fps` of
     `HostClock` time (`sleep(until:)`), so idle windows still produce every frame and a late tick catches up instead
     of leaving a gap.
   - Stops on: `stop()`; `options.duration` reached (the clip is exactly `duration × fps` frames); the source ending
     with "window closed"; free space below 2 GB (checked every 5 s of clip time); a writer error.
   - Every stop finalizes a playable partial or full clip and returns a `RecordingResult` (id, duration = frames /
     fps, fps, width, height, codec, startedAt, startedBy, folder, `complete`, stop reason, `stats`).
     Window closed, disk low and write failure surface as `recording_failed` (exit 7) with the design spec's copy:
     `The window closed at 0:31. The clip up to that point was saved.`,
     `Less than 2 GB free. The clip up to 4:12 was saved.`, `The output folder isn't writable.`
   - `discard()` stops and deletes the clip folder.
   - A frame whose pixel size differs from the output size is skipped (the previous frame repeats) and counted.
   - A tick hook lets 04 sample the cursor once per slot and read the first frame's host time.
6. **Recording stats** (`RecordingStats` from 01), kept by the session and returned with the result:
   - `slotsWritten` (always `duration × fps`), `framesFresh` (slots that got a new source frame),
     `framesRepeatedIdle` (repeats because the source sent nothing: an idle window, not a fault),
     `framesDropped` (slots that repeated because the writer input wasn't ready, or because a fresh frame arrived more
     than one slot late), `sourceFramesSkipped` (fresh source frames never written: superseded or wrong size),
   - `startToFirstFrameMs` (from the `start` call to the first frame appended), `stopToFinalizedMs` (from the stop
     request to `finishWriting` completing with the file closed), `encoder` (`hardware` or `software`), `pixelFormat`.
   - A recording is **clean** when `framesDropped == 0` and `sourceFramesSkipped == 0`.
7. `OutputFolder` (Core, pure + FileManager): `~/Movies/Skreenrek/` by default (`outDir` overrides), created if
   missing. Folder name `YYYY-MM-DD_HHMMSS_<slug>` in local time; the slug is the app name lowercased, ASCII
   `[a-z0-9-]`, at most 40 characters, `region` for regions; `name` overrides the slug (slugified). A collision in the
   same second adds `-2`, `-3`, …. An unwritable folder fails before recording starts with `recording_failed`
   (`The output folder isn't writable.`).
8. `SCStreamFrameSource` (`SkreenrekSystem`, thin): window targets use `SCContentFilter(desktopIndependentWindow:)`;
   regions use `SCContentFilter(display:excludingApplications: [Skreenrek])` plus `sourceRect`. Configuration: width
   and height = output px (scaling happens on the GPU inside ScreenCaptureKit), `minimumFrameInterval` = 1 / fps,
   `showsCursor` = options.cursor, pixel format `420v`, `queueDepth` 6, no audio. Only `.complete` frames are
   delivered, as the original `CVPixelBuffer` (no copy). The stream stopping because the window went away ends the
   stream with "window closed". A permission failure maps to `permission_denied` (Screen Recording).
9. `LiveRecordTests` (opt-in, `SKREENREK_LIVE=1` and Screen Recording already granted): records a test-owned window for
   2 s at 60 fps and checks 120 frames and a clean recording. Skipped otherwise.

## Performance acceptance

Enforced by `make check` (`swift test`, no permissions, hosted macos-15 VM, so budgets are loose multiples of the
real targets; each test prints its measured value):

- `PerfStartTests`: `SyntheticFrameSource` with a frame ready at once, real clock, software encoder, 1920 × 1080: the
  median of 5 runs of `startToFirstFrameMs` ≤ 150 ms.
- `PerfSustainTests`: real clock, a `SyntheticFrameSource` delivering in real time, and a no-op `PixelBufferSink`
  (measures our pipeline, not the VM's encoder): 3 s at 60 fps and 3 s at 30 fps are clean (`framesDropped == 0`,
  `sourceFramesSkipped == 0`, `slotsWritten` exact).
- `StatsAccountingTests` (manual clock, deterministic): an idle gap counts as `framesRepeatedIdle`, not drops; a
  writer-not-ready slot and a frame two slots late count as `framesDropped`; a superseded frame counts in
  `sourceFramesSkipped`; a wrong-size frame counts as skipped.
- `ZeroCopyTests`: every appended buffer is `===` a buffer the source delivered, and is IOSurface-backed `420v`.
- `PerfFinalizeTests`: a 10 s 1280 × 800 at 30 fps synthetic clip (software encoder): `stopToFinalizedMs` ≤ 1500 ms,
  and the file is playable right after.
- Guard (prints nothing):
  `rg -n "CVPixelBufferLockBaseAddress|memcpy|vImage|CIContext|CGContext|CVPixelBufferCreate\(" Sources/SkreenrekCore/Recording Sources/SkreenrekSystem/Capture`

Real targets that need a capture (Raph, manual, see "How to test"; Apple silicon, 2× display, app already running):

- Start to first frame: p95 ≤ 250 ms over 10 runs (window already at size).
- Sustained 60 s at 60 fps 1920 × 1080 and 60 s at 30 fps 1280 × 800: clean (0 dropped, 0 skipped), `encoder`
  `hardware`, `nb_frames` = 3600 and 1800 in `ffprobe`.
- Stop to finalized: ≤ 500 ms for a 60 s clip, ≤ 1 s for a 15-minute clip.

## Defaults

- 60 fps when no fps is given; H.264.
- `t0` is the first frame's host time, so clip time and events time share one zero (used by 04).
- Encoding runs off the main actor; nothing in the pipeline touches the main thread.

## Guardrails

- No time or size cap anywhere.
- Never block the capture callback on encoding; if the writer input isn't ready, the slot repeats (counted as dropped)
  rather than queues.
- Hold at most two source buffers at a time, so ScreenCaptureKit's queue never runs dry.
- Partial clips are always finalized; a crash path must not leave a zero-byte `clip.mp4` when frames were written.
- Deterministic tests use `SyntheticFrameSource` and `ManualClock`; only the `Perf…` suites use the real clock, and none
  need a permission.

## Out of scope

events.json and the HyperFrames snippet (04), the controller and state machine (05), HUD exclusion UI (10), the
`skreenrek debug perf` harness (06).

## Open question (built with the default)

- Bit-rate formula: the 0.08 bits-per-pixel-per-frame rule above (pattern borrowed from Fraime's recorder, rewritten).
- Fast start (`moov` at the front) is off so stop stays fast at any length; browsers and HyperFrames play local MP4s
  either way.

## How to test (Raph)

1. No hand test is needed to merge: CI `factory check` must be green. Besides the performance suites above, the tests
   write real MP4s from synthetic frames and check them with `AVAssetReader`: 2 s at 60 fps with a 300 ms gap in
   source frames → exactly 120 samples, each 1/60 s, frame content shows the repeated frame during the gap; the same
   at 30 fps → 60 samples; 1280 × 800, 1920 × 1080 and 1080 × 1920 sizes; `duration` 1.5 s → 90 frames at 60 fps;
   window closed at 0.5 s → playable partial clip, `complete: false`, exit 7 copy; disk below 2 GB → stop with the
   disk copy; discard deletes the folder; folder naming, slug and `-2` collision with a fixed clock and time zone; an
   unwritable folder fails before start; an HEVC clip when the runner has an HEVC encoder (skipped, not failed, when
   it hasn't).
2. Optional smoke (needs Screen Recording for the test runner, about 2 min): `SKREENREK_LIVE=1 swift test --filter Live`.
3. Optional performance run (needs the app and permissions, about 10 min, available once 06 and hand spec 11 land):
   `make perf`, which checks the real targets in "Performance acceptance" and exits non-zero on a miss.

## Implementation notes

- **Layout.** Core: `Sources/SkreenrekCore/Recording/` (`CFRScheduler`, `PixelBufferSink` + `ClipWriterSettings`,
  `ClipWriter`, `RecordingSession`, `RecordingResult` + `StopReason` + `FrameSourceError`, `OutputFolder`,
  `HostTimeClock`). System: `Sources/SkreenrekSystem/Capture/` (`SCStreamFrameSource`, `VolumeDiskSpaceProbe`).
  No `Package.swift` change: `LiveRecordTests` joins 02's `SkreenrekSystemTests` target.
- **Slot rule.** Slot n is `t0 + n / fps`, t0 = the first frame's host time. "Newest frame with host time ≤ slot
  time" is built with half a slot of jitter tolerance: a frame belongs to the first slot whose time is ≥ its host
  time − ½ slot (exactly half rounds down), so ScreenCaptureKit's jitter around a boundary never pushes a frame into
  the next slot and causes a skip. The first frame is written at once as slot 0 (fast start).
- **When slots are decided.** A frame's arrival decides every slot before its own, so a steady source is written
  one frame behind with no timer. The tick loop (`sleep(until:)` on `HostClock`, one wake per slot) writes slots that
  fell due with no new frame; a slot is due `RecordingSession.defaultTickGrace` = **0.25 s** after its time, and a
  late tick catches up every due slot at once. The grace only gives a late frame time to land in its own slot (a
  0.1 s grace let a ~300 ms test-runner stall show up as idle repeats + skips); it adds no latency to slots with
  frames and nothing to the clip's timing (timestamps are slot numbers).
- **Stats accounting.** Every slot is exactly one of fresh, idle repeat or dropped (tests check the sum). A slot
  that finds the writer input busy is dropped: nothing queues; it is appended later as a repeat of the last
  appended buffer (timestamps only, no extra buffers held), and a fresh frame stays pending for the next slot (if a
  newer one arrives first, the old one counts in `sourceFramesSkipped`). A fresh frame written more than one slot
  after its own slot moves up to that many directly preceding idle repeats to `framesDropped`; one slot late is
  tolerated. A frame still pending at stop counts as skipped. `slotsWritten` is the appended count.
- **Stops.** `stop()` and "window closed" write every slot up to now plus the pending frame; `duration` stops at
  exactly `duration × fps` (frames after it are ignored, not counted as skipped); disk low and write failure stop at
  the slots already decided. Free space is checked at slot 0 and every 5 s of clip time; low is < 2,000,000,000
  bytes; the `at` in the copy is the check's clip time (`Less than 2 GB free. The clip up to 0:05 was saved.`).
  Window closed reports the clip length (`The window closed at 0:31. …`). A probe error is ignored. A source that
  finishes without an error (only fakes do) keeps the recording going with idle repeats until stop or duration.
  Before finishing, owed repeats are flushed (waiting up to 2 s per wait for the input). No frame at all: no
  `clip.mp4`, duration 0. `start` creates the writer before starting the source, so an unwritable folder never
  starts capture; a failed start removes the clip folder if it is still empty.
- **`RecordingResult`.** Fields per the spec, with `origin: RecordingOrigin` (`startedBy` + MCP `client`, 01's type;
  `startedBy` is a computed shortcut), `stopReason: StopReason` (`stopped`, `duration`, `windowClosed(at:)`,
  `diskLow(at:)`, `writeFailed`, `sourceFailed(SkreenrekError)`, `discarded`, each with a `code`), `error` (the
  `recording_failed` copy, or e.g. `permission_denied` if the source failed with it), `firstFrameHostTime` and
  `clipURL`. Not `Codable`: 05 shapes the JSON. `discard()` cancels the writer, deletes the folder and ends with
  `.discarded`.
- **Tick hook for 04.** `RecordingSession(onSlot:)` gets a `SlotTick` (`index`, slot `hostTime`,
  `firstFrameHostTime`) once per slot, in order, including catch-up slots. For 04's `EventRecorder`:
  `if tick.index == 0 { recorder.firstFrame(hostTime: tick.firstFrameHostTime) }; recorder.sample(hostTime: tick.hostTime)`.
- **`ClipWriter`.** `.mp4`, `shouldOptimizeForNetworkUse = false`, PTS `CMTime(value: n, timescale: fps)`,
  `endSession` at `slots / fps` (every sample lasts exactly 1/fps). H.264 High (`AVVideoProfileLevelH264HighAutoLevel`)
  or HEVC Main; `AVVideoAverageBitRateKey` from the 0.08 rule (pure `ClipWriterSettings.averageBitRate`);
  `MaxKeyFrameInterval` 2 × fps and `MaxKeyFrameIntervalDuration` 2 s; Rec. 709 colour properties;
  `AVVideoExpectedSourceFrameRateKey`; frame reordering off (no B-frames: lower latency, faster finalize).
  `.requireHardware` sets `RequireHardwareAcceleratedVideoEncoder`; if `canApply` or `startWriting` fails it logs
  (`os.Logger`, subsystem `com.raphaelterrier.skreenrek`) and restarts with software. `.software` sets
  `EnableHardwareAcceleratedVideoEncoder = false`. The adaptor has no source attributes (with them it allocates a
  buffer pool we never use; it moved the software encoder's lazy first-frame setup into `init`, no net gain). The
  forced-fallback path isn't unit-tested: CI can't be made to refuse the hardware request (`ClipWriterTests` prints
  which encoder `.requireHardware` got; it was hardware here).
- **Offline writer for tests.** `RecordingSession(realTimeWriter: false)` makes `ClipWriter.isReady` wait for the
  encoder (key-value observed), so deterministic MP4 tests get every frame even when synthetic frames arrive faster
  than the VM encodes. The app uses the default real-time mode (`expectsMediaDataInRealTime`, never blocks).
- **`HostTimeClock`** (`CMClockGetHostTimeClock()`, the base ScreenCaptureKit stamps frames with; sleeps on the
  suspending clock and re-checks) lives in Core, not System: it is pure time, and the `Perf…` suites in
  `SkreenrekCoreTests` need the real clock.
- **`SCStreamFrameSource`.** As specified (filters, size, `minimumFrameInterval`, cursor, `420v`, `queueDepth` 6, no
  audio), plus `colorMatrix` = ITU-R 709 to match the writer's tags. Region `sourceRect` = px ÷ the filter's
  `pointPixelScale`. Frames go through `FrameStreamFeed` (Core): an `AsyncThrowingStream` with
  `.bufferingNewest(1)`, so a lagging recorder never piles up ScreenCaptureKit's IOSurfaces (at most one waiting in
  the stream plus the scheduler's two), and every frame it drops is counted. `FrameSource.droppedFrameCount`
  (defaults to 0, so the fakes are unchanged) exposes that count; the session adds it to `sourceFramesSkipped`, so
  a lossy recording is never reported clean. `SourceFloodTests` floods 50 frames from a pool with an allocation
  limit while the recorder's consumer is held: the pool never runs dry, and 49 drops become 49 skipped. A stream that
  stops on its own (`didStopWithError` or a `.stopped` frame status) ends with "window closed" only when the window
  is really gone (`windowExists`, a `CGWindowListCopyWindowInfo` check by ID, which needs no permission); otherwise
  it ends with `recording_failed` (`Screen capture stopped: <reason>`). A 0.5 s check of the same kind also ends the
  stream when the window disappears. `userDeclined`/`missingEntitlements` map to `permission_denied` (Screen
  Recording). The decision is the pure `SCStreamFrameSource.endError(stoppedWith:windowID:windowExists:)`, covered
  by `StreamEndTests`. `SCStreamFrameSource.screenRecordingAllowed` wraps the non-prompting
  preflight so tests never name the API. Not run here (needs the permission).
- **Output folder.** Slugs fold accents and full-width forms, turn every other run into one `-`, trim, cap at 40.
  A name that slugifies to nothing falls back to the app slug; an app name with no ASCII letters or digits gives
  `window`. Date parts come from a Gregorian calendar in the given time zone (no locale-dependent formatter).
- **Tests.** `CFRSchedulerTests`, `StatsAccountingTests` (pure), `RecorderVideoTests` (real MP4s: 60 and 30 fps with
  a 300 ms gap → 120 / 60 samples of exactly 1/fps showing the repeated frame; three sizes; 1.5 s → 90 frames;
  window closed; disk low; HEVC when available), `RecordingSessionTests`, `ZeroCopyTests`, `OutputFolderTests`,
  `ClipWriterTests`, `RecorderGuardrailTests` (the `rg` guard as a test), `PerfStartTests`, `PerfSustainTests`,
  `PerfFinalizeTests`, and the opt-in `LiveRecordTests`. Suites that encode or measure time are nested in one
  `.serialized` `RecorderSuites` so they don't starve each other on the VM. `PerfStartTests` does one uncounted
  warm-up run (it loads the encoder; 300–1000 ms cold) before the 5 measured runs.
- **Measured here** (Apple silicon, Xcode 26.2, under heavy load from parallel lanes): start to first frame median
  7–55 ms (171 ms once at load average ~220), sustain 60/30 fps clean, finalize 10 s 1280 × 800 in 67–700 ms.
  The macos-15 CI run is the check for the runner's toolchain.
