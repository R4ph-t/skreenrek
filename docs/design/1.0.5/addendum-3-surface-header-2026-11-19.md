# Skreenrek: one shared surface + Settings header, addendum 3 (2026-11-19)

> **Revised 2026-11-19 10:04 Paris (Raph: "no don't go full native glass shit though" / "I'm not asking to change one thing to revert back 5 things in return").** Everything below stands, including the shared solid surface in Settings (§1), with two changes. First, §2's custom header and segmented tabs become standard toolbar tabs on the solid surface, with the icon, name and version at the top of General. Second, per-tab resizing is removed. Both are in §3, which replaces §2.


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
  - Form: `.formStyle(.grouped)`, `.scrollContentBackground(.hidden)`, `.background(surface.base)`, rows `.listRowBackground(surface.cell)`, with separators tinted `surface.separator`. If SwiftUI's grouped Form won't take the tint, build the sections as plain `VStack`s: 10 pt rounded rect `surface.cell`, 44 pt rows, `Divider` replaced by a 1 px `surface.separator` line.
- Settings keeps the existing shadow and system window frame. Only the colours change.

## 2. Settings header (superseded by §3, 2026-11-19 10:04)

Toolbar tabs can't carry an app logo and name cleanly (the toolbar title is the tab name), so Settings moves to a custom header with a segmented tab switch. That's the same pattern as Raph's Manufacture settings: same tone as the body, with no system toolbar band.

Layout at 480 pt wide, y from the top of the window:

| Part | Frame (pt) | Notes |
| --- | --- | --- |
| Title bar | y 0–28 | Traffic lights only. Title hidden (`titleVisibility = .hidden`). |
| Header | y 28–84 (56 tall), x 16–464 | Same `surface.base`, no divider under it. |
| App icon | 32 × 32 at x 16, vertically centred (y 40–72) | The real app icon (V1 diamond frame kit, `final-V1/`), not a tinted symbol. |
| Name | x 56, 13 semibold `labelColor` | `Skreenrek`. Lower-case "skreenrek" only in the wordmark asset; the UI string is capitalised like every other app name. |
| Version | x 56, 12 regular `secondaryLabelColor`, 2 pt under the name | `Version 1.0.5` (from `CFBundleShortVersionString`). Name and version are centred together on the icon's centre line. |
| Tabs | segmented control, 3 equal segments of 88 = 264 wide, right edge x 464, vertically centred on the icon | `General` · `Agents` · `Permissions`, text only, system `.segmented` style (regular size, 24 tall). |
| Content | starts at y 92 (8 pt gap) | The existing grouped sections, with rows at the same x 28 / x 452 edges as before. |

- **Window title:** `Skreenrek Settings`, constant. It isn't drawn, but it's what the Window menu, Mission Control, ⌘` and VoiceOver use. It no longer changes per tab.
- **Version:** shown in the header only. The About section keeps the Updates row (its detail stays `Skreenrek 1.0.5 is up to date.`, which is a status, not a repeat label) and View on GitHub. There's no separate version row.
- **Keyboard:** ⌘, opens Settings on the last tab used. The segmented control is Tab-reachable, and ←/→ switch tabs when it has focus. No numeric shortcuts (AZERTY).
- **Height:** still fits each tab's content with no scroll view. Header plus title bar is 84 pt, about the old 80 pt toolbar, so the totals stay roughly as specced (General ≈ 592).
- **Tab switch:** the content crossfades over 0.15 s while the window resizes with the system animation. Under Reduce Motion, both are instant.
- **VoiceOver:** the header reads `Skreenrek, version 1.0.5`. The segmented control reads `Settings tabs, General, selected, 1 of 3`.

## Acceptance

1. Place the dark menu panel next to the dark Settings window and sample both: the base is #1E1E1E on both, and the panel cells and Settings sections are both #2A2A2A. Same in light (#F5F5F5 / #FFFFFF).
2. Settings shows one tone from the top edge through the header to the bottom, with no lighter toolbar band.
3. The header shows the 32 pt app icon, `Skreenrek` and `Version 1.0.5` on the left, and the three-segment control on the right, both centred on one line, at x 16 and x 464.
4. The window title is `Skreenrek Settings` in the Window menu on every tab.
5. No hex literals outside the surface tokens (grep).
6. Light and dark renders of: the panel next to Settings General, plus Settings Agents and Permissions.

## 3. Settings tabs and identity row (2026-11-19 10:04, replaces §2)

- **Tabs:** standard SwiftUI `Settings { TabView }` toolbar tabs with icons: `General` `gearshape`, `Agents` `terminal`, `Permissions` `hand.raised`. System selection styling, no segmented control. The window title is the selected tab's name, as macOS does it.
- **Surface stays solid (§1):** one `surface.base` tone from the top edge through the toolbar to the bottom, with no glass and no lighter toolbar band. Set the window `backgroundColor = surface.base` and `titlebarAppearsTransparent = true`, and hide the toolbar background (`.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)`, or the AppKit equivalent). Sections stay the plain 10 pt `surface.cell` stacks with 44 pt rows and `surface.separator` lines.
- **Identity row:** at the top of **General only**, above the first section, directly on `surface.base` with no card.
  - The app icon is 32 × 32 (`NSApp.applicationIconImage`), aligned with the sections' leading edge.
  - `Skreenrek` is 13 semibold `labelColor`, 12 pt after the icon. `Version 1.0.5` is 12 regular `secondaryLabelColor`, 2 pt under the name. The name and version are centred together on the icon.
  - The row is 48 tall, with 8 pt above it and the usual section gap below.
  - VoiceOver reads it as one element: `Skreenrek, version 1.0.5`.
  - The version shows only here. About keeps Updates and View on GitHub.
- **Height:** there is no per-tab resizing and no live height reports, which caused the 10:00 resize loop and dropped clicks. Use one fixed content height, set by the tallest tab (General, including the identity row), with shorter tabs top-aligned. No scroll view, and no animation on tab switch.
- **Acceptance:**
  - Tabs switch on the first click, with no resize and no lag.
  - The toolbar is the same tone as the body in light and dark.
  - The identity row shows on General only.
  - Light and dark renders of all three tabs.
