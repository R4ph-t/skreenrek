# 03: Constant-frame-rate recorder pipeline and ScreenCaptureKit frame source

Status: Ready · Branch: – · Depends on: 01 (scaffold) · Estimate: 6–8 h agent run + 0 h Raph review (no hand test) · Risk: high
Source: Designer's spec (Notion "Agent capture tool — design spec v1 (2026-11-17)", 2026-11-17), from CPO's brief (Notion "Fraime — Agent-controlled capture — brief — 2026-11-17"). Plan: Fraime Lead's "Skreenrek v1 implementation plan (2026-11-17)".

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

_(filled in by the agent)_
