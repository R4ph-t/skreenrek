# Skreenrek control bar: spec, 18 Nov 2026

Status: Active (design). Target: `docs/design-spec.md`, new section "Control bar", after "On-screen selected outline".
Brief: CPO, *skreenrek: control bar under the picked window* (Bot Docs, 2026-11-18). Raph, 14:01 Paris: "somethign that would be cool is a controler at the bottom of the seletected window. to change the sieze and start the rec" (verbatim, relayed by Fraime Lead).
Builds on: *Skreenrek 1.0.5 menu panel and Settings spec 2026-11-18* (panel rows, outline §4, strings), `addendum-solid-panel-2026-11-18.md` (opaque surfaces: every fill, hairline, shadow, radius and hover below comes from it), spec 13 v2 (presets are exact clip px, presets that don't fit are disabled with a tooltip).
Code baseline: `R4ph-t/skreenrek` main at `a7ad1af` (`SelectionOutlineModel.swift`, `SelectionOutlineWindow.swift`, `RecordingHUD.swift`, `HUDModel.swift`, `PanelModel.swift`, `MenuPanelView.swift`, `SettingsStore.swift`, `SettingsView.swift`, `UIStrings.swift`, `SizePreset`/`WindowFitFailure` in `WindowFit.swift`). Copy comes from `UIStrings` unless it's marked **new**.
Sequencing: per the lead (2026-11-18 14:13), this is built now. It no longer waits for v1 core-capture acceptance.
Amended by: [`addendum-1-2026-11-18.md`](addendum-1-2026-11-18.md) (after PR #47 at `11f9be4`), folded into the sections below. Its item 8 is about the picker's size chip, not the bar: see `docs/design-spec.md`.
Amended by: [`addendum-2-2026-11-19.md`](addendum-2-2026-11-19.md) (red recording outline, Clear on the bar, Saved on the bar), folded into §2, §3, §3.2, §7 and §8. Where this spec and addendum 2 disagree, the addendum wins.
Box folder: `/workspace/design-skreenrek-controlbar-2026-11-18/` (`renders/`, `redlines/`, `boards/`, `src/`). The mockups use Inter in place of SF Pro (tabular figures stand in for `.monospacedDigit()`) and hand-drawn stand-ins for SF Symbols. Build with the system font and real symbols.

## 1. What it is
A small, opaque, floating bar centred under the picked window. It holds the Size preset menu, the clip size readout and Record. While recording it holds an elapsed timer and Stop. It lets Raph pick a window, size it and start or stop a recording without going to the menu bar. Agents keep using the CLI and MCP, which don't change.

## 2. Anatomy and sizes (pt). Redlines: `redlines/redline-{idle,recording}-{light,dark}@2x.png`
| Part | Size | Notes |
|---|---|---|
| Bar | **336 × 36** (228 × 36 compact) | r**10** continuous. Horizontal padding 6, vertical padding 6. Gaps of 12 between the slots and Clear. The width is the same in idle, recording, saving, Saved and disabled, so the bar never jumps when the state changes. (Was 300 / 192 before Clear, PR #51, addendum 2 §B.) |
| Slot 1 (idle): **Size pop-up** | 84 × 24, r6 | Cell fill. Value: preset name, 13 medium, at x 8 inside the slot. `chevron.up.chevron.down` 9 pt semibold secondary, right edge 8 from the slot's end. No "Size" label (the bar is too small and the value is self-evident). VoiceOver supplies "Size". |
| Slot 1 (recording): **status** | 84 × 24 | Red dot 8 pt `systemRed` at bar x 14. Timer 13 regular `labelColor` `.monospacedDigit()` at bar x 30 (dot + 8). Format `TimeFormat.elapsed`, the QuickTime pattern: m:ss under an hour (`0:12`, `59:59`), h:mm:ss from an hour (`1:02:03`). All fit in the slot, so the bar stays 300 wide and the readout doesn't move. |
| Slot 2: **readout** | 96 wide, text centred, 15 tall | 12/15 `secondaryLabelColor` `.monospacedDigit()`: `1920 × 1080 px`. 96 fits any 4 + 4 digit size, so changing presets doesn't change the width. It's the first thing dropped (§5). |
| Slot 3: **Record / Stop** | 84 × 24, r6 | Record: solid `controlAccentColor`, white Skreenrek mark 16 pt (the same mark as the panel's Record), 6, `Record` 13 semibold, centred. Stop: solid `systemRed`, white 10 pt rounded square (r2), 6, `Stop` 13 semibold, centred. |
| **Clear** | 24 × 24, r6 | `xmark` at the trailing edge, the same borderless icon button as Saved's folder and copy in every state: no cell at rest, only the panel's hover 8%/5% and pressed 12%/9% tones. Tooltip `Clear Window`, VoiceOver `Clear picked window` (the panel's strings). Action = the panel's Clear: the pick is dropped, and the bar and the outline go away. **Hidden** (not just disabled) while recording and saving; its slot stays, so nothing reflows. Shown again in Saved. |
| Bar x positions | 6 · 90 · 102 · 198 · 210 · 294 · 306 · 330 | Slot edges inside the 336 pt bar (Clear at 306–330; compact: 6 · 90 · 102 · 186 · 198 · 222). |

Radii: 10 for the bar, 6 for the controls, 4 for the tooltip. Nothing else. The controls use r6 rather than a concentric r4, so they match every other 24 pt control in Skreenrek (Settings push buttons and segmented controls).
Type: 13 (values, timer, button labels) and 12 (readout, tooltip). Nothing else.

### Surface and colours (all opaque, from the solid-panel addendum)
| Token | Light | Dark |
|---|---|---|
| Bar fill | #F6F6F8 | #1E1E20 |
| Bar hairline (1 px inside) | black 10% | white 10% (25% with Increase Contrast) |
| Bar shadow (one) | black 15%, blur 20, y 6 | black 35%, blur 24, y 8 |
| Pop-up cell | #FFFFFF + 1 px black 8% hairline | #2C2C2F |
| Pop-up pressed (menu open) | cell darkened 12% | cell darkened 12% |
| Record | `controlAccentColor`, hover −6%, pressed −12% | same |
| Stop | `systemRed`, hover −6%, pressed −12% | same |
| Disabled Record | cell fill + hairline, label `tertiaryLabelColor`, `exclamationmark.triangle.fill` in `systemOrange` | same |
| Pop-up hover | cell + row hover overlay (black 5% / white 8%) | same |

No NSVisualEffectView, no material, no vibrancy.

## 3. States. Renders: `renders/bar-*-{light,dark}@2x.png`
| State | Render | Slot 1 | Slot 2 | Slot 3 |
|---|---|---|---|---|
| **Idle** (window picked, ready) | `bar-idle-below` | Size pop-up, e.g. `1080p` | `1920 × 1080 px` | Record |
| **Custom size** (not a preset, e.g. Current Size or Custom… from the panel) | `bar-narrow` shows `Custom` | `Custom` (`Panel.custom`), no checkmark in the menu | the exact px | Record |
| **Resizing** (a preset was just chosen, waiting for the read-back) | — | new preset name | the previous px at 50% opacity | Record disabled, no triangle. ≤ 1 s, so no spinner |
| **Not exact** (read-back differs from the preset) | — | preset name | the actual size **without the " px" suffix** (`1286 × 800`), with an `exclamationmark.triangle.fill` 12 pt `systemOrange` 4 pt before it, centred as one group in the 96 slot (12 + 4 + ≈ 74 fits). Tooltip `Menu.notExactReason`. The same layout is used for Resize refused | Record |
| **Resize refused** (the app didn't change size at all) | — | reverts to the previous value | triangle + previous size for 4 s, then plain `W × H px` | Record |
| **Disabled** (Record unavailable) | `bar-disabled` | Size pop-up (still usable) | px | Disabled Record: triangle replaces the mark. Tooltip carries the reason (§3.1) |
| **Recording** | `bar-recording` | status: dot + timer | px (unchanged) | Stop |
| **Saving** (writing the file) | `control-bar-saving` in `render-ui` | Slots 1 and 2 become one area (bar x 6–198). `ProgressView` small (16), or `arrow.down.circle` under Reduce Motion, sits directly left of `Saving clip…` (`Menu.savingClip`, 12/15 secondary) with a 6 pt gap, and the pair is centred together in that area. The indicator is never pinned to the left edge | (part of the area) | Record disabled, no triangle. Turns into Saved when the clip is written (§3.2) |
| **Saved** (the clip was just written, bar on screen) | `control-bar-saved`, `-saved-compact`, `-saved-copied` | Status area 6–198: `checkmark.circle.fill` 16 `systemGreen` at x 14, `Saved · 0:07` 13 medium at x 36, `folder` 146–170, `doc.on.doc` 174–198 | (part of the area) | Record, enabled. × shown |

The size control is **hidden** while recording and saving: the timer takes its slot. Size can't change mid-clip. Clear is hidden too, in the same slot.

### 3.2 Saved on the bar (addendum 2, §C)
If the bar is on screen when a save finishes, the bar turns into Saved and the HUD's Saved doesn't appear. Otherwise (region and full-screen clips, bar off or hidden, an agent's recording that dropped the pick) the HUD shows Saved as before. `--no-hud` or Show recording indicator off: neither.
- Same frame, surface and padding. Nothing moves: the spinner crossfades into the check and `Saving clip…` into `Saved · 0:07` over 0.2 s, and the buttons, Record and × fade in with them.
- Icon buttons 24 × 24, r6, no fill at rest, the panel's hover and pressed tones. Show in Finder (tooltip and VoiceOver `Show in Finder`) reveals the file and ends Saved. Copy (tooltip `Copy File Path`, VoiceOver `Copy file path`) copies the path, and its glyph reads `checkmark` with `Copied` for 1.5 s.
- Compact (228): slot 1 is the check and `Saved`, and the duration moves into the tooltip and VoiceOver. `folder` at 116–140 and `doc.on.doc` at 148–172 replace Record until Idle.
- Saved lasts 6 s, then crossfades to Idle over 0.2 s. The pointer over the bar pauses the countdown, and leaving restarts it at 6 s. Record, a new size, Show in Finder and × end it at once. × is Clear Window: it drops the pick. Under Reduce Motion every change is one frame.
- VoiceOver: `Clip saved, 7 seconds` is announced. The status reads `Saved, 7 seconds, clip.mp4`.
- The outline is the accent during Saved.

### 3.1 Disabled: reasons, in priority order (the first that applies wins)
| Cause | Tooltip and VoiceOver (on the disabled Record) |
|---|---|
| Screen Recording not allowed | `Screen Recording isn't allowed. Skreenrek can't record until you allow it.` (existing `Settings.screenRecordingNotAllowed`) |
| Direct capture not approved | `Direct capture isn't approved. Finish setup so macOS asks about its private window picker first.` (existing `Errors.directCaptureOff` + `Errors.directCaptureDetail`, joined with ". ") |
| The current preset no longer fits (the window moved to a smaller display) | `WindowFitFailure.tooltip`, e.g. `4K needs room for a 1920 × 1080 pt window. Use a larger display or pick 1440p.` |
| Output folder not writable | `Couldn't save the clip` is an after-the-fact error, so instead use **new** `The output folder isn't writable. Choose another folder in Settings.` |

- Look: calm. No red, no banner, no text change in the bar. The button keeps its 84 pt slot, goes to the cell fill with `tertiaryLabelColor` text, and the Skreenrek mark is replaced by a 16 pt orange `exclamationmark.triangle.fill`. The triangle's shape carries the state; the sentence is in the tooltip.
- The tooltip must show on the disabled button. SwiftUI drops `.help` on disabled controls, so put the help on a non-disabled wrapper, or use an AppKit `toolTip` on the hosting view.
- VoiceOver: "Record, dimmed. Screen Recording isn't allowed. Skreenrek can't record until you allow it." (label `Brand.record`, trait not-enabled, hint = the sentence).
- Clicking does nothing. The fix lives where it already lives: the menu panel's error rows and Settings › Permissions. The Size pop-up stays usable, so a preset that doesn't fit can be swapped from the bar.
- Accessibility not allowed is **not** a disabled-Record cause: recording works, only resizing doesn't. In that case the **Size pop-up** is disabled and the readout shows the window's current px in the not-exact layout, with the triangle. Size and the readout share the tooltip `Skreenrek can't resize windows without Accessibility. Recording at the current size.` Record records the window at its current size, and a preset that wouldn't fit can't block it. The panel keeps its existing Accessibility error.

## 4. Size menu. Render: `bar-size-menu`
- A standard pop-up menu (SwiftUI `Menu` with `.menuStyle(.button)`, exactly like the panel's Size cell). It opens below the button, left edges aligned, 4 pt below. The menu itself is system chrome.
- Items, reusing the panel's `SubmenuModel` entries: `720p`, `1080p`, `1440p`, `4K`, separator, `Square`, `Portrait`. Each has its trailing px (`Menu.dimensions`, 12 secondary) and a checkmark on the active preset.
- **Not in the bar's menu:** `Current Size` and `Custom…`. They stay in the menu panel. Custom… opens a sheet that needs the app active, which the bar must not do (§7), and the brief keeps custom entry out of the bar's scope. When the size is custom, the pop-up reads `Custom` and no item is checked.
- Presets that don't fit the window's display are **disabled** with `WindowFitFailure.tooltip` (spec 13), e.g. 4K on a laptop.
- Choosing a preset uses the same pixel-exact resize with read-back as the CLI (`ExactResizer`). The bar shows the confirmed size from the read-back (§3 Resizing, Not exact, Refused). After a refusal, post a VoiceOver announcement with the tooltip text.

## 5. Placement. Renders: `bar-idle-below`, `bar-above`, `bar-docked`, `bar-narrow`
All geometry is in global top-left points on **the window's display**: the screen holding the largest part of the window. `V` is that screen's `visibleFrame` (excluding the menu bar and Dock). `W` is the window frame.
1. **Below:** top = `W.maxY + 8`. Use it if `W.maxY + 8 + 36 + 8 ≤ V.maxY`.
2. **Above** (no room below): bottom = `W.minY − 8`. Use it if `W.minY − 8 − 36 − 8 ≥ V.minY`.
3. **Docked** (neither fits, e.g. a full-height or full-screen window): **inside** the window, bottom = `W.maxY − 12`. It overlaps the window's content, which is fine because the bar is never captured (§8).
- Horizontal: centred on `W.midX`, rounded to whole points, then clamped to `[V.minX + 8, V.maxX − 8 − width]` so it never goes off-screen. It never straddles two displays.
- 8 pt from the window edge leaves the 3 pt outline (r19) plus 5 pt of clear space. The outline always stays around the window and the bar always sits outside it, except in docked mode, where the bar sits inside the window and the outline still runs around the outside.
- **Width:** 300 by default. If `W.width < 300`, drop the readout and use the **compact 192** bar (Size, 12, Record). The px moves to the pop-up's tooltip and VoiceOver (`Size, Custom, 520 by 800 pixels`), as do the size warnings. While saving, the compact bar shows only the centred indicator, and `Saving clip…` is its tooltip and VoiceOver label. If `W.width < 192`, keep 192, centred (it may overhang the window, clamped on-screen). Presets never make windows that narrow; only a picked small window does.
- The mode is chosen fresh on every frame update, so it changes instantly with no animation (no sliding across the window).

## 6. When it shows
Shows only when **all** of these are true:
- `Show Control Bar` is on (new `SettingsStore` key `showControlBar`, default **on**).
- The menu-bar app is running. The headless host (CLI/MCP without the app) never shows it, and never shows the outline.
- A **window** is picked. Regions get no bar in this version.
- The window is on screen. Hide it while the window is minimised, its app is hidden (⌘H), the window is on another Space, or it's closed (the panel's Window closed state).
- The window picker isn't open.
- While recording or saving, the HUD's rule allows on-screen chrome: `Show recording indicator` is on and the recording didn't ask for `--no-hud`. "No on-screen chrome" covers the bar too. Idle and starting don't depend on this.

So the bar shows for any pick, including an agent's MCP pick (which also flashes the outline), and stays while that window stays picked. It's not tied to the panel being open. Clear (panel) and a closed window remove it.

**Agent recordings.** If an agent records a window without a pick and the HUD would show, the bar shows in its recording state (timer and Stop) in place of the HUD's, then hides when the recording ends unless that window is picked.

**After a clip (Raph, 15:04 Paris).** With the control bar on, a window recorded from the bar or the menu stays picked after the clip, so the bar returns to Record. With the bar off, the window is forgotten as before. Agent and MCP recordings also still forget the window.

Motion: it appears with a 0.15 s fade-in at the moment of the pick, alongside the outline flash, and disappears with a 0.15 s fade-out. Moves, resizes and flips follow the window with no animation. **Reduce Motion:** no fades; it appears and disappears in one frame.

Tracking: reuse the outline's tracking (`WindowFrameTracking`: AXObserver moved and resized notifications when Accessibility is allowed, otherwise a 100 ms `CGWindowListCopyWindowInfo` poll). The tracker must run **whenever the bar is visible**, not only while the outline is (today `SelectionOutlineModel.wantsTracking` stops after the flash). Give the bar its own model (`ControlBarModel`, pure, like `SelectionOutlineModel`) that shares the tracker.

## 7. Window behaviour
- An `NSPanel` with `[.borderless, .nonactivatingPanel]`. `becomesKeyOnlyIfNeeded = true`, never main, `hidesOnDeactivate = false`, `hasShadow = false` (we draw the one shadow; don't double it). Clicking it never activates Skreenrek and never takes focus from the window being recorded.
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]`.
- Ordering: `order(.above, relativeTo: targetWindowNumber)`, the same as the outline, and re-ordered on every tracking tick. Windows in front of the target cover the bar too. It never floats over everything.
- Not draggable. It's anchored to the window.
- **Full screen:** a full-screen target has no room above or below, so the bar docks inside its bottom edge on that full-screen Space (`.fullScreenAuxiliary`). With auto-hiding Dock, `V` is the whole screen, so the docked rule still applies.
- **Multi-display:** the window's display decides `V` (§5). When the window is dragged across, the bar jumps to the new display once most of the window is there. Mixed scale factors don't matter: everything is in points.
- **Relation to the recording HUD:** while the bar is visible and a recording runs, the HUD's recording and saving states are **suppressed**. There's one timer and one Stop on screen, and they're on the bar. If the bar is up when the save finishes, Saved shows on the bar and the HUD's Saved is suppressed (§3.2). The HUD's Stopped state still appears as today. If the bar is off or hidden (window minimised, other Space), the HUD behaves exactly as today under `Show recording indicator`. With `--no-hud` or that setting off, neither the bar nor the HUD's recording or Saved state shows.
- **Agent recordings that drop the pick:** the bar goes away when saving starts.
- **Recording outline (addendum 2, §A):** while recording, the outline around the window is `systemRed` (token `record-red`) with the pick outline's geometry, and it shows whether or not the bar or the panel is up. It goes back to the accent at saving when the window stays picked with the bar on, and fades out over 0.3 s otherwise. Region recordings get a square red frame just outside the region; full-screen recordings get none.

## 8. Never in a clip (hard requirement)
- `sharingType = .none` on the bar's panels. This is what keeps the bar out of every capture.
- **Do not add the bar to `exceptingWindows`** of any `SCContentFilter`: that would put it back into the capture.
- Region captures already exclude the whole app, and a window-only filter never includes the bar, docked or not.
- Same as the outline: §4 of the 1.0.5 spec. The red recording outline keeps `sharingType = .none` and is in no `exceptingWindows` either (addendum 2, §A).
- Acceptance: the bar never appears in a clip, whether the clip is a window, a region or a full-screen capture.

## 9. Keyboard and VoiceOver
- No new keyboard shortcuts (AZERTY). ⌃⌘⎋ stays the global stop. The bar never takes keyboard focus on its own. Keyboard-only users have the same actions in the menu panel (Size cell, Record, Stop Recording).
- The bar is one accessibility group, labelled **new** `Skreenrek controls for Safari — localhost:3000` (`controlBar(title)`), so VoiceOver users can reach it with VO navigation.
  - Size pop-up: `Panel.popupLabel(title: Menu.size, value:)` → "Size, 1080p, pop-up button". In compact width, add the px: "Size, Custom, 520 by 800 pixels".
  - Readout: "1920 by 1080 pixels".
  - Record: `Brand.record`, hint **new** `Records Safari — localhost:3000.` Disabled: §3.1.
  - Recording: the status slot is hidden from VoiceOver. Stop is `Brand.stopLabel(seconds:)` → "Stop Recording, 12 seconds".
- Tooltips (system, standard delay):
  - Size pop-up: **new** `Clip size. Skreenrek resizes the window to fit.`
  - Readout: **new** `The clip will be 1920 × 1080 px. The window is 1440 × 810 pt on screen.`
  - Record: **new** `Record this window.`
  - Stop: `Panel.stopHelp` → `Stop Recording (⌃⌘⎋)`.
  - Disabled presets: `WindowFitFailure.tooltip`. Not exact: `Menu.notExactReason`. Disabled Record: §3.1. Accessibility off (Size and the readout): §3.1.
- Increase Contrast: hairline 25%. Accent, red and orange stay system colours. No meaning relies on colour alone: the triangle, the dot plus a running timer, and the square-in-Stop are all shapes.

## 10. Menu panel: Show Control Bar. Render: `renders/panel-row-{light,dark}@2x.png`
- A new switch row **after Write Click Events**, matching it exactly: 28 tall, highlight x 8–292 r6, icon 16 at x 16, title at x 40, mini switch with its right edge at x 284.
- Title **new** `Show Control Bar`. Symbol `rectangle.bottomthird.inset.filled` (stand-in drawn), in the same weight and colour as `cursorarrow`. VoiceOver "Show Control Bar, switch, on". The action keeps the panel open (add it to `PanelModel.keepsPanelOpen`).
- It shows wherever the other two switch rows show (picked, no window, window closed). Panel heights each grow by 28:
  - No window or window closed: **351** (412 with Last Clip, 379 with the update row, 440 with both).
  - Picked: **558.5** (619.5 with Last Clip, 647.5 with Last Clip and the update row).
  - The panel height cap is now **648**, which covers the picked + clip + update case. It still fits a 13" display (776 pt usable).
- Turning it off hides the bar at once (fade under §6 rules). Turning it on shows it if §6 allows.
- **Settings › General › Recording** gets the same switch, **new** `Show control bar` (sentence case like its neighbours), placed after `Show recording indicator`. The General content becomes 552 tall (window ≈ 632). Both switches bind to `showControlBar`.

## 11. New strings (add to `UIStrings` and `allFixed` for the copy audit)
`Show Control Bar` · `Show control bar` · `Skreenrek controls for <title>` · `Records <title>.` · `Record this window.` · `Clip size. Skreenrek resizes the window to fit.` · `The clip will be <W × H> px. The window is <w × h> pt on screen.` · `The output folder isn't writable. Choose another folder in Settings.` · `Skreenrek can't resize windows without Accessibility. Recording at the current size.`
Reused: `Record`, `Stop`, `Stop Recording (⌃⌘⎋)`, `Custom`, `Saving clip…`, the preset titles and px, `WindowFitFailure.tooltip`, `Menu.notExactReason`, `Settings.screenRecordingNotAllowed`, `Errors.directCaptureOff` + `directCaptureDetail`.

## 12. Acceptance
1. Pick a window: the bar appears centred under it within one frame of the outline flash, 8 pt below the window edge (5 pt clear of the outline). It's 300 × 36, r10, opaque, and shows the preset name, `W × H px` and Record. Checked on the purple wallpaper and on a white window in light and dark: nothing shows through.
2. Slot x positions inside the bar are 6 / 90 / 102 / 198 / 210 / 294 (±0.5). Controls are 24 tall, 6 from the top and bottom. Type is 13/12 only. Radii are 10/6/4 only.
3. Move a window near the Dock: the bar flips above it. Make it full height: the bar docks inside, 12 above the window's bottom edge. Full screen: docked on that Space. The bar never leaves the window's display and never goes off-screen.
4. Make the window narrower than 300: the readout drops and the bar is 192. The px is in the pop-up's tooltip and VoiceOver.
5. Drag and resize the window: the bar follows within 100 ms (one poll) without Accessibility, and smoothly with it. Minimise, ⌘H, switching Space, closing the window or opening the picker hides it. Clear in the panel removes it.
6. Size menu: same presets and px as the panel; 4K disabled on a laptop with the spec 13 sentence; no Current Size or Custom…. Choosing 720p resizes through the exact path, and the readout shows the read-back px (a triangle plus the reason when not exact, or 4 s for a refusal).
7. Record from the bar starts recording without activating Skreenrek or changing the frontmost app. The bar switches to dot + timer + Stop at the same 300 width, the HUD's recording state doesn't appear, and Stop ends the clip. Saved shows in the HUD as today.
8. Disabled: with Screen Recording off, Record is grey with an orange triangle, does nothing on click, shows the sentence as a tooltip and is read as dimmed with the sentence by VoiceOver. The Size pop-up still works. Same for direct capture, an unfit preset after a display change, and an unwritable folder.
9. **Capture exclusion:** record a docked-bar window, a display capture and a region capture over the bar. No frame and no preview still contains the bar or the outline, and the bar is in no `exceptingWindows` list. A ⌘⇧4 screenshot doesn't contain it either (`sharingType = .none`).
10. Show Control Bar in the panel and in Settings: one shared value, default on. The panel row lines up with the other switch rows at x 16 / 40 / 284. Panel heights are as listed in §10.
11. Reduce Motion: no fades. Increase Contrast: 25% hairline. VoiceOver reads the group and each control as in §9. No shortcuts were added.
12. An agent recording with `--no-hud`, or any recording with `Show recording indicator` off, shows no bar until it ends. An agent recording an unpicked window with the HUD allowed shows the timer and Stop on the bar, and the bar goes away when the recording ends.
13. The timer reads `59:59`, then `1:00:00`, and the bar stays 300 wide.
14. Accessibility off: Size is disabled, the readout shows the triangle and current px, both carry the §3.1 tooltip, and Record records at the current size.
15. Saving: the indicator sits 6 pt left of `Saving clip…`, and the pair is centred left of Record, with and without Reduce Motion.
16. With the bar on, a window recorded from the bar or the menu is still picked after the clip.

## 13. Decisions taken here (beyond the brief)
- One fixed **300 pt** width in every state (96 pt readout slot, 84 pt slots 1 and 3), so the bar never jumps when the state or preset changes. It matches the panel width.
- Size is a value-only pop-up (no "Size" label). Current Size and Custom… stay in the panel.
- The Record button uses the Skreenrek mark, the same as the panel's Record.
- Disabled Record keeps its place and gets a triangle. The Size pop-up stays usable. Accessibility off disables Size, not Record.
- The bar suppresses the HUD's recording/saving states while it's visible (one Stop on screen).
- The bar shows for every window pick, including MCP picks in the running app; never headless; never for regions.
- The bar follows the HUD's rule during a recording, and stands in for the HUD when an agent records an unpicked window (addendum 1).
- With the bar on, a window recorded from the bar or the menu stays picked after the clip (Raph, 15:04 Paris). Agent and MCP recordings still forget it.
- Bar ordering follows the target window (like the outline). It never floats above other apps.
- Show Control Bar also goes in Settings › General › Recording, because every panel switch has a Settings twin.

## 14. Files
- Renders (each `-light` and `-dark`, @2x): `renders/bar-idle-below`, `bar-recording`, `bar-above`, `bar-docked`, `bar-narrow`, `bar-size-menu`, `bar-disabled`, `panel-row`.
- Redlines: `redlines/redline-idle-{light,dark}@2x.png`, `redlines/redline-recording-{light,dark}@2x.png` (drawn at 300%, labels in pt).
- Boards: `boards/board-{light,dark}@2x.png`.
- Source: `src/build.py`, `src/bar.css`, `src/base.css` (from 1.0.5), `src/redline.py`, `src/board.py`. Measurements: `src/sizes.json`. Repo snapshot: `src/repo` (main `a7ad1af`).
