#!/usr/bin/env bash
# Rebuild packaging/AppIcon.icns from the V1 icon kit in docs/brand/final-V1/icon/. Run by hand when the kit changes
# and commit the result; scripts/bundle-app.sh only copies the committed .icns, so `make app`, `make check` and the
# Homebrew formula never need an SVG renderer.
#
#   scripts/make-app-icon.sh
#
# The default app icon is icon-dark (graphite body, white mark, red dot). The kit's own PNG exports are used where
# they exist: 1024/256/128 from icon-dark.svg, 64/32/16 from icon-dark-small.svg (heavier stroke). The kit has no
# 512, so this renders icon-dark.svg at 512 px through WebKit (scripts/render-svg.swift).
set -euo pipefail

fail() { echo "make-app-icon: $*" >&2; exit 1; }

root="$(cd "$(dirname "$0")/.." && pwd)"
kit="$root/docs/brand/final-V1/icon"
out="$root/packaging/AppIcon.icns"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
iconset="$work/AppIcon.iconset"
mkdir "$iconset"

swift "$root/scripts/render-svg.swift" "$kit/icon-dark.svg" 512 "$work/icon-dark-512.png" \
  || fail "rendering icon-dark.svg at 512 px failed"

# <iconset name> <source png> <pixels>
while read -r name src px; do
  [ -f "$src" ] || fail "$src is missing"
  w=$(sips -g pixelWidth "$src" | awk '/pixelWidth/ {print $2}')
  h=$(sips -g pixelHeight "$src" | awk '/pixelHeight/ {print $2}')
  [ "$w" = "$px" ] && [ "$h" = "$px" ] || fail "$src is ${w}x${h}, expected ${px}x${px}"
  cp "$src" "$iconset/$name"
done <<LIST
icon_16x16.png $kit/icon-dark-16.png 16
icon_16x16@2x.png $kit/icon-dark-32.png 32
icon_32x32.png $kit/icon-dark-32.png 32
icon_32x32@2x.png $kit/icon-dark-64.png 64
icon_128x128.png $kit/icon-dark-128.png 128
icon_128x128@2x.png $kit/icon-dark-256.png 256
icon_256x256.png $kit/icon-dark-256.png 256
icon_256x256@2x.png $work/icon-dark-512.png 512
icon_512x512.png $work/icon-dark-512.png 512
icon_512x512@2x.png $kit/icon-dark-1024.png 1024
LIST

iconutil -c icns -o "$out" "$iconset" || fail "iconutil failed"
echo "$out"
