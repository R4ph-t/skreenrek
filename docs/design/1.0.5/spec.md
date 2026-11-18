# Skreenrek 1.0.5 menu panel and Settings: spec, 18 Nov 2026

Status: Active (design). Target: `docs/design-spec.md`, sections "Menu-bar panel" and "Settings". It builds on and amends *Skreenrek menu panel B (hero record) spec 2026-11-18* (B-final). Where this spec says something different, this spec wins.
Code baseline: `R4ph-t/skreenrek` main at `58f80d8` (`MenuPanelView.swift`, `PanelModel.swift` (`PanelMetrics`), `SettingsView.swift`, `AgentsPanel.swift`, `PickerOverlay.swift`). Copy comes from `UIStrings` unless it's marked **new**.
Folder: `docs/design/1.0.5/` (`renders/`, `redlines/`, `boards/`, `sizes.json`; the HTML sources stay in Designer's box folder `/workspace/design-skreenrek-1.0.5-2026-11-18/src/`). The mockups use Inter in place of SF Pro and hand-drawn stand-ins for SF Symbols, so build with the real system font and symbols.

## 0. What changed and why (Raph's 1.0.5 feedback)
| Raph said | Change |
|---|---|
| "having a big empty screen spot at the start is weird" | With no window picked, the panel has **no preview box**. A compact header (viewfinder icon, "No window", "Pick a window to record") sits above the cells and a full-width **Pick Window…** button. The disabled Record button is gone. The panel goes from 591.5 to **323 pt**. The window-closed state uses the same compact layout. |
| "no way to deselect a window" | There's a **Clear button** (`xmark.circle.fill`) at the end of the window title line under the preview. It goes back to the compact state. **Pick Another Window…** stays as the way to re-pick. |
| "the selected window should have an outline or something to show it's selected" | Both places: **(a)** in the panel, the preview gets a **2 pt accent inner stroke** while a window is picked (red while recording). **(b)** On screen, a click-through overlay draws a **3 pt accent outline just outside the picked window**. It shows while the panel is open and flashes for 1.5 s right after a pick. |
| "the settings panel is completely nuts… built by a drunk person" | Settings is now a standard macOS **Settings window with toolbar tabs** (General · Agents · Permissions). The decorative icon tiles and the hero header are gone. Rows use grouped inset sections with headers, **one 44 pt row height**, labels on one left edge (x 28) and every trailing control on one right edge (x 452). About and Updates sit at the bottom of General, and the GitHub link is a plain row. |

Fixes from the native B renders (`/workspace/skreenrek/menu-b-final/`) that are folded in here:
- **Row geometry changes to one shared content edge.** Everything in the panel now starts at x = 16 and ends at x = 284: the preview, captions, cells, hero, separators, row icons and trailing controls. The row highlight is inset 8 pt from the panel edge (x 8–292, r6), the row content is inset 16 (icon at x 16, title at x 40), and trailing content ends at x 284. This replaces B-final's icon at x 24, text at x 48 and end at x 276. All row titles share x = 40.
- **Hero labels are centred**, including Stop Recording: `■ Stop Recording  0:12`, with tabular digits and the timer 4 pt after the label. There's no leading hero title left to drift off the edge, which fixes the "Stop Recording ~5 pt left" delta.
- **Last Clip icon buttons and the Clear button:** the 16 pt **glyph** ends at x 284. The 24 pt hit area overhangs the content edge by 4 pt (it ends at x 288). This fixes the "icons ~4 pt left" delta.
- 13 pt row icons are fine if every row uses them. The mockups show 16 pt. Pick one size for all rows, then centre it in a 16 pt column so titles stay at x 40.
- The corners-only `viewfinder` symbol is accepted. It's used for Pick Window…, Pick Another Window… and the no-window header.
- 1.0.5 regression seen in Raph's screenshot: the Show Cursor and Write Click Events switches sit right after their labels. Switches must be trailing, with their right edge at x 284 (`Spacer()` + `.labelsHidden()`).

## 1. Menu panel: common
- Width **300 pt** (unchanged). Panel padding 16 at the top and sides, 8 at the bottom. Radius 10 with the `.menu` material.
- Block width 268 (x 16–284). The gap between window-block elements is 12. A separator is 17 (8 + 1 pt line + 8), x 16–284.
- Rows are 28 tall. The Last Clip row is 44. The hero is 40. Cells are 28 (Size 116, gap 8, Frame Rate 144). Switches are mini (≈ 32 × 18) and end at x 284. Shortcut text (`⌘,`, `⌘Q`) ends at x 284.
- Type: 13/16 body, 13/16 semibold for titles and hero labels, 12/15 secondary. Nothing else.
- Radii: 10 for the panel, 6 for the preview, cells, hero, row highlight and Settings buttons, 4 for icon buttons, the thumbnail, the Clear hover and the tooltip.

## 2. Menu panel states

### 2.1 No window picked (compact). Render: `renders/panel-nowindow-{light,dark}@2x.png`, redline: `redlines/redline-nowindow-*`
| # | Element | Size (pt) | Gap above |
|---|---|---|---|
| 1 | **Header**: `viewfinder` 16 pt in `secondaryLabelColor` at x 16, vertically centred. Title **new** `No window` (13/16 semibold) and detail **new** `Pick a window to record` (12/15 secondary), both at x 40, 2 pt apart | 268 × 33 | 16 |
| 2 | Size and Frame Rate cells (unchanged behaviour, still editable) | 268 × 28 | 12 |
| 3 | Hero **Pick Window…** (accent, white `viewfinder` + label, centred) | 268 × 40 | 12 |
| 4 | Separator | 17 | — |
| 5 | Show Cursor, Write Click Events (switch rows) | 2 × 28 | — |
| 6 | (Separator + Last Clip row, only if a clip exists) | 17 + 44 | — |
| 7 | Separator, then the footer: (Update available · x.y.z), Open Output Folder, Settings… ⌘,, Quit Skreenrek ⌘Q | 17 + 3 × 28 (+28) | — |
| — | Bottom padding | 8 | |

- **Height: 323 pt** (no clip, no update, which is Raph's first-run case). It's 384 with Last Clip, 351 with the update row, and 412 with both.
- No Record button. No Pick Another Window… row, because Pick is the hero.
- VoiceOver: the header is one element, "No window picked. Pick a window to record." The hero is "Pick Window…". Return triggers the hero.

### 2.2 Window picked, idle. Render: `renders/panel-picked-*`
Order: preview (268 × 167.5) · 12 · caption (33) · 12 · cells (28) · 12 · **Record** (40) · separator · **Pick Another Window…**, Show Cursor, Write Click Events · separator · Last Clip (44) · separator · footer · 8.
- **Height: 530.5 pt** with no clip, **591.5** with Last Clip (as rendered), and **619.5** with Last Clip and the update row. That's B-final's 620 cap, unchanged.
- **Selected stroke:** the preview's 0.5 pt hairline becomes a **2 pt `controlAccentColor` inner stroke** (r6) whenever a window is picked. That covers idle, loading, capture failed and Screen Recording missing. It never shows in the no-window state, which has no preview anyway.
- **Caption:** the window title (13/16 semibold) truncates in the middle and stops 32 pt before x 284. The size line (12/15 secondary) is unchanged.
- **Clear button** (§3) sits at the end of the title line.
- **Re-pick:** keep the **Pick Another Window…** row (existing `UIStrings.Menu.pickAnotherWindow`). It's a labelled command in the menu-style list, so it's discoverable, Tab-reachable and read by VoiceOver. Clicking the preview isn't a macOS convention. The preview stays non-interactive and decorative.

### 2.3 Recording. Render: `renders/panel-recording-*`
Order: preview (2 pt `systemRed` inner stroke) · 12 · caption `Recording Safari — localhost:3000` / size line (**no Clear button**) · 12 · **Stop Recording** hero (systemRed, centred `■ Stop Recording 0:12`) · 8 · origin line (12/15 secondary, centred, 15) · separator · Discard Recording… · separator · footer · 8.
- **Height: 457.5 pt**, or **485.5** with the update row.
- No on-screen outline while recording (§4).

### 2.4 Clear button hover. Render: `renders/panel-clear-hover-*`
The hover fill is `row.hover` (r4) on the 24 × 24 hit area, and the glyph goes from `secondaryLabelColor` to `labelColor`. A system tooltip, `Clear Window`, appears after the standard delay.

### 2.5 Window closed (compact). Render: `renders/panel-window-closed-*`
- This replaces B-final's dimmed-still layout, so there's no big dead area here either. It's the same layout as 2.1, with the header icon `macwindow` + `xmark` (stand-in drawn), the title `Window closed` (existing `Panel.windowClosed`) and the detail set to the last window title (`Safari — localhost:3000`, middle-truncated). The hero is **Pick Window…**. Height is the same as 2.1 (**323 pt** base).
- The other B-final states (loading, capture failed, Screen Recording missing) are unchanged, plus the selected stroke from 2.2 and the Clear button.

### 2.6 Transitions
- When the state changes **while the panel is open** (Clear, or an agent picks or closes a window over MCP), the panel's height animates top-anchored: the top edge stays under the status item and the bottom moves. The preview fades in or out with `.easeInOut(duration: 0.2)`. The header and caption cross-fade over the same 0.2 s.
- **Reduce Motion:** no animation. The height and content change in one frame.
- Opening the panel never animates. It opens at the height of the current state.
- After Clear, focus moves to the **Pick Window…** hero, and VoiceOver announces "No window picked".

## 3. Clear button
- Symbol `xmark.circle.fill`, 16 pt glyph, `secondaryLabelColor` (hover: `labelColor`). It's a 24 × 24 hit area with no border and a hover fill of `row.hover`, r4. The glyph's right edge is at x 284 (the hit area ends at x 288). It's vertically centred on the title line (16 pt line, so the hit area overhangs 4 pt above and below it).
- Tooltip **new** `Clear Window`. VoiceOver label **new** `Clear picked window`, button trait. Tab-reachable, triggered with Space. No keyboard shortcut.
- Action: forget the picked window (`PanelModel` → no window). Size and Frame Rate keep their values. Leave the target window's size as it is now, and don't restore it. The panel stays open and collapses to 2.1. The on-screen outline (§4) disappears at once, with no fade.
- Hidden while recording or finalizing. Also hidden in the window-closed state, which already has no window.

## 4. On-screen selected outline. Render: `renders/screen-outline-*`
- **What:** a borderless, click-through overlay window draws a **3 pt stroke in `controlAccentColor`** (light `#007AFF`, dark `#0A84FF`, following the user's accent) **just outside** the picked window's frame. The stroke's inner edge sits on the window edge, and its outer edge is the frame outset by 3 pt. A 0.5 pt `rgba(0,0,0,.30)` hairline on the outer edge keeps it visible on blue or purple wallpapers. There's no fill and no glow.
- **Corner radius:** the window's corner radius + 3 (concentric). macOS has no public API for another app's window radius. Use **16 pt on macOS 26** (so the outline is r19) and 10 pt on macOS 15 (r13). This is the one radius outside the 10/6/4 scale, because it follows the target window rather than Skreenrek's own chrome. **Verify against a real Safari and a real Terminal window on Tahoe.** Toolbar windows may be closer to 26, so tune it in the native preview if the corners don't sit concentric.
- **Never in the clip:** the overlay is outside the window bounds, so a window-filtered SCStream wouldn't include it anyway. Also set `sharingType = .none` and exclude the overlay from every `SCContentFilter`.
- **Window setup:** `NSPanel` with `[.borderless, .nonactivatingPanel]`, `ignoresMouseEvents = true`, `hasShadow = false`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]`. Order it directly above the target window (`order(.above, relativeTo: targetWindowNumber)`), not at a floating level, so windows in front of the target still cover the outline.
- **When it shows:**
  1. **Right after a pick** (picker click, `Pick Another Window…`, or an agent's MCP pick): show it at full opacity for **1.5 s**, then **fade out over 0.3 s** (ease-out).
  2. **While the menu panel is open** and a window is picked: shown the whole time the panel is open. It hides with the same 0.3 s fade when the panel closes. If the panel opens during the post-pick flash, the outline just stays.
  3. **Not shown** while recording or finalizing, while the picker overlay is up (the picker has its own hover highlight), when the window is minimised, hidden, or on another Space, or in the no-window or window-closed states.
- **Follows the window:** while it's visible, it tracks moves and resizes. With Accessibility allowed, use `AXObserver` (`kAXMovedNotification`, `kAXResizedNotification`). Otherwise, poll the window bounds with `CGWindowListCopyWindowInfo` every 100 ms. Moves in Skreenrek's own size changes (presets) follow the same path.
- **Reduce Motion:** no fade. The outline appears and disappears in one frame, and the post-pick flash still lasts 1.5 s. **Increase Contrast:** the outer hairline becomes 1 pt `rgba(0,0,0,.6)`.
- **Accessibility:** decorative, so it isn't exposed to VoiceOver. The caption and the "picked" state already carry the meaning. After a pick, post a VoiceOver announcement **new** `Picked Safari — localhost:3000`.

## 5. Settings window
- A standard SwiftUI `Settings { TabView { … } }` scene with toolbar-style tabs. The window title is the selected tab's name. **Width 480 pt** (same as today). The **height fits each tab's content**: let the TabView size to each tab with `.fixedSize(horizontal: false, vertical: true)` per tab, and the system animates the resize. There's no scroll view and no empty space.
- Tabs (SF Symbols): **General** `gearshape`, **Agents** `terminal`, **Permissions** `hand.raised`. Their labels are system toolbar text, not restyled. There are no keyboard shortcuts for tabs (AZERTY), and ⌘, opens Settings on the last tab used.
- Content: `Form` with `.formStyle(.grouped)`, outer padding **16**. Groups are 448 wide, `r10`, with the system grouped background and hairline. **16** between groups. Section headers are 13/16 semibold `labelColor` at x 28, with 8 below them before the group. Group footers are 12/15 secondary at x 28, 8 below the group.
- **Rows:** every row is **44 pt** (the system minimum height is 44, and a 13/16 label + 2 + 12/15 secondary line = 33 fits inside it). Horizontal padding is 12, so labels sit at x 28 and trailing controls end at x 452. Separators between rows are inset to x 28–452. There are **no leading icons** in any row.
- **Controls:** push buttons are regular size, 24 tall, r6, with a **min width 80**. The Agents buttons are all **88** wide so they line up as one column. Switches are system `.switch` at `.controlSize(.mini)`. Segmented controls are system `.segmented` (2 × 64, 24 tall). A trailing control always keeps its own size, and the label column truncates in the middle (paths) or at the tail, never the control. There's a 12 pt minimum gap between them.
- Remove `SettingsRow`/`SettingsIconTile` and the 88 pt hero (`KitAppIcon`, the 20 pt name, the 11 pt version, the bottom-aligned link).

### 5.1 General. Render: `renders/settings-general-*`, redline: `redlines/redline-settings-general-*`
| Group | Row | Secondary line | Trailing |
|---|---|---|---|
| (no header) | Output folder | `~/Movies/Skreenrek` (middle-truncated, tooltip = full path) | `Choose…` |
| | Open at login | (only after a failed change: `loginItemOnFailed` / `loginItemOffFailed`) | switch |
| **Recording** | Default frame rate | — | segmented `30 fps` · `60 fps` |
| | Show cursor in video | — | switch |
| | Write click events | — | switch |
| | Show recording indicator | — | switch |
| | Stop shortcut | — | `⌃⌘⎋` in `secondaryLabelColor` (read-only) |
| **About** **new** header | Updates | `UpdateRowModel.detail`, e.g. `Skreenrek 1.0.5 is up to date.` | `Check for Updates` (or the state's button: Update / Retry / Relaunch / Open Release Page, `.borderedProminent` when it's prominent, plus a small spinner 8 pt before it while busy) |
| | **new** `View on GitHub` | — | `arrow.up.right` 13 pt, secondary. The whole row is a button that opens `Brand.repoURL`. Tooltip `Brand.repoHelp`. VoiceOver "View on GitHub, link". |
- **Content height 508 pt, window ≈ 588 pt** (with a toolbar of about 80 pt, which is system and varies by OS).
- What's new notes, when there's an update: a disclosure under the Updates row, inside the same group, capped at 160 pt and scrolling (the existing `WhatsNewNotes`). This is the only place a row's group grows past 44 per row.
- Version and app name: carried by the Updates line. VoiceOver for that row is "Updates, Skreenrek 1.0.5 is up to date."

### 5.2 Agents. Render: `renders/settings-agents-*`
- One headerless group with rows for Claude Code, Codex, Cursor and Command-line tool. The title is the agent name. The secondary line is `AgentConnection.status` (`Connected`, `Found ~/.codex`, `Not installed`, `Skreenrek moved. Connect to repair.`, or `Links skreenrek into ~/.local/bin`). The trailing button is `Remove` when connected and `Connect` otherwise, 88 wide. It's disabled when the agent isn't installed and has no connection, with the tooltip **new** `Install <Agent> first.`
- Setup results and warnings replace the secondary line for that row (12/15 secondary, one line, tail-truncated, with the tooltip holding the full text). The row stays 44.
- Footer **new**: `Connect adds the Skreenrek MCP server and the record-window skill.`
- **Content height 231 pt, window ≈ 311 pt.**

### 5.3 Permissions. Renders: `renders/settings-permissions-*` (both allowed) and `renders/settings-permissions-notallowed-*`
- One headerless group:
  - `Screen Recording` / `Required. Records the window you pick.`
  - `Accessibility` / `Required for exact window sizes.`
- **Allowed:** `checkmark.circle.fill` 16 pt in `systemGreen` + `Allowed` (13, secondary). VoiceOver: "Screen Recording, allowed."
- **Not allowed:** `exclamationmark.triangle.fill` 16 pt in `systemOrange`, 8 pt, then `Open System Settings…` (existing `Settings.openSystemSettings`). It opens the matching Privacy & Security pane. The triangle shape carries the state, so there's no "Not allowed" word: at 480 pt, the word, the button and the requirement line don't fit together without truncation. Tooltip and VoiceOver on the triangle **new**: `Accessibility isn't allowed. Skreenrek can record, but windows keep their current size.` / `Screen Recording isn't allowed. Skreenrek can't record until you allow it.` The row's VoiceOver reads: "Accessibility, required for exact window sizes, not allowed, Open System Settings…, button".
- The status refreshes when the window shows and when the app becomes active (the existing `refresh()`). It never prompts.
- **Content height 120 pt, window ≈ 200 pt.**
- Note: onboarding mentions three permissions (with direct capture). Settings shows two, as in 1.0.5. If direct capture belongs here, it's a third row with the same pattern.

All three tabs fit a 13" display (800 pt). The tallest is General at about 588.

## 6. Tokens
These are the B-final tokens (system colours first). New ones:
| Token | System | Light | Dark |
|---|---|---|---|
| selected stroke (preview, on-screen outline) | `controlAccentColor` | #007AFF | #0A84FF |
| outline contrast edge | — | rgba(0,0,0,.30) 0.5 pt | rgba(0,0,0,.30) 0.5 pt |
| permission allowed | `systemGreen` | #34C759 | #30D158 |
| permission warning | `systemOrange` | #FF9500 | #FF9F0A |
| Settings group | grouped form background | system | system |

Red appears only while recording. Accent is used only for controls and the selected state.

## 7. New strings (add to `UIStrings` and the copy audit)
`No window` · `Pick a window to record` · `Clear Window` · `Clear picked window` · `Picked <window title>` · `About` · `View on GitHub` · `Connect adds the Skreenrek MCP server and the record-window skill.` · `Install <Agent> first.` · `Accessibility isn't allowed. Skreenrek can record, but windows keep their current size.` · `Screen Recording isn't allowed. Skreenrek can't record until you allow it.`
Retired from the panel: `Ready` / `No window picked` as the caption, and `Pick a window first.` (the disabled Record is gone). Keep `No window picked` as the VoiceOver announcement.

## 8. Acceptance
1. With no window picked, the panel has no preview and no Record button, and it is **323 pt** tall with no clip and no update row (384 / 351 / 412 for the variants). Window closed matches it.
2. With a window picked, the preview shows a 2 pt accent inner stroke. While recording it's a 2 pt red stroke. In no state is there a 0.5 pt hairline when a window is picked.
3. The Clear button shows only in the picked, not-recording states. Its glyph's right edge is at x 284. Tooltip `Clear Window`, VoiceOver `Clear picked window`. Clicking it returns to the 323 pt layout within 0.2 s (instantly under Reduce Motion), moves focus to Pick Window…, and removes the on-screen outline.
4. Every row title in the panel starts at x 40, and every row icon starts at x 16. Switches, shortcuts, the Last Clip glyphs and the Clear glyph end at x 284. The preview, caption, cells, hero and separators span x 16–284 (checked in `debug render-ui`).
5. Hero labels are centred. Stop Recording shows `■ Stop Recording 0:12` with tabular digits.
6. On screen, the outline is 3 pt, accent, outside the picked window, with corners concentric to the window. It's visible while the panel is open, flashes for 1.5 s and fades over 0.3 s after a pick, never shows while recording, follows moves and resizes within 100 ms, never takes clicks, and never appears in a clip or a preview still (check with a test recording of a window that has the outline on).
7. Settings has the three toolbar tabs. Every row is 44 pt, with labels at x 28 and trailing controls ending at x 452. There are no icon tiles, no hero header and no blue link text. The window's height matches each tab's content (General ≈ 588, Agents ≈ 311, Permissions ≈ 200 at 480 wide) with no scroll view and no empty space.
8. Permissions shows a check plus "Allowed", or a triangle plus Open System Settings…, and its tooltip and VoiceOver carry the full sentence. Nothing in Settings relies on colour alone.
9. Every new string passes the copy audit. Type is 13/12 only, apart from system chrome. The only radii are 10/6/4, plus the system switch, segmented control and the on-screen outline (§4).
10. Light and dark, plus Increase Contrast and Reduce Motion, are checked for every render in §9.

## 9. Files
- Panel: `renders/panel-{nowindow,picked,recording,clear-hover,window-closed}-{light,dark}@2x.png`
- On screen: `renders/screen-outline-{light,dark}@2x.png`
- Settings: `renders/settings-{general,agents,permissions,permissions-notallowed}-{light,dark}@2x.png`
- Redlines: `redlines/redline-nowindow-{light,dark}@2x.png`, `redlines/redline-settings-general-{light,dark}@2x.png`
- Boards: `boards/board-{light,dark}@2x.png`
- Source: `src/build.py`, `src/style.css`, `src/redline.py`, `src/board.py`. Measured sizes are in `src/sizes.json`.
