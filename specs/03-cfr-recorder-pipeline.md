# 03: Constant-frame-rate recorder pipeline and ScreenCaptureKit frame source

Status: Ready · Branch: – · Depends on: 01 (scaffold) · Estimate: 5–7 h agent run + 0 h Raph review (no hand test) · Risk: high
Source: Designer's spec (Notion "Agent capture tool — design spec v1 (2026-11-17)", 2026-11-17), from CPO's brief (Notion "Fraime — Agent-controlled capture — brief — 2026-11-17"). Plan: Fraime Lead's "Skreenrek v1 implementation plan (2026-11-17)".

## Goal

Turn a stream of captured frames into a smooth H.264 MP4 at exactly 30 or 60 fps at native resolution, with no time
or size cap, written into one folder per clip, and stop cleanly on stop, duration, window close, low disk or a write
failure. Risk is high because the real frame source is ScreenCaptureKit (Screen Recording permission).

## Behaviour

1. `CFRScheduler` (Core, pure): slot n has time `t0 + n / fps`, where t0 is the host time of the first frame. Each slot
   takes the newest frame whose host time is ≤ the slot time; when no new frame arrived, it repeats the previous one.
   Frames that arrive late for a slot already written are dropped, never written out of order. It holds at most one
   pending frame (memory stays flat for any length).
2. `ClipWriter` (Core): `AVAssetWriter` to `clip.mp4` (`.mp4`, `shouldOptimizeForNetworkUse = true`), one video input
   through a BGRA pixel-buffer adaptor, presentation time exactly `CMTime(value: n, timescale: fps)`.
   H.264 High profile by default, HEVC when `codec == .hevc`. Average bit rate `width × height × fps × 0.08` bits/s,
   clamped to 4–80 Mbit/s. Keyframe at least every 2 s. Rec. 709 colour properties. Output size = the target's
   native pixel size (window px from 02, or the region px).
3. `RecordingSession` (Core) ties `FrameSource`, `CFRScheduler`, `ClipWriter`, `HostClock` and `DiskSpaceProbe`:
   - `start(target, options, folder)` starts the source and a tick loop that writes one slot per `1 / fps` of
     `HostClock` time (`sleep(until:)`), so idle windows still produce every frame.
   - Stops on: `stop()`; `options.duration` reached (the clip is exactly `duration × fps` frames); the source ending
     with "window closed"; free space below 2 GB (checked every 5 s of clip time); a writer error.
   - Every stop finalizes a playable partial or full clip and returns a `RecordingResult` (id, duration = frames /
     fps, fps, width, height, codec, startedAt, startedBy, folder, `complete`, stop reason).
     Window closed, disk low and write failure surface as `recording_failed` (exit 7) with the design spec's copy:
     `The window closed at 0:31. The clip up to that point was saved.`,
     `Less than 2 GB free. The clip up to 4:12 was saved.`, `The output folder isn't writable.`
   - `discard()` stops and deletes the clip folder.
   - A frame whose pixel size differs from the output size is skipped (the previous frame repeats).
   - A tick hook lets 04 sample the cursor once per slot and read the first frame's host time.
4. `OutputFolder` (Core, pure + FileManager): `~/Movies/Skreenrek/` by default (`outDir` overrides), created if
   missing. Folder name `YYYY-MM-DD_HHMMSS_<slug>` in local time; the slug is the app name lowercased, ASCII
   `[a-z0-9-]`, at most 40 characters, `region` for regions; `name` overrides the slug (slugified). A collision in the
   same second adds `-2`, `-3`, …. An unwritable folder fails before recording starts with `recording_failed`
   (`The output folder isn't writable.`).
5. `SCStreamFrameSource` (`SkreenrekSystem`, thin): window targets use `SCContentFilter(desktopIndependentWindow:)`;
   regions use `SCContentFilter(display:excludingApplications: [Skreenrek])` plus `sourceRect`. Configuration: width
   and height = output px, `minimumFrameInterval` = 1 / fps, `showsCursor` = options.cursor, BGRA, `queueDepth` 6, no
   audio. Only `.complete` frames are delivered. The stream stopping because the window went away ends the stream
   with "window closed". A permission failure maps to `permission_denied` (Screen Recording).
6. `LiveRecordTests` (opt-in, `SKREENREK_LIVE=1` and Screen Recording already granted): records a test-owned window for
   2 s at 60 fps and checks 120 frames. Skipped otherwise.

## Defaults

- 60 fps when no fps is given; H.264.
- `t0` is the first frame's host time, so clip time and events time share one zero (used by 04).
- Encoding runs off the main actor; nothing in the pipeline touches the main thread.

## Guardrails

- No time or size cap anywhere.
- Never block the capture callback on encoding; if the writer input isn't ready, the slot repeats rather than queues.
- Partial clips are always finalized; a crash path must not leave a zero-byte `clip.mp4` when frames were written.
- Tests use `SyntheticFrameSource` and `ManualClock`; no real capture, no permission, no sleeps.

## Out of scope

events.json and the HyperFrames snippet (04), the controller and state machine (05), HUD exclusion UI (10).

## Open question (built with the default)

- Bit-rate formula: the 0.08 bits-per-pixel-per-frame rule above (pattern borrowed from Fraime's recorder, rewritten).

## How to test (Raph)

1. No hand test is needed to merge: CI `factory check` must be green. The tests write real MP4s from synthetic frames
   and check them with `AVAssetReader`: 2 s at 60 fps with a 300 ms gap in source frames → exactly 120 samples, each
   1/60 s, frame content shows the repeated frame during the gap; the same at 30 fps → 60 samples; 1280 × 800,
   1920 × 1080 and 1080 × 1920 sizes; `duration` 1.5 s → 90 frames at 60 fps; window closed at 0.5 s → playable partial
   clip, `complete: false`, exit 7 copy; disk below 2 GB → stop with the disk copy; discard deletes the folder; folder
   naming, slug and `-2` collision with a fixed clock and time zone; an unwritable folder fails before start; an HEVC
   clip when the runner has an HEVC encoder (skipped, not failed, when it hasn't).
2. Optional smoke (needs Screen Recording for the test runner, about 2 min): `SKREENREK_LIVE=1 swift test --filter Live`.

## Implementation notes

_(filled in by the agent)_
