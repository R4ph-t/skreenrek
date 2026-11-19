# Agent capture tool — design spec v1 (2026-11-17)

Source: Designer's Notion spec, https://app.notion.com/p/41b0d0d44592815d89b9d08c1b414ee2

> Design spec v1 for the agent capture tool, written from CPO's approved brief: [Fraime — Agent-controlled capture — brief — 2026-11-17](https://app.notion.com/p/41b0d0d4459281588387f2e14d779d81). Built in a new repo through Manufacture, owned by Fraime Lead. The run has zero input from Raph except the name, so Designer has decided every open design point below, each with a one-line rationale. Nothing here needs a reply.

## Name

The chosen name is **Skreenrek**, picked by Raph on 2026-11-17. The GitHub user/org name and the Homebrew names were free when checked that day.

How it is used: UI copy and the product name are Skreenrek. The CLI command, the MCP tool prefix (`skreenrek_…`) and the Application Support folder are `skreenrek`. The output folder is `~/Movies/Skreenrek/` and the bundle ID is `com.raphaelterrier.skreenrek`. The skill is `record-window`. App copy never uses "Raph" or "CTO".

## What it is

One signed, unsandboxed macOS app (macOS 26 Tahoe; also runs on 15 Sequoia). It's also a CLI, a menu-bar app with a panel, a stdio MCP server and an agent skill. The job: pick a window (or region), resize it to an exact pixel size and verify that size by reading it back, record native 30/60 fps video at a constant frame rate, stop, and get back `clip.mp4`, `events.json` (cursor, clicks, mouse button, no keystrokes) and a short HyperFrames snippet. It's a sibling to [Fraime.it](http://Fraime.it), written fresh (path B, no code from Fraime). It ships as a notarized download, then as a Homebrew cask. Free and open source.

Out of scope (from the brief): screenshots and grids, the editor, effects, webcam, microphone and system audio, Windows and Linux, an upstream HyperFrames component, and a public launch.

## Architecture decisions that shape the design

| Decision | Rationale |
| --- | --- |
| The app process always does the capture. The CLI and MCP are thin clients that talk to the running app over a local Unix socket in `~/Library/Application Support/skreenrek/`, and launch it (hidden, menu bar only) if it isn't running. | Screen Recording and Accessibility permissions then belong to the app's bundle ID, not to every terminal or agent host. This removes the per-terminal prompt risk the brief calls out. |
| The CLI binary is the app's own executable run with arguments, symlinked to `~/.local/bin/skreenrek`. The Homebrew cask uses a `binary` stanza for this. | This gives one artefact, as the brief decided. `~/.local/bin` needs no admin rights. |
| One recording at a time. | It keeps every surface simple, and agents never need recording IDs to stop the right recording. |
| No pause or resume in v1. Trimming happens downstream (HyperFrames `data-media-start` / `data-duration`). | Clip time stays equal to events time, the tool-call count stays small, and it holds the brief's "not a second editor" line. |
| Sizes are always **output pixels** (`1280x800` means the video is 1280 × 800 px). Points are derived: px ÷ display scale. | Agents ask for the video size they need. Read-back reports both units so nobody has to guess. |
| A size means the whole window frame (title bar included, shadow excluded). SCK captures the window without its shadow. | What you resize is exactly what you get in the video: no crop, no surprises. |
| Exact means pixel-equal, with 0 px tolerance (not Fraime's within-2-pt rule). The tool retries the resize up to three times, then reports the actual size. | This exactness is the product's reason to exist. |
| Video is H.264 MP4 at a constant frame rate. The writer repeats the last frame when SCK sends no new frame. `--codec hevc` is an option. | It plays in every browser and in HyperFrames. A constant frame rate is the quality bar from the brief, and it beats Peekaboo's stitched PNG bursts. |
| No time or size caps. Recording stops only on stop, `--duration`, window close or low disk space (below 2 GB free). | The brief explicitly rejects Peekaboo-style 3-minute or 1440 px caps. |
| Default output folder is `~/Movies/Skreenrek/`. | It's where macOS puts screen recordings, it's easy to find, and you can change it in Settings or with `--out`. |
| No sound, no notification banner, no Dock icon (LSUIElement). | Keeps it calm. The HUD and menu-bar icon carry all feedback. |

## Surfaces

Shared visual rules: native AppKit and SwiftUI controls, system materials, and SF Symbols at 16 pt in a 16 pt column. 13 pt for titles and menu items, 12 pt for details in a quieter colour (secondary label). A 4 pt grid. Radii come only from 10 / 6 / 4 (windows, HUD and menus 10; buttons and highlights 6; checkboxes and small chips 4). Detail appears only when something is wrong. Light and dark use system colours; the only tints are system red (recording), system green (allowed or saved) and the system accent (selection and picker highlight). No numeric shortcuts.

### 1. Menu-bar icon

A template image, so it follows light, dark and tinted menu bars. Every state has its own shape, and each one carries a full sentence in its tooltip and VoiceOver label.

| State | Symbol | Tint | Tooltip and VoiceOver |
| --- | --- | --- | --- |
| Idle | `record.circle` | template | "Skreenrek is ready. No window picked." |
| Window picked (armed) | `viewfinder` | template | "Skreenrek is ready to record Safari at 1280 × 800 pixels." |
| Recording | `record.circle.fill`  • elapsed time `0:12` (SF Mono digits, 12 pt) | system red symbol only | "Skreenrek is recording Safari. 12 seconds." |
| Writing output | `arrow.down.circle` | template | "Skreenrek is saving the clip." |
| Error | `exclamationmark.triangle` | template | "Skreenrek stopped recording: the window closed." (always the actual reason) |

Decisions: no blinking or pulsing (calm, Reduce Motion-safe). The recording symbol is the only tinted one, and it also differs in shape and text, so colour is never the only cue. The elapsed time updates once a second, and the VoiceOver value updates every 10 s to avoid chatter. Clicking the icon opens the panel. There is no click-to-stop on the icon, so a recording is never stopped by accident; Stop is the panel's hero button.

### 2. Menu-bar panel

> **Updated for 1.0.5 (18 Nov 2026).** The measured detail, renders and redlines are in Designer's [1.0.5 spec](design/1.0.5/spec.md) (§5) and `docs/design/1.0.5/`. **Header and surface (19 Nov 2026):** [addendum 3](design/1.0.5/addendum-3-surface-header-2026-11-19.md) replaces the toolbar tabs and the per-tab title, and sets the colours below.

A macOS Settings window, 480 pt wide, one tone (`surface.base`, #1E1E1E dark, #F5F5F5 light) from the top edge through the header to the bottom, with the system window frame and shadow. The title bar (y 0–28) is transparent with only the traffic lights, and its title is hidden. The window title is `Skreenrek Settings` on every tab (Window menu, Mission Control, VoiceOver). There's no toolbar.

**Header** (y 28–84, x 16–464, same tone, no divider): the 32 pt V1 app icon at x 16 (y 40–72), then `Skreenrek` (13 semibold, `labelColor`) and `Version <current>` (12 regular, `secondaryLabelColor`, 2 pt under the name) at x 56, centred together on the icon's centre line. On the right, a system segmented control **General | Agents | Permissions**, 3 × 88 = 264 pt, regular size (24 tall), right edge at x 464, on the same centre line. VoiceOver reads the header as `Skreenrek, version 1.0.5` and the control as `Settings tabs`. The control is Tab-reachable, and ←/→ switch tabs while it has focus (no numeric shortcuts). ⌘, reopens the last tab used.

Content starts at y 92 and the height fits each tab with no scroll view. Switching tabs crossfades the content over 0.15 s while the window resizes with the system animation; both are instant under Reduce Motion.

Each tab is a stack of sections, 16 pt from the window edges (x 16–464): a 10 pt rounded rect in `surface.cell` (#2A2A2A dark, #FFFFFF light with a 1 px black 8% edge), 1 px `surface.separator` lines between rows, inset 12 pt from the section's leading edge and running to its trailing edge. (A grouped `Form` won't take the cell tint, so the sections are drawn by hand, the addendum's fallback.) Every row is 44 pt, with its label at x 28 and its trailing control ending at x 452, at least 12 pt apart. The label truncates and the control never does. There are no leading icons or tiles in the rows. Switches are mini, push buttons are at least 80 pt wide.

- **General.** Output folder (the path, tooltip with the full path, \[Choose…\]) and Open at login. **Recording:** Default frame rate (30 / 60 fps), Show cursor in video, Write click events, Show recording indicator, Stop shortcut ⌃⌘⎋ (read-only). **About:** Updates (its detail, such as `Skreenrek 1.0.5 is up to date.`, is a status), with What's new under it when a release is waiting, and View on GitHub, where the whole row is the link. The version shows only in the header; there's no version row.
- **Agents.** Claude Code, Codex, Cursor and Command-line tool, each with its status and an 88 pt \[Connect\] or \[Remove\]. It is disabled with "Install <Agent> first." when the agent isn't installed. Setup problems replace the status line. Footer: "Connect adds the Skreenrek MCP server and the record-window skill."
- **Permissions.** Screen Recording and Accessibility. Allowed is a green check and "Allowed". Not allowed is an orange triangle, whose tooltip and VoiceOver give the full sentence, and \[Open System Settings…\]. The status refreshes when the window shows and when the app becomes active, and never prompts.

## CLI

It's styled after `gh`: noun-light verbs, human output by default, `--json` for agents, errors on stderr, and nothing printed in colour unless stdout is a TTY. Examples use the `skreenrek` command.

```txt
skreenrek windows [--app NAME] [--json]            List windows that can be recorded
skreenrek pick [--json]                            Open the picker overlay and print the chosen window
skreenrek resize <window> --size WxH [--json]      Resize to exact pixels and read the size back
skreenrek record <window> [flags]                  Start recording (returns immediately)
skreenrek record --region X,Y,W,H [--display ID]   Record a screen region in pixels
skreenrek stop [--json]                            Stop, write files, print paths
skreenrek discard                                  Stop and delete the current recording
skreenrek status [--json]                          idle | armed | recording | writing | error
skreenrek last [--json]                            Paths of the last clip
skreenrek doctor [--json]                          Permissions, app, version, output folder
skreenrek setup agents [--claude] [--codex] [--cursor] [--remove]
skreenrek mcp                                      Run the stdio MCP server
Global: --json  --quiet  --no-color  --help  --version
```

`<window>` is either a numeric window ID from `windows`, or `--app Safari [--title "localhost"]`. If an `--app` match is ambiguous, the command fails with exit code 5 and lists the candidates.

`record` flags: `--size WxH` (resize first, and fail with exit code 4 if the size isn't exact, unless you pass `--allow-inexact`), `--fps 30|60` (default from Settings, otherwise 60), `--duration 30s` (auto-stop), `--no-cursor`, `--no-events`, `--no-hud`, `--out DIR`, `--name SLUG`, `--assets DIR` (also copy the clip into a HyperFrames project's assets folder and point the snippet at it), `--codec h264|hevc`, `--wait` (block until stop or duration; Ctrl-C stops and saves).

Decision: `record` returns immediately by default. Rationale: agents need their shell back to drive the app they're recording. Humans can use `--wait`.

Human output (stdout):

```txt
$ skreenrek resize --app Safari --size 1280x800
✓ Safari — localhost:3000 is 1280 × 800 px (640 × 400 pt at 2×)

$ skreenrek record --app Safari --size 1280x800 --fps 60
✓ Safari — localhost:3000 is 1280 × 800 px
● Recording at 60 fps. Stop with: skreenrek stop

$ skreenrek stop
✓ Saved 0:42 · 1280 × 800 px · 60 fps
  clip    ~/Movies/Skreenrek/2026-11-17_104207_safari/clip.mp4
  events  ~/Movies/Skreenrek/2026-11-17_104207_safari/events.json
  snippet ~/Movies/Skreenrek/2026-11-17_104207_safari/hyperframes.html
```

Error output (stderr). The shape is always `error:` plus one sentence, then `hint:` with the exact next command:

```txt
error: Screen Recording isn't allowed for Skreenrek.
hint:  Allow it in System Settings › Privacy & Security › Screen & System Audio Recording, then run: skreenrek doctor

error: Safari can't be narrower than 1286 px. It is 1286 × 800 px now.
hint:  Pick a width of 1286 px or more, or pass --allow-inexact.

error: 2 windows match --app Safari. Pass a window ID:
  4127  Safari  localhost:3000      1280 × 800 px
  4133  Safari  GitHub              1512 × 945 px
```

Exit codes:

| Code | Meaning |
| --- | --- |
| 0 | OK (for `resize`: the size is exact) |
| 1 | Unexpected error |
| 2 | Usage error (bad flag or value, e.g. an odd pixel width on a 2× display) |
| 3 | Permission missing (Screen Recording or Accessibility) |
| 4 | Size not exact after read-back |
| 5 | Window not found or ambiguous |
| 6 | Wrong state (already recording / not recording) |
| 7 | Recording failed (window closed, disk low, write failed); a partial clip may exist |
| 130 | Interrupted (Ctrl-C during `--wait`; the clip is saved) |

JSON read-back (`resize --json`, and embedded in `record --json` and `stop --json`). Shape only:

```json
{
  "window": { "id": 4127, "app": "Safari", "bundleId": "com.apple.Safari", "title": "localhost:3000", "pid": 812 },
  "display": { "id": 1, "name": "Built-in Retina Display", "scale": 2 },
  "requested": { "width": 1280, "height": 800, "unit": "px" },
  "actual":    { "width": 1280, "height": 800, "unit": "px" },
  "frame":     { "x": 120, "y": 80, "width": 640, "height": 400, "unit": "pt" },
  "exact": true,
  "attempts": 1
}
```

`stop --json` returns `{ "recording": {id, duration, fps, width, height, codec, startedAt, startedBy}, "files": {clip, events, snippet}, "snippet": "<video …>" , "readback": {…} }`. Errors with `--json` go to stderr as `{ "error": { "code": "permission_denied", "message": "…", "hint": "…", "exit": 3 } }`. The code strings are `permission_denied`, `not_exact`, `window_not_found`, `window_ambiguous`, `wrong_state`, `recording_failed`, `usage`, `internal`.

## MCP server

`skreenrek mcp` runs a stdio server. It has seven tools, all prefixed with the name. Inputs and outputs use the same JSON as the CLI, so the docs are shared. Errors set `isError: true` and return the same `{error:{code,message,hint}}` body. The typical flow is three calls: list → start (with size) → stop.

| Tool | Inputs | Output |
| --- | --- | --- |
| `skreenrek_list_windows` | `app?` | `{ windows: [{id, app, bundleId, title, width, height, unit:"px", displayId, onScreen}] }` |
| `skreenrek_resize_window` | `windowId` or `app`  • `title?`, `width`, `height` (px) | read-back JSON (above) |
| `skreenrek_start_recording` | `windowId` or `app`  • `title?`, or `region:{x,y,width,height}`  • `displayId?`; `width?`, `height?` (resize first), `allowInexact?`, `fps?` (30/60), `durationSeconds?`, `cursor?` (true), `events?` (true), `hud?` (true), `outDir?`, `assetsDir?` | `{ recordingId, startedAt, readback?, fps }` |
| `skreenrek_stop_recording` | none | `{ recording, files, snippet, readback }` |
| `skreenrek_status` | none | `{ state, recording?, window?, lastClip? }` |
| `skreenrek_discard_recording` | none | `{ discarded: true }` |
| `skreenrek_pick_window` | `timeoutSeconds?` (default 60) | the chosen window, or `{ cancelled: true }`. Opens the overlay for a human. |

The MCP client name from `initialize` (e.g. "Claude Code") feeds the "Started by … over MCP" row.

## Skill

One skill, `record-window`, at `skills/record-window/SKILL.md` in the repo. `skreenrek setup agents` installs it into `~/.claude/skills/`, `~/.codex/skills/` and `~/.cursor/skills/`. Shape:

- Frontmatter: `name: record-window`, `description: Record a macOS window at an exact pixel size as a smooth 30/60 fps MP4 with click events and a HyperFrames snippet. Use when asked to record, screencast or capture video of an app or window. Not for screenshots.`
- **Before you start:** run `skreenrek doctor --json`. If a permission is missing, tell the user which one and stop.
- **Steps:** list windows → `record --size WxH --fps 60` (read `exact` from the read-back) → do the actions → `stop --json` → report the three paths.
- **Rules:** prefer MCP tools if they're available, otherwise the CLI. Never record windows showing secrets or tokens. Keep clips short (start just before the first action). One recording at a time. Don't take screenshots with this tool.
- **Errors:** a table from exit code (or error code) to the action to take.
- **Using the output with HyperFrames:** where the snippet is, and `--assets` to drop the clip straight into a project.

## Output folder and file naming

```txt
~/Movies/Skreenrek/                               (Settings or --out)
└── 2026-11-17_104207_safari/                     YYYY-MM-DD_HHMMSS_<app-slug>, local time; --name overrides the slug
    ├── clip.mp4                                  H.264, constant frame rate, exact px
    ├── events.json                               omitted with --no-events
    └── hyperframes.html                          the snippet, plain text
```

Decisions: one folder per clip, with fixed file names inside, so agents never parse file names. The names are lowercase with no spaces, so they're shell-safe. A collision within the same second adds `-2`. A partial clip after a failure keeps the same layout and gets `"complete": false` in events.json.

## events.json schema (shape only)

```json
{
  "schema": "skreenrek.events/1",
  "complete": true,
  "recording": {
    "id": "2026-11-17_104207_safari",
    "startedAt": "2026-11-17T10:42:07.120+01:00",
    "duration": 42.0, "fps": 60,
    "video": { "file": "clip.mp4", "width": 1280, "height": 800, "scale": 2, "codec": "h264" },
    "source": { "kind": "window", "app": "Safari", "bundleId": "com.apple.Safari", "title": "localhost:3000", "windowId": 4127,
                "frame": { "x": 120, "y": 80, "width": 640, "height": 400, "unit": "pt" } },
    "startedBy": "mcp", "client": "Claude Code"
  },
  "coordinates": { "unit": "px", "origin": "top-left", "space": "video" },
  "cursor": { "sampleRate": 60, "samples": [[0.000, 412, 306], [0.017, 414, 305]] },
  "events": [
    { "t": 1.234, "type": "down", "button": "left", "clickCount": 1, "x": 640, "y": 52 },
    { "t": 1.310, "type": "up",   "button": "left", "clickCount": 1, "x": 640, "y": 52 }
  ],
  "clicks": [ { "t": 1.234, "button": "left", "x": 640, "y": 52, "xPct": 50.0, "yPct": 6.5 } ]
}
```

- `t` is seconds from the first video frame. Cursor samples are `[t, x, y]` arrays, at the recording fps, to keep the file small. Points outside the video keep their real coordinates (which can be negative or beyond the width).
- `button` is one of `left`, `right`, `middle` or `other`. No keystrokes, no scroll, no window titles beyond the source (v1, per the brief).
- `clicks` is derived from the `down` events. The percentages match how HyperFrames' Zoom Follow Cursor takes click points.

## HyperFrames snippet

It's written to `hyperframes.html` in the clip folder, printed as `snippet` by `stop --json`, and copied by "Copy HyperFrames Snippet" in the dropdown. It's a single clip element plus one comment line, nothing else:

```html
<!-- Skreenrek · Safari — localhost:3000 · 1280×800 px · 60 fps · 42.0 s · clicks: events.json -->
<video class="clip" src="assets/2026-11-17_104207_safari.mp4"
       data-start="0" data-duration="42.0" data-track-index="0" muted playsinline></video>
```

Decision: `src` always points at `assets/<clip-id>.mp4`, the HyperFrames convention, with paths that resolve from the project root. With `--assets DIR` the tool copies the clip there under that name. Without it, the comment line is followed by a second comment with the exact `cp` command. Rationale: the snippet pastes straight into a composition, and it never contains absolute paths from someone's Mac.

## Copy rules

- Plain sentences in sentence case, title case for menu items (the macOS convention), and an ellipsis on items that open UI.
- Sizes are always written `1280 × 800 px` in UI and `1280x800` in CLI flags. Times are `m:ss`.
- Errors give what happened plus what to do, and never blame the user. Every error has a fix item or hint.
- The product name is Skreenrek in UI copy, and `skreenrek` for the command, the MCP tool prefix and the Application Support folder. No "Raph" or "CTO" anywhere in the app, CLI, MCP descriptions or skill.

## Accessibility

- Every status symbol has a VoiceOver label carrying the full sentence (table above), and the tooltip uses the same text.
- The HUD and picker label are single accessibility elements with named actions (Stop, Pick). The picker is fully keyboard-operable (Tab or arrows, Return, Esc).
- Reduce Motion: no fades on the HUD (it appears and disappears instantly), and the spinner becomes a static `arrow.down.circle`. Increase Contrast: strokes go to 2 pt (picker 3 pt), and the HUD and panel hairlines go to 25%.
- Contrast: all text meets 4.5:1 on its material in both appearances. Secondary text uses system secondaryLabel.
- Dynamic system text size isn't applied in menus (macOS doesn't), but the onboarding and Settings windows grow with the content and never clip.
- Global shortcut ⌃⌘⎋ has no digits and works on AZERTY. No other global shortcuts are added.

## Light and dark

Everything uses system materials and semantic colours, so it follows the appearance with no custom palette. The menu-bar icon is a template image. Tints: system red (recording symbol and region outline), system green (allowed or saved check), and the system accent (picker highlight, selected items, default buttons). The boards below show both appearances.

## Mockups

Rendered from HTML with headless Chrome at @2x. Box paths are listed below; Notion can't host the images. **The fonts and symbols are stand-ins:** Inter and Geist Mono stand in for SF Pro and SF Mono, and hand-drawn SVG glyphs stand in for the named SF Symbols. Build with Apple's actual fonts and symbols. All copy uses the name Skreenrek.

- `/workspace/design-capture-tool-2026-11-17/dropdown-idle-dark@2x.png` · `…/dropdown-idle-light@2x.png`: idle (no window), plus window picked with the Size submenu open
- `/workspace/design-capture-tool-2026-11-17/dropdown-recording-dark@2x.png` · `…/dropdown-recording-light@2x.png`: recording, error (window closed), error (permission off)
- `/workspace/design-capture-tool-2026-11-17/picker-overlay-dark@2x.png` · `…/picker-overlay-light@2x.png`
- `/workspace/design-capture-tool-2026-11-17/recording-indicator-dark@2x.png` · `…/recording-indicator-light@2x.png`: the HUD under the window, plus all four HUD states
- `/workspace/design-capture-tool-2026-11-17/onboarding-dark@2x.png` · `…/onboarding-light@2x.png`: steps 1 and 2
- `/workspace/design-capture-tool-2026-11-17/menubar-icons-dark@2x.png` · `…/menubar-icons-light@2x.png`: five icon states with their tooltip and VoiceOver sentences
- Source: `build.py` and the `.html` files are in the same folder. `geometry.json` is the automated overflow, overlap, containment and 4 pt-grid check (all pass). Designer also inspected every raster by eye.

## Acceptance criteria

Fraime Lead checks these on a real Mac (Apple silicon, 2× display, plus one 1× external display if available), in dark and light.

1. **Exact size:** `skreenrek resize --app Safari --size 1280x800 --json` returns `exact: true`, and `ffprobe` on a following recording reports 1280 × 800. This repeats for 1920x1080 and 1080x1920 on a 2× display. An odd width on a 2× display exits 2 with the hint.
2. **Smooth video:** a 60 s recording at 60 fps has `r_frame_rate == avg_frame_rate == 60/1`, `nb_frames` = 3600 ± 1, and no gaps, including while the window is idle. The same check runs at 30 fps. A 15-minute recording completes, with no time or size cap.
3. **Not exact:** resizing Terminal to a size it can't reach exits 4. The JSON shows the actual size, and the menu status row reads "not exact" with the reason.
4. **Three-call agent flow:** from Claude Code over MCP, `list_windows` → `start_recording` (with size) → `stop_recording` produces clip, events and snippet. The panel shows "Started by Claude Code over MCP" during the recording.
5. **Permissions belong to the app:** running the CLI from Terminal, iTerm and Cursor's terminal never triggers a per-terminal Screen Recording prompt.
6. **events.json:** clicks land within ±2 px of the real click position when overlaid on the video, mouse buttons are correct, and there are no keystroke fields.
7. **Snippet:** pasting `hyperframes.html` into a fresh HyperFrames project (with `--assets`) previews the clip with no edits.
8. **The HUD and region outline never appear in the clip** (checked frame by frame on a region recording that overlaps the HUD position).
9. **Menu-bar icon:** each of the five states shows its symbol, and its tooltip and VoiceOver label match the table word for word. Recording is the only tinted state, and nothing blinks.
10. **Menu panel:** the direction B panel, 300 pt wide. With a window, an update and a last clip it is 647.5 pt with the Show Control Bar row (at most 648). Recording with an update is 485.5 pt (at most 490). No window and window-closed are 323 pt. Everything shares the content edge x 16–284, and row titles start at x 40. Matches the panel states in both appearances.
11. **Picker:** tint and 2 pt outline follow the hovered window, the label shows the correct px size per display, Tab/arrows/Return/Esc work, and VoiceOver announces the window.
12. **Onboarding:** status updates live when permissions are granted in System Settings, Continue unlocks on Screen Recording, the window comes back on the same step after macOS's relaunch, and step 2 installs MCP and the skill for the checked agents only.
13. **Errors:** each row of the error copy table can be triggered, and each shows its exact title, detail and fix item. The CLI prints `error:` + `hint:` and the right exit code.
14. **Copy audit:** no "Raph" or "CTO" in any string, the name reads Skreenrek in UI copy and `skreenrek` in the CLI, MCP tools and support folder, and no placeholder is left.
15. **Distribution:** a notarized DMG installs and launches without Gatekeeper warnings (or an ad-hoc build first if credentials are missing, per the brief). The Homebrew cask installs the app and links the CLI.

## Unresolved (not blocking the build)

- **Terminal and other apps that snap to a size step** (character cells) can't always hit an exact pixel size. v1 reports it honestly (exit 4, `--allow-inexact`). Padding or cropping to the exact size is deferred.
- **Odd pixel sizes on 2× displays** are rejected in v1. Supporting them would need sub-point window frames, which macOS doesn't offer.
- **Developer ID / notarization credentials:** whether the factory already has them is Fraime Lead's check. The brief's fallback applies.

## Output format and compression (design addition, 2026-11-17)

Agents can pick the file format, codec and compression. Defaults don't change: H.264 in MP4 at `high` quality. The menu panel and Settings stay as they are; this is CLI and MCP only.

### CLI flags (on `record`)

| Flag | Values | Default |
|---|---|---|
| `--format` | `mp4` \| `mov` | `mp4` |
| `--codec` | `h264` \| `hevc` \| `prores` | `h264` |
| `--quality` | `low` \| `medium` \| `high` \| `max` | `high` |
| `--bitrate` | number of Mbps, `1`–`200`, decimals allowed (e.g. `12`, `7.5`) | none |

- `--quality` and `--bitrate` can't be combined. With `--bitrate`, the encoder targets that average bitrate. With `--quality`, the engine picks a bitrate that scales with width × height × fps, so `high` looks the same at any size.
- `prores` needs `--format mov`. It's ProRes 422, and `--quality` picks the flavour: `low` = Proxy, `medium` = LT, `high` = 422, `max` = 422 HQ. ProRes doesn't take `--bitrate`.
- `max` is the name for the "near-lossless" preset. Don't call it lossless, because it isn't.
- The clip file follows the format: `clip.mp4` or `clip.mov`. The snippet and `files.clip` point at the real file name.
- When the codec is `prores`, human output adds one line after `✓ Saved …`: `note:  ProRes doesn't play in Chrome or Firefox. Use --codec h264 for web pages.` `--json` and `--quiet` don't print it.
- Human success line, non-default case only: `✓ Saved 0:42 · 1280 × 800 px · 60 fps · HEVC MOV · 9.8 Mbps`. With the defaults it stays as it is now.

### MCP parameters (`skreenrek_start_recording`)

Added: `format?` (`"mp4"` | `"mov"`), `codec?` (`"h264"` | `"hevc"` | `"prores"`), `quality?` (`"low"` | `"medium"` | `"high"` | `"max"`), `bitrateMbps?` (number, 1–200). The defaults and rules are the same as the CLI. The output gains `video: { container, codec, profile, quality, requestedBitrateMbps }`, holding the settings as resolved at start.

### Read-back JSON

Same keys in `record --json`, `stop --json` (inside `recording`), `skreenrek_stop_recording`, and `events.json` (inside `video`):

```json
"video": {
  "file": "clip.mov",
  "container": "mov",
  "codec": "hevc",
  "profile": "main",
  "quality": "high",
  "requestedBitrateMbps": null,
  "bitrateMbps": 9.8,
  "width": 1280, "height": 800, "scale": 2
}
```

- `container` is `mp4` or `mov`, and `codec` is `h264`, `hevc` or `prores`. Both are read from the written file, not echoed from the request.
- `profile` is the codec's own profile: `high` (H.264), `main` (HEVC), or `proxy`, `lt`, `422` or `422hq` (ProRes).
- `quality` is the preset used, or `null` when `--bitrate` was given.
- `requestedBitrateMbps` is the asked-for value, or `null` with a preset.
- `bitrateMbps` is the actual average for the whole file (size × 8 ÷ duration), rounded to 0.1. It's only known after stop, so in the `record --json` / start output it's `null`.
- In `stop --json`, the existing `recording.codec` stays a plain string (same value as `video.codec`) for compatibility.

### Errors

All of these exit 2 with code `usage`, are checked before any resize or recording starts, and follow the usual shape (`error:` plus one sentence, then `hint:` plus the exact fix):

```
error: ProRes can only be saved as a .mov file.
hint:  Add --format mov, or use --codec h264 or --codec hevc.

error: Bitrate must be between 1 and 200 Mbps. You passed 500.
hint:  Pass a --bitrate from 1 to 200, or use --quality high.

error: Use either --quality or --bitrate, not both.
hint:  Drop one. --bitrate sets an exact target; --quality picks one for the window size.

error: ProRes doesn't take a bitrate. Its quality comes from --quality.
hint:  Replace --bitrate with --quality low, medium, high or max.

error: "av1" isn't a codec Skreenrek can record.
hint:  Use --codec h264, hevc or prores.

error: "webm" isn't a format Skreenrek can save.
hint:  Use --format mp4 or mov.

error: "ultra" isn't a quality preset.
hint:  Use --quality low, medium, high or max, or set --bitrate in Mbps.
```

In MCP, the same message and hint go into `{error:{code:"usage", message, hint}}`, and the hints use parameter names instead of flags (`format: "mov"`, `bitrateMbps`, `quality: "high"`).

### Menu-bar dropdown and Settings

There are no new controls; the dropdown keeps Frame Rate only. The one visible change: when the last clip isn't H.264 MP4, its Last Clip status row adds the format to the end of the detail line, in the same quiet style, and drops the clock time so the line doesn't wrap: `0:42 · 1280 × 800 px · 60 fps · H.264 MOV`. Default clips show nothing extra and keep the clock time: `0:42 · 1280 × 800 px · 60 fps · 10:24`. (Designer, 2026-11-17, replaces the earlier `… · ProRes MOV · 10:24` example.)

Status rows in the dropdown keep at least a 16 pt right inset; a detail line that doesn't fit wraps to a second line, the same as the error rows, instead of running to the menu edge. Copy is unchanged. (Designer, 2026-11-17.)

Settings: agents have their own tab (section 6, updated for 1.0.5).

### Acceptance

- `ffprobe` on each combination (h264/hevc × mp4/mov, prores × mov) reports the codec and container the read-back says, and the constant-frame-rate check from criterion 2 still passes.
- `--bitrate 8` gives an actual `bitrateMbps` within ±15% of 8 on a 60 s recording with motion.
- Each error above can be triggered, exits 2 before anything is resized, and prints that exact copy.
- With no new flags, output is identical to today: `clip.mp4`, H.264, and the same success line.
