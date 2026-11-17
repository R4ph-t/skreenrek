# 08: Menu-bar icon, dropdown, Settings and the ⌃⌘⎋ stop shortcut

Status: Done · Branch: lane/08-menu-bar-dropdown-and-settings · Depends on: 05 (controller) · Estimate: 5–7 h agent run + 0 h Raph review (no hand test)
Source: Designer's spec (Notion "Agent capture tool — design spec v1 (2026-11-17)", 2026-11-17), from CPO's brief (Notion "Fraime — Agent-controlled capture — brief — 2026-11-17"). Plan: Fraime Lead's "Skreenrek v1 implementation plan (2026-11-17)".

## Goal

Skreenrek runs as a menu-bar-only app whose icon and native dropdown show and drive the controller exactly as in the
design spec's "Menu-bar icon", "Dropdown" and "Settings" sections and the dropdown and icon mockups, in light and dark.

## Behaviour

1. New library target `SkreenrekUI` (depends on Control; AppKit and SwiftUI allowed here) and test target
   `SkreenrekUITests`. Running the app (06's dispatch) starts the controller, the control server and the menu bar
   (LSUIElement-style: no Dock icon, no main window).
2. `StatusIconModel` (pure) maps a `ControllerSnapshot` to the design spec's five states: symbol (`record.circle`,
   `viewfinder`, `record.circle.fill`, `arrow.down.circle`, `exclamationmark.triangle`), template or red tint
   (recording only), elapsed `m:ss` in SF Mono 12 pt while recording, and the tooltip / VoiceOver sentence word for
   word (`Skreenrek is ready. No window picked.`, `Skreenrek is ready to record Safari at 1280 × 800 pixels.`,
   `Skreenrek is recording Safari. 12 seconds.`, `Skreenrek is saving the clip.`, `Skreenrek stopped recording: <reason>.`).
   Elapsed text updates once a second; the VoiceOver value every 10 s. Nothing blinks. Clicking the icon only opens
   the menu.
3. `MenuModel` (pure) builds the dropdown as a list of entries (status row, item, header, separator, submenu) for:
   idle; armed exact; armed not exact (`1286 × 800 px · not exact (min width 1286 px)`); recording (status row, the
   disabled "Started by Claude Code over MCP" / "Started from the menu" / "Started from the command line" row, Stop
   Recording ⌃⌘⎋ as the default item, Discard Recording…, Open Output Folder, Settings…, Quit); writing; each of the
   six error rows in the design spec's error-copy table with its fix items; and the Last Clip section (Show in Finder,
   Copy File Path, Copy HyperFrames Snippet). When the last clip isn't H.264 MP4, the status row's detail line
   appends the format in the same quiet style (`0:42 · 1280 × 800 px · 60 fps · ProRes MOV · 10:24`); default
   H.264 MP4 clips keep `0:42 · 1280 × 800 px · 60 fps · 10:24` (Designer's 2026-11-17 addition; labels
   `H.264` / `HEVC` / `ProRes` and `MP4` / `MOV`). A missing container (clips from before spec 12) is treated
   as `mp4`. No new dropdown or Settings controls. Size submenu and Frame Rate submenu exactly as specified; Custom Size…
   opens a sheet with px fields and the pt equivalent in 12 pt secondary text. Choosing a size while armed resizes
   immediately through the controller. Size, frame rate and picking are hidden while recording.
4. `MenuController` (AppKit, thin) renders `MenuModel` into an `NSStatusItem` with an `NSMenu`: 300 pt wide, 24 pt
   rows, status rows as custom 48 pt views (8 pt padding, 13 pt title, 12 pt secondary detail, 16 pt symbol column,
   text starting at 32 pt). SF Pro and SF Symbols only. The error state clears after the menu is opened and closed
   once, or on the next action.
5. Alerts with the design spec's copy: "Discard this recording?" (destructive Discard), and "Stop and save the
   recording before quitting?" [Cancel] [Stop and Quit] when quitting while recording.
6. Settings: one SwiftUI grouped `Form` window, 480 pt wide, rows: Output folder [Choose…], Default frame rate
   (segmented 30 / 60 fps), Show cursor in video, Write click events, Show recording indicator, Open at login
   (`SMAppService.mainApp`; a failure shows inline under the row), Stop shortcut ⌃⌘⎋ (shown, not editable),
   Permissions (the two rows with status and an Open System Settings… button that opens the matching Privacy pane
   URL), and a footer with the version. No "Check for Updates" in v1. Values persist in a `SettingsStore` over an
   injectable `UserDefaults` and feed the controller's defaults.
7. Stop shortcut ⌃⌘⎋: a Carbon `RegisterEventHotKey` hot key (no Accessibility needed), registered while a
   recording runs and released after. If registration fails, the menu item still works and the failure is logged.
8. Hidden `skreenrek debug render-ui --out DIR` renders the status rows, a composed dropdown for each state, and the
   Settings window to PNG at 2× in light and dark (`NSHostingView`/`cacheDisplay`, appearance forced), file names
   `<surface>-<state>-<light|dark>@2x.png`. This is how screenshots reach Designer without a hand session.

## Defaults

- AppKit `NSStatusItem` + `NSMenu` rather than SwiftUI `MenuBarExtra`: `MenuBarExtra`'s menu style can't host the
  48 pt custom status rows the design asks for, while `NSMenu` keeps native keyboard, VoiceOver and Tahoe styling.
- Agents rows in Settings arrive with 09.

## Guardrails

- All copy comes from one strings file in `SkreenrekUI` so a test can audit it: no "Raph", no "CTO", no `<name>`
  placeholder, Skreenrek spelled the same everywhere.
- View logic lives in the pure models; AppKit classes only render them.
- No permission prompt from the menu or Settings (opening System Settings is not a prompt).

## Out of scope

Picker overlay, recording HUD and onboarding (10); Agents rows (09); Sparkle updates (later, notarized builds only).

## Open question (built with the default)

- `MenuBarExtra` versus `NSMenu`: `NSMenu` (see Defaults).
- The hot key is registered only while recording, so it never shadows macOS's own ⌃⌘⎋ at other times.

## How to test (Raph)

1. No hand test is needed to merge: CI `factory check` must be green. The tests cover `StatusIconModel` for the five
   states (symbol, tint, sentence), `MenuModel` entries and copy for every state and error row, the Last Clip
   detail line with and without a non-default format suffix, the Size and Frame Rate submenus, the copy audit,
   `SettingsStore` round trips, and `debug render-ui` producing non-empty PNGs of the expected sizes (300 pt wide
   rows, 48 pt status rows) in both appearances.
2. Optional smoke (after hand spec 11, 3 min): open Skreenrek.app, open the menu in light and dark, pick a size, open
   Settings.

## Implementation notes

- **Layout.** `Sources/SkreenrekUI`: `UIStrings` (every string), `MenuContext` + `StatusIconModel` + `MenuModel` +
  `CustomSizeModel` (pure), `SettingsStore` (`UserDefaults`, injectable), `AppModel` (main-actor state and actions over
  the controller, with a `UIEffects` seam for Finder, pasteboard, alerts and panels), and thin AppKit/SwiftUI
  renderers: `MenuController` (`NSStatusItem` + `NSMenu`), `StatusRowView`, `SettingsView`, `CustomSizeView`,
  `StopHotKey` (Carbon), `SystemEffects`, `MenuBarApp`, `UIRenderer`. Tests: `Tests/SkreenrekUITests` (64 tests).
- **Dispatch.** 06's `LaunchMode` `.app` (a Finder or `open` launch, or `skreenrek app`) now runs the menu-bar app
  (controller, control server, menu bar, `.accessory` activation policy) instead of the headless host. The hidden
  `skreenrek debug render-ui --out DIR` is matched in `main.swift` before the CLI parser, because it draws with
  AppKit on the main thread and the CLI target doesn't depend on `SkreenrekUI`.
- **Open questions, built with the defaults:** `NSMenu`, not `MenuBarExtra`; the ⌃⌘⎋ hot key is registered only
  while recording, and a failed registration is logged (the menu item still stops).
- **Errors the menu shows.** The controller only holds recording failures, so `AppModel` keeps the error from an
  action the menu started (pick, resize, record) as `actionError`. Both clear after the menu opens and closes once,
  or on the next action. Rows not in the error-copy table: `recording_failed` with another cause uses "Recording
  stopped" + Show in Finder · Copy Error Details; any other error uses "Something went wrong", its message and Copy
  Error Details (which copies the CLI's `error:` / `hint:` lines). "Pick Another Size…" opens Custom Size….
- **Icon sentences.** Beyond the spec's examples: durations over a minute read `1 minute 5 seconds`; a region reads
  "a screen region"; the error reason is the cause in lower case (`the window closed`, `less than 2 GB free`, `the
  output folder isn't writable`, `Screen Recording is off`, …). Tooltip and VoiceOver are pushed on each state
  change and every 10 s while recording; the elapsed `m:ss` beside the symbol updates every second (a common-mode
  timer, so it moves while the menu is open). Recording uses `record.circle.fill` with a hierarchical system-red
  tint; every other state is a template image.
- **Size.** The Size row shows the current choice right-aligned (`1280 × 800 px`, or "Keep Current Size"). The
  choice persists (`nextSize`; not a Settings row). Picking a window does not resize it; choosing a size while armed
  resizes immediately with `allowInexact`, so a size the app can't reach shows in the status row as `… · not exact
  (min width 1286 px)`. Record Window resizes first to the chosen size unless the armed read-back already asked for
  it; that resize is strict, so an unreachable size shows the "Size isn't exact" row. A just-picked window without a
  read-back shows its size alone (no "exact size" claim). Custom Size… is a small panel rather than a sheet (a
  menu-bar app has no window to hang a sheet on); it validates with `SizeRequest`, so odd sizes on 2× are refused
  with the CLI's wording.
- **States without copy in the design spec.** Writing: `arrow.down.circle` · "Saving clip…" (the HUD's wording) ·
  `0:42 · 1280 × 800 px · 60 fps`, the origin row, then Open Output Folder · Settings… · Quit. MCP with no client
  name: "Started over MCP". The Last Clip section is hidden while recording and writing. Quit reads "Quit
  Skreenrek ⌘Q" in every state.
- **Last Clip.** The title is remembered from the recording's window (`LastClipTracker`), falling back to the
  read-back, then the clip ID. The time is the clip's local start time in the Mac's short time style. The format
  suffix reads the codec from `recording.codec` (labels H.264 / HEVC / ProRes, ready for 12's `prores`) and the
  container from the clip's file extension (`.mov` → MOV, anything else → MP4), since `StopBody` has no container
  field before 12. A non-default suffix makes the detail too long for one line at 12 pt, so that row wraps to 64 pt.
- **Metrics.** 300 pt menu; status rows 48 pt (64 pt when the detail wraps), 8 pt vertical padding, 16 pt symbol
  column at 12 pt, text at 32 pt, running to 4 pt from the right edge so `1286 × 800 px · not exact (min width
  1286 px)` fits on one line in SF Pro. Native `NSMenu` items keep AppKit's own row height (it can't be set); the
  rendered dropdowns use 24 pt. `NSMenu` has no default-item API, so Stop Recording is flagged `isDefault` in the
  model and is the first actionable item.
- **Alerts.** Discard: [Cancel] [Discard], Discard destructive, Return doesn't discard, Esc cancels. Quit while
  recording: [Cancel] [Stop and Quit] → stop and save, then quit; quitting while a clip is written waits for it.
- **Settings.** Checkbox toggles, segmented frame rate, output folder shown with `~`. Open at login failures show
  "Skreenrek couldn't be added to your login items." (or "removed from") under the row; an unbundled build always
  fails here. Permission rows read the probe (never prompt) and refresh when Skreenrek becomes active again. Footer:
  "Skreenrek 0.1.0". The dropdown's Frame Rate, Show Cursor and Write Click Events write the same stored values as
  Settings; every change is pushed to `controller.updateSettings`.
- **`render-ui`.** Writes `menubaricon-<state>`, `statusrow-<state>`, `dropdown-<state>` for 13 states (idle,
  lastclip, lastclipmov, armed, armednotexact, recording, writing, and the six error rows), `submenu-size`,
  `submenu-framerate` and `settings-default`, each `-light` and `-dark@2x.png`. An offscreen `NSMenu` can't be drawn,
  so dropdowns are composed from the same `MenuEntry` list and `StatusRowView`, on a solid stand-in for the menu
  material (radius 10).
