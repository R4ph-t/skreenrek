#!/usr/bin/env bash
# Print one Keep a Changelog section.
#
#   scripts/release-notes.sh <version> [file]
#   make release-notes VERSION=x.y.z
#
# The section runs from the `## [version]` heading through the line before the next `## ` heading, or through the
# end of the file when nothing follows. The default file is CHANGELOG.md at the repo root. A missing section is an
# error, so `make release` can refuse to build. `make release` writes the same text to
# dist/Skreenrek-<version>-notes.md, and publishing passes it to
# `gh release create vX.Y.Z dist/Skreenrek-X.Y.Z.zip --notes-file dist/Skreenrek-X.Y.Z-notes.md`.
set -euo pipefail

fail() { echo "release-notes: error: $*" >&2; exit 1; }

[ $# -ge 1 ] && [ $# -le 2 ] || fail "usage: scripts/release-notes.sh <version> [changelog]"
version="$1"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version '$version' isn't x.y.z"

root="$(cd "$(dirname "$0")/.." && pwd)"
file="${2:-$root/CHANGELOG.md}"
[ -f "$file" ] || fail "no changelog at $file"

# Match the heading as text. A version is a prefix of a longer one (`1.0.1` vs `1.0.10`), so the character after
# `## [x.y.z]` has to be the end of the line or whitespace, not another digit.
heading="## [$version]"
section="$(
  awk -v heading="$heading" '
    function is_heading(line,    n, c) {
      n = length(heading)
      if (index(line, heading) != 1) return 0
      if (length(line) == n) return 1
      c = substr(line, n + 1, 1)
      return c == " " || c == "\t"
    }
    is_heading($0) { found = 1; print; next }
    found && index($0, "## ") == 1 { exit }
    found { print }
    END { if (!found) exit 1 }
  ' "$file"
)" || fail "no ## [$version] section in $file"

printf '%s\n' "$section"
