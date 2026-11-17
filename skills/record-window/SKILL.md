---
name: record-window
description: Record a macOS window at an exact pixel size as a smooth 30/60 fps MP4 with click events and a HyperFrames snippet. Use when asked to record, screencast or capture video of an app or window. Not for screenshots.
---

# Record a window

## Before you start

Run `skreenrek doctor --json`. If a permission is missing, tell the user which one and stop.

## Steps

1. List windows with `skreenrek_list_windows` or `skreenrek windows --json`. Pick a window ID.
2. Start with `skreenrek_start_recording` (windowId, size: "1080p", fps: 60) or
   `skreenrek record <window> --size 1080p --fps 60 --json`. Sizes are the clip's pixels: 720p, 1080p, 1440p, 4k,
   square, portrait, or WxH. Skreenrek sizes the window to fit the display. Read `exact` from the read-back.
   If it isn't true, stop and report the actual size. Never claim an exact size without the read-back.
3. Do the actions.
4. Stop with `skreenrek_stop_recording` or `skreenrek stop --json`.
5. Report the three paths from `files`: `clip`, `events`, and `snippet`. `events` is omitted with `--no-events`.

## Rules

- Prefer MCP tools if they're available, otherwise the CLI.
- Never record windows showing secrets or tokens.
- Keep clips short (start just before the first action).
- One recording at a time.
- Don't take screenshots with this tool.

## Errors

| Exit code | Error code | Action |
| --- | --- | --- |
| 0 | — | OK (for `resize`: the size is exact). Read the result. |
| 1 | `internal` | Report the error and its hint. Stop. |
| 2 | `usage` | Fix the flag or value using the hint, then retry. |
| 3 | `permission_denied` | Tell the user which permission is missing and stop. Run `skreenrek doctor --json` after it is allowed. |
| 4 | `not_exact` | Report the actual size. Pick the size in the hint, or use `--allow-inexact` only if an inexact size is acceptable. |
| 5 | `window_not_found` | List windows again and pick a window ID. |
| 5 | `window_ambiguous` | Pick a distinct window ID from the candidates. If Accessibility can't distinguish the windows, change the title or frame and list again. |
| 6 | `wrong_state` | Check `skreenrek status --json`. Stop the current recording before starting another. |
| 7 | `recording_failed` | Report the failure and any partial clip paths. Fix the cause in the hint before retrying. |
| 130 | — | Interrupted (Ctrl-C during `--wait`; the clip is saved). Report the saved paths. |

## Using the output with HyperFrames

The snippet is in `hyperframes.html` in the clip folder and in `snippet` from `stop --json`.
Paste it into the composition. Use `--assets DIR` (MCP: `assetsDir`) to drop the clip straight into a project's
assets folder. Without it, follow the exact `cp` command in the snippet's comment.

```html
<!-- Skreenrek · Safari — localhost:3000 · 1280×800 px · 60 fps · 42.0 s · clicks: events.json -->
<video class="clip" src="assets/2026-11-17_104207_safari.mp4"
       data-start="0" data-duration="42.0" data-track-index="0" muted playsinline></video>
```
