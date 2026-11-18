# Contributing to Skreenrek

Notes for working on Skreenrek itself. To install and use it, see the [README](README.md). The build plan is in
`specs/` (index: `specs/README.md`). Skreenrek shares no code with Fraime.

## Building from source

Needs Xcode 16 or later. The source build is ad-hoc signed, so it needs no certificate, but macOS ties permission
grants to the signature and every rebuild changes it. Use it to work on Skreenrek; use the cask to run it.

With Homebrew (the `skreenrek` formula builds the latest commit; uninstall the cask first, both install `skreenrek`):

```sh
brew tap r4ph-t/skreenrek https://github.com/R4ph-t/skreenrek
brew trust r4ph-t/skreenrek
brew install --HEAD skreenrek
rm -rf /Applications/Skreenrek.app && cp -R "$(brew --prefix)/opt/skreenrek/Skreenrek.app" /Applications/
open /Applications/Skreenrek.app
```

The app is copied, not linked, because Spotlight, Launchpad and the Finder Applications view skip symlinks. Redo the
`rm -rf … && cp -R …` line after each `brew upgrade --fetch-HEAD skreenrek`. Newer Homebrew refuses to load a formula
from a third-party tap until you trust it, hence `brew trust`.

From a checkout: `make app` builds `build/Skreenrek.app`, and `make check` builds, tests and bundles a debug app.

### Reset permissions after a rebuild

After each rebuild macOS no longer matches the old grants to the new ad-hoc signature. Reset them, then open
Skreenrek and allow both again:

```sh
tccutil reset ScreenCapture com.raphaelterrier.skreenrek
tccutil reset Accessibility com.raphaelterrier.skreenrek
```

## Releasing

`make release VERSION=x.y.z` (maintainers only) builds a universal (arm64 + x86_64) app, signs it with the Developer ID
identity, the hardened runtime and a secure timestamp, verifies it with `codesign` and `spctl`, notarizes it with
`notarytool submit --wait`, staples the ticket, and writes `dist/Skreenrek-x.y.z.zip` and its `.sha256`. VERSION must
match `SkreenrekVersion.current`, and `CHANGELOG.md` must have a `## [x.y.z]` section. Before it builds, the script
writes that section to `dist/Skreenrek-x.y.z-notes.md`. It reads two environment variables, both names of Keychain
items, never secrets:

- `SKREENREK_SIGN_IDENTITY`: the `Developer ID Application: …` identity (defaults to the maintainer's).
- `SKREENREK_NOTARY_PROFILE`: a `xcrun notarytool store-credentials` profile (defaults to `skreenrek`).

`make release-notes VERSION=x.y.z` prints that section without building.

It never tags or publishes. To ship:

```sh
gh release create vx.y.z dist/Skreenrek-x.y.z.zip --notes-file dist/Skreenrek-x.y.z-notes.md
```

Then set `version` and `sha256` in `Casks/skreenrek.rb` to the new zip's. When you bump the version, move the lines
under `## [Unreleased]` in `CHANGELOG.md` into `## [x.y.z] - YYYY-MM-DD` and leave `[Unreleased]` empty.
