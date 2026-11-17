# 01: Swift package scaffold, domain types and test seams

Status: Done · Branch: lane/01-package-scaffold-and-seams · Depends on: – · Estimate: 3–4 h agent run + 0 h Raph review (no hand test)
Source: Designer's spec (Notion "Agent capture tool — design spec v1 (2026-11-17)", 2026-11-17), from CPO's brief (Notion "Fraime — Agent-controlled capture — brief — 2026-11-17"). Plan: Fraime Lead's "Skreenrek v1 implementation plan (2026-11-17)".

## Goal

Create the Swift package every later spec builds on: the domain types, the error and exit-code model, and the seam
protocols that keep every test free of Screen Recording and Accessibility permission. Prove early, on the GitHub
macos-15 runner, the riskiest CI assumption: synthetic frames encode to a real H.264 MP4 through AVAssetWriter.

## Behaviour

1. `Package.swift`: `swift-tools-version:6.0`, `platforms: [.macOS(.v15)]`, Swift 6 language mode, no external
   dependencies yet. Product: executable `skreenrek`. Targets:
   - `SkreenrekCore` (library): imports only Foundation, CoreGraphics, CoreMedia, CoreVideo, AVFoundation.
   - `SkreenrekSystem` (library, depends on Core): one placeholder file; real seam implementations arrive in 02–04.
   - `SkreenrekTesting` (library, depends on Core): fakes. Only test targets depend on it.
   - `skreenrek` (executable, depends on Core and System): `Sources/skreenrek/main.swift`. For now
     `skreenrek --version` prints `skreenrek 0.1.0` and exits 0; anything else prints a one-line usage to stderr and
     exits 2.
   - `SkreenrekCoreTests` (Swift Testing), depending on Core and Testing.
2. Domain types in `Sources/SkreenrekCore/Domain/`, all `Sendable`, `Codable` where they appear in JSON:
   - `PixelSize` (width, height in px), `PointRect` (x, y, width, height in pt, top-left global origin, the
     coordinate space ScreenCaptureKit and Accessibility use), `PixelRect`.
   - `DisplayInfo` (id, name, scale, frame: PointRect, visibleFrame: PointRect).
   - `WindowID` (wraps the CGWindowID `UInt32`), `WindowInfo` (id, app, bundleId, title, pid, frame, displayId,
     onScreen) with a computed `pixelSize` on a given display.
   - `WindowQuery` (`.id(WindowID)` or `.app(name: String, title: String?)`).
   - `CaptureTarget` (`.window(WindowInfo)` or `.region(PixelRect, displayId)`).
   - `Readback` with the exact JSON shape of the design spec's "JSON read-back" block
     (window, display, requested, actual, frame, exact, attempts).
   - `RecordingOptions` (fps 30 or 60, cursor, events, hud, outDir, name, assetsDir, codec h264/hevc,
     duration, allowInexact), `StartedBy` (`cli`, `mcp`, `menu`) plus optional client name.
   - `ControllerState` enum: `idle`, `armed`, `recording`, `writing`, `error` (raw values are the CLI
     `status` words).
   - `EncoderPolicy` (`requireHardware`, `software`) and `RecordingStats` (`slotsWritten`, `framesFresh`,
     `framesRepeatedIdle`, `framesDropped`, `sourceFramesSkipped`, `startToFirstFrameMs`, `stopToFinalizedMs`,
     `encoder` `hardware`/`software`, `pixelFormat`, computed `isClean`), filled in by 03 and reported by 04–06.
3. `SkreenrekError` (Core) with one case per row of the design spec's exit-code table. Each case exposes `exitCode`
   (0–7, 130), `code` (`permission_denied`, `not_exact`, `window_not_found`, `window_ambiguous`, `wrong_state`,
   `recording_failed`, `usage`, `internal`), `message` (one sentence) and `hint` (the exact next command or
   action), and encodes as `{ "error": { "code", "message", "hint", "exit" } }`. Messages and hints for the cases
   the design spec words (Screen Recording off, not exact, ambiguous window) use its copy word for word.
4. Seam protocols in `Sources/SkreenrekCore/Seams/`, all `Sendable`:
   - `WindowCatalog`: `windows() async throws -> [WindowInfo]` (front to back), `displays() async throws -> [DisplayInfo]`.
   - `WindowResizer`: `setFrame(_ frame: PointRect, of: WindowInfo) async throws`,
     `readFrame(of: WindowInfo) async throws -> PointRect`.
   - `FrameSource`: `start(target:size:fps:showsCursor:) async throws -> AsyncThrowingStream<CapturedFrame, Error>`,
     `stop() async`. `CapturedFrame` carries an IOSurface-backed `420v` `CVPixelBuffer` (the source's own buffer, never a copy) and
     a host time in seconds.
   - `MouseEventSource`: start/stop delivering `MouseEvent` (type down/up, button index, clickCount, global
     PointRect-space location, host time) and `cursorLocation() -> CGPoint` (top-left global pt).
   - `HostClock`: `now() -> TimeInterval` (host time seconds) and `sleep(until:) async throws`.
   - `PermissionProbe`: `screenRecording` and `accessibility`, each `.allowed` / `.missing`. Read-only: it never
     prompts.
   - `DiskSpaceProbe`: `freeBytes(at: URL) throws -> Int64`.
5. `SkreenrekTesting` provides: `FakeWindowCatalog`, `FakeWindowResizer` (programmable rules: minimum size,
   size steps, an attempt that is ignored, a maximum size), `SyntheticFrameSource` (IOSurface-backed `420v` buffers, the
   same kind ScreenCaptureKit delivers, whose luma value encodes the frame index; real-time or scripted timestamps; irregular timestamps allowed; can end with an error), `FakeMouseEventSource`,
   `ManualClock` (advances only when told; `sleep(until:)` resumes when the clock reaches the time),
   `FakePermissionProbe`, `FakeDiskSpaceProbe`.
6. Encoder canary test (`EncoderCanaryTests`): 30 synthetic IOSurface-backed `420v` 1280 × 800 frames appended to a real `AVAssetWriter`
   (H.264, `AVAssetWriterInputPixelBufferAdaptor`, presentation time n/30) in a temp folder. The test loads the
   file with `AVURLAsset` and asserts: one video track, natural size 1280 × 800, 30 samples (counted with
   `AVAssetReader`), duration 1.0 s ± 1/30 s, codec H.264. It also prints whether the runner accepts
   `.requireHardware` (informational; the virtual machine is expected to fall back to software).

## Defaults

- Version string 0.1.0 in one place (`SkreenrekVersion.current`).
- JSON encoding: `JSONEncoder` with `.sortedKeys` and `.withoutEscapingSlashes`, so goldens are stable.
- No hardware-encoder requirement anywhere (GitHub's macOS runners are virtual machines).

## Guardrails

- `rg -n "import (ScreenCaptureKit|AppKit|ApplicationServices|SwiftUI)" Sources/SkreenrekCore Sources/SkreenrekTesting`
  prints nothing.
- No test calls a permission API or prompts. `swift test` on a fresh runner shows no system dialog.
- No sleeps in tests; time comes from `ManualClock`.
- No SwiftPM `resources:`.

## Out of scope

Real ScreenCaptureKit, Accessibility or mouse implementations (02–04), the CLI parser (06), any UI (08, 10), the app
bundle and Info.plist (hand spec 11).

## Open question (built with the default)

- Swift Testing versus XCTest: Swift Testing (it ships with the runner's Xcode). Fall back to XCTest only if the
  runner's toolchain can't run it, and say so in Implementation notes.

## How to test (Raph)

1. No hand test is needed to merge: CI `factory check` runs `make check` (config lint, `swift build`, `swift test`)
   on macos-15 and must be green, including `EncoderCanaryTests`.
2. Optional (1 min, no permissions): `swift build && .build/debug/skreenrek --version` prints `skreenrek 0.1.0`.

## Implementation notes

- **Layout.** `Package.swift` (tools 6.0, macOS 15, `swiftLanguageModes: [.v6]`, no dependencies, no `resources:`).
  Domain types in `Sources/SkreenrekCore/Domain/`, seams in `Sources/SkreenrekCore/Seams/`, JSON settings in
  `SkreenrekJSON` (`.sortedKeys`, `.withoutEscapingSlashes`), version in `SkreenrekVersion.current`.
  `SkreenrekSystem` is one placeholder namespace (`SkreenrekSystem.swift`).
- **Swift Testing** throughout (no XCTest fallback needed). 50 tests in 8 suites; no sleeps, time comes from
  `ManualClock`.
- **JSON units.** `PixelSize`/`PixelRect` encode with `"unit": "px"` and `PointRect` with `"unit": "pt"`, so
  `Readback` matches the design spec block exactly; a test decodes that block verbatim and another pins the encoded
  golden. Decoding accepts a missing `unit` and rejects a wrong one. `Readback.window.bundleId` is always present
  (`null` when unknown) so the shape never changes. `WindowID` encodes as a bare number; `DisplayID` is a
  `UInt32` typealias (`CGDirectDisplayID`).
- **Names added beyond the spec's list** (small, needed to type the fields): `FrameRate` (30/60), `VideoCodec`,
  `RecordingOrigin` (`startedBy` + optional `client`), `EncoderKind` (`hardware`/`software`, the stats field),
  `Permission`, `PermissionStatus`, `MouseEventType`, `WindowCandidate`, `NotExactReason`, `WrongStateReason`,
  `RecordingFailure`, `ErrorBody`/`ErrorEnvelope`, and `TimeFormat.minutesSeconds` (`m:ss`).
- **`RecordingStats.isClean`** is `framesDropped == 0 && sourceFramesSkipped == 0`, the definition in spec 03.
- **`SkreenrekError`.** Cases: `internal` (1), `usage` (2), `permissionDenied` (3), `notExact` (4),
  `windowNotFound`/`windowAmbiguous` (5), `wrongState` (6), `recordingFailed` (7), `interrupted` (130). Design-spec
  copy is word for word for Screen Recording off, not exact (min width) and the ambiguous list, and the
  window-closed, disk-low and not-writable sentences reuse the dropdown error table. The `steps` wording follows
  spec 02. Open points built with a default:
  - The design spec lists no code string for exit 130; `interrupted` uses `"interrupted"`.
  - The ambiguous case has no hint in the design spec; the candidate lines are part of `message` (as spec 02 says)
    with columns aligned by padding, and the hint is `Pass one of the IDs above, e.g. skreenrek record <first id>`.
  - Copy the design spec doesn't word (Accessibility off, window not found, wrong state, interrupted, the other
    not-exact directions) follows the same pattern: one sentence, plus a hint naming the next command.
- **`MouseEventSource.start()`** returns an `AsyncStream<MouseEvent>` that finishes on `stop()`; `MouseEvent.button`
  is the raw index (0 left, 1 right, 2 middle, 3+ other), for 04 to name.
- **`FakeWindowResizer`** rules are in points: minimum size, maximum size, size steps (`base + n × step`, rounding
  down, base = minimum size or 0), and ignored attempts (1-based `setFrame` calls per window); per-window rules and
  an injectable failure.
- **`SyntheticFrameSource`** makes buffers from a `CVPixelBufferPool` (IOSurface-backed `420v`). Luma is
  `16 + (index mod 55) × 4` (video range, 4-level gaps so a lossy encode still decodes the index;
  `frameIndex(forLuma:)` and `meanLuma(of:)` read it back). Timing: `.scripted` (all at once, any timestamps),
  `.onClock` (waits on a `HostClock` for each timestamp) and `.realTime` (every `1 / fps` of clock time until
  `count` or `stop()`). It can throw on start, end with an error after the last frame, `fail(with:)` mid-stream, and
  make chosen frames at another size. The stream buffers without limit, so very long `.scripted` runs hold every
  buffer; use `.onClock`/`.realTime` for long runs.
- **`ManualClock`** adds `advance(by:)`/`advance(to:)` (never backwards), `sleeperCount`, `nextDeadline` and
  `waitForSleepers(_:)`, which lets a test wait until a task reaches its sleep without sleeping itself. Cancelling a
  sleeper throws `CancellationError`.
- **`EncoderCanaryTests`** collects 30 frames from `SyntheticFrameSource`, writes them through
  `AVAssetWriterInputPixelBufferAdaptor` (H.264, pts n/30, `endSession` at 30/30), and checks track count, natural
  size, `avc1` codec, duration and the `AVAssetReader` sample count. The hardware probe uses a
  `VTCompressionSession` with `RequireHardwareAcceleratedVideoEncoder` and only prints the result. It printed `true`
  on this Mac and, unexpectedly, also on the GitHub macos-15 runner (first CI run of PR #9). Spec 03 still uses
  `.software` in tests as planned, so CI never depends on it.
- **`GuardrailTests`** enforce the guardrails in `swift test`: no ScreenCaptureKit/AppKit/ApplicationServices/SwiftUI
  import in Core or Testing, no permission API or ScreenCaptureKit import in tests, no `resources:` in the manifest.
- `skreenrek --version` prints `skreenrek 0.1.0` (exit 0); anything else prints `usage: skreenrek --version` to
  stderr (exit 2).
- Only Xcode 26.2 (Swift 6.2.3) was available locally; the macos-15 CI run is the check for the runner's toolchain.
