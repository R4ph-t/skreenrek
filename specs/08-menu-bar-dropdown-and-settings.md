# 08: Menu-bar icon, dropdown, Settings and the ⌃⌘⎋ stop shortcut

Status: Ready · Branch: – · Depends on: 05 (controller) · Estimate: 5–7 h agent run + 0 h Raph review (no hand test)
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
   Copy File Path, Copy HyperFrames Snippet). Size submenu and Frame Rate submenu exactly as specified; Custom Size…
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
   states (symbol, tint, sentence), `MenuModel` entries and copy for every state and error row, the Size and Frame
   Rate submenus, the copy audit, `SettingsStore` round trips, and `debug render-ui` producing non-empty PNGs of the
   expected sizes (300 pt wide rows, 48 pt status rows) in both appearances.
2. Optional smoke (after hand spec 11, 3 min): open Skreenrek.app, open the menu in light and dark, pick a size, open
   Settings.

## Implementation notes

_(filled in by the agent)_
