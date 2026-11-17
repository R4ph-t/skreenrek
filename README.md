# skreenrek

A small standalone macOS agent screen-capture tool (menu bar, CLI, MCP and an agent skill in one binary). It lists
windows, resizes one to an exact pixel size and reads the frame back, records it at native resolution (H.264, constant
30 or 60 fps), and writes `clip.mp4`, `events.json`, and a HyperFrames snippet.

Free and open source (MIT). Unsandboxed; v1 is ad-hoc signed and installed with a Homebrew build-from-source formula.
It shares no code with Fraime. The build plan is in `specs/` (index: `specs/README.md`).
