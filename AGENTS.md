# skreenrek

A small standalone macOS agent screen-capture tool: one Swift binary that is a menu-bar app, a CLI, a stdio MCP server, and
an agent skill. It lists windows, resizes one to an exact pixel size through Accessibility and reads the frame back,
records it with ScreenCaptureKit and AVAssetWriter at native resolution (H.264, constant 30 or 60 fps), and writes one
folder per clip with `clip.mp4`, `events.json`, and `hyperframes.html`.

Free and open source (MIT). Unsandboxed. v1 ships ad-hoc signed through a Homebrew build-from-source formula; there is
no Developer ID certificate yet. Written fresh: it shares no code with Fraime.

## Layout

A Swift package at the repo root (`Package.swift`), macOS 15+, Swift 6 language mode. The targets are added by the
specs in `specs/`: `SkreenrekCore` (domain, seams, pure logic, the AVAssetWriter pipeline), `SkreenrekSystem` (thin real
implementations of the seams: ScreenCaptureKit, Accessibility, mouse monitors), `SkreenrekTesting` (fakes, tests only),
`SkreenrekControl` (controller and local socket), `SkreenrekCLI`, `SkreenrekMCP`, `SkreenrekUI` (menu bar, picker, HUD,
onboarding, settings), and the `skreenrek` executable. `make app` (added by hand spec 11) wraps the executable into
`Skreenrek.app` (bundle ID `it.fraime.skreenrek`).

## Architecture and test rules (every spec)

- **The app owns capture.** Only the app process records and resizes, so Screen Recording and Accessibility belong to
  its bundle ID. The CLI and the MCP server are clients of the running app over the local socket.
- **Seams.** Window listing, window resizing, the frame source, the mouse event source, the clock, permission checks,
  disk space, app launching and the window picker are protocols in `SkreenrekCore` (or the target that owns them).
  Real implementations live in `SkreenrekSystem`/`SkreenrekUI` and stay thin: no logic that a fake can't exercise.
- **Tests never need a permission.** `swift test` runs on a GitHub-hosted macos-15 runner with no Screen Recording or
  Accessibility grant. Tests use the fakes in `SkreenrekTesting`, never import ScreenCaptureKit, and never call
  `CGRequestScreenCaptureAccess`, `CGPreflightScreenCaptureAccess` or `AXIsProcessTrustedWithOptions`.
  Video tests push synthetic `CVPixelBuffer`s through the real AVAssetWriter pipeline and check the real `.mp4` with
  `AVAsset`/`AVAssetReader`.
- **Live tests are opt-in.** A test that touches the real system goes in a `Live…Tests` suite that is disabled unless
  `SKREENREK_LIVE=1` and the permission is already granted. It must never prompt.
- Use Swift Testing (`import Testing`, `@Test`). No sleeps in tests: drive time with the manual clock.
- No SwiftPM `resources:` (resource bundles break the app bundle's signature). Embed text as Swift string literals.
- Dependencies: Apple frameworks plus `swift-argument-parser` (pinned with `exact:`). Nothing else without a spec.
- UI copy says Skreenrek; the command, MCP tool prefix (`skreenrek_…`) and Application Support folder say `skreenrek`.
  No "Raph" or "CTO" in any string the app, CLI, MCP or skill shows.

## Rules

- Do not edit signing, entitlements, Info.plist, notarization or release files without Raph's explicit OK.
- Tests that need Screen Recording or Accessibility permission are opt-in live tests (above). The factory does not run
  them, and merging never waits on them.
- `make check` is the factory's gate: an offline lint of `.factory/project.conf`, then `swift build` and `swift test`
  once `Package.swift` exists. CI runs it on macOS 15 (check name: `factory check`). New warnings count as failures in
  review.
- Never commit secrets, keys, team ids or personal paths, and never read `.release.env`, `.env`, key or cert files.

## Factory (Manufacture)

The factory builds specs from `specs/` (index: `specs/README.md`), one `factory/<nn>-<slug>` branch and PR each; its
config is `.factory/project.conf`. Raph merges every PR (`AUTO_MERGE=0`).

- `make check` is the only target the factory runs. After `Package.swift` exists it also builds and tests the package.
  Tests that need Screen Recording or Accessibility stay out of that gate.
- The factory never pushes the paths in `GUARDED_PATHS` (`.factory/`, `.github/`, `scripts/`, `Makefile`, this file,
  `CLAUDE.md`, entitlements, Info.plists, and signing, notarization and release files). `Package.swift` is not guarded:
  specs may edit it, and it is in `.factory/risky-paths.txt`, so those PRs get a close review.
- Never commit secrets, keys, team ids or personal paths, and never read `.release.env`, `.env`, key or cert files.
