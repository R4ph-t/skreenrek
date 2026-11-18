# Skreenrek menu panel: solid background (addendum, 2026-11-18)

Raph, 14:00 Paris: "i don't want the glass look". The panel becomes fully opaque. This supersedes any material, vibrancy or glass in spec.md §panel. Layout, sizes and strings are unchanged.

## Panel surface
- Remove every translucent material: no NSVisualEffectView, no SwiftUI `.material` or `.glassEffect`, no vibrancy on text or icons. Use plain `primary`/`secondary` label colours.
- Fill: dark #1E1E20, light #F6F6F8, at 100% opacity.
- Corner radius: 10 pt (the largest step of the 10/6/4 scale), continuous corners, with the panel content clipped to it.
- Border: a 1 px inside hairline. Dark uses white at 10%, light uses black at 10%. With Increase Contrast it goes to 25%.
- Shadow: one soft drop shadow, black. Dark is 35% opacity, blur 24, y 8. Light is 15% opacity, blur 20, y 6. Use the system window shadow if the NSPanel provides it, but not both.
- Separators: 1 px. Dark uses white at 10%, light uses black at 8%, inset to x 16–284 as in spec.md.

## Things that sit on the surface (all opaque)
- Size and Frame Rate cells: dark #2C2C2F, light #FFFFFF with a 1 px black 8% hairline (light only). Radius 6.
- Preview well: dark #2C2C2F, light #E9E9EE. Radius 6. The picked accent and recording red strokes are unchanged.
- Pick Window… and Record: solid system accent (`controlAccentColor`) with white label, no gradient or translucency. Hover darkens by 6% and pressed by 12%. Stop Recording is solid system red with the same rules. Radius 6.
- Row hover: dark white 8%, light black 5%. Pressed: dark white 12%, light black 9%. Radius 6, spanning x 8–292 as specified.
- Switches, shortcut glyphs and icons: standard system colours. Secondary text uses `secondaryLabelColor` (not vibrant).

## Acceptance
- On the purple wallpaper and on a white window, nothing behind the panel shows through anywhere, including the corners, cells, button and hover. Check with a screenshot in light and dark.
- The edges read as one clean 10 pt rounded rectangle with a hairline and a single shadow. There's no double border and no grey halo.
- Sizes and positions are identical to the 1.0.5 spec.
