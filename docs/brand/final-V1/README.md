# Skreenrek logo kit — V1 (approved by Raph, 17 Nov 2026)

Mark: two mirrored k's around a record dot, |< • >|, long 45° arms that nearly close a diamond.
Square-cut ends and sharp corners everywhere (Raph: no rounded ends). Only the record dot is round.
24-unit grid, 2 u stroke (1.5 pt at 18 pt). Exact mirror symmetry.

## icon/
- icon-dark-*.png / .svg — the app icon. Dark graphite body, white mark, only the dot red (#FF5F55→#E5281E).
- 1024/256/128 from icon-dark.svg; 64/32/16 from icon-dark-small.svg (heavier 2.5 u stroke for small sizes).
- icon-light-* — alternate light body, not the default.
- Rebuild in Icon Composer for Tahoe if you ship an .icon; keep geometry identical.

## menubar/
States: idle (hollow dot), armed (stems slide inward), recording (filled dot), saving (down arrow), error ("!").
- mono/ — use as template images (NSImage.isTemplate = true). This is the default.
- bichrome/ — template layer plus an accent layer: recording dot red (systemRed), error "!" orange (systemOrange). Draw in code as two layers so the black part still follows the menu-bar appearance; the PNGs are references only.
- 18 pt glyph, @1x 18 px, @2x 36 px. Elapsed time sits next to the glyph while recording (e.g. 0:12, monospaced digits).
- State is carried by shape, so mono alone is unambiguous; colour is extra.

## wordmark/
- wordmark-{light,dark}.svg / @2x.png — README and site. Text is Inter SemiBold, outlined.
- *-echo — both k's redrawn to match the mark. Optional; plain is the default.
- Clear space: at least the height of the record dot on every side. Don't recolour the mark beyond ink + red dot.

## Direction C
Use icon-dark for the graphite brand tile in the dropdown header and the Settings hero (keep the tile graphite, not red).
