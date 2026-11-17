# 11: App bundle packaging, Info.plist and ad-hoc signing (hand spec)

Status: Done · Branch: lane/11-app-bundle-packaging · Depends on: 01 (scaffold), by hand (Fraime Lead) · Estimate: – agent run (by hand, about 2 h Fraime Lead) + 0 h Raph review · Risk: high
Source: Designer's spec (Notion "Agent capture tool — design spec v1 (2026-11-17)", 2026-11-17), from CPO's brief (Notion "Fraime — Agent-controlled capture — brief — 2026-11-17"). Plan: Fraime Lead's "Skreenrek v1 implementation plan (2026-11-17)".

## Goal

Wrap the SwiftPM `skreenrek` executable into `Skreenrek.app` (bundle ID `it.fraime.skreenrek`, menu-bar only) with an
ad-hoc signature, so Screen Recording and Accessibility belong to the app and Homebrew can build it from source. Every
file here is a guarded path (Info.plist, `scripts/`, `Makefile`, `.github/`), so the factory can't push it: Fraime Lead
writes it by hand in its own PR.

## Behaviour

1. `packaging/Info.plist`: `CFBundleIdentifier` `it.fraime.skreenrek`, `CFBundleName` and `CFBundleDisplayName`
   `Skreenrek`, `CFBundleExecutable` `skreenrek`, `CFBundlePackageType` `APPL`, `CFBundleShortVersionString` `0.1.0`,
   `CFBundleVersion` `1`, `LSMinimumSystemVersion` `15.0`, `LSUIElement` true, `NSHighResolutionCapable` true,
   `LSApplicationCategoryType` `public.app-category.developer-tools`, `NSHumanReadableCopyright` (MIT). No
   entitlements file: unsandboxed, no special entitlements.
2. `scripts/bundle-app.sh <products-dir> <out-dir>`: builds `<out-dir>/Skreenrek.app/Contents/{MacOS/skreenrek,
   Info.plist}`, stamps the version from `SkreenrekVersion`, then `codesign --force --sign - --options runtime
   --identifier it.fraime.skreenrek` and `codesign --verify --strict`. It prints the bundle path and never reads
   signing identities, keychains or secrets.
3. `Makefile`: `make app` = `swift build -c release --product skreenrek` + `bundle-app.sh .build/release build/`.
   `make check` additionally runs `plutil -lint packaging/Info.plist` and, once `Package.swift` exists, bundles the
   debug build into `.build/app-check/` and runs its `skreenrek --version`, so a factory PR that breaks bundling turns
   CI red.
4. `make perf` (manual, never part of `check`): `make app`, then runs `build/Skreenrek.app/Contents/MacOS/skreenrek
   debug perf --app "$(PERF_APP)"` (default `Safari`) and fails when a target is missed (06's harness).
5. `.gitignore`: `build/`.
6. `.github/workflows/live.yml` (manual dispatch only, not a required check): runs
   `SKREENREK_LIVE=1 swift test --filter Live` on macos-15 to learn whether a hosted runner can record without a hand
   grant. Informational; nothing waits on it.

## Defaults

- Ad-hoc signature with the hardened runtime. A Developer ID signature and notarization replace it when a certificate
  exists (after v1).

## Guardrails

- No team ID, certificate name, keychain path or personal path anywhere.
- `make check` stays offline apart from SwiftPM's dependency fetch.

## Out of scope

Developer ID signing, notarization, a DMG, Sparkle, an app icon (the default icon ships in v1).

## Open question (built with the default)

- TCC ties an ad-hoc-signed app to its exact build, so macOS may ask for permissions again after an upgrade. Accepted
  for v1; a Developer ID fixes it later.

## How to test (Raph)

1. No hand test is needed to merge: CI `factory check` must be green, including the bundle and `--version` step.
2. Optional (2 min): `make app && open build/Skreenrek.app`; the menu-bar icon appears and there's no Dock icon.

## Implementation notes

- **Files:** `packaging/Info.plist`, `scripts/bundle-app.sh`, `Makefile` (`check`, `app`, `perf`), `.gitignore`
  (`build/`), `.github/workflows/live.yml`. `check.yml` and `scripts/factory-check.sh` are unchanged.
- **Info.plist:** the keys from Behaviour 1, plus `CFBundleDevelopmentRegion` `en` and `CFBundleInfoDictionaryVersion`
  `6.0` (standard boilerplate). `NSHumanReadableCopyright` is "Copyright © 2026 the Skreenrek contributors. Released
  under the MIT License." It names no person, because shown strings may not contain "Raph" (and the LICENSE holder's
  name does). No entitlements file.
- **Version stamp:** `bundle-app.sh` reads `SkreenrekVersion.current` from
  `Sources/SkreenrekCore/SkreenrekVersion.swift` with `sed` (it doesn't run the binary) and writes it into
  `CFBundleShortVersionString` with `plutil -replace`. `CFBundleVersion` stays `1`.
- **Signing:** the linker already signs the arm64 binary ad hoc, so the script removes that signature before
  `codesign --force --sign - --options runtime --identifier it.fraime.skreenrek` on the bundle, which keeps the output
  free of "replacing existing signature". It then runs `codesign --verify --strict`. Result: `flags=0x10002(adhoc,runtime)`,
  `TeamIdentifier=not set`. No identity, keychain or secret is read.
- **`make check`:** factory lint, `plutil -lint packaging/Info.plist`, then `swift build`, `swift test`, bundling
  `$(swift build --show-bin-path)` into `.build/app-check/Skreenrek.app`, and running its `skreenrek --version`. The
  step fails if the output doesn't contain the version from `SkreenrekVersion.swift`, so it keeps working when 06
  changes the `--version` format.
- **`make perf`:** `make app`, then `skreenrek debug perf --app "$(PERF_APP)"` (default `Safari`). The `debug perf`
  subcommand comes with 06's harness, so until 06 lands `make perf` fails at that step. It's manual and never part of
  `check`.
- **`live.yml`:** `workflow_dispatch` only, `continue-on-error: true`, not a required check. It runs
  `SKREENREK_LIVE=1 swift test --filter Live` on macos-15. No `Live…` suite exists yet, so the run is a no-op until 02/03
  add them.
- **Open question (default built):** ad-hoc TCC grants are tied to the exact build, so macOS may ask again after an
  upgrade. Accepted for v1.
