#!/usr/bin/env bash
# `make check`: a light, offline check of the factory's own config. Once Package.swift exists, the Makefile also
# runs `swift build` and `swift test`. It never signs, notarizes, or runs tests that need Screen Recording or
# Accessibility permission; those stay with Raph.
set -euo pipefail

cd "$(dirname "$0")/.."

fail() { echo "factory-check: $*" >&2; exit 1; }

conf=.factory/project.conf
[ -f "$conf" ] || fail "$conf is missing"

required="NAME REPO OWNER ROOT SPEC_DIR SPEC_INDEX BRANCH_PREFIX PROFILE MAKE_TARGETS TOOLS CI_WORKFLOW CHECK_NAME
RISKY_PATHS GUARDED_PATHS VM PROMPT_EXTRA AUTO_MERGE STATE_DIR"
optional="MAX_RUNS_PER_DAY MAX_TURNS_PER_DAY EXECUTOR EXECUTOR_FALLBACK EXECUTOR_BUILD EXECUTOR_FIX EXECUTOR_RESUME
AGENT_BUILD AGENT_FIX"

value() { grep -E "^$1=" "$conf" | head -n1 | cut -d= -f2-; }

n=0
while IFS= read -r line || [ -n "$line" ]; do
  n=$((n + 1))
  case "$line" in '' | '#'*) continue ;; esac
  key=${line%%=*}
  [ "$key" != "$line" ] || fail "$conf:$n: not KEY=value"
  case " $(echo $required $optional) " in *" $key "*) ;; *) fail "$conf:$n: unknown key $key" ;; esac
done < "$conf"

for key in $required; do
  grep -qE "^$key=" "$conf" || fail "$conf: missing $key"
done

[ "$(value AUTO_MERGE)" = 0 ] || fail "$conf: AUTO_MERGE must stay 0; Raph merges every PR"

wf=$(value CI_WORKFLOW)
check=$(value CHECK_NAME)
if [ "$wf" = none ]; then
  [ "$check" = none ] || fail "$conf: CI_WORKFLOW and CHECK_NAME are both none or both set"
else
  [ "$check" != none ] && [ -n "$check" ] || fail "$conf: CI_WORKFLOW and CHECK_NAME are both none or both set"
  compgen -G ".github/workflows/*.yml" >/dev/null || fail "$conf: CI_WORKFLOW=$wf but no .github/workflows/*.yml"
fi

# Each regex must compile (grep -E exits 2 on a bad pattern).
check_regex() {
  local status=0
  printf '' | grep -E -- "$1" >/dev/null 2>&1 || status=$?
  [ "$status" -ne 2 ] || fail "$2: bad regex: $1"
}
check_regex "$(value GUARDED_PATHS)" "$conf: GUARDED_PATHS"

risky=$(value RISKY_PATHS)
if [ "$risky" != none ]; then
  [ -f "$risky" ] || fail "$risky is missing"
  n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    case "$line" in '' | '#'*) continue ;; esac
    check_regex "$line" "$risky:$n"
  done < "$risky"
fi

index=$(value SPEC_INDEX)
[ -f "$index" ] || fail "$index is missing"
grep -qE '^\| # \| Spec \| Status \| Depends on \| Agent run \| Raph review \|$' "$index" \
  || fail "$index: missing the six-column table header"

prompt=$(value PROMPT_EXTRA)
[ -f "$prompt" ] || fail "$prompt is missing"

echo "factory-check: ok"
