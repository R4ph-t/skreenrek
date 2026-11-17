#!/usr/bin/env bash
# Wrap the SwiftPM `skreenrek` executable into Skreenrek.app and sign it ad hoc.
#
#   scripts/bundle-app.sh <products-dir> <out-dir>
#
# <products-dir> is a SwiftPM bin path (e.g. .build/release) that holds the `skreenrek` executable. The script writes
# <out-dir>/Skreenrek.app/Contents/{MacOS/skreenrek,Info.plist} from packaging/Info.plist, stamps
# CFBundleShortVersionString from SkreenrekVersion.current, signs ad hoc with the hardened runtime, verifies the
# signature, and prints the bundle path. Ad hoc only: it never reads signing identities, keychains or secrets.
set -euo pipefail

fail() { echo "bundle-app: $*" >&2; exit 1; }

[ $# -eq 2 ] || fail "usage: scripts/bundle-app.sh <products-dir> <out-dir>"

root="$(cd "$(dirname "$0")/.." && pwd)"
products="$1"
out="$2"

bundle_id=it.fraime.skreenrek
plist_src="$root/packaging/Info.plist"
version_src="$root/Sources/SkreenrekCore/SkreenrekVersion.swift"
binary="$products/skreenrek"

[ -f "$binary" ] && [ -x "$binary" ] || fail "$binary is missing or not executable (run swift build first)"
[ -f "$plist_src" ] || fail "$plist_src is missing"
[ -f "$version_src" ] || fail "$version_src is missing"

# The one version string lives in SkreenrekVersion.swift: `static let current = "X.Y.Z"`.
version=$(sed -nE 's/.*static let current = "([^"]+)".*/\1/p' "$version_src" | head -n1)
[ -n "$version" ] || fail "can't read SkreenrekVersion.current from $version_src"

app="$out/Skreenrek.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"

cp "$binary" "$app/Contents/MacOS/skreenrek"
# The linker already signed the binary ad hoc; drop that so the bundle signature below starts clean.
codesign --remove-signature "$app/Contents/MacOS/skreenrek" || fail "codesign --remove-signature failed"
cp "$plist_src" "$app/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$version" "$app/Contents/Info.plist"
plutil -lint -s "$app/Contents/Info.plist" || fail "the bundled Info.plist doesn't lint"

# Ad-hoc signature (`-`) with the hardened runtime. No entitlements: unsandboxed, nothing special.
codesign --force --sign - --options runtime --identifier "$bundle_id" "$app" \
  || fail "codesign failed for $app"
codesign --verify --strict "$app" || fail "codesign --verify --strict failed for $app"

echo "$app"
