# Fraime — Agent-controlled capture — brief — 2026-11-17

Source: CPO's Notion brief, https://app.notion.com/p/41b0d0d4459281588387f2e14d779d81

> Decision 2026-11-17
>
> Raph, relayed by Chief, \~10:15 Europe/Paris: "ok so let's build that. can be really simple cli with menu bar dd and that's it."
>
> Later the same day, also relayed by Chief, verbatim: "mcp", then "etc.. and sklills", then "we have a lot of that in fraiemit already".
>
> Later still, 10:27 Europe/Paris, relayed by Chief, verbatim: "yes to all".
>
> Later still, 10:29 Europe/Paris, relayed by Chief, verbatim: "I want that to be built with zero input from my end. let's see if we can go from brief/spec to final usable product".
>
> Later still, 10:30 Europe/Paris, relayed by Chief, verbatim: "no except for the nam".

Trigger: your note via Chief on 2026-11-17 ("the missing part to truly make it a good agent xp is the control over screenshot/screencast. Maybe a simpler tool hyperfocused on doing this perfectly for agents"). Read with your 2026-11-05 call: Fraime stays for demos only, and agent screenshot needs (grids, UI review) go to a separate thin tool. Context for the 2026-11-17 decision: Chief had told you Peekaboo can set window bounds pixel-exact (`window set-bounds`, and it reads the frame back) but its video is a burst of PNG frames stitched to MP4 (15 fps max, drops frames when idle, 3 min max, 1440 px cap by default). Your need is selecting windows and resizing them pixel-perfect so recordings come out at exactly the right size.

**Verdict: build it, by reusing what Fraime already has, as a thin capture surface — not a reframe of the app, and not a new engine.** The job is agent-controlled capture of a real window or region: list and select a window, set exact pixel bounds and verify the frame read back, record smooth real video, stop, and optionally write a click/cursor events file. Plain screenshots stay out of scope.

Decisions: [Fraime: agent-controlled capture as (a) a reframe of Fraime, (b) a new separate thin tool, or (c) an agent-capture mode/CLI that shares Fraime's engine and keeps the demo editor?](https://app.notion.com/p/41b0d0d44592812a9a4bf43be6ccdf3d) · [Fraime: run a 1–2 day spike exporting a .fraimeit recording as a HyperFrames clip bundle (raw MP4 + events.json + snippet) before building any agent-capture tool?](https://app.notion.com/p/41b0d0d4459281929d11cf1909521802)

## Problem

- HyperFrames builds videos from HTML. To get real product screens it captures a public website from a URL. That website capture only connects to public hosts (PR #5668), so [localhost](http://localhost), logged-in states, native Mac apps, IDEs and terminals are out of reach.
- Its screen-recording zoom component (Zoom Follow Cursor) takes one still screenshot plus three click points typed by hand as percentages. It doesn't take a real recording or real click timing.
- Peekaboo can size a window to the exact pixel and read the frame back, but its video is a stitched PNG burst with the caps above. That is not good enough when the recording has to come out at a chosen size, smoothly.
- Fraime can already record under agent control: it stages a window, can resize it, pauses capture while the agent thinks, resumes during each action, marks beats and writes session telemetry. But that path is built around Fraime's own editor and composited export — a large MCP surface plus a full demo-recording skill and orchestration doc. That's heavier than "record this window at this size and give me a clip".

## Who it's for

You, first: coding agents (Claude Code, Codex, Cursor) that need a correctly sized, smooth recording of your own apps (Fraime, WriteGood, motjong, raph-dev), including footage you might later drop into a HyperFrames video. Later, other HyperFrames users on Mac, if dogfooding shows it's worth it.

## Prior art (Chief's check, 2026-11-17)

Relayed by Chief; not independently verified by CPO.

Nothing does the whole job. Closest stack: Peekaboo `window set-bounds` (exact resize with read-back, MIT) plus Cap ([https://cap.so/docs/agents](https://cap.so/docs/agents): CLI, skill, `cap mcp serve`, `record --window --fps` up to 120, cursor and keypress tracks in Studio; no window resize; AGPL plus commercial terms). Others: Kestrel (menu-bar app plus MCP, window to MP4, no resize, €12 MCP licence), macos-screencap-mcp (thin MIT ScreenCaptureKit MP4, no resize or clicks, brand new), Screen Studio (exact resize and 4K/60, GUI only, no API), Aperture (Kap's engine, library only), autodemo (MCP, CLI and skill, but polished narrated demos rather than raw exact-size footage).

Gap to build: one command that does exact resize with read-back plus real 30/60 fps window video, through CLI, menu bar, MCP and skills, with cursor/click data and a short HyperFrames snippet.

## What exists vs what's missing

To be confirmed by Fraime Lead. Read-only pass over `R4ph-t/screencode` on 2026-11-17, default branch (`main`).

### Already in the repo

- **Recorder.** `screencode/screencode/CaptureEngine/` records a display, window, or area via ScreenCaptureKit. The README documents 30 or 60 fps, optional retina capture, and raw media stored in a `.fraimeit` package (`recording.mov` plus `session.fraimeit.json` with cursor samples and click events). Effects are applied at export, not at capture (`docs/adr/0003-record-raw-media-and-apply-effects-at-preview-export.md`). No Peekaboo-style 3-minute or 1440 px cap showed up in this pass; Fraime Lead should confirm there isn't one hiding in the encoder path.
- **Exact-ish window resize, with read-back.** `screencode/screencode/CaptureEngine/WindowResizeController.swift`, plus `screencode/WindowResizeHelper/` and `screencode/WindowResizeShared/`. The helper can resize to a named preset or to an exact global rect, then reads the accessibility frame back. `WindowResizeOutcome.isExact` treats a match within 2 points as exact.
- **MCP.** `screencode/FraimeMCP/main.swift` is a stdio MCP server. This pass counted 63 tools: 61 registered with `tool(name:)`, plus `fraimeit_stage_layout` and `fraimeit_activate_window`. Capture-related tools already include `fraimeit_list_capture_sources`, `fraimeit_stage_window`, `fraimeit_stage_layout`, `fraimeit_activate_window`, `fraimeit_configure_recording`, start/pause/resume/stop, `fraimeit_bind_viewport`, `fraimeit_mark_beat`, and begin/end window action. The rest is browser automation, IDE automation, and the editor (timeline, edit plans, transcription, export, and so on). An earlier draft of this brief said 74 tools; the current file has 63. `fraimeit_stop_recording` finalizes the recording, opens it, and returns a `packagePath` — a `.fraimeit` package, not a standalone clip. `screencode/screencode/AgentAPI/FraimeMCPInstallManager.swift` installs that helper into Claude Code, Codex, and Cursor. It also notes that the sandboxed app cannot execute a user-installed CLI.
- **CLI-ish piece.** FraimeMCP is that stdio MCP executable, not a human command-line tool for list / select / resize / record / stop.
- **Menu bar.** `screencode/screencode/App/ScreenCodeApp.swift` already has a `MenuBarExtra` (`ScreenCodeMenuBarView`): Start / Stop / Pause / Resume Recording, Recording Settings, Setup & Permissions, license and updates, Quit. It does not pick a window, apply size presets, or show the last clip. `screencode/screencode/App/MenuBarActions.swift` is the shared request/state layer used by the menu bar and by the agent bridge.
- **Skills and orchestration.** One bundled skill, `screencode/screencode/Resources/AgentSkills/record-fraimeit-demo/SKILL.md`, installed by `screencode/screencode/AgentAPI/FraimeAgentSkillManager.swift` into Cursor, Claude, and Codex. The orchestration doc is `docs/agents/agent-driven-demo-recording.md` (124 lines). Both describe the full demo path: stage, dry-run, record, edit, verify, export. They are not capture-only.

### Likely gaps

- A thin capture-only MCP and CLI surface for the same job, without the editor, browser, and IDE tools.
- Exact custom pixel bounds set-and-verify for a **single** window on that agent/CLI surface. The engine already has `resizeWindow(for:toGlobalRect:)`. `fraimeit_stage_window` takes a named preset only (`hd720p`, `fullHD1080p`, `portrait720p`, `maxPortrait9x16`, `square1080p`), not an arbitrary width and height. Explicit width and height exist on `fraimeit_stage_layout`, which arranges exactly two windows.
- A menu-bar dropdown for pick window, size presets, record/stop, and last clip.
- A capture-only skill (the existing skill is the full record–edit–export demo).
- A stop path that writes plain output files (a real video file, optional events file, and a short HyperFrames snippet as plain text) without opening the editor.

## v1 scope

Reuse Fraime's recorder, window-resize helper, MCP, and skill machinery where the engineer finds they fit. v1 is the same capture job, exposed four ways:

1. **A small CLI** to list windows, select a window, set its bounds to an exact pixel size and verify the frame read back, start and stop recording that window or region to a real video file (smooth, constant frame rate, native resolution, no Peekaboo-style 3-minute or 1440 px caps), optionally write a click/cursor events file, and write a short HyperFrames snippet as small plain-text output.
2. **A menu-bar dropdown** for the same controls: pick window, size presets, record/stop, last clip.
3. **A small MCP server** covering the same capture job, not the full editing MCP.
4. **Agent skills** for that same capture job.

Outputs: a real video file, an optional click/cursor events file, and a short HyperFrames snippet as small plain-text output.

The first milestone should prove recording quality (smooth, constant frame rate, native resolution, exact requested size). The earlier 1–2 day HyperFrames export-spike gate is superseded by the 2026-11-17 go-ahead; quality proof stays as the first milestone, not as a gate that blocks starting the work.

### Out of scope

- Editor integration, and any work on the Fraime editor, export pipeline, pricing, or website
- The full editing MCP (the current 63-tool surface in `screencode/FraimeMCP/main.swift`)
- Screenshots and grids for UI review or measuring (covered by Peekaboo, macos-screencap-mcp, and similar tools; GridProof stays parked)
- Windows or Linux
- Webcam, microphone, or system audio in this capture mode
- An upstream HyperFrames plugin or catalog component
- Public launch

## Effort and risks

- **Effort (Fraime Lead's guesses, not a sized plan):**
  - **Path A** — extract a shared Swift package: 3–5 weeks, high risk to [Fraime.app](http://Fraime.app) (CaptureEngine is 2,340 lines with 18 references to app-only types; no CI, so recorder regressions only show up in Raph's manual testing).
  - **Path B** — write it fresh on SCStream + AVAssetWriter + Accessibility resize + global mouse monitors, copying Fraime's patterns: 1.5–2.5 weeks for v1, no risk to Fraime, downside is two recorders that drift.
  - Either way: 2–4 days first-time Developer ID signing and notarization; own bundle ID, so users grant permissions again; unsandboxed, so resize runs in-process with no XPC helper; one `.app` that is also the CLI and the stdio MCP when run with arguments, with the CLI run from inside the bundle (a symlink is fine).
  - CPO recommendation: path B. Decided 2026-11-17 ("yes to all").
- **Risk, Cap overlap:** Cap is the strongest overlap; if Fraime Lead's inventory shows the reuse path is heavy, compare against wrapping Peekaboo + Cap (licence: Cap AGPL/commercial) before building.
- **Risk, quality:** if the first milestone does not produce smooth, correctly sized recordings that clearly beat Peekaboo's stitched PNG video, stop and reassess before expanding the surface.
- **Risk, scope creep:** the capture surface slowly turning into a second editor, or into a general screenshot tool. Hold the out-of-scope list.
- **Risk, permissions:** capture still depends on a signed app holding Screen Recording and Accessibility permission. A headless CLI without the app would bring back per-terminal permission prompts. A new bundle ID means users grant permissions again.
- **Risk, overlap:** HeyGen could ship native app capture itself. Low cost to drop the HyperFrames-oriented output if they do.

## Success metric (proposed, not observed)

- First milestone: a recording of a real window, at an exact requested size (verified on the frame read back), as a smooth real video file at native resolution, with no Peekaboo-style caps. If that isn't clearly better than a stitched PNG recording, stop.
- Target: constant 30 or 60 fps at native resolution, exact requested window size verified by read-back.
- After v1: from one prompt ("record this window at this size"), an agent can list, resize, record, and stop, and get back plain output files (video, optional events file, short HyperFrames snippet), with no manual recording and no editor window. Tool-call count should stay small relative to today's full demo MCP flow.

## Open decisions

Raph approved all seven on 2026-11-17, 10:27 Europe/Paris, relayed by Chief, verbatim: "yes to all". Marked Decided:

1. **Path:** B, write fresh. (CPO recommendation: B.) Decided.
2. **Name:** Designer proposes name options, Raph picks the name, and that pick is the only input from him. (Corrected 10:30 Europe/Paris, verbatim: "no except for the nam". Earlier CPO recommendation that Designer proposes the name is superseded.)
3. **Free/OSS vs paid:** free/OSS. (CPO recommendation: free/OSS.) Decided.
4. **Distribution:** notarized download first, then a Homebrew cask. (CPO recommendation: a notarized download, then a Homebrew cask.) Decided.
5. **`events.json`**** fields:** mouse button yes, keystrokes no in v1. (CPO recommendation: mouse button yes, keystrokes no in v1.) Decided.
6. **"dd":** dropdown menu. (CPO recommendation: read as menu-bar dropdown, assumed.) Decided.
7. **Signing setup for a new bundle ID:** signing/notarization for a new bundle ID approved. Decided.

## Repo and lead

Decided, per Manufacture Lead (relayed by Chief): this is built in Manufacture as its own new repo, owned by Fraime Lead. Raph had asked "should that be built in manufacture?"

## Zero-input run

No questions go back to Raph, except the name. Designer proposes name options, Raph picks the name, and that pick is the only input from him. CPO's recommended defaults are otherwise final, and Designer and the lead decide anything else. The only other thing that may need Raph is a Developer ID/notarization credential if none is already set up for the factory; if that's missing, ship an unsigned or ad-hoc-signed build first and add notarization once credentials exist, rather than blocking on him. Success for this run means going from brief to a usable product with no input from Raph besides the name pick.

## Sources

- Repo (private, read-only, 2026-11-17): [R4ph-t/screencode](https://github.com/R4ph-t/screencode) — README, `screencode/screencode/CaptureEngine/`, `screencode/screencode/CaptureEngine/WindowResizeController.swift`, `screencode/WindowResizeHelper/`, `screencode/WindowResizeShared/`, `screencode/FraimeMCP/main.swift`, `screencode/screencode/AgentAPI/FraimeMCPInstallManager.swift`, `screencode/screencode/App/ScreenCodeApp.swift`, `screencode/screencode/App/MenuBarActions.swift`, `screencode/screencode/Resources/AgentSkills/record-fraimeit-demo/SKILL.md`, `screencode/screencode/AgentAPI/FraimeAgentSkillManager.swift`, `docs/agents/agent-driven-demo-recording.md`, `docs/adr/0003-record-raw-media-and-apply-effects-at-preview-export.md`
- HyperFrames repo (Apache-2.0, HeyGen): [https://github.com/heygen-com/hyperframes](https://github.com/heygen-com/hyperframes)
- HyperFrames CLI guide (`capture` = capture a website): [https://hyperframes.heygen.com/developers/cli](https://hyperframes.heygen.com/developers/cli)
- HyperFrames website capture limited to public hosts: [https://github.com/heygen-com/hyperframes/pull/5668](https://github.com/heygen-com/hyperframes/pull/5668)
- Zoom Follow Cursor component (one screenshot plus hand-set click points): [https://hyperframes.heygen.com/catalog/components/cursor-zoom-follow.md](https://hyperframes.heygen.com/catalog/components/cursor-zoom-follow.md)
- Peekaboo (macOS screenshots and UI automation, MCP): [https://github.com/steipete/Peekaboo](https://github.com/steipete/Peekaboo) and [https://peekaboo.sh/MCP.html](https://peekaboo.sh/MCP.html)
- macos-screencap-mcp (ScreenCaptureKit screenshots and start/stop recording): [https://github.com/freeflow-im/macos-screencap-mcp](https://github.com/freeflow-im/macos-screencap-mcp)
- Notion: [fraime.it](https://app.notion.com/p/4030d0d4459281dc81e5ce8549e9f143)
