# 06: CLI commands, output and exit codes

Status: Ready · Branch: – · Depends on: 05 (controller and socket) · Estimate: 5–7 h agent run + 0 h Raph review (no hand test)
Source: Designer's spec (Notion "Agent capture tool — design spec v1 (2026-11-17)", 2026-11-17), from CPO's brief (Notion "Fraime — Agent-controlled capture — brief — 2026-11-17"). Plan: Fraime Lead's "Skreenrek v1 implementation plan (2026-11-17)".

## Goal

`skreenrek` is a `gh`-style CLI over the running app: human output by default, `--json` for agents, errors on stderr
with a `hint:`, and the design spec's exit codes. It launches the app hidden when it isn't running.

## Behaviour

1. New library target `SkreenrekCLI` (depends on Control and `swift-argument-parser`, pinned with `exact:` to the
   newest 1.x release that builds on the CI toolchain) and test target `SkreenrekCLITests`. `main.swift` hands every
   invocation with arguments to the CLI.
2. Commands, exactly as the design spec's CLI block: `windows [--app NAME]`, `pick`, `resize <window> --size WxH`,
   `record <window> [flags]`, `record --region X,Y,W,H [--display ID]`, `stop`, `discard`, `status`, `last`,
   `doctor`. Global: `--json --quiet --no-color --help --version`. (`mcp` arrives in 07, `setup agents` in 09.)
   - `<window>` is a numeric window ID, or `--app NAME [--title TEXT]`.
   - `record` flags: `--size WxH`, `--allow-inexact`, `--fps 30|60`, `--duration` (`30s`, `2m`, `1m30s` or plain
     seconds), `--no-cursor`, `--no-events`, `--no-hud`, `--out DIR`, `--name SLUG`, `--assets DIR`,
     `--codec h264|hevc`, `--wait`. Without `--wait`, `record` returns as soon as recording starts.
   - `--wait` blocks until stop or duration. Ctrl-C (SIGINT) during `--wait` stops and saves, prints the stop output,
     and exits 130.
   - `--region X,Y,W,H` is in pixels of the chosen display (default: the main display), top-left origin.
3. Output matches the design spec's examples character for character, with `~` for the home folder in human output:
   `✓ Safari — localhost:3000 is 1280 × 800 px (640 × 400 pt at 2×)`, `● Recording at 60 fps. Stop with: skreenrek
   stop`, `✓ Saved 0:42 · 1280 × 800 px · 60 fps` plus the three aligned path lines. `windows` prints one row per
   window: `<id>  <app>  <title>  <w> × <h> px`. `status` prints the state word, plus the window and elapsed time when
   recording. `--json` prints the controller's JSON (the design spec's shapes) and nothing else on stdout.
4. Errors go to stderr as `error: <sentence>` then `hint:  <next command>`, or with `--json` as the design spec's
   `{ "error": {code, message, hint, exit} }`. Exit codes per the table: parse and validation errors exit 2 (not
   ArgumentParser's default 64).
5. Colour only when stdout is a TTY, `--no-color` isn't set and `NO_COLOR` is unset. `--quiet` prints nothing on
   success.
6. App launch (`AppLauncher` seam): when the socket doesn't answer, and the running executable resolves (through
   symlinks) to `…/Skreenrek.app/Contents/MacOS/skreenrek`, open that bundle hidden with `NSWorkspace` (no activation)
   and wait up to 10 s for `hello`. Outside a bundle: `error: Skreenrek isn't running.` / `hint:  Open Skreenrek.app,
   or run: skreenrek app` (exit 1).
7. Mode dispatch in `main.swift`: no arguments and stdin not a TTY (a Finder or `open` launch) → run the app;
   `skreenrek app` → run the app; no arguments in a terminal → help; anything else → CLI.
8. `doctor` prints one line per check (Screen Recording, Accessibility, app version and running, output folder, CLI
   path, socket) with `✓` or `✗` and a fix; exits 3 when Screen Recording is missing, else 0.
9. `stop` human output adds one quiet line when a recording isn't clean or used the software encoder:
   `  note    3 dropped frames · software encoder` (nothing when clean and hardware). `--json` always has `stats`.
10. Hidden `skreenrek debug perf --app NAME [--title T] [--runs 10] [--json]` (needs the app and its permissions):
    with the app running, it times 10 starts (request to first frame), records 60 s at 60 fps 1920 × 1080 and 60 s at
    30 fps 1280 × 800, and records one 15-minute clip only with `--long`. It reads each clip with `AVAssetReader`
    (frame count, constant duration) and prints a table of measured versus target: start p95 ≤ 250 ms, 0 dropped and 0
    skipped frames, `encoder` hardware, exact frame counts, stop to finalized ≤ 500 ms (≤ 1 s for 15 min). Exit 0 when
    every target is met, 1 otherwise. Clips go to a temp folder and are deleted unless `--keep`.

## Defaults

- `--fps` default comes from the app's settings, else 60.
- Ambiguous `--app` prints the candidate list from 02 and exits 5.

## Guardrails

- The CLI never captures or resizes in its own process; it only talks to the app.
- stdout carries only the command's output (JSON when `--json`); diagnostics go to stderr.
- Tests run the CLI in process against a real socket served by a `HeadlessHost` with fakes; signals are simulated
  through an injected interrupt source; no sleeps.

## Out of scope

`mcp` (07), `setup agents` and the CLI symlink (09), the picker UI (10: `pick` returns an `internal` error
`The window picker isn't available yet.` until then).

## Open question (built with the default)

- How the single binary tells an app launch from a terminal call: the dispatch rule in 7.

## How to test (Raph)

1. No hand test is needed to merge: CI `factory check` must be green. The tests cover golden human and JSON output for
   every command, each exit code (2, 3, 4, 5, 6, 7, 130), `--wait` with a simulated Ctrl-C, `--duration` parsing,
   `--region`, colour rules, `--quiet`, the app-launch path with a fake launcher (socket appears) and the
   not-in-a-bundle error, the dispatch rule, the `stop` note line, and `debug perf`'s report and exit code with a
   fake host (targets met and missed).
2. Optional smoke (after hand spec 11 and with permissions granted, 3 min): `skreenrek windows`, then
   `skreenrek record --app Safari --size 1280x800 --duration 5s --wait`, and open the printed clip.
3. Optional performance run (after hand spec 11, with permissions, about 10 min; 25 min with `--long`): open a
   Safari window and run `make perf` (or `skreenrek debug perf --app Safari`). Every row must read `met`.

## Implementation notes

_(filled in by the agent)_
