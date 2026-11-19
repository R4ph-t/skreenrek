#!/usr/bin/env bash
# Wrap the SwiftPM `skreenrek` executable into Skreenrek.app and sign it ad hoc.
#
#   scripts/bundle-app.sh [--unsigned] <products-dir> <out-dir>
#
# <products-dir> is a SwiftPM bin path (e.g. .build/release) that holds the `skreenrek` executable and the
# Sparkle.framework SwiftPM copies next to it. The script writes
# <out-dir>/Skreenrek.app/Contents/{MacOS/skreenrek,Info.plist,Resources/AppIcon.icns} from packaging/, embeds
# Contents/Frameworks/Sparkle.framework without its XPC services (Skreenrek is unsandboxed, so Sparkle doesn't need
# them), stamps CFBundleShortVersionString from SkreenrekVersion.current, signs ad hoc inside-out (Sparkle's
# Autoupdate, Updater.app, the framework, then the app), verifies the signature, and prints the bundle path. Ad hoc only: it never reads signing identities, keychains or secrets.
# The ad-hoc bundle (make app, make check, the source formula) also drops SUFeedURL and SUPublicEDKey, so Sparkle
# stays off and a dev build never updates itself into a Developer ID release.
# --unsigned skips signing and keeps the Sparkle keys, for scripts/release.sh to sign with Developer ID.
set -euo pipefail

fail() { echo "bundle-app: $*" >&2; exit 1; }

sign=1
if [ "${1:-}" = --unsigned ]; then
  sign=0
  shift
fi
[ $# -eq 2 ] || fail "usage: scripts/bundle-app.sh [--unsigned] <products-dir> <out-dir>"

root="$(cd "$(dirname "$0")/.." && pwd)"
products="$1"
out="$2"

bundle_id=com.raphaelterrier.skreenrek
plist_src="$root/packaging/Info.plist"
# Committed; rebuild it from the brand kit with scripts/make-app-icon.sh.
icon_src="$root/packaging/AppIcon.icns"
version_src="$root/Sources/SkreenrekCore/SkreenrekVersion.swift"
binary="$products/skreenrek"
sparkle_src="$products/Sparkle.framework"

[ -f "$binary" ] && [ -x "$binary" ] || fail "$binary is missing or not executable (run swift build first)"
[ -f "$plist_src" ] || fail "$plist_src is missing"
[ -f "$icon_src" ] || fail "$icon_src is missing"
[ -f "$version_src" ] || fail "$version_src is missing"
[ -d "$sparkle_src" ] \
  || fail "$sparkle_src is missing (swift build copies it next to skreenrek; run swift build first)"

# The one version string lives in SkreenrekVersion.swift: `static let current = "X.Y.Z"`.
version=$(sed -nE 's/.*static let current = "([^"]+)".*/\1/p' "$version_src" | head -n1)
[ -n "$version" ] || fail "can't read SkreenrekVersion.current from $version_src"

app="$out/Skreenrek.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"

cp "$binary" "$app/Contents/MacOS/skreenrek"
# The linker already signed the binary ad hoc; drop that so the bundle signature below starts clean.
codesign --remove-signature "$app/Contents/MacOS/skreenrek" || fail "codesign --remove-signature failed"
cp "$plist_src" "$app/Contents/Info.plist"
cp "$icon_src" "$app/Contents/Resources/AppIcon.icns"
plutil -replace CFBundleShortVersionString -string "$version" "$app/Contents/Info.plist"
plutil -lint -s "$app/Contents/Info.plist" || fail "the bundled Info.plist doesn't lint"

# Sparkle, found by the executable's @executable_path/../Frameworks rpath. The XPC services are only for sandboxed
# apps; Sparkle's docs say to remove them otherwise.
sparkle="$app/Contents/Frameworks/Sparkle.framework"
ditto "$sparkle_src" "$sparkle" || fail "can't copy $sparkle_src"
rm -rf "$sparkle/Versions/B/XPCServices" "$sparkle/XPCServices"
[ -e "$sparkle/Versions/B/Autoupdate" ] && [ -d "$sparkle/Versions/B/Updater.app" ] \
  || fail "$sparkle has no Versions/B/Autoupdate or Versions/B/Updater.app"

if [ "$sign" -eq 0 ]; then
  echo "$app"
  exit 0
fi

# Ad hoc builds never auto-update: without a feed and a key, Sparkle stays off and the update UI hides.
for key in SUFeedURL SUPublicEDKey; do
  if plutil -extract "$key" raw -o /dev/null "$app/Contents/Info.plist" >/dev/null 2>&1; then
    plutil -remove "$key" "$app/Contents/Info.plist" || fail "can't remove $key from the bundled Info.plist"
  fi
done

# Ad-hoc signature (`-`), inside-out in the same order as scripts/release.sh. No entitlements: unsandboxed, nothing
# special. No hardened runtime here: its library validation only loads a framework signed by the app's own team, and
# an ad-hoc signature has no team, so dyld would refuse Sparkle.framework. The Developer ID release keeps the hardened
# runtime (one team signs both).
for part in "$sparkle/Versions/B/Autoupdate" "$sparkle/Versions/B/Updater.app" "$sparkle"; do
  codesign --force --sign - "$part" || fail "codesign failed for $part"
done
codesign --force --sign - --identifier "$bundle_id" "$app" \
  || fail "codesign failed for $app"
codesign --verify --deep --strict "$app" || fail "codesign --verify --deep --strict failed for $app"

echo "$app"
