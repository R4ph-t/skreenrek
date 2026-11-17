# skreenrek specs: index

Specs for the factory (Manufacture, `.factory/project.conf`) live here, one branch and PR each. The factory picks the
first `Ready` row whose `Depends on` are all `Done`. `AUTO_MERGE=1`: it merges on a green `factory check` plus a `merge`
verdict; `Risk: high` specs and risky paths wait for a Merge OK.

Skreenrek v1 is specs 01–11, planned in Fraime Lead's "Skreenrek v1 implementation plan (2026-11-17)" (Notion, Bot Docs)
from Designer's spec. 11 is a hand spec (guarded files: Info.plist, `scripts/`, `Makefile`, `.github/`), so the
factory skips it; 09 waits until it is `Done`. Every spec merges on a green `factory check` with no hand test.

| # | Spec | Status | Depends on | Agent run | Raph review |
|---|---|---|---|---|---|
| 01 | [Swift package scaffold, domain types and test seams](01-package-scaffold-and-seams.md) | Ready | – | 3–4 h | 0 h |
| 02 | [Window list and exact resize with read-back](02-window-list-and-exact-resize.md) | Ready | 01 | 3–5 h | 0 h |
| 03 | [Constant-frame-rate recorder pipeline and ScreenCaptureKit frame source](03-cfr-recorder-pipeline.md) | Ready | 01 | 6–8 h | 0 h |
| 04 | [events.json and the HyperFrames snippet](04-events-json-and-hyperframes-snippet.md) | Ready | 01 | 3–4 h | 0 h |
| 05 | [Controller state machine and the local control socket](05-controller-and-local-socket.md) | Ready | 02, 03, 04 | 4–6 h | 0 h |
| 06 | [CLI commands, output and exit codes](06-cli-commands.md) | Ready | 05 | 5–7 h | 0 h |
| 07 | [stdio MCP server](07-stdio-mcp-server.md) | Ready | 06 | 3–4 h | 0 h |
| 08 | [Menu-bar icon, dropdown, Settings and the stop shortcut](08-menu-bar-dropdown-and-settings.md) | Ready | 05 | 5–7 h | 0 h |
| 11 | [App bundle packaging, Info.plist and ad-hoc signing (hand spec)](11-app-bundle-packaging.md) | Ready | 01, by hand (Fraime Lead) | – | 0 h |
| 09 | [record-window skill, agent setup and the Homebrew formula](09-skill-agent-setup-and-homebrew.md) | Ready | 06, 07, 11 | 3–5 h | 0 h |
| 10 | [Window picker overlay, recording HUD and permissions onboarding](10-picker-hud-and-onboarding.md) | Ready | 08, 09 | 6–8 h | 0 h |

Status values: `Draft` → `Ready` (Raph approved the spec) → `In progress` → `In review` → `Done`.
**Approval:** Raph merging a spec PR that sets `Status: Ready` is his approval of that spec.
