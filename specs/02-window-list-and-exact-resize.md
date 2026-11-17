# 02: Window list and exact resize with read-back

Status: Done · Branch: lane/02-window-list-and-exact-resize · Depends on: 01 (scaffold) · Estimate: 3–5 h agent run + 0 h Raph review (no hand test) · Risk: high
Source: Designer's spec (Notion "Agent capture tool — design spec v1 (2026-11-17)", 2026-11-17), from CPO's brief (Notion "Fraime — Agent-controlled capture — brief — 2026-11-17"). Plan: Fraime Lead's "Skreenrek v1 implementation plan (2026-11-17)".

## Goal

An agent can list recordable windows, resolve one by ID or by app and title, and resize it to an exact output-pixel
size of the whole window frame, verified by reading the frame back, with up to three attempts and an honest report
when the app won't take the size. Risk is high because the real implementation uses Accessibility.

## Behaviour

1. `WindowDirectory` (Core) wraps a `WindowCatalog`:
   - Lists only normal app windows: layer 0, on screen, at least 40 × 40 pt, not owned by Skreenrek's own pid, the
     Dock, the menu bar or Window Server. Order is front to back. `app` filter matches the app name or bundle ID,
     case-insensitively.
   - `resolve(WindowQuery)`: `.id` must exist, else `window_not_found` (exit 5). `.app(name, title?)` matches name or
     bundle ID case-insensitively and `title` as a case-insensitive substring. No match → `window_not_found`; more
     than one → `window_ambiguous` (exit 5) carrying the candidates, front to back. Message:
     `2 windows match --app Safari. Pass a window ID:` and one line per candidate `<id>  <app>  <title>  <w> × <h> px`.
   - Each window's display is the display containing the largest part of its frame; its pixel size is
     `round(pt × scale)`.
2. `SizeRequest` validation (Core), before any resize: width and height are whole px from 2 to 16384. On a display of
   scale s, each must be divisible by s, else `usage` (exit 2), message `Width 1281 px is odd. On a 2× display sizes
   must be even.`, hint `Use 1280 or 1282 px.` (same for height). Points are `px ÷ scale`.
3. `ExactResizer` (Core, uses `WindowResizer`):
   - Target frame: same top-left origin, size `px ÷ scale` pt. If the target would cross the display's visible frame
     edge, first move the origin so the frame starts inside the visible frame (top-left corner of the visible frame
     at worst).
   - Attempt: `setFrame`, then `readFrame`; actual px = `round(pt × scale)`. Exact means both dimensions are
     pixel-equal (0 px tolerance). Up to 3 attempts; stop at the first exact read-back.
   - Result is a `Readback` (requested, actual, frame in pt, display, exact, attempts).
   - Not exact after 3 attempts → `not_exact` (exit 4) unless `allowInexact`, in which case the read-back is returned
     with `exact: false`. The reason uses the design spec's copy: `Safari can't be narrower than 1286 px. It is
     1286 × 800 px now.` (actual wider than asked), `can't be wider than` (narrower), `shorter`/`taller` for height,
     and `Terminal resizes in steps, so 1280 × 800 px isn't possible. It is 1281 × 798 px now.` when actual differs in
     both directions or alternates between attempts. Hint: `Pick a width of 1286 px or more, or pass --allow-inexact.`
     (adapted per reason).
4. Real implementations in `SkreenrekSystem` (thin):
   - `SCWindowCatalog`: `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)`, mapping
     `SCWindow` to `WindowInfo`; displays from `NSScreen.screens` (`backingScaleFactor`, `CGDirectDisplayID`, frames
     converted to top-left global pt with `ScreenGeometry`). A ScreenCaptureKit permission failure maps to
     `permission_denied` (Screen Recording).
   - `AXWindowResizer`: `AXUIElementCreateApplication(pid)`, `kAXWindowsAttribute`, matching the target by title and
     frame (public API only, no `_AXUIElementGetWindow`), then `kAXPositionAttribute` and `kAXSizeAttribute`, and
     reading both back. `AXIsProcessTrusted()` false → `permission_denied` (Accessibility). No prompt.
   - `ScreenGeometry` (Core, pure): AppKit bottom-left screen frames ↔ top-left global pt.
5. `LiveResizeTests` (opt-in, `SKREENREK_LIVE=1` and Accessibility already granted): resizes a window the test opens
   itself to 800 × 600 px and expects `exact: true`. Skipped otherwise.

## Defaults

- Three attempts, no delay between attempts beyond awaiting the AX calls (no sleeps).
- A requested size larger than the display's visible frame is still attempted; the read-back reports what happened.
- The JSON read-back uses the design spec's field names, `unit` fields included.

## Guardrails

- `ExactResizer` never reports `exact: true` without a read-back that matches to the pixel.
- No Accessibility or ScreenCaptureKit call in `SkreenrekCore`; tests use `FakeWindowCatalog` and `FakeWindowResizer`.
- No private API.

## Out of scope

CLI wiring and exit handling (06), the picker (10), recording (03), padding or cropping inexact windows (v2).

## Open question (built with the default)

- Window identity across AX and ScreenCaptureKit: match by pid, title and frame. If two AX windows match equally, fail
  with `window_ambiguous` rather than guess.

## How to test (Raph)

1. No hand test is needed to merge: CI `factory check` (`make check` on macos-15) must be green. The tests cover, with
   fakes: 1× and 2× displays, 1280x800 / 1920x1080 / 1080x1920 exact on the first attempt, an app that ignores the
   first attempt (exact, `attempts: 2`), a minimum width of 1286 px (exit 4, exact copy), a terminal-style 7 × 14 px
   step (exit 4), `allowInexact` (no error, `exact: false`), an odd width on 2× (exit 2), not found and ambiguous
   (exit 5), the off-screen origin move, and a golden read-back JSON.
2. Optional smoke (needs Accessibility for the test runner, about 2 min): `SKREENREK_LIVE=1 swift test --filter Live`.

## Implementation notes

- **Core** (`Sources/SkreenrekCore/Windows/`): `WindowDirectory` (filter, front-to-back order, display assignment,
  `resolve`), `ResolvedWindow` (window + display), `SizeRequest`, `ExactResizer`, `ScreenGeometry` and
  `AXWindowMatch` (the pure AX-to-listed-window matching the real resizer uses). All tested with the fakes.
- **`WindowInfo.layer`** was added (init default `0`, decodes as `0` when missing) so the layer-0 filter lives in Core,
  not in the ScreenCaptureKit mapping. Existing call sites are unchanged.
- **System filter set:** the Dock, the menu bar and Window Server are excluded by app name (`Dock`, `SystemUIServer`,
  `Control Center`, `Window Server`) or bundle ID (`com.apple.dock`, `com.apple.systemuiserver`,
  `com.apple.controlcenter`), on top of the layer-0 rule that already drops most of them.
- **Front to back:** `SCShareableContent` doesn't document its order, so `SCWindowCatalog` sorts by the window
  server's on-screen list (`CGWindowListCopyWindowInfo`, IDs only, no permission) through
  `WindowDirectory.ordered(_:byZOrder:)`.
- **Display:** largest overlap wins; a frame on no display gets the nearest display.
- **Query wording in messages:** `4127` for an ID, `--app Safari`, `--app Safari --title "localhost"` (the CLI
  syntax), e.g. `No window matches --app Safari --title "nope".`
- **Size validation:** the 2× copy is the design spec's, verbatim. Out of range (not in the design spec):
  `Width 0 px is out of range. Sizes go from 2 to 16384 px.` / `Use a width from 2 to 16384 px.` Other integer
  scales (none ship today) say `doesn't fit a 3× display … whole points (px ÷ 3)` with the same `Use A or B px.` hint.
- **Visible-frame move:** if the target crosses the visible frame's right or bottom edge it moves left/up; then it is
  clamped so it starts inside the visible frame (its top-left corner at worst). A frame bigger than the visible frame
  is still attempted at that corner.
- **Not-exact reason:** taken from the last read-back. Steps when both dimensions are off, or when the size differs
  between attempts 2 and 3 (attempt 1 may be ignored by the app, as in the `attempts: 2` case); otherwise min/max
  for the one dimension that is off. The hint for steps is spec 01's `Pick another size, or pass --allow-inexact.`
- **`AXWindowResizer`:** checks `AXIsProcessTrusted()` (no prompt), lists `kAXWindowsAttribute` for the pid, and
  matches by title and frame (±1 pt), then title alone, then frame alone; two equal matches are `window_ambiguous`.
  The matched element is cached per window ID, because after the first `setFrame` the frame no longer matches the
  listing. It sets position, size, then position again (some apps shift while resizing). `apiDisabled` →
  `permission_denied`, `invalidUIElement` → `window_not_found`, other AX errors → `internal`.
- **`SCWindowCatalog`:** `SCStreamError.userDeclined` → `permission_denied` (Screen Recording); other failures →
  `internal`. Displays come from `AppKitDisplays.current()` (`NSScreen`, main actor, via `ScreenGeometry`).
- **`LiveResizeTests`** is in a new `SkreenrekSystemTests` target (`Package.swift`). It opens its own resizable window
  in a child `osascript` process (JXA Cocoa bridge), so AX talks to a process with a running event loop, reads its
  bounds from `CGWindowListCopyWindowInfo` (no permission needed), and resizes it to 800 × 600 px. Skipped unless
  `SKREENREK_LIVE=1` and `AXIsProcessTrusted()`; not run here (it needs the grant).
- `make check`: 87 tests in 14 suites pass, no warnings on a clean build (Swift 6.2.3); the live suite is skipped.
