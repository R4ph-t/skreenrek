# 11: App bundle packaging, Info.plist and ad-hoc signing (hand spec)

Status: Ready · Branch: – · Depends on: 01 (scaffold), by hand (Fraime Lead) · Estimate: – agent run (by hand, about 2 h Fraime Lead) + 0 h Raph review · Risk: high
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
4. `.gitignore`: `build/`.
5. `.github/workflows/live.yml` (manual dispatch only, not a required check): runs
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

_(filled in by Fraime Lead)_
