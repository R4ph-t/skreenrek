#!/usr/bin/env bash
# Build, Developer ID sign, notarize and staple Skreenrek.app, then zip it for a GitHub release.
#
#   scripts/release.sh <version>          (or: make release VERSION=x.y.z)
#
# Writes dist/Skreenrek-<version>.zip (the stapled app, zipped with ditto --keepParent),
# dist/Skreenrek-<version>.zip.sha256, and dist/Skreenrek-<version>-notes.md (the CHANGELOG.md section for
# <version>). It never creates a git tag or a GitHub release: publishing stays a manual step
# (`gh release create v<version> dist/Skreenrek-<version>.zip --notes-file dist/Skreenrek-<version>-notes.md`).
#
# Signing material comes from the login Keychain, named by two env vars:
#   SKREENREK_SIGN_IDENTITY   the Developer ID Application identity (default below)
#   SKREENREK_NOTARY_PROFILE  a `notarytool store-credentials` profile (default: skreenrek)
# The script only passes these names to codesign and notarytool. It never reads, prints or exports a key or password.
#
# Local and dev builds (`make app`, `make check`) stay ad-hoc signed and need no certificate.
set -euo pipefail

fail() { echo "release: error: $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

[ $# -eq 1 ] || fail "usage: scripts/release.sh <version>   (e.g. make release VERSION=1.0.1)"
version="$1"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version '$version' isn't x.y.z"

identity="${SKREENREK_SIGN_IDENTITY-Developer ID Application: Raphael Terrier (XUVRMHYZV7)}"
profile="${SKREENREK_NOTARY_PROFILE-skreenrek}"
[ -n "$identity" ] || fail "SKREENREK_SIGN_IDENTITY is empty; set it to a 'Developer ID Application: …' identity"
[ -n "$profile" ] || fail "SKREENREK_NOTARY_PROFILE is empty; set it to a notarytool keychain profile"
case "$identity" in
  "Developer ID Application: "*) ;;
  *) fail "SKREENREK_SIGN_IDENTITY must be a 'Developer ID Application: …' identity, got '$identity'" ;;
esac

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

bundle_id=com.raphaelterrier.skreenrek
version_src=Sources/SkreenrekCore/SkreenrekVersion.swift
source_version=$(sed -nE 's/.*static let current = "([^"]+)".*/\1/p' "$version_src" | head -n1)
[ "$source_version" = "$version" ] \
  || fail "VERSION=$version but $version_src says $source_version; bump SkreenrekVersion.current first"

work="build/release-$version"
dist=dist
app="$work/Skreenrek.app"
zip="$dist/Skreenrek-$version.zip"
notes="$dist/Skreenrek-$version-notes.md"
notary_zip="$work/Skreenrek-$version-notarize.zip"

# Before the Keychain, the build, or signing: a release with no changelog section does not get a zip.
step "Reading the changelog"
notes_tmp="$(mktemp)"
if ! bash scripts/release-notes.sh "$version" >"$notes_tmp"; then
  rm -f "$notes_tmp"
  fail "CHANGELOG.md has no section for $version. Add a ## [$version] section before releasing."
fi
mkdir -p "$dist"
cat "$notes_tmp" >"$notes"
rm -f "$notes_tmp"

step "Checking the signing identity and notary profile"
command -v xcrun >/dev/null || fail "xcrun not found; install Xcode"
identities=$(security find-identity -v -p codesigning)
grep -qF "\"$identity\"" <<<"$identities" \
  || fail "no valid codesigning identity '$identity' in the Keychain (set SKREENREK_SIGN_IDENTITY)"
xcrun notarytool history --keychain-profile "$profile" --output-format json >/dev/null 2>&1 \
  || fail "notarytool keychain profile '$profile' is missing or invalid (set SKREENREK_NOTARY_PROFILE, or run xcrun notarytool store-credentials $profile)"
echo "identity: $identity"
echo "profile:  $profile"

step "Building universal release binary (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64 --product skreenrek
products=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

step "Bundling (unsigned)"
rm -rf "$work"
mkdir -p "$work" "$dist"
rm -f "$zip" "$zip.sha256"
bash scripts/bundle-app.sh --unsigned "$products" "$work" >/dev/null
[ -d "$app" ] || fail "bundle-app.sh didn't produce $app"
plutil -replace CFBundleVersion -string "$version" "$app/Contents/Info.plist"

step "Signing with Developer ID (hardened runtime, secure timestamp)"
# Inside-out: every nested Mach-O first (frameworks, helpers, dylibs), then the app bundle, which seals the main
# executable. No entitlements file: the app is unsandboxed and needs no hardened-runtime exception.
main_exec="$app/Contents/MacOS/skreenrek"
while IFS= read -r -d '' file; do
  [ "$file" = "$main_exec" ] && continue
  kind=$(file -b "$file")
  if [[ "$kind" == *Mach-O* ]]; then
    codesign --force --sign "$identity" --options runtime --timestamp "$file" || fail "codesign failed for $file"
  fi
done < <(find "$app/Contents" -type f -print0 | sort -rz)
codesign --force --sign "$identity" --options runtime --timestamp --identifier "$bundle_id" "$app" \
  || fail "codesign failed for $app"

step "Verifying the signature"
codesign --verify --deep --strict --verbose=2 "$app" || fail "codesign --verify --deep --strict failed"
# Capture before grepping: `grep -q` exits early, and under pipefail the writer's SIGPIPE would fail the pipeline.
entitlements=$(codesign -d --entitlements - --xml "$app" 2>/dev/null || true)
case "$entitlements" in
  *get-task-allow*) fail "the signed app carries get-task-allow; notarization would reject it" ;;
esac
details=$(codesign -dv --verbose=2 "$app" 2>&1)
grep -E '^(Identifier|Format|Authority|TeamIdentifier|Timestamp|CodeDirectory)' <<<"$details" || true
grep -qE '^CodeDirectory .*flags=.*runtime' <<<"$details" || fail "the hardened runtime flag is missing"
grep -qF "Authority=$identity" <<<"$details" || fail "the app isn't signed by '$identity'"
# Before notarization spctl may accept the app (source=Developer ID) or reject it as "Unnotarized Developer ID",
# depending on the Mac's Gatekeeper state. Either is fine here; the origin must be our identity.
pre=$(spctl -a -vv -t exec "$app" 2>&1 || true)
echo "$pre"
case "$pre" in
  *"origin=$identity"*) ;;
  *) fail "spctl doesn't see '$identity' as the origin of $app" ;;
esac

step "Notarizing (notarytool submit --wait)"
ditto -c -k --keepParent "$app" "$notary_zip"
result="$work/notary-submit.json"
xcrun notarytool submit "$notary_zip" --keychain-profile "$profile" --wait --output-format json >"$result" \
  || true
submission=$(plutil -extract id raw -o - "$result" 2>/dev/null || true)
status=$(plutil -extract status raw -o - "$result" 2>/dev/null || true)
[ -n "$submission" ] || { cat "$result" >&2; fail "notarytool submit returned no submission id"; }
echo "submission id: $submission"
echo "status:        $status"
xcrun notarytool log "$submission" --keychain-profile "$profile" "$work/notary-log.json" >/dev/null 2>&1 || true
if [ "$status" != Accepted ]; then
  [ -f "$work/notary-log.json" ] && cat "$work/notary-log.json" >&2
  fail "notarization status is '$status', not Accepted (log: $work/notary-log.json)"
fi
rm -f "$notary_zip"

step "Stapling"
xcrun stapler staple "$app" || fail "stapler staple failed"
xcrun stapler validate "$app" || fail "stapler validate failed"
codesign --verify --deep --strict "$app" || fail "codesign --verify failed after stapling"
post=$(spctl -a -vv -t exec "$app" 2>&1) || { echo "$post" >&2; fail "spctl rejects the stapled app"; }
echo "$post"
case "$post" in
  *accepted*"Notarized Developer ID"*) ;;
  *) fail "spctl doesn't report 'accepted' with 'Notarized Developer ID'" ;;
esac

step "Zipping the stapled app"
ditto -c -k --keepParent "$app" "$zip"
(cd "$dist" && shasum -a 256 "$(basename "$zip")" >"$(basename "$zip").sha256")
# Check what ships: the app unpacked from the final zip must still verify and carry its ticket.
check="$work/zip-check"
rm -rf "$check"
mkdir -p "$check"
ditto -x -k "$zip" "$check"
codesign --verify --deep --strict "$check/Skreenrek.app" || fail "the app in $zip doesn't verify"
xcrun stapler validate "$check/Skreenrek.app" >/dev/null || fail "the app in $zip has no stapled ticket"
rm -rf "$check"

step "Done"
echo "submission id: $submission"
codesign -dv --verbose=2 "$app" 2>&1 | sed -E '/^(Executable|Hash|CandidateCDHash|CMSDigest|Sealed|Internal|Info.plist)/d'
cat "$dist/$(basename "$zip").sha256"
echo "Publish (not done here): gh release create v$version $zip --notes-file $notes"
