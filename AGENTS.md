This file is mirrored as `AGENTS.md` and `CLAUDE.md`; keep both in sync.

# skreenrek

A small standalone macOS agent screen-capture tool: one Swift binary with a CLI, a SwiftUI `MenuBarExtra`, a stdio MCP server, and agent skills. It lists windows, resizes one to exact pixels via Accessibility and reads the frame back, records it with ScreenCaptureKit and AVAssetWriter at native resolution (30 or 60 fps), and writes `clip.mov`, `events.json`, and a HyperFrames snippet.

Free and open source. Signed with Developer ID, unsandboxed. Written fresh: it shares no code with Fraime.

## Layout

A Swift package at the repo root (`Package.swift`) with one executable target. No package or sources have been added yet; `make check` skips `swift build` and `swift test` until `Package.swift` exists.

## Rules

- Do not edit signing, entitlements, Info.plist, notarization or release files without Raph's explicit OK.
- Tests that need Screen Recording or Accessibility permission are Raph's to run on his Mac. The factory does not run them.
- `make check` is the factory's gate: an offline lint of `.factory/project.conf`, then `swift build` and `swift test` once `Package.swift` exists. CI runs it on macOS 15 (check name: `factory check`).
- Never commit secrets, keys, team ids or personal paths, and never read `.release.env`, `.env`, key or cert files.

## Factory (Manufacture)

The factory builds specs from `specs/` (index: `specs/README.md`), one `factory/<nn>-<slug>` branch and PR each; its
config is `.factory/project.conf`. Raph merges every PR (`AUTO_MERGE=0`).

- `make check` is the only target the factory runs. After `Package.swift` exists it also builds and tests the package.
  Tests that need Screen Recording or Accessibility stay out of that gate.
- The factory never pushes the paths in `GUARDED_PATHS` (`.factory/`, `.github/`, `scripts/`, `Makefile`, this file,
  `Package.swift`, entitlements, Info.plists, and signing, notarization and release files). PRs touching
  `.factory/risky-paths.txt` paths wait for Raph's close review.
- Never commit secrets, keys, team ids or personal paths, and never read `.release.env`, `.env`, key or cert files.
