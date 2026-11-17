# 10: Window picker overlay, recording HUD and permissions onboarding

Status: Done · Branch: lane/10-picker-hud-and-onboarding · Depends on: 08 (menu bar), 09 (agent setup) · Estimate: 6–8 h agent run + 0 h Raph review (no hand test) · Risk: high
Source: Designer's spec (Notion "Agent capture tool — design spec v1 (2026-11-17)", 2026-11-17), from CPO's brief (Notion "Fraime — Agent-controlled capture — brief — 2026-11-17"). Plan: Fraime Lead's "Skreenrek v1 implementation plan (2026-11-17)".

## Goal

A person can pick a window or a region with the overlay, sees a calm recording HUD with a Stop button that never
appears in the clip, and gets a two-step onboarding that asks for Screen Recording and Accessibility and connects
agents, all as in the design spec's sections 3–5 and the picker, indicator and onboarding mockups. Risk is high
because onboarding triggers the macOS permission prompts.

## Behaviour

1. `PickerModel` (pure): from the window list (front to back, without Skreenrek's own windows, the menu bar or the
   Dock) and the pointer, the hovered window; Tab or arrow keys move front to back, Return picks, Esc cancels. Label
   line 1 `App — Window title`, line 2 `1280 × 800 px · Click to pick` using that window's display scale. Dragging
   switches to region mode with a live px size chip; regions snap to even pixel sizes. VoiceOver text
   `Safari, localhost:3000, 1280 by 800 pixels. Press Return to pick.`
2. `PickerOverlay` (AppKit, thin): one borderless, non-activating panel per display above normal windows, no
   dimming; accent tint at 18% plus a 2 pt inside accent stroke following the window's corner radius; the 280 × 56 pt
   HUD-material label; the 44 pt hint bar (`Click a window, or drag to pick a region.` · `Esc to cancel` ·
   [Cancel]). It implements the controller's `WindowPicker` seam: "Pick Window…", `skreenrek pick` and
   `skreenrek_pick_window` (with its timeout) all use it. Picking arms the window; it never starts recording.
3. `HUDModel` (pure) for the four states in the design spec's table (Recording with elapsed `m:ss` and Stop; Writing
   "Saving clip…"; Saved "Saved · 0:42" with Show in Finder, fading after 4 s or 8 s while hovered; Error "Stopped:
   <reason>" with Show Details, staying until dismissed). `HUDPlacement` (pure): centred 16 pt below the recorded
   window, or 16 pt inside the bottom of that screen when there's no room; a dragged position is remembered per
   display. Reduce Motion: no fades, and the spinner becomes a static `arrow.down.circle`. Increase Contrast: 2 pt
   strokes, opaque borders.
4. `RecordingHUD` (AppKit/SwiftUI, thin): 36 pt tall, radius 10, HUD material; one accessibility element
   ("Recording Safari, 12 seconds") with one action, Stop. Hidden with Settings' "Show recording indicator" off or
   `--no-hud` / `hud: false`. For region recordings a 1 pt system-red outline marks the region. Both windows belong to
   Skreenrek, so 03's filters keep them out of the clip (window captures include only the target window; region
   captures exclude Skreenrek's own app); a test asserts the filter plan excludes Skreenrek's pid.
5. `OnboardingModel` (pure, over `PermissionProbe` and a `PermissionRequester` seam): step 1 "Set up Skreenrek" with the
   two rows, their exact copy and live status (probe polled every second while the window is open), Continue enabled
   once Screen Recording is allowed; step 2 "Connect your agents" with a checkbox per detected agent and the
   command-line tool, calling 09's installer on Connect, or Skip. The current step persists so the window reopens on
   it after macOS's "Quit and reopen". The window (520 × 496 pt) shows on first launch, and when the controller rejects
   an action for a missing permission (the CLI or MCP call still fails with exit 3).
6. Real `PermissionRequester` (`SkreenrekSystem`): Screen Recording → `CGRequestScreenCaptureAccess()` then open the
   Screen Recording privacy pane; Accessibility → `AXIsProcessTrustedWithOptions` with the prompt option, then open
   the Accessibility pane. Only called from an onboarding or Settings button press.
7. `debug render-ui` (08) also renders the picker label and hint bar, the four HUD states and both onboarding steps,
   light and dark, at 2×.

## Defaults

- Accessibility is asked for but not required: without it, recording works at the current size and resize returns
  exit 3 with the "Can't resize windows" copy.

## Guardrails

- No permission request outside a user's button press in onboarding or Settings; tests use a fake requester and never
  call the real APIs.
- The overlay and HUD never become key windows that steal focus from the recorded app.
- All copy goes through the strings file and passes 08's copy audit.

## Out of scope

Editing, trimming, pause/resume, keystroke capture, a notarized build.

## Open question (built with the default)

- Overlay window level: above normal and floating windows, below the screen saver; the menu bar stays usable.

## How to test (Raph)

1. No hand test is needed to merge: CI `factory check` must be green. The tests cover `PickerModel` (hover, keyboard,
   region drag with even snapping on 1× and 2×, exclusions, label and VoiceOver text), `HUDModel` states and timings,
   `HUDPlacement` (below, no room, remembered drag), the filter plan exclusion, `OnboardingModel` (live status,
   Continue gating, persisted step, Connect calling the installer with the checked agents only), and `render-ui`
   output for every new surface in both appearances.
2. Optional smoke, your first real use (5 min): open Skreenrek.app, allow Screen Recording and Accessibility when
   macOS asks, pick a window, record 5 s from the menu, and stop with ⌃⌘⎋.

## Implementation notes

- `PickerModel` owns front-to-back hover/keyboard selection, exclusions, display-local even-pixel region snapping,
  copy and VoiceOver text. The menu, CLI and MCP share `PickerOverlay`; picking only arms the target. Label/chip
  decorations pass pointer events through so a drag can start over the label. The keyboard registrations and bounded
  picker timeout are removed on selection, cancellation or timeout.
- Built the overlay-level default: one nonactivating, non-key panel per display at `mainMenu - 1`, above floating
  windows and below the menu bar and screen saver. Panels cover the visible screen area, leaving the menu bar and
  Dock usable. The hover uses an inside 2 pt accent stroke (3 pt with Increase Contrast), 18% tint and a 10 pt corner
  radius; AppKit's window catalogue does not expose individual windows' corner radii.
- `HUDModel` and `HUDPlacement` keep state, monotonic saved deadlines, hover extension and per-display dragged
  positions separate from presentation. The 36 pt HUD and region outline never take key/main status. Settings and
  the active recording's `hud` option suppress both; region capture excludes Skreenrek by PID even without a bundle
  ID. Reduce Motion uses the static writing symbol and no fade; Increase Contrast thickens strokes and the HUD border.
- `OnboardingModel` persists the current step and completion. The window polls the read-only probe every second
  while open; only Screen Recording gates Continue. A separate requester runs only from onboarding/Settings buttons.
  Permission rejections open step 1 while control clients retain exit 3. The real window catalogue checks permission
  before asking ScreenCaptureKit for content, preventing an implicit prompt from an agent request.
- Connect passes only checked, detected clients to spec 09's installer (an empty selection never invokes its
  all-detected default). Failed installs stay on step 2 with the installer's details; Skip finishes without installing.
- Every dropdown status row reserves a 16 pt trailing inset. Long detail text uses the existing two-line/64 pt layout,
  including `armednotexact`, with the copy unchanged.
- `debug render-ui` covers window/keyboard/region/empty picker states, contrast variants, all four HUD states plus
  Reduce Motion/contrast and region outlines, and both onboarding steps with every permission combination, in light
  and dark at 2×. Tests check geometry, transparency, dimensions, copy, exclusion, persistence, installer selection,
  control error delivery and status wrapping. All test waits have watchdogs; live capture tests remain opt-in.
- Validation uses `make check` on the Devin macOS VM, including offscreen renders and synthetic video tests. No app
  launch, real capture, permission request or manual smoke test is required or performed for this lane.
