# skreenrek

A small standalone macOS agent screen-capture tool (menu bar, CLI, MCP and an agent skill in one binary). It lists
windows, resizes one to an exact pixel size and reads the frame back, records it at native resolution (H.264, constant
30 or 60 fps), and writes `clip.mp4`, `events.json`, and a HyperFrames snippet.

Free and open source (MIT). Unsandboxed; v1 is ad-hoc signed and installed with a Homebrew build-from-source formula.
It shares no code with Fraime. The build plan is in `specs/` (index: `specs/README.md`).

## Install

Requires macOS 15 Sequoia or later and Xcode 16 or later. v1 builds from source with Homebrew:

```sh
brew tap r4ph-t/skreenrek https://github.com/R4ph-t/skreenrek
brew trust r4ph-t/skreenrek
brew install --HEAD skreenrek
rm -rf /Applications/Skreenrek.app && cp -R "$(brew --prefix)/opt/skreenrek/Skreenrek.app" /Applications/
open /Applications/Skreenrek.app
```

The app is copied, not linked, because Spotlight, Launchpad and the Finder Applications view skip symlinks. Until
there is a cask, redo the `rm -rf … && cp -R …` line after each `brew upgrade`.

Newer Homebrew refuses to load a formula from a third-party tap until you trust it, hence `brew trust`. To update
to the latest commit, run `brew upgrade --fetch-HEAD skreenrek`.

Open the app once to grant Screen Recording and Accessibility. Then connect detected agents:

```sh
skreenrek setup agents
skreenrek --version
```

Setup detects `~/.claude`, `~/.codex` and `~/.cursor`, and installs the `record-window` skill and the `skreenrek`
MCP server. Use `--claude`, `--codex` or `--cursor` to select clients explicitly, `--cli` to link the command into
`~/.local/bin`, `--json` for per-agent results, and `--remove` to remove the connections setup added. Existing
configs get a `.skreenrek-backup` before their first edit. Other servers and settings stay in place.

Skreenrek is ad-hoc signed, so macOS forgets its permissions after an upgrade. See
[Troubleshooting permissions](#troubleshooting-permissions).

## Troubleshooting permissions

- **Screen Recording is allowed but Skreenrek still says it's off.** macOS applies a Screen Recording grant only to a
  new process. Click Quit & Reopen in the setup window, or quit Skreenrek from the menu bar and open it again.
- **Where to allow a missing permission.** Choose "Permissions needed…" in the Skreenrek menu (it shows whenever
  Screen Recording or Accessibility is missing), or run `skreenrek doctor` to see what is missing.
- **Grants stop working after `brew upgrade`.** The Homebrew build is ad-hoc signed (`codesign --sign -`), and every
  rebuild changes the signature, so macOS no longer matches the old grants to the new app. Reset them, then open
  Skreenrek and allow both again:

  ```sh
  tccutil reset ScreenCapture it.fraime.skreenrek
  tccutil reset Accessibility it.fraime.skreenrek
  ```
