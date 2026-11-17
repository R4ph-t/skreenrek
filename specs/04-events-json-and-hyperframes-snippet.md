# 04: events.json and the HyperFrames snippet

Status: Queued (herdr) · Branch: – · Depends on: 01 (scaffold) · Estimate: 3–4 h agent run + 0 h Raph review (no hand test)
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

_(filled in by the agent)_
