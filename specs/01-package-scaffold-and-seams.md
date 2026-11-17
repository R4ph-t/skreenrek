# 01: Swift package scaffold, domain types and test seams

Status: Done · Branch: – · Depends on: – · Estimate: 3–4 h agent run + 0 h Raph review (no hand test)
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

- Swift Testing runs on the toolchain; no XCTest fallback needed.
- Exit codes live in `SkreenrekExitCode` (0–7 and 130). `SkreenrekError` has one case per error row (exit 1–7);
  0 (success) and 130 (Ctrl-C during `--wait`, clip saved) aren't errors, so they're exit codes only.
- `not_exact`, `usage`, `wrong_state`, `recording_failed` and `internal` take their message and hint from the caller
  (02, 03, 05 build them from the copy quoted in those specs). `window_ambiguous` builds the 02 copy itself.
- **Not from the design spec (it isn't in the repo):** the Screen Recording and Accessibility messages and hints in
  `ErrorCopy`, the `window_not_found` copy, and the `window`/`display` sub-objects of `Readback` (`{id, app, title}`
  and `{id, scale}`; sizes carry `"unit": "px"`, the frame `"unit": "pt"`). Replace them with the design spec's
  wording and shape.
- `SyntheticFrames` encodes the frame index as luma `16 + 4 × (index mod 55)`, so a decoded H.264 frame still maps
  back to its index; the index wraps every 55 frames.
- `ManualClock.waitForSleepers(_:)` lets a test advance the clock only after the code under test is parked in
  `sleep(until:)`, with no real sleeps.
- On the dev Mac the canary printed `.requireHardware accepted`; on the CI VM it is expected to print not accepted.
