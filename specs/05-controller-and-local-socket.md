# 05: Controller state machine and the local control socket

Status: Done · Branch: lane/05-controller-and-local-socket · Depends on: 02 (resize), 03 (recorder), 04 (events) · Estimate: 4–6 h agent run + 0 h Raph review (no hand test)
Source: Designer's spec (Notion "Agent capture tool — design spec v1 (2026-11-17)", 2026-11-17), from CPO's brief (Notion "Fraime — Agent-controlled capture — brief — 2026-11-17"). Plan: Fraime Lead's "Skreenrek v1 implementation plan (2026-11-17)".

## Goal

One controller in the app process owns all capture state (one recording at a time, no pause), and the CLI and MCP reach
it over a private local Unix socket. The whole flow runs headless against fakes in tests, end to end over a real
socket.

## Behaviour

1. New library target `SkreenrekControl` (depends on Core) and test target `SkreenrekControlTests`.
2. `SkreenrekController` (actor) built from the seams (catalog, resizer, frame source, mouse source, clock,
   permissions, disk, a `WindowPicker` seam) and settings (output folder, default fps, cursor, events, HUD):
   - States: `idle` → `armed` (a picked window, its last read-back) → `recording` → `writing` → `idle` (with
     `lastClip`); `error` holds the last failure and clears on the next action.
   - Operations: `windows(app?)`, `pick(timeout)`, `resize(query, size, allowInexact)`, `start(params, startedBy,
     client?)`, `stop()`, `discard()`, `status()`, `last()`, `doctor()`, `waitForEnd()`.
   - `start`: resolve the window (02) → resize first when a size is given (exit 4 unless `allowInexact`) → Screen
     Recording check (`permission_denied`, exit 3) → output folder (03) → session (03) with `EventRecorder` (04) →
     returns `{ recordingId, startedAt, readback?, fps }`. Starting while recording or writing → `wrong_state` (exit 6,
     `Skreenrek is already recording Safari.` / hint `Run: skreenrek stop`).
   - `stop`: finalizes clip, events and snippet → `{ recording{id, duration, fps, width, height, codec, startedAt,
     startedBy, stats}, files{clip, events, snippet}, snippet, readback }` (the design spec's `stop --json` shape plus
     03's `stats`). Stop or
     discard while idle → `wrong_state` (`Nothing is recording.`).
   - Resize while recording → `wrong_state`. Resize without Accessibility → `permission_denied`
     (`Can't resize windows` copy) and nothing else changes.
   - `doctor`: permissions, version, output folder writable, socket path.
   - `snapshots`: an `AsyncStream<ControllerSnapshot>` (state, elapsed, window, size, fps, startedBy, client, lastClip,
     error) for the UI (08, 10).
3. Wire protocol `skreenrek.control/1`: one JSON object per line, UTF-8, over a stream Unix socket.
   - Request `{"v":1,"id":7,"method":"record.start","params":{…},"client":{"kind":"cli|mcp|menu","name":"Claude Code"}}`.
   - Response `{"v":1,"id":7,"result":{…}}` or `{"v":1,"id":7,"error":{"code","message","hint","exit"}}`.
   - Methods: `hello` (returns `{version, protocol: 1, pid}`), `windows`, `pick`, `resize`, `record.start`,
     `record.stop`, `record.discard`, `record.wait`, `status`, `last`, `doctor`. Params use the MCP field names from the
     design spec (`windowId`, `app`, `title`, `width`, `height`, `allowInexact`, `fps`, `durationSeconds`, `cursor`,
     `events`, `hud`, `outDir`, `assetsDir`, `region`, `displayId`, `name`, `codec`).
   - Unknown method or bad params → `usage` error; malformed JSON → `usage` error and the connection stays usable;
     a different `v` → `internal` error with hint `Quit and reopen Skreenrek so the app and the command match.`
4. `ControlServer`: socket at `~/Library/Application Support/skreenrek/control.sock` (path injectable). Folder mode
   0700, socket 0600. Accepts only peers with the same uid (`getpeereid`). A stale socket file with no listener is
   replaced; a live one means another instance runs, and `start()` fails with `alreadyRunning`. Several clients may
   connect; the actor serializes operations.
5. `ControlClient`: connects with a 2 s timeout, one request at a time per connection, no timeout for `pick`
   (bounded by its own timeout) and `record.wait`.
6. `HeadlessHost`: builds a controller plus server from injected seams. The executable gets a hidden `skreenrek app`
   that runs the headless host with the real seams until the UI arrives in 08.

## Performance acceptance

Enforced by `make check` (no permissions; loose CI budgets, measured values printed):

- `PerfSocketStartTests`: a client sends `record.start` (no resize) over the real socket to a `HeadlessHost` whose
  `SyntheticFrameSource` has a frame ready: median of 5 runs from sending the request to the first frame appended
  ≤ 250 ms; the response arrives before or with that first frame, never blocked on encoding.
- `PerfSocketStopTests`: `record.stop` round trip for a 10 s 1280 × 800 synthetic clip returns ≤ 2 s after the request
  with the clip finalized and `stats.stopToFinalizedMs` filled in.
- A status poll during a recording answers in ≤ 50 ms (median of 20), so polling agents never slow the capture.

Manual targets with a real capture are 03's, measured end to end by `make perf` (06 and hand spec 11).

## Defaults

- Socket path override: `SKREENREK_SOCKET` environment variable (tests and development only).
- `record.wait` returns the same body as `stop` when the recording ends by any means.

## Guardrails

- No capture or resize happens outside the controller.
- The socket never listens on TCP and never accepts another user.
- Tests run the real server on a short temp path (Unix socket paths are limited to 104 bytes) with fakes; no sleeps.

## Out of scope

The CLI parser and output formats (06), MCP (07), UI (08, 10), launching the app from a client (06).

## Open question (built with the default)

- The design spec names the socket's folder but not the protocol: newline-delimited JSON as above.

## How to test (Raph)

1. No hand test is needed to merge: CI `factory check` must be green. The tests run a real socket with fakes:
   `windows` → `record.start` with a size → `record.stop` produces `clip.mp4`, `events.json` and `hyperframes.html` in a
   temp folder with the right shapes; two clients starting at once (exactly one wins, the other gets exit 6); stop
   while idle; not-exact start (exit 4) and `allowInexact`; permission missing (exit 3) for start and resize;
   `record.wait`; discard; malformed JSON; version mismatch; socket file mode 0600; stale socket replaced; snapshot
   stream order idle → recording → writing → idle.
2. Optional: none needed.

## Implementation notes

- **Target.** `SkreenrekControl` (Core only) holds `SkreenrekController` (actor), the wire types and bodies
  (`ControlProtocol`, `ControlBodies`), `ControlRouter` (line in, line out), `ControlServer`, `ControlClient`,
  `HeadlessHost` and `ControlPaths`. The `WindowPicker` seam (`PickResult`) lives in `SkreenrekCore/Seams` with
  `FakeWindowPicker` in `SkreenrekTesting`; until 10 the controller's default picker is `UnavailableWindowPicker`,
  which fails with 06's copy `The window picker isn't available yet.` (`internal`). `SystemPermissionProbe`
  (read-only, never prompts) was added to `SkreenrekSystem`, and `skreenrek app` (hidden) runs the headless host with
  the real seams under an accessory `NSApplication`.
- **Wire.** Newline-delimited JSON as the spec's default. Malformed JSON answers with `id: null`; a missing `v` counts
  as a mismatch (`internal`, the reopen hint). Unknown params keys are ignored, so 12's `format`/`quality`/
  `bitrateMbps` can be added without a protocol bump; wrong types and missing required fields are `usage`
  (`The params for record.start aren't valid: fps has the wrong type.`). Requests without a `client` count as `cli`.
  The `client.name` is kept only for `mcp` (events.json's `client` is null for the CLI and the menu).
- **Bodies.** Optional keys are always present (null), like 02/04. `stop`/`wait`/`last` are exactly the design spec's
  `stop --json` keys plus `recording.stats`; `files.events` is null with events off; `readback` is null when the
  recording didn't resize. `record.wait` returns `{discarded: true}` when the recording was discarded. `pick` returns
  the window entry, `{region, displayId}` for a dragged region, or `{cancelled: true}`. `status` is
  `{state, window, readback, recording{id, elapsed, fps, width, height, startedAt, startedBy, client}, lastClip, error}`;
  `doctor` is `{version, permissions{screenRecording, accessibility}, outputFolder{path, writable}, socket}`.
- **States.** `error` is entered only when a recording ends in a failure (window closed, disk low, write failed); a
  failed `start` or `resize` throws to its caller and leaves the state as it was. The error clears on pick, resize,
  start, stop, discard or `dismissError()` (for 08's "open the menu once"). After a recording the controller is
  `idle`, not armed. A recording failure throws `recording_failed` (exit 7) from `stop`/`wait`; its partial clip is
  `last`. `last` before any clip is a new `wrong_state` reason, `noClip` (`No clip has been saved yet.`). The last clip
  is kept in memory only (not across app restarts). Stopping while the clip is being written waits for the same result;
  discarding then is `wrong_state` (`stillWriting`).
- **Copy.** `WrongStateReason.alreadyRecording` now carries the app: `Skreenrek is already recording Safari.` /
  `Run: skreenrek stop` (also for resize and pick while recording); not recording is `Nothing is recording.`.
- **Start order** is the spec's: resolve → resize (Accessibility checked first, exit 3) → Screen Recording (exit 3,
  after the resize) → output folder → events → recorder. With no window and no region, `start` and `resize` use the
  armed target; nothing armed is `usage`. A region can't take a size, and must lie inside its display (default: the
  first display listed, the main one).
- **Spec 04 follow-ups.** Click times stay `clock.now()` on the main thread (not `NSEvent.timestamp`); the controller
  is an actor off the main thread, and the UI (08) must keep the main actor free while recording. The window frame is
  fixed when recording starts: the event mapping uses the frame read back after the resize, so a window moved
  mid-recording drifts (fine for v1: resize and hold). `CursorGeometry` is gone; `ScreenGeometry.topLeft(fromAppKit:)`
  now flips points too, and `NSEventMouseSource` uses it.
- **Client timeouts.** Connect 2 s; every request other than `pick` and `record.wait` waits up to 30 s for its answer
  (a resize with retries, or finalizing a long clip, can exceed 2 s). Blocking socket I/O runs on dispatch queues, not
  the Swift concurrency pool.
- **Server.** The folder is created 0700 (and tightened to 0700 when this user owns it, never for a shared folder
  like `/tmp`), the socket chmod 0600 right after bind. A path that exists but isn't a socket is refused, not deleted.
  Requests run at user-initiated priority: at default priority, test tasks polling with `Task.yield()` starved the
  server's tasks and hung the suite, so the tests wait on events (`ObservedSink.waitForAppends`,
  `waitForEndWaiters`, the snapshot stream, `FakeWindowPicker.waitForPick`) instead of polling.
- **Perf (measured locally, Apple silicon, software encoder).** Request → first frame median 5 ms (budget 250); the
  response always arrived before the first frame. `record.stop` for 10 s 1280 × 800 at 30 fps: 63 ms round trip
  (budget 2 s). Status poll during recording: median 0.4 ms (budget 50).
