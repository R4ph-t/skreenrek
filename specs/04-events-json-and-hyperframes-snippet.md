# 04: events.json and the HyperFrames snippet

Status: Done · Branch: lane/04-events-json-and-hyperframes-snippet · Depends on: 01 (scaffold) · Estimate: 3–4 h agent run + 0 h Raph review (no hand test)
Source: Designer's spec (Notion "Agent capture tool — design spec v1 (2026-11-17)", 2026-11-17), from CPO's brief (Notion "Fraime — Agent-controlled capture — brief — 2026-11-17"). Plan: Fraime Lead's "Skreenrek v1 implementation plan (2026-11-17)".

## Goal

Every clip folder gets `events.json` (cursor samples, mouse downs and ups with the button, derived clicks; no
keystrokes) in video pixel coordinates on the clip's time base, and `hyperframes.html`, a paste-ready HyperFrames clip
element.

## Behaviour

1. `EventRecorder` (Core) takes a `MouseEventSource`, the capture target (window frame in pt or region in px), the
   display scale, fps and the first frame's host time:
   - Records `down` and `up` events with `button` (`left` for index 0, `right` 1, `middle` 2, `other` above) and
     `clickCount`.
   - Samples `cursorLocation()` once per written slot (the tick hook from 03), so cursor samples run at the clip fps.
   - Converts top-left global pt to video px: `x = (gx − frame.x) × scale`, `y = (gy − frame.y) × scale` for windows,
     relative to the region origin for regions. Points outside the video keep their real (possibly negative or
     oversized) values. Rounded to whole px.
   - `t` = host time − first frame host time, in seconds, rounded to 3 decimals; events before the first frame are
     dropped.
2. `EventsFile` (Core): `Codable` with exactly the design spec's schema `skreenrek.events/1` (schema, complete,
   recording{id, startedAt (ISO 8601 with offset, local time), duration, fps, video{file, width, height, scale, codec},
   source{kind, app, bundleId, title, windowId, frame} or source{kind: "region", displayId, rect}, startedBy, client,
   stats}, where `stats` is 03's `RecordingStats` (an addition to the design spec's shape, so drops are countable from
   the file),
   coordinates{unit "px", origin "top-left", space "video"}, cursor{sampleRate, samples as `[t, x, y]`}, events,
   clicks). `clicks` is derived from the `down` events with `xPct`/`yPct` = x / width × 100 and y / height × 100,
   rounded to 1 decimal. Written atomically (temp file, then rename) when the recording stops, with `complete` from the
   recording result, after the clip is finalized so `stopToFinalizedMs` is known. Not written with `events: false`
   (the stats still reach `stop --json`).
3. `SnippetBuilder` (Core, pure) writes `hyperframes.html` in the clip folder and returns the same text:
   ```html
   <!-- Skreenrek · Safari — localhost:3000 · 1280×800 px · 60 fps · 42.0 s · clicks: events.json -->
   <video class="clip" src="assets/2026-11-17_104207_safari.mp4"
          data-start="0" data-duration="42.0" data-track-index="0" muted playsinline></video>
   ```
   - Duration with one decimal. Without events the `· clicks: events.json` part is left out. Regions read
     `Region 1280×800 px` in place of `App — Title`. `--` and `>` in titles are replaced so the comment stays valid.
   - With `assetsDir`: copies `clip.mp4` to `<assetsDir>/<clip-id>.mp4` (creating the folder) and writes nothing else.
   - Without it: a second comment line with the copy command, using `~` for the home folder so the snippet never holds
     a user name: `<!-- Copy the clip first: cp ~/Movies/Skreenrek/<clip-id>/clip.mp4 assets/<clip-id>.mp4 -->`.
4. `NSEventMouseSource` (`SkreenrekSystem`, thin): global and local `NSEvent` monitors for left/right/other mouse down
   and up; `cursorLocation()` from `NSEvent.mouseLocation` converted with `ScreenGeometry`. It never asks for a
   permission; if no events arrive, the file is still written with empty `events` and `clicks`.

## Defaults

- Cursor samples are `[t, x, y]` arrays, at the clip fps.
- No scroll, no keys, no window titles beyond the source.

## Guardrails

- The JSON contains no keystroke field of any kind (a test walks every key and fails on `key`, `keyCode`,
  `characters`, `modifiers`).
- The snippet never contains an absolute path or a user name.
- Pure logic stays in Core; tests use `FakeMouseEventSource` and `ManualClock`.

## Out of scope

Keyboard or scroll events, HyperFrames components beyond the single clip element, wiring into the controller (05).

## Open question (built with the default)

- The design spec asks for "the exact `cp` command" but also "never absolute paths from someone's Mac": the copy
  command uses `~/…` (see 3).

## How to test (Raph)

1. No hand test is needed to merge: CI `factory check` must be green. The tests cover golden `events.json` and
   `hyperframes.html` files; 1× and 2× conversions, a window not at the origin, a second display at negative x, points
   outside the video; t alignment to the first frame; `clicks` percentages; right and middle buttons; `events: false`;
   `assetsDir` copy; comment escaping; region wording; the keystroke-field guard; `recording.stats` present with every
   field of `RecordingStats`.
2. Optional: none needed.

## Implementation notes

Built on `lane/04-events-json-and-hyperframes-snippet`. New code is in `Sources/SkreenrekCore/Events/` and
`Sources/SkreenrekSystem/NSEventMouseSource.swift`; tests are `Tests/SkreenrekCoreTests/EventsTests.swift`.

- **Interfaces for 03 and 05.** 03's tick hook and `RecordingResult` aren't on main yet, so 04 exposes its own small
  surface and doesn't define either:
  - `EventRecorder(source:target:display:fps:)`: `start()` before the first frame, `firstFrame(hostTime:)` once,
    `sample(hostTime:)` once per written slot (pass the slot's host time, so a catch-up tick still gets one sample per
    slot), then `stop() -> EventLog`. Events and samples are kept raw and converted at stop, so anything before the
    first frame is dropped even if it arrived before `firstFrame` was called. No first frame gives an empty log.
  - `EventsFile.Recording` is the `recording` block (`id`, `startedAt` string, `duration`, `fps`, `video`, `source`,
    `startedBy`, `client`, `stats`). 05 maps 03's `RecordingResult` onto it; `EventsFile.timestamp(_:timeZone:)` gives
    the `startedAt` string (`2026-11-17T10:42:07.120+01:00`, always a numeric offset, never `Z`).
  - `ClipArtifacts.write(recording:complete:log:events:assetsDir:clipFolder:)` is the stop-time call: it writes
    `events.json` (skipped with `events: false`) and then `hyperframes.html`, and returns the URLs and snippet text for
    `stop --json`. Call it after the clip is finalized so `stats.stopToFinalizedMs` is set.
- **Coordinates.** `VideoMapping` does the pt → px conversion. Regions map from their display's frame origin, then
  subtract the region's pixel origin. `x`/`y` round half away from zero.
- **JSON.** Encoded with the shared `SkreenrekJSON` settings (sorted keys, so key order differs from the design
  spec's example; the shape is the same), plus a trailing newline. `client` and `bundleId` are always present and
  are `null` when missing. Whole-number doubles encode without `.0` (`"duration":42`, `"xPct":50`), which is how
  `JSONEncoder` writes them. `stats` uses `RecordingStats`' own `Codable`, so a field that is nil (e.g.
  `startToFirstFrameMs` when no frame arrived) is left out; it is always set for a finalized clip with frames.
  Atomic write is `Data.write(options: .atomic)` (temp file, then rename).
- **Snippet.** `SnippetBuilder.text(_:copy:)` is pure; `SnippetBuilder.write` adds the file and the assets copy (an
  older copy of `<clip-id>.mp4` is replaced). A window with an empty title reads just the app name. Comment escaping:
  `--` → `—`, `>` → `›`, and also `<` → `‹` and line breaks → spaces, so the comment stays on one valid line.
  The copy command writes the home folder as `~`. **Open:** if `--out` points outside the home folder, the path can't
  be shortened and is written as-is (it holds no user name, but it is absolute); the default folder and every path
  under home are `~/…`.
- **NSEventMouseSource.** Takes the `HostClock` and stamps events with `clock.now()` so they share the recorder's
  time base (instead of `NSEvent.timestamp`, whose base 03's clock may not match). `ScreenGeometry` comes from 02,
  which runs in parallel, so the single-point flip lives in `CursorGeometry.topLeft(fromAppKit:primaryDisplayHeight:)`
  with the primary height from `CGDisplayBounds(CGMainDisplayID())`. Follow-up once 02 is merged: switch to
  `ScreenGeometry` if it covers points. It is not exercised by `swift test` (no live suite: it needs no permission,
  but a global monitor needs a running app and real input).
- `make check`: green, 83 tests, no warnings.
