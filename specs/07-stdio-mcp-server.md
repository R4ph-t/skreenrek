# 07: stdio MCP server

Status: Done · Branch: lane/07-stdio-mcp-server · Depends on: 06 (CLI) · Estimate: 3–4 h agent run + 0 h Raph review (no hand test)
Source: Designer's spec (Notion "Agent capture tool — design spec v1 (2026-11-17)", 2026-11-17), from CPO's brief (Notion "Fraime — Agent-controlled capture — brief — 2026-11-17"). Plan: Fraime Lead's "Skreenrek v1 implementation plan (2026-11-17)".

## Goal

`skreenrek mcp` runs a stdio MCP server with the design spec's seven `skreenrek_…` tools, so an agent can do the
three-call flow (list → start with size → stop) and get the clip, events and snippet.

## Behaviour

1. New library target `SkreenrekMCP` (depends on Control) and test target `SkreenrekMCPTests`; `skreenrek mcp` in the
   CLI starts it. No MCP SDK dependency: JSON-RPC 2.0, one message per line on stdin/stdout.
2. Methods: `initialize` (negotiates `protocolVersion`: answers with the client's version when it is one of
   `2025-06-18`, `2025-03-26`, `2024-11-05`, else `2025-06-18`; `capabilities: { tools: { listChanged: false } }`;
   `serverInfo: { name: "skreenrek", version }`), `notifications/initialized`, `ping`, `tools/list`, `tools/call`.
   Unknown method → `-32601`; bad params or unknown tool → `-32602`; unparsable line → `-32700`.
3. Tools, inputs and outputs exactly as the design spec's MCP table: `skreenrek_list_windows`,
   `skreenrek_resize_window`, `skreenrek_start_recording`, `skreenrek_stop_recording`, `skreenrek_status`,
   `skreenrek_discard_recording`, `skreenrek_pick_window` (`timeoutSeconds`, default 60). Each has a JSON Schema
   `inputSchema` and a one-sentence description (no "Raph" or "CTO"). Results return `structuredContent` with the
   JSON plus one `text` content item holding the same JSON. Tool failures return `isError: true` with the
   `{ error: {code, message, hint} }` body.
4. Each call goes to the app over the control socket with `client.kind = "mcp"` and the client name from
   `initialize.clientInfo.name`, mapped for display: `claude-code` → `Claude Code`, `codex-mcp-client` → `Codex`,
   `cursor-vscode` → `Cursor`, anything else as given. The app is launched hidden when needed (06's launcher).
5. stdout carries only protocol messages; logs go to stderr.

## Defaults

- The protocol version list above; servers ignore unknown notifications.

## Guardrails

- The MCP process never captures in its own process.
- Tool names and schemas are covered by a golden `tools/list` snapshot test, so changes are deliberate.

## Out of scope

Installing the server into agent configs (09), resources and prompts, HTTP transport.

## Open question (built with the default)

- Client display names: the mapping table in 4.

## How to test (Raph)

1. No hand test is needed to merge: CI `factory check` must be green. The tests drive the server through in-memory
   pipes against a `HeadlessHost` with fakes: `initialize` (version negotiation), `tools/list` golden, list → start
   (with width and height) → stop producing the three files, the "Started by Claude Code over MCP" client name
   reaching the controller snapshot, not-exact and wrong-state errors as `isError: true`, the JSON-RPC error codes,
   and no stray stdout output.
2. Optional smoke (after hand spec 11 and 09, 3 min): in Claude Code, ask it to record a window for 5 seconds with
   the Skreenrek tools.

## Implementation notes

- **Targets.** `SkreenrekMCP` (Core + Control) holds the server; `SkreenrekCLI` depends on it and runs it for
  `skreenrek mcp`. No MCP SDK: `JSONValue` plus JSON-RPC 2.0, one message per line. stdin is read on a thread of its
  own (`StdioLines`), never on the Swift concurrency pool; a line over 4 MiB is cut and answered `-32700`.
- **Shared launcher.** 06's connect-and-launch logic moved from `SkreenrekCLI/AppConnector` to
  `SkreenrekControl/ControlConnector` (the same messages, hints and 10 s launch wait), so the CLI and MCP share it.
  `AppConnector` now delegates to it; `ControlClientError.body` holds the not-running/closed/timed-out bodies both
  report.
- **Calls.** Each tool call opens its own control connection as `{kind: "mcp", name}` (with the hidden launch when
  needed) and closes it after the answer. `tools/call` runs concurrently, so a 60 s `pick` doesn't block `ping`;
  every other method answers in order. On end of stdin the server waits for calls in flight, then exits 0.
- **Results.** The app's result JSON goes back as it is (`structuredContent` plus one `text` item with the same
  compact, sorted JSON), so fields later specs add to the control bodies (12's `video`) reach MCP with no change
  here. `isError: false` is set explicitly on success.
- **Errors.** Tool failures (app errors, app not running) are `isError: true` with `{error: {code, message, hint}}`,
  without the CLI's `exit` field (the design spec's MCP body names only those three). Unknown keys (also inside
  `region`), wrong types and missing required arguments are `-32602` before the app is contacted; range and state
  checks (`fps: 45`, wrong state, not exact) are the app's and come back as tool errors. A non-object message or a
  missing/wrong `jsonrpc` is `-32600`. Responses sent by the client and all notifications are ignored.
- **Inputs.** Exactly the design spec's MCP table: `skreenrek_resize_window` has no `allowInexact` (not in the table);
  `codec` and `name` stay CLI-only until 12 adds the format parameters. `outDir`/`assetsDir` resolve `~` and relative
  paths against the server's folder, as the CLI does.
- **Lenient start.** Tools work before `initialize` (the client name is then null, `startedBy` still `mcp`).
  `initialize` without `protocolVersion` answers `2025-06-18`. No `outputSchema` in `tools/list` (optional in
  `2025-06-18`; left out so the schema snapshot stays the inputs only).
- **Open question (default built):** the client display names are the table in 4; any other name shows as given, a
  blank name is null.
- **Tests.** `SkreenrekMCPTests` drives the server through a real stdin `Pipe` against a `HeadlessHost` with fakes on
  a real socket: version negotiation, the `tools/list` golden (`ToolsListGoldenTests`, pretty-printed), list → start
  (width/height) → stop writing clip, events and snippet with `client: "Claude Code"` in the snapshot, status and
  events.json, not-exact and wrong-state tool errors, the JSON-RPC codes, a pick not blocking ping, the hidden launch,
  and that stdout holds exactly one response per request. `MCPCommandTests` (CLI) runs `skreenrek mcp` itself.
