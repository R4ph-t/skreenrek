# 12: Output format and compression

Status: Done · Branch: lane/12-output-format-and-compression · Depends on: 03 (recorder), 04 (events), 06 (CLI), 07 (MCP) · Estimate: 4–6 h agent run + 0 h Raph review (no hand test)
Source: Designer's "Output format and compression (design addition, 2026-11-17)" in `docs/design-spec.md`, from Raph's call that agents should be able to pick output format and compression. Earlier design and plan: Designer's spec v1 and Fraime Lead's "Skreenrek v1 implementation plan (2026-11-17)".

## Goal

Agents can pick the container, codec and compression of a recording through the CLI and MCP, while today's
defaults stay identical: H.264 in `clip.mp4` at the `high` quality preset, and the same human success line. The
engine writes through AVAssetWriter (hardware H.264 / HEVC, ProRes 422 flavours via `AVVideoCodecType`), validates
the combination before any resize or recording starts, and reports what was actually written, read back from the
file. There are no new menu-bar or Settings controls; the Last Clip detail-line change is noted in spec 08 so this
lane is not blocked on the menu-bar work.

## Behaviour

1. **Output settings** (Core). Extend the domain types from 01:
   - `VideoContainer`: `mp4` | `mov` (default `mp4`).
   - `VideoCodec`: add `prores` to the existing `h264` | `hevc`.
   - `QualityPreset`: `low` | `medium` | `high` | `max` (default `high`).
   - `OutputSettings`: the resolved combination (`container`, `codec`, `profile`, `quality` or `nil`,
     `requestedBitrateMbps` or `nil`, and the target bitrate in bits/s when the codec takes one). Built by a pure
     `OutputSettings.resolve(container:codec:quality:bitrateMbps:)` that throws `SkreenrekError.usage` with the
     design addition's exact message and hint. `RecordingOptions` gains `container`, `quality` and `bitrateMbps`
     (and `codec` already exists). Passing both `quality` and `bitrateMbps` is a usage error; passing neither
     resolves to `quality: high`. Values are case-insensitive on the way in and canonicalised to the lowercase
     spellings above.
   - H.264 / HEVC profile is `high` / `main`. ProRes 422 flavour comes from `--quality`: `low` = Proxy
     (`AVVideoCodecType.proRes422Proxy`, profile `proxy`), `medium` = LT (`.proRes422LT`, `lt`), `high` = 422
     (`.proRes422`, `422`), `max` = 422 HQ (`.proRes422HQ`, `422hq`). Never call `max` lossless.
2. **Bitrate for H.264 and HEVC.** With `--bitrate`, the writer targets that average bitrate (Mbps, 1–200 inclusive,
   decimals allowed) and `quality` is `null`. With `--quality`, the engine picks a bitrate that scales with
   width × height × fps, so a given preset looks the same at any size. `high` is today's formula from 03, so
   default recordings do not change: `width × height × fps × 0.08` bits/s, clamped to 4–80 Mbit/s. The other
   presets are the same formula with a coefficient and clamp relative to `high` (open question below). Keyframe
   at least every 2 s and Rec. 709 colour properties stay as in 03. ProRes does not take a bitrate; its quality
   is the flavour in (1).
3. **`ClipWriter` / `RecordingSession` (03).** The writer takes `OutputSettings` and:
   - Uses `AVAssetWriter` file type `.mp4` or `.mov`, output URL `clip.mp4` or `clip.mov`,
     `shouldOptimizeForNetworkUse = false`. Hardware H.264 / HEVC (and ProRes when the machine has it) through
     03's `EncoderPolicy`; tests on CI use `.software`. The same zero-copy `420v` path and constant-frame-rate
     timestamps as 03. Codec types: `AVVideoCodecType.h264`, `.hevc`, or the ProRes 422 type from (1).
   - After `finishWriting`, builds a `VideoReadback` by inspecting the written file, not the request:
     `container` from the file itself (`ftyp` brand or the asset's file type: MPEG-4 vs QuickTime), `codec` and
     `profile` from the video track's format descriptions (`CMFormatDescriptionGetMediaSubType` and the
     codec's profile-level extensions; ProRes fourccs map to `proxy` / `lt` / `422` / `422hq`), `file` is the
     real file name, `bitrateMbps` is `fileSizeBytes × 8 ÷ durationSeconds`, rounded to one decimal place, or
     `null` before stop. Width, height and scale stay as today. The session result carries this object;
     `RecordingResult.codec` remains a plain string equal to `video.codec`.
4. **Validation timing.** `OutputSettings.resolve` runs in the controller `start` path (and the CLI / MCP
   parsers may call it first) *before* any resize or `RecordingSession.start`. A usage error leaves the window
   untouched and writes no folder. The seven CLI copies are word for word from the design addition (including
   the two spaces after `hint:` and the passed value in `You passed 500.`). MCP uses the same `message` and
   `code: "usage"`, with hints that name parameters instead of flags. Exact MCP hints:

   ```
   Add format: "mov", or use codec: "h264" or codec: "hevc".
   Pass a bitrateMbps from 1 to 200, or use quality: "high".
   Drop one. bitrateMbps sets an exact target; quality picks one for the window size.
   Replace bitrateMbps with quality: "low", "medium", "high" or "max".
   Use codec: "h264", "hevc" or "prores".
   Use format: "mp4" or "mov".
   Use quality: "low", "medium", "high" or "max", or set bitrateMbps in Mbps.
   ```

5. **events.json and the snippet (04).** The `recording.video` object gains `container`, `profile`, `quality`,
   `requestedBitrateMbps` and `bitrateMbps` alongside the existing `file`, `width`, `height`, `scale`, `codec`.
   `file` is `clip.mp4` or `clip.mov`. `SnippetBuilder` and the `assetsDir` copy use that same extension
   (`assets/<clip-id>.mov` when the clip is a MOV). Schema stays `skreenrek.events/1`.
6. **Controller, CLI and MCP (05–07).** `record.start` params add `format?`, `codec?` (now including `prores`),
   `quality?`, `bitrateMbps?` (MCP field names, already the wire names in 05). Start / `record --json` (without
   `--wait`) gain `video: { container, codec, profile, quality, requestedBitrateMbps }` as resolved at start;
   `bitrateMbps` is `null` there (the file is not finished). `stop --json`, `record.wait`,
   `skreenrek_stop_recording` and `last` put the full post-stop `video` object inside `recording`, and keep
   `recording.codec` as a plain string equal to `video.codec`. `files.clip` points at the real file.
   - CLI `record` flags: `--format mp4|mov`, `--codec h264|hevc|prores`, `--quality low|medium|high|max`,
     `--bitrate` (Mbps, decimals allowed). `--codec` already exists in 06; this spec only adds `prores` and the
     three new flags.
   - Human success line stays `✓ Saved 0:42 · 1280 × 800 px · 60 fps` when the resolved settings are the
     defaults (mp4, h264, quality high, no bitrate), even if those flags were passed explicitly. Otherwise it
     appends ` · {Codec} {CONTAINER} · {bitrate} Mbps`, where Codec is `H.264`, `HEVC` or `ProRes`, CONTAINER
     is `MP4` or `MOV`, and bitrate is the actual `bitrateMbps` with one decimal place (e.g.
     `✓ Saved 0:42 · 1280 × 800 px · 60 fps · HEVC MOV · 9.8 Mbps`).
   - When the codec is `prores`, one extra human line immediately after `✓ Saved …`:
     `note:  ProRes doesn't play in Chrome or Firefox. Use --codec h264 for web pages.`
     `--json` and `--quiet` do not print it. (This is separate from 06's indented `note    dropped frames · …`
     line.)
   - `tools/list` for `skreenrek_start_recording` includes the new properties; update the golden.
7. **Last Clip row (08, not in this lane).** Copy is in the design addition: default H.264 MP4 clips keep
   `0:42 · 1280 × 800 px · 60 fps · 10:24`; any other container or codec appends the format, e.g.
   `0:42 · 1280 × 800 px · 60 fps · ProRes MOV · 10:24`. Spec 08 owns that one-line `MenuModel` change (a note
   is in that spec). If 08 is already `Done` when this lane starts and the suffix is missing, add it here.

## Performance acceptance

Enforced by `make check` (`swift test`, no permissions, hosted macos-15 VM). `ffprobe` is not on the runner;
every automated check uses AVFoundation (`AVURLAsset`, `AVAssetReader`, format descriptions), the same seam as
01's `EncoderCanaryTests` and 03's clip tests. Treat the design addition's `ffprobe` criterion as an optional
hand check (or skip it when `ffprobe` is absent). Each test prints its measured values.

- `OutputSettingsTests` (pure, no writer): each of the seven usage errors throws with the exact CLI message and
  hint (and the MCP hint variant); bitrate `500`, `0.5`, `0` and `200.1` fail, `1` and `200` and `7.5` pass;
  `prores` + `mp4` fails; `prores` + `--bitrate` fails; quality and bitrate together fail; unknown
  `av1` / `webm` / `ultra` fail; a default resolve is mp4, h264, quality high, H.264 High profile, and the
  03 bitrate formula.
- `ClipFormatTests`: short synthetic clips (about 2 s, `SyntheticFrameSource`, software encoder, ManualClock)
  for each combination h264/hevc × mp4/mov and prores × mov. For each, the written file's container, codec and
  profile match the `VideoReadback`; sample count and per-sample duration match 03's constant-frame-rate check;
  `file` and `files.clip` use the real name; `bitrateMbps` equals `size × 8 ÷ duration` rounded to 0.1. A combo
  the runner cannot encode is skipped, not failed (same rule as 03's HEVC clip). One case writes a non-default
  request and asserts container/codec/profile came from the asset, not from echoing the request.
- `BitrateTargetTests`: 5 s at 30 fps, 1280 × 800, software encoder, `--bitrate 8`, with *synthetic motion*
  frames (a pattern that changes every frame — not the still luma-index buffers; extend `SyntheticFrameSource`
  or add a motion helper in `SkreenrekTesting`). Prints measured `bitrateMbps`. CI budget is ±30% of 8 (a loose
  multiple of the design's ±15%, because the clip is short and the VM encoder is software). Optional hand
  check: 60 s with motion, ±15%, and `ffprobe` if present.
- `DefaultOutputUnchangedTests`: a recording with no new flags writes `clip.mp4`, H.264 High, quality `high`,
  and the human success line is byte-for-byte `✓ Saved 0:42 · 1280 × 800 px · 60 fps` (drive the formatter with
  a fixture of that duration/size/fps). Start-to-stop JSON keeps `recording.codec` as the string `"h264"`.
- `FormatUsageGuardTests`: triggering each usage error through the controller (and CLI once 06's in-process
  tests exist) exits 2 and never calls the resizer or starts a session.
- `ProResNoteTests`: human stop output for a ProRes clip includes the exact `note:` line after `✓ Saved …`;
  `--json` and `--quiet` do not.

## Defaults

- H.264 in MP4 at `high` quality, `clip.mp4`, and the existing success line, when no new flags (or only default
  values) are passed.
- 03's encoder policy, zero-copy path, keyframe interval, colour properties and `shouldOptimizeForNetworkUse =
  false` are unchanged.
- Flag and parameter names, error copy and JSON keys are taken verbatim from the design addition.

## Guardrails

- No resize and no `RecordingSession.start` on a usage error.
- Defaults are byte-for-byte unchanged in human output; new JSON keys are additive and `recording.codec` stays a
  string.
- Tests never need a permission and never call `ffprobe`. Time comes from `ManualClock` except the short real-clock
  bitrate test, which prints what it measured.
- Don't call the `max` preset lossless in any string the app, CLI or MCP shows.
- No new Settings rows or dropdown controls in this lane.

## Out of scope

The Last Clip detail line (08; see the note in that spec), the `record-window` skill wording (09), ffmpeg or any
other post-processor, WebM, AV1, GIF, and a quality or format control in the menu bar.

## Open question (built with the default)

- Quality-preset coefficients, since the design addition doesn't give them. `high` stays 03's
  `width × height × fps × 0.08` bits/s, clamped 4–80 Mbit/s. The others are the same rule times a coefficient:
  `low` = 0.25× (`0.02`, clamp 1–20), `medium` = 0.5× (`0.04`, clamp 2–40), `max` = 2× (`0.16`, clamp 8–160).

## How to test (Raph)

1. No hand test is needed to merge: CI `factory check` must be green, including the suites above.
2. Optional (needs `ffprobe` and, for a real window, Screen Recording; about 2 min once 06 and 11 have landed):
   record each combination (h264/hevc × mp4/mov, prores × mov) and check that `ffprobe` reports the same codec
   and container as the read-back, with `r_frame_rate == avg_frame_rate` and the expected `nb_frames` (03's
   criterion 2). A 60 s motion recording with `--bitrate 8` should read back within ±15% of 8. A default
   `skreenrek record … --wait` still prints `✓ Saved … · 60 fps` with no format suffix and writes `clip.mp4`.

## Implementation notes

- The open preset question uses the stated defaults: low/medium/high/max multiply the 03 formula and its clamps
  by 0.25/0.5/1/2. H.264 High in MP4 at high remains the default; explicit bitrate requests leave quality null.
- CLI, control and MCP validate before resizing or creating a clip folder. Start JSON reports resolved settings
  with a null measured bitrate. Stop/wait/last and events report the completed asset's ftyp container, codec
  configuration profile (or ProRes fourcc), dimensions and measured file-size bitrate, rounded to 0.1 Mbps.
  Snippets and asset copies follow the actual container extension.
- Hardware startup prepares the VideoToolbox session eagerly and retries in software if setup or the first
  append fails, preserving that source buffer and timestamp. Failures after accepted samples still stop the
  recording rather than discarding frames to restart it. Readiness uses KVO and a deadline instead of the 1 ms
  poll. Offline writer waits run on the recording actor's dedicated dispatch executor, outside Swift's
  cooperative pool; recorder completion waits and new integration tests have hard watchdog deadlines.
- The Designer follow-up is included: non-default Last Clip formats replace the clock time. Render fixtures
  cover H.264 MOV and ProRes MOV; model tests also cover HEVC MP4 and the unchanged default clock time.
- Permission-free tests encode H.264/HEVC in both containers and all four ProRes MOV flavours, check CFR samples,
  asset-derived facts even with a deliberately misleading request/extension, extension-correct artifacts,
  exact CLI/MCP errors, default output and the ProRes note. The five-second 1280 × 800, 30 fps software motion
  clip requested 8 Mbps and measured 7.3 Mbps (within the spec's ±30% budget). No app or live capture was run.
