# 07: stdio MCP server

Status: Queued (herdr) · Branch: – · Depends on: 06 (CLI) · Estimate: 3–4 h agent run + 0 h Raph review (no hand test)
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

_(filled in by the agent)_
