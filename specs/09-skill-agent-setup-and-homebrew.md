# 09: record-window skill, agent setup and the Homebrew formula

Status: Queued (herdr) · Branch: – · Depends on: 06 (CLI), 07 (MCP), 11 (app bundle, by hand) · Estimate: 3–5 h agent run + 0 h Raph review (no hand test) · Risk: high
Source: Designer's spec (Notion "Agent capture tool — design spec v1 (2026-11-17)", 2026-11-17), from CPO's brief (Notion "Fraime — Agent-controlled capture — brief — 2026-11-17"). Plan: Fraime Lead's "Skreenrek v1 implementation plan (2026-11-17)".

## Goal

Agents learn the tool from one skill, `skreenrek setup agents` connects Claude Code, Codex and Cursor (MCP server plus
skill) and links the CLI, and a Homebrew formula in this repo builds and installs Skreenrek from source with no Apple
certificate. Risk is high because setup edits files in the user's agent folders.

## Behaviour

1. `skills/record-window/SKILL.md` with the design spec's shape: frontmatter (`name: record-window` and the exact
   description), "Before you start" (`skreenrek doctor --json`; stop and name the missing permission), "Steps"
   (list → `record --size WxH --fps 60`, read `exact` → act → `stop --json` → report the three paths), "Rules"
   (prefer MCP tools, never record windows showing secrets or tokens, keep clips short, one recording at a time, no
   screenshots), "Errors" (a table from each exit code and error code to the action), "Using the output with
   HyperFrames" (the snippet and `--assets`). The binary embeds the same text as a Swift string; a test fails if the
   two differ by one byte.
2. `skreenrek setup agents [--claude] [--codex] [--cursor] [--cli] [--remove] [--json]`. Without agent flags it acts
   on the agents it detects (`~/.claude`, `~/.codex`, `~/.cursor`). Per agent:
   - Skill → `~/.<agent>/skills/record-window/SKILL.md`.
   - MCP server `skreenrek` with command = the stable CLI path (below) and args `["mcp"]`: Claude Code in
     `~/.claude.json` `mcpServers`; Cursor in `~/.cursor/mcp.json` `mcpServers`; Codex in `~/.codex/config.toml` as a
     `[mcp_servers.skreenrek]` table between `# >>> skreenrek >>>` and `# <<< skreenrek <<<` marker lines. JSON files
     are merged, never rewritten wholesale; other keys keep their order and values.
   - `--cli`: symlink `~/.local/bin/skreenrek` to the app's executable; warns when `~/.local/bin` isn't on `PATH`.
   - Stable path: when the real executable sits in a Homebrew Cellar, use the `opt` path
     (`<brew prefix>/opt/skreenrek/Skreenrek.app/Contents/MacOS/skreenrek`) so upgrades don't break configs;
     otherwise the resolved real path.
   - Before the first edit of a file, one backup `<file>.skreenrek-backup`. Running twice changes nothing.
     `--remove` removes exactly what setup added. A file it can't parse is left untouched and reported (exit 1).
   - Human output: one `✓`/`✗` line per agent; `--json` a per-agent result list.
3. Settings (08) gains the Agents rows: one per client with status (`Connected`, `Found ~/.codex`, `Not installed`
   shown disabled) and [Connect] / [Remove] buttons calling the same installer.
4. `Formula/skreenrek.rb` (repo-local tap: `brew tap r4ph-t/skreenrek https://github.com/R4ph-t/skreenrek`):
   `head "https://github.com/R4ph-t/skreenrek.git", branch: "main"` (a `url`/`sha256` stable block is added at the v1
   tag), `depends_on macos: :sequoia`, `depends_on xcode: ["16.0", :build]`. `install` runs
   `swift build -c release --disable-sandbox --product skreenrek`, then `scripts/bundle-app.sh` (hand spec 11) to
   build an ad-hoc-signed `Skreenrek.app` into `prefix`, and `bin.install_symlink` to its executable. `caveats` say:
   link the app into `~/Applications`, open it once to grant Screen Recording and Accessibility, run
   `skreenrek setup agents`, and that macOS may ask for the permissions again after an upgrade (ad-hoc signature).
   `test do` checks `skreenrek --version`.
5. README gains an "Install" section with those commands.

## Defaults

- Claude Code's config is edited directly (no dependency on the `claude` command being installed).

## Guardrails

- Never touch a key or table that setup didn't add; never delete a user file; backups before the first edit.
- No absolute personal paths, user names or team IDs in the formula, the skill or tests.
- Tests use a temp `HOME`; they never read or write the real home folder.

## Out of scope

A Homebrew cask, a notarized DMG and Sparkle (after v1, when a Developer ID exists); publishing to homebrew-core.

## Open question (built with the default)

- The design spec mentions a cask; v1 has no certificate, so a build-from-source formula in this repo ships instead.

## How to test (Raph)

1. No hand test is needed to merge: CI `factory check` must be green. The tests cover the skill byte-equality, install
   into a temp `HOME` for each agent (JSON merge keeps other servers, TOML marker block), idempotence, `--remove`
   restoring the originals, an unparsable config left untouched, the Cellar → `opt` path rule, the `~/.local/bin`
   symlink and PATH warning, and `ruby -c Formula/skreenrek.rb` passing when Ruby is present.
2. Optional smoke (5–10 min, builds from source): `brew tap r4ph-t/skreenrek https://github.com/R4ph-t/skreenrek &&
   brew install --HEAD skreenrek && skreenrek --version`.

## Implementation notes

_(filled in by the agent)_
