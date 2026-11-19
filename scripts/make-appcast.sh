#!/usr/bin/env bash
# Write the Sparkle appcast for one release: an RSS 2.0 feed with a single item, the zip `make release` built.
#
#   scripts/make-appcast.sh <version> <zip> <notes.md> <out.xml>
#
# scripts/release.sh runs it after the zip check and writes dist/appcast.xml, which is uploaded next to the zip:
# `gh release create vX.Y.Z dist/Skreenrek-X.Y.Z.zip dist/appcast.xml --notes-file …`. The app's SUFeedURL is
# https://github.com/R4ph-t/skreenrek/releases/latest/download/appcast.xml, which always follows the newest
# non-prerelease release, so one item is enough.
#
# The EdDSA signature comes from Sparkle's sign_update with the private key in the login Keychain (account
# `skreenrek`). The script never passes a key or key file, and never prints one. SPARKLE_SIGN_UPDATE overrides the
# tool's path (default: the copy SwiftPM unpacks into .build/artifacts).
# The notes (the CHANGELOG section) go in as Markdown, which Sparkle 2.9 and later renders in its update window.
set -euo pipefail

fail() { echo "make-appcast: error: $*" >&2; exit 1; }

[ $# -eq 4 ] || fail "usage: scripts/make-appcast.sh <version> <zip> <notes.md> <out.xml>"
version="$1"
zip="$2"
notes="$3"
out="$4"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version '$version' isn't x.y.z"
[ -f "$zip" ] || fail "no zip at $zip"
[ -f "$notes" ] || fail "no release notes at $notes"
command -v xmllint >/dev/null || fail "xmllint not found"

root="$(cd "$(dirname "$0")/.." && pwd)"
sign_update="${SPARKLE_SIGN_UPDATE:-$root/.build/artifacts/sparkle/Sparkle/bin/sign_update}"
[ -x "$sign_update" ] || fail "sign_update not found at $sign_update (run swift build first, or set SPARKLE_SIGN_UPDATE)"

# Prints `sparkle:edSignature="…" length="…"`. Capture before parsing: under pipefail a failed tool must stop here.
attributes=$("$sign_update" --account skreenrek "$zip") || fail "sign_update failed for $zip"
signature=$(sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p' <<<"$attributes" | head -n1)
length=$(sed -nE 's/.*length="([0-9]+)".*/\1/p' <<<"$attributes" | head -n1)
[[ "$signature" =~ ^[A-Za-z0-9+/=]+$ ]] || fail "sign_update printed no sparkle:edSignature"
[[ "$length" =~ ^[0-9]+$ ]] || fail "sign_update printed no length"

# The section without its `## [x.y.z] - date` heading (Sparkle's window already names the version). A literal `]]>`
# would end the CDATA block early, so it is split across two blocks.
body=$(sed '1{/^## \[/d;}' "$notes")
body=${body//']]>'/']]]]><![CDATA[>'}

pub_date=$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')
url="https://github.com/R4ph-t/skreenrek/releases/download/v$version/Skreenrek-$version.zip"

mkdir -p "$(dirname "$out")"
cat >"$out" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Skreenrek</title>
    <link>https://github.com/R4ph-t/skreenrek</link>
    <description>Skreenrek releases</description>
    <language>en</language>
    <item>
      <title>Skreenrek $version</title>
      <pubDate>$pub_date</pubDate>
      <sparkle:version>$version</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/R4ph-t/skreenrek/releases</sparkle:fullReleaseNotesLink>
      <description sparkle:format="markdown"><![CDATA[
$body
]]></description>
      <enclosure url="$url" type="application/octet-stream" sparkle:edSignature="$signature" length="$length"/>
    </item>
  </channel>
</rss>
EOF

xmllint --noout "$out" || fail "$out isn't well-formed XML"
grep -q 'sparkle:edSignature="' "$out" || fail "$out has no sparkle:edSignature"
echo "$out"
