# 09: record-window skill, agent setup and the Homebrew formula

Status: Done · Branch: lane/09-skill-agent-setup-and-homebrew · Depends on: 06 (CLI), 07 (MCP), 11 (app bundle, by hand) · Estimate: 3–5 h agent run + 0 h Raph review (no hand test) · Risk: high
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

1. No hand test is needed to merge: local `make check` must pass at the PR head, with its result posted as a PR comment.
   The tests cover the skill byte-equality, install
   into a temp `HOME` for each agent (JSON merge keeps other servers, TOML marker block), idempotence, `--remove`
   restoring the originals, an unparsable config left untouched, the Cellar → `opt` path rule, the `~/.local/bin`
   symlink and PATH warning, and `ruby -c Formula/skreenrek.rb` passing when Ruby is present.
2. Optional smoke (5–10 min, builds from source): `brew tap r4ph-t/skreenrek https://github.com/R4ph-t/skreenrek &&
   brew install --HEAD skreenrek && skreenrek --version`.

## Implementation notes

- Added the repository skill and its byte-identical embedded Swift string, the shared `AgentInstaller` in Core,
  `setup agents`, and an Agents section between Stop shortcut and Permissions in Settings. The Settings renderer
  uses a synthetic home; installer tests use temporary homes, never the user's agent folders.
- JSON edits replace only the Skreenrek member, preserving other keys, values, order and formatting. Codex gets
  the specified marker block. Existing user-owned servers and skills are left untouched and reported. First-edit
  backups of existing files are retained. A private ownership ledger in Application Support records what setup
  added; removal restores an unchanged config byte for byte, or removes just the owned entry after unrelated edits.
  Config files are never deleted; a newly created config becomes empty TOML or an empty JSON object on removal.
- Defaults where no exact setup copy/schema was specified: JSON is an array of `{agent, success, message, warnings}`;
  human output is one `✓`/`✗` line per selection. No flags selects detected agent folders; `--cli` alone only links
  the command. A missing PATH entry is a warning, not a failed install. Settings also includes Command-line tool.
- Setup fails closed on symlinked config files, paths outside the supplied home, duplicate keys, malformed or
  unsupported TOML, and later user edits to an owned server or skill. The conservative TOML reader supports quoted
  and dotted keys, strings (including multiline), arrays, inline tables and arrays of tables; date/time literals
  are left untouched and reported as unsupported. A nonblocking file lock prevents concurrent setup writes.
- Built the stated distribution default: a repo-local, HEAD-only Homebrew formula, using spec 11's existing
  bundler and ad-hoc signature. A stable `url`/`sha256` block waits for the v1 tag; no cask or certificate is needed.
  Cellar paths become `opt/skreenrek` paths for both MCP commands and the optional CLI link.
- PR #12's distinct AX candidate IDs, invalid-element cache eviction and per-window unreadable-frame handling
  are already present on the base branch; this lane does not alter those implementations.
- Validation uses permission-free tests, Ruby syntax checking when available, and `make check` on the Devin
  macOS VM. Async test waits have watchdogs; no live capture, Accessibility test or menu-bar app launch is used.
  The optional Homebrew installation smoke is left for a machine where installing the app is intended.
