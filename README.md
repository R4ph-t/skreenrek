# skreenrek

A small standalone macOS agent screen-capture tool (menu bar, CLI, MCP and an agent skill in one binary). It lists
windows, resizes one to an exact pixel size and reads the frame back, records it at native resolution (H.264, constant
30 or 60 fps), and writes `clip.mp4`, `events.json`, and a HyperFrames snippet.

Free and open source (MIT). Unsandboxed. Releases are signed with a Developer ID, notarized by Apple and installed
with a Homebrew cask. It shares no code with Fraime. The build plan is in `specs/` (index: `specs/README.md`).

## Install

Requires macOS 15 Sequoia or later.

```sh
brew tap r4ph-t/skreenrek https://github.com/R4ph-t/skreenrek
brew install --cask r4ph-t/skreenrek/skreenrek
open /Applications/Skreenrek.app
```

The cask installs Skreenrek.app into /Applications and links the `skreenrek` command. The app is notarized and keeps
the same Developer ID signature across versions, so Screen Recording and Accessibility grants survive
`brew upgrade --cask skreenrek`. The tap URL is needed because the tap lives in this repo, not in `homebrew-skreenrek`.

Open the app once to grant Screen Recording and Accessibility. Then connect detected agents:

```sh
skreenrek setup agents
skreenrek --version
```

Setup detects `~/.claude`, `~/.codex` and `~/.cursor`, and installs the `record-window` skill and the `skreenrek`
MCP server. Use `--claude`, `--codex` or `--cursor` to select clients explicitly, `--cli` to link the command into
`~/.local/bin`, `--json` for per-agent results, and `--remove` to remove the connections setup added. Existing
configs get a `.skreenrek-backup` before their first edit. Other servers and settings stay in place.

To remove Skreenrek and its settings: `brew uninstall --zap --cask skreenrek`.

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

After each rebuild macOS no longer matches the old grants to the new ad-hoc signature. Reset them, then open
Skreenrek and allow both again:

```sh
tccutil reset ScreenCapture it.fraime.skreenrek
tccutil reset Accessibility it.fraime.skreenrek
```

## Releasing

`make release VERSION=x.y.z` (maintainers only) builds a universal (arm64 + x86_64) app, signs it with the Developer ID
identity, the hardened runtime and a secure timestamp, verifies it with `codesign` and `spctl`, notarizes it with
`notarytool submit --wait`, staples the ticket, and writes `dist/Skreenrek-x.y.z.zip` and its `.sha256`. VERSION must
match `SkreenrekVersion.current`. It reads two environment variables, both names of Keychain items, never secrets:

- `SKREENREK_SIGN_IDENTITY`: the `Developer ID Application: …` identity (defaults to the maintainer's).
- `SKREENREK_NOTARY_PROFILE`: a `xcrun notarytool store-credentials` profile (defaults to `skreenrek`).

It never tags or publishes. To ship: `gh release create vx.y.z dist/Skreenrek-x.y.z.zip`, then set `version` and
`sha256` in `Casks/skreenrek.rb` to the new zip's.

## Troubleshooting permissions

- **Screen Recording is allowed but Skreenrek still says it's off.** macOS applies a Screen Recording grant only to a
  new process. Click Quit & Reopen in the setup window, or quit Skreenrek from the menu bar and open it again.
- **Where to allow a missing permission.** Choose "Permissions needed…" in the Skreenrek menu (it shows whenever
  Screen Recording or Accessibility is missing), or run `skreenrek doctor` to see what is missing.
- **Grants stop working after an upgrade.** This happens with source builds only: they are ad-hoc signed, and every
  rebuild changes the signature. See [Building from source](#building-from-source) for the `tccutil` reset. The cask
  keeps one Developer ID signature, so its grants carry over.
