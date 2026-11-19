# Skreenrek: one shared surface + Settings header, addendum 3 (2026-11-19)

Raph, 09:19 Paris: "why is the setting and dropdown not the same tone?" and "for the settings we need to have in the header the title and logo of the app".
Overrides addendum-solid-panel-2026-11-18 (fills) and spec §Settings (toolbar tabs, About version). Everything else stands.

## 1. One surface, shared by the menu panel, the control bar, the HUDs and Settings

The panel was slightly blue (#1E1E20) and Settings used the system window background with system grouped cards, so they never matched. Both now use one neutral token set, with no blue tint, so it also sits right next to macOS chrome.

| Token | Dark | Light | Use |
| --- | --- | --- | --- |
| `surface.base` | #1E1E1E | #F5F5F5 | Panel, control bar and HUD fill. Settings window background, including the title bar and header (one tone, top to bottom). |
| `surface.cell` | #2A2A2A | #FFFFFF | Settings grouped sections. Panel Size and Frame Rate cells, the bar's Size pop-up, the preview well (light well stays #EBEBEB so the preview reads on white). |
| `surface.hairline` | white 10% | black 10% | 1 px inside edge of floating surfaces (panel, bar, HUD). Light cells also get a black 8% 1 px edge. Increase Contrast: 25%. |
| `surface.separator` | white 8% | black 8% | 1 px lines between rows in a Settings section, inset 12 pt from the section's leading edge, full to the trailing edge. Panel dividers use the same token. |
| `surface.hover` / `surface.pressed` | white 8% / 12% | black 5% / 9% | Unchanged from the solid addendum. |

- Radii unchanged: floating surfaces 10, Settings sections 10, cells 6, chips 4.
- Text stays system: `labelColor` and `secondaryLabelColor`.
- **Implementation:** one `SkreenrekSurface` enum (or asset catalog colours with Any/Dark) that every surface reads from. No hex literals in views.
  - Settings window: `backgroundColor = surface.base`, `titlebarAppearsTransparent = true`.
  - Onboarding window: the same tokens. `surface.base` background under a transparent title bar (`.fullSizeContentView`, title hidden but kept for the Window menu and VoiceOver) with a 28 pt band at the top for the traffic lights; its cards are 10 pt `surface.cell` rects with the light 1 px black 8% edge, and rows inside a card are split by 1 px `surface.separator` lines inset 12 pt.
  - Form: `.formStyle(.grouped)`, `.scrollContentBackground(.hidden)`, `.background(surface.base)`, rows `.listRowBackground(surface.cell)`, with separators tinted `surface.separator`. If SwiftUI's grouped Form won't take the tint, build the sections as plain `VStack`s: 10 pt rounded rect `surface.cell`, 44 pt rows, `Divider` replaced by a 1 px `surface.separator` line.
- Settings keeps the existing shadow and system window frame. Only the colours change.

## 2. Settings header

Toolbar tabs can't carry an app logo and name cleanly (the toolbar title is the tab name), so Settings moves to a custom header with a segmented tab switch. That's the same pattern as Raph's Manufacture settings: same tone as the body, with no system toolbar band.

Layout at 480 pt wide, y from the top of the window:

| Part | Frame (pt) | Notes |
| --- | --- | --- |
| Title bar | y 0–28 | Traffic lights only. Title hidden (`titleVisibility = .hidden`). |
| Header | y 28–84 (56 tall), x 16–464 | Same `surface.base`, no divider under it. |
| App icon | 32 × 32 at x 16, vertically centred (y 40–72) | The real app icon, not a tinted symbol: drawn from `NSApp.applicationIconImage`, so it is always the Dock's icon (no light variant). Unbundled runs (swift run, tests, renders) fall back to the V1 artwork the bundle icon was made from (`final-V1/`). |
| Name | x 56, 13 semibold `labelColor` | `Skreenrek`. Lower-case "skreenrek" only in the wordmark asset; the UI string is capitalised like every other app name. |
| Version | x 56, 12 regular `secondaryLabelColor`, 2 pt under the name | `Version 1.0.5` (from `CFBundleShortVersionString`). Name and version are centred together on the icon's centre line. |
| Tabs | segmented control, 3 equal segments of 96 = 288 wide (x 176–464), right edge x 464, vertically centred on the icon | `General` · `Agents` · `Permissions`, text only, system `.segmented` style (regular size, 24 tall). |
| Content | starts at y 92 (8 pt gap) | The existing grouped sections, with rows at the same x 28 / x 452 edges as before. |

- **Window title:** `Skreenrek Settings`, constant. It isn't drawn, but it's what the Window menu, Mission Control, ⌘` and VoiceOver use. It no longer changes per tab.
- **Version:** shown in the header only. The About section keeps the Updates row (its detail stays `Skreenrek 1.0.5 is up to date.`, which is a status, not a repeat label) and View on GitHub. There's no separate version row.
- **Keyboard:** ⌘, opens Settings on the last tab used. The segmented control is Tab-reachable, and ←/→ switch tabs when it has focus. No numeric shortcuts (AZERTY).
- **Height:** still fits each tab's content with no scroll view. Header plus title bar is 84 pt, about the old 80 pt toolbar, so the totals stay roughly as specced. As built: General 627.5 pt, Agents 306.5 pt, Permissions 196.5 pt.
- **Tab switch:** the content crossfades over 0.15 s while the window resizes with the system animation. Under Reduce Motion, both are instant.
- **VoiceOver:** the header reads `Skreenrek, version 1.0.5`. The segmented control reads `Settings tabs, General, selected, 1 of 3`.

## Acceptance

1. Place the dark menu panel next to the dark Settings window and sample both: the base is #1E1E1E on both, and the panel cells and Settings sections are both #2A2A2A. Same in light (#F5F5F5 / #FFFFFF).
2. Settings shows one tone from the top edge through the header to the bottom, with no lighter toolbar band.
3. The header shows the 32 pt app icon, `Skreenrek` and `Version 1.0.5` on the left, and the three-segment control on the right, both centred on one line, at x 16 and x 464.
4. The window title is `Skreenrek Settings` in the Window menu on every tab.
5. No hex literals outside the surface tokens (grep).
6. Light and dark renders of: the panel next to Settings General, plus Settings Agents and Permissions.
