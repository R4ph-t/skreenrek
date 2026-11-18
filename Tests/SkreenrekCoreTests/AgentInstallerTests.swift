import Foundation
@testable import SkreenrekCore
import Testing

@Suite struct AgentInstallerTests {
    struct Home {
        let temp: TempFolder
        var url: URL { temp.url.resolvingSymlinksInPath() }
        var installer: AgentInstaller { installer(executable: "Skreenrek.app/Contents/MacOS/skreenrek") }
        /// Real files, but only inside this home: /Applications and Homebrew on the test Mac never count.
        var files: CommandFiles {
            let root = url.path + "/"
            let system = CommandFiles.system
            return CommandFiles(
                exists: { $0.hasPrefix(root) && system.exists($0) },
                isExecutable: { $0.hasPrefix(root) && system.isExecutable($0) }, resolve: system.resolve)
        }
        /// The app executable setup records. It exists, so connections read as working.
        var executable: URL { file("Skreenrek.app/Contents/MacOS/skreenrek") }
        init() throws {
            temp = try TempFolder("agents")
            try makeExecutable("Skreenrek.app/Contents/MacOS/skreenrek")
        }
        func makeExecutable(_ path: String) throws {
            try write(path, "binary")
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file(path).path)
        }
        func installer(executable path: String) -> AgentInstaller {
            AgentInstaller(home: url, executablePath: file(path).path, path: url.appendingPathComponent(".local/bin").path,
                           files: files)
        }
        func file(_ path: String) -> URL { url.appendingPathComponent(path) }
        func write(_ path: String, _ text: String) throws {
            try FileManager.default.createDirectory(at: file(path).deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file(path))
        }
        func read(_ path: String) throws -> String { try String(contentsOf: file(path), encoding: .utf8) }
        func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: file(path).path) }
    }

    @Test func skillMatchesRepositoryByteForByte() throws {
        let file = GuardrailTests.root.appendingPathComponent("skills/record-window/SKILL.md")
        #expect(try Data(contentsOf: file) == Data(RecordWindowSkill.text.utf8))
    }

    @Test func skillPrefersMCPToolsAndCoversTheSandbox() {
        let text = RecordWindowSkill.text
        for tool in ["skreenrek_list_windows", "skreenrek_resize_window", "skreenrek_start_recording",
                     "skreenrek_stop_recording", "skreenrek_status", "skreenrek_discard_recording", "skreenrek_pick_window"] {
            #expect(text.contains("`\(tool)`"), "\(tool)")
        }
        #expect(text.contains("Use the skreenrek MCP tools first"))
        #expect(text.contains("`sandboxed`"))
        #expect(text.contains("ask the user to allow network access for that command"))
        for section in ["## Before you start", "## Steps", "## Rules", "## Errors", "## Using the output with HyperFrames"] {
            #expect(text.contains("\n\(section)\n"), "\(section)")
        }
    }

    /// The skill 1.0.1 installed, byte for byte.
    static let earlierSkill = #"""
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
"""# + "\n"

    @Test(arguments: [AgentClient.claude, .codex, .cursor])
    func earlierSkillIsUpdatedOnReconnectAndRemovable(_ agent: AgentClient) throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        #expect(home.installer.run(agents: [agent]).allSatisfy { $0.success })
        let config = try home.read(agent.config)
        try home.write(agent.skill, Self.earlierSkill)
        #expect(home.installer.connections().first { $0.agent == agent }?.connected == true)
        #expect(home.installer.run(agents: [agent]).allSatisfy { $0.success })
        #expect(try home.read(agent.skill) == RecordWindowSkill.text)
        #expect(try home.read(agent.config) == config)
        try home.write(agent.skill, Self.earlierSkill)
        #expect(home.installer.run(agents: [agent], remove: true).allSatisfy { $0.success })
        #expect(!home.exists(agent.skill))
        // An edited skill is still the user's.
        #expect(home.installer.run(agents: [agent]).allSatisfy { $0.success })
        try home.write(agent.skill, Self.earlierSkill + "mine\n")
        #expect(home.installer.run(agents: [agent]).allSatisfy { !$0.success })
        #expect(try home.read(agent.skill) == Self.earlierSkill + "mine\n")
    }

    @Test(arguments: [AgentClient.claude, .codex, .cursor])
    func roundTripAndIdempotence(_ agent: AgentClient) throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        let original = agent == .codex
            ? "# Keep this comment\nmodel = \"gpt-5\"\n[mcp_servers.other]\ncommand = \"other\"\nargs = [\"a\", \"b\"]\n"
            : "{\n  \"theme\": \"dark\",\n  \"mcpServers\": {\"other\" : {\"command\": \"other\", \"args\": [\"a\"]}},\n  \"tail\": [1, {\"key\": true}]\n}\n"
        try home.write(agent.config, original)
        #expect(home.installer.run(agents: [agent]).allSatisfy { $0.success })
        let installed = try home.read(agent.config)
        #expect(installed.contains(agent == .codex ? "[mcp_servers.other]\ncommand = \"other\"" : "\"other\" : {\"command\": \"other\", \"args\": [\"a\"]}"))
        #expect(installed.contains(agent == .codex ? "# >>> skreenrek >>>\n[mcp_servers.skreenrek]" : "\"skreenrek\""))
        #expect(try home.read(agent.skill) == RecordWindowSkill.text)
        #expect(try home.read(agent.config + ".skreenrek-backup") == original)
        #expect(home.installer.connections().first { $0.agent == agent }?.status == "Connected")
        let ledger = try home.read("Library/Application Support/skreenrek/agent-setup.json")
        #expect(home.installer.run(agents: [agent]).allSatisfy { $0.success })
        #expect(try home.read(agent.config) == installed)
        #expect(try home.read("Library/Application Support/skreenrek/agent-setup.json") == ledger)
        #expect(home.installer.run(agents: [agent], remove: true).allSatisfy { $0.success })
        #expect(try home.read(agent.config) == original)
        #expect(!home.exists(agent.skill))
        #expect(home.installer.run(agents: [agent], remove: true).allSatisfy { $0.success })
        #expect(try home.read(agent.config + ".skreenrek-backup") == original)
        // A later reconnect keeps the very first backup.
        try home.write(agent.config, original + (agent == .codex ? "# new\n" : "\n"))
        #expect(home.installer.run(agents: [agent]).allSatisfy { $0.success })
        #expect(try home.read(agent.config + ".skreenrek-backup") == original)
    }

    @Test(arguments: [AgentClient.claude, .codex, .cursor])
    func removalKeepsLaterUserEdits(_ agent: AgentClient) throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        try home.write(agent.config, agent == .codex ? "model = \"first\"\n" : "{\"model\":\"first\",\"mcpServers\":{\"other\":{}}}\n")
        #expect(home.installer.run(agents: [agent]).allSatisfy { $0.success })
        let updated = try home.read(agent.config).replacingOccurrences(of: "first", with: "second")
        try home.write(agent.config, updated)
        #expect(home.installer.run(agents: [agent], remove: true).allSatisfy { $0.success })
        let removed = try home.read(agent.config)
        #expect(removed.contains("second"))
        #expect(!removed.contains("skreenrek"))
        if agent == .codex { try TOMLConfig.validate(removed) }
        else { _ = try JSONSerialization.jsonObject(with: Data(removed.utf8)) }
    }

    @Test(arguments: [AgentClient.claude, .codex, .cursor])
    func changedOwnedEntryIsLeftAlone(_ agent: AgentClient) throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        #expect(home.installer.run(agents: [agent]).allSatisfy { $0.success })
        let changed = try home.read(agent.config).replacingOccurrences(of: "\"mcp\"", with: "\"custom\"")
        try home.write(agent.config, changed)
        #expect(home.installer.run(agents: [agent], remove: true).allSatisfy { !$0.success })
        #expect(try home.read(agent.config) == changed)
        #expect(home.exists(agent.skill))
    }

    @Test(arguments: ["{}", "{\"mcpServers\":{\"other\":{\"command\":\"other\"}}}"])
    func jsonByteOrderMarkSurvivesSetupAndRemoval(_ object: String) throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        let original = "\u{feff}" + object + "\n"
        try home.write(AgentClient.claude.config, original)
        #expect(home.installer.run(agents: [.claude]).allSatisfy { $0.success })
        let installed = String(decoding: try Data(contentsOf: home.file(AgentClient.claude.config)), as: UTF8.self)
        #expect(installed.hasPrefix("\u{feff}"))
        #expect(try JSONConfig.server(in: installed) != nil)
        #expect(home.installer.run(agents: [.claude], remove: true).allSatisfy { $0.success })
        #expect(try Data(contentsOf: home.file(AgentClient.claude.config)) == Data(original.utf8))
    }

    @Test(arguments: ["{", "[]", "{\"a\":1,\"a\":2}", "{\"mcpServers\":null}", "{\"mcpServers\":[]}"])
    func badJSONIsUntouched(_ text: String) throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        try home.write(AgentClient.claude.config, text)
        #expect(home.installer.run(agents: [.claude]).allSatisfy { !$0.success })
        #expect(try home.read(AgentClient.claude.config) == text)
        #expect(!home.exists(AgentClient.claude.skill))
        #expect(!home.exists(AgentClient.claude.config + ".skreenrek-backup"))
    }

    @Test(arguments: ["broken", "model = ", "model = [1,", "model = \"unterminated", "model = 1\nmodel = 2",
                      "[table\nkey = true", "model = wrong", "# >>> skreenrek >>>\n"])
    func badTOMLIsUntouched(_ text: String) throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        try home.write(AgentClient.codex.config, text)
        #expect(home.installer.run(agents: [.codex]).allSatisfy { !$0.success })
        #expect(try home.read(AgentClient.codex.config) == text)
        #expect(!home.exists(AgentClient.codex.skill))
    }

    @Test(arguments: [AgentClient.claude, .codex, .cursor])
    func preexistingUserServerOrSkillIsNeverOverwritten(_ agent: AgentClient) throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        let text = agent == .codex ? "[mcp_servers.skreenrek]\ncommand = \"mine\"\n" : "{\"mcpServers\":{\"skreenrek\":{\"command\":\"mine\"}}}"
        try home.write(agent.config, text)
        #expect(home.installer.run(agents: [agent]).allSatisfy { !$0.success })
        #expect(home.installer.run(agents: [agent], remove: true).allSatisfy { $0.success })
        #expect(try home.read(agent.config) == text)
        try home.write(agent.config, agent == .codex ? "" : "{}")
        try home.write(agent.skill, "user skill")
        #expect(home.installer.run(agents: [agent]).allSatisfy { !$0.success })
        #expect(try home.read(agent.skill) == "user skill")
    }

    @Test(arguments: [AgentClient.claude, .codex, .cursor])
    func removingAConnectionWithADeletedConfigAllowsReconnection(_ agent: AgentClient) throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        #expect(home.installer.run(agents: [agent]).allSatisfy { $0.success })
        try FileManager.default.removeItem(at: home.file(agent.config))
        #expect(home.installer.run(agents: [agent], remove: true).allSatisfy { $0.success })
        #expect(!home.exists(agent.config))
        #expect(!home.exists(agent.skill))
        #expect(home.installer.run(agents: [agent]).allSatisfy { $0.success })
        #expect(home.installer.connections().first { $0.agent == agent }?.connected == true)
    }

    @Test func detectedAgentsAndExplicitSelection() throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        #expect(home.installer.connections().filter { $0.agent != .cli }.allSatisfy { $0.status == "Not installed" })
        #expect(home.installer.run().isEmpty)
        try home.write(".codex/exists", "")
        try home.write(".cursor/exists", "")
        #expect(home.installer.connections().first { $0.agent == .codex }?.status == "Found ~/.codex")
        #expect(home.installer.run().map(\.agent) == [.codex, .cursor])
        #expect(!home.exists(AgentClient.claude.config))
        #expect(home.installer.run(agents: [.claude]).allSatisfy { $0.success })
        #expect(home.exists(AgentClient.claude.skill))
    }

    @Test func defaultRemovalIncludesOwnedAgentsWhoseFolderWasDeleted() throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        let original = "{\"theme\":\"dark\",\"mcpServers\":{\"other\":{}}}\n"
        try home.write(AgentClient.claude.config, original)
        #expect(home.installer.run(agents: [.claude]).allSatisfy { $0.success })
        try FileManager.default.removeItem(at: home.file(".claude"))
        #expect(home.installer.connections().first { $0.agent == .claude }?.connected == false)
        let results = home.installer.run(remove: true)
        #expect(results.map(\.agent) == [.claude])
        #expect(results.allSatisfy { $0.success })
        #expect(try home.read(AgentClient.claude.config) == original)
        #expect(!home.exists(".claude"))
        #expect(home.installer.run(remove: true).isEmpty)
        #expect(home.installer.run(agents: [.claude]).allSatisfy { $0.success })
    }

    @Test func cliLinkAndPathWarning() throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        let installer = AgentInstaller(home: home.url, executablePath: home.executable.path, path: "/usr/bin", files: home.files)
        let result = installer.run(agents: [.cli])
        #expect(result.count == 1 && result[0].success)
        #expect(result[0].warnings == ["~/.local/bin isn't on PATH. Add it to PATH to run skreenrek."])
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: home.file(AgentClient.cli.config).path) == home.executable.path)
        #expect(home.installer.run(agents: [.cli])[0].warnings.isEmpty)
        #expect(home.installer.run(agents: [.cli], remove: true).allSatisfy { $0.success })
        try home.write(AgentClient.cli.config, "user executable")
        #expect(home.installer.run(agents: [.cli]).allSatisfy { !$0.success })
        #expect(try home.read(AgentClient.cli.config) == "user executable")
    }

    @Test func cliLinkIsRepointedWhenItsTargetMoved() throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        try home.makeExecutable("old/Skreenrek.app/Contents/MacOS/skreenrek")
        #expect(home.installer(executable: "old/Skreenrek.app/Contents/MacOS/skreenrek").run(agents: [.cli]).allSatisfy { $0.success })
        try FileManager.default.removeItem(at: home.file("old"))
        #expect(home.installer.connections().first { $0.agent == .cli }?.broken == true)
        #expect(home.installer.run(agents: [.cli]).allSatisfy { $0.success })
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: home.file(AgentClient.cli.config).path) == home.executable.path)
        #expect(home.installer.connections().first { $0.agent == .cli }?.connected == true)
    }

    private static let cliRefusal = "~/.local/bin/skreenrek is another file. Move or delete it, then click Connect again."

    private func linkTarget(_ home: Home) throws -> String {
        try FileManager.default.destinationOfSymbolicLink(atPath: home.file(AgentClient.cli.config).path)
    }

    private func placeLink(_ home: Home, to target: String) throws {
        try FileManager.default.createDirectory(at: home.file(".local/bin"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: home.file(AgentClient.cli.config).path, withDestinationPath: target)
    }

    private func expectLinkReplaced(_ home: Home) throws {
        #expect(home.installer.run(agents: [.cli]).allSatisfy { $0.success })
        #expect(try linkTarget(home) == home.executable.path)
        #expect(home.installer.connections().first { $0.agent == .cli }?.connected == true)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: home.file(".local/bin").path)
        #expect(leftovers == ["skreenrek"])
    }

    /// The link an old Homebrew build left behind, and relative or looping links that lead nowhere.
    @Test(arguments: ["/opt/homebrew/opt/skreenrek/Skreenrek.app/Contents/MacOS/skreenrek", "/nowhere/tool", "../gone/tool", "skreenrek"])
    func danglingCLILinkIsReplaced(target: String) throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        try placeLink(home, to: target)
        try expectLinkReplaced(home)
    }

    @Test(arguments: [true, false]) func cliLinkToAnotherSkreenrekIsReplaced(relative: Bool) throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        try home.makeExecutable("old/Skreenrek.app/Contents/MacOS/skreenrek")
        let absolute = home.file("old/Skreenrek.app/Contents/MacOS/skreenrek").path
        try placeLink(home, to: relative ? "../../old/Skreenrek.app/Contents/MacOS/skreenrek" : absolute)
        try expectLinkReplaced(home)
    }

    @Test(arguments: [true, false]) func cliLinkToAnUnrelatedBinaryIsRefused(relative: Bool) throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        try home.makeExecutable("tools/skreenrek")
        let target = relative ? "../../tools/skreenrek" : home.file("tools/skreenrek").path
        try placeLink(home, to: target)
        let result = home.installer.run(agents: [.cli])
        #expect(result.count == 1 && !result[0].success && result[0].message == Self.cliRefusal)
        #expect(try linkTarget(home) == target)
        #expect(try home.read("tools/skreenrek") == "binary")
    }

    @Test func regularFileAtTheCLIPathIsRefused() throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        try home.write(AgentClient.cli.config, "user executable")
        let result = home.installer.run(agents: [.cli])
        #expect(result.count == 1 && !result[0].success && result[0].message == Self.cliRefusal)
        #expect(try home.read(AgentClient.cli.config) == "user executable")
    }

    @Test func replacedCLILinkIsRestoredWhenTheLedgerCantBeSaved() throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        try placeLink(home, to: "../gone/skreenrek")
        let folder = home.file("Library/Application Support/skreenrek")
        try home.write("Library/Application Support/skreenrek/agent-setup.lock", "")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        #expect(home.installer.run(agents: [.cli]).allSatisfy { !$0.success })
        #expect(try linkTarget(home) == "../gone/skreenrek")
        #expect(try FileManager.default.contentsOfDirectory(atPath: home.file(".local/bin").path) == ["skreenrek"])
    }

    @Test(arguments: [
        "/Applications/Skreenrek.app/Contents/MacOS/skreenrek",
        "/opt/homebrew/opt/skreenrek/Skreenrek.app/Contents/MacOS/skreenrek",
        "/opt/homebrew/bin/skreenrek", "/usr/local/bin/skreenrek",
        "/opt/homebrew/opt/skreenrek/bin/skreenrek", "/usr/local/opt/skreenrek/bin/skreenrek",
        "/opt/homebrew/Cellar/skreenrek/1.0.5/bin/skreenrek",
    ]) func skreenrekBinaryPaths(path: String) {
        #expect(AgentInstaller.isSkreenrekBinary(path))
    }

    @Test(arguments: [
        "/usr/bin/skreenrek", "/opt/homebrew/opt/other/bin/skreenrek", "/opt/homebrew/Cellar/other/1.0/bin/skreenrek",
        "/opt/homebrew/bin/other", "/Applications/Other.app/Contents/MacOS/skreenrek",
    ]) func unrelatedBinaryPaths(path: String) {
        #expect(!AgentInstaller.isSkreenrekBinary(path))
    }

    /// A fake file system: each listed path exists, is executable, and resolves to its value.
    static func files(_ links: [String: String]) -> CommandFiles {
        CommandFiles(exists: { links[$0] != nil }, isExecutable: { links[$0] != nil }, resolve: { links[$0] ?? $0 })
    }

    @Test func stableCommandPrefersTheLinkOnPathThatRunsThisExecutable() {
        let cellar = "/opt/homebrew/Cellar/skreenrek/1.0.0/Skreenrek.app/Contents/MacOS/skreenrek"
        let opt = "/opt/homebrew/opt/skreenrek/Skreenrek.app/Contents/MacOS"
        let files = Self.files([
            cellar: cellar, "/opt/homebrew/bin/skreenrek": cellar, opt + "/skreenrek": cellar,
            "/elsewhere/skreenrek": "/other/skreenrek",
        ])
        // The opt link comes first on PATH and runs this executable, but it vanishes with the formula.
        #expect(AgentInstaller.stableCommand(
            executablePath: cellar, searchPath: [opt, "/elsewhere", "/opt/homebrew/bin"], files: files)
            == "/opt/homebrew/bin/skreenrek")
        // Without a lasting link, a versioned executable has no path to record.
        #expect(AgentInstaller.stableCommand(executablePath: cellar, searchPath: ["/elsewhere"], files: files) == nil)
        #expect(AgentInstaller.stableCommand(executablePath: opt + "/skreenrek", searchPath: [opt], files: files) == nil)
    }

    @Test func stableCommandFallsBackToTheAppInApplications() {
        let app = AgentInstaller.applicationsExecutable
        let cask = Self.files([app: app, "/opt/homebrew/bin/skreenrek": app])
        // The app under Finder's minimal PATH, and the CLI through the cask's binary link.
        #expect(AgentInstaller.stableCommand(executablePath: app, searchPath: ["/usr/bin"], files: cask) == app)
        #expect(AgentInstaller.stableCommand(executablePath: app, searchPath: ["/opt/homebrew/bin"], files: cask)
            == "/opt/homebrew/bin/skreenrek")
        // A formula's Cellar app, with the cask's app installed too.
        let cellar = "/usr/local/Cellar/skreenrek/1.0.0/Skreenrek.app/Contents/MacOS/skreenrek"
        #expect(AgentInstaller.stableCommand(executablePath: cellar, searchPath: [], files: Self.files([app: app, cellar: cellar]))
            == app)
        // A dev build runs from where it is; the CLI link never points at itself.
        let dev = "/dev/build/skreenrek"
        let link = "/home/.local/bin/skreenrek"
        #expect(AgentInstaller.stableCommand(
            executablePath: dev, searchPath: ["/home/.local/bin"], files: Self.files([link: dev, dev: dev]), excluding: link)
            == dev)
        #expect(AgentInstaller.stableCommand(
            executablePath: dev, searchPath: ["/home/.local/bin"], files: Self.files([link: dev, dev: dev])) == link)
    }

    @Test(arguments: ["/opt/homebrew/Cellar/skreenrek/1/Skreenrek.app/Contents/MacOS/skreenrek",
                      "/opt/homebrew/opt/skreenrek/Skreenrek.app/Contents/MacOS/skreenrek",
                      "/usr/local/Cellar/skreenrek/1/bin/skreenrek", "/usr/local/opt/skreenrek/bin/skreenrek",
                      "/Users/me/brew/opt/skreenrek/bin/skreenrek"])
    func versionedHomebrewPaths(_ path: String) {
        #expect(AgentInstaller.isVersioned(path))
    }

    @Test(arguments: ["/opt/homebrew/bin/skreenrek", "/usr/local/bin/skreenrek", AgentInstaller.applicationsExecutable,
                      "/Users/me/.local/bin/skreenrek"])
    func lastingPaths(_ path: String) {
        #expect(!AgentInstaller.isVersioned(path))
    }

    /// The command in the agent's config.
    static func command(_ agent: AgentClient, in text: String) throws -> String? {
        if agent == .codex {
            let line = text.split(separator: "\n").first { $0.hasPrefix("command = ") }
            return try line.map { try JSONDecoder().decode(String.self, from: Data($0.dropFirst(10).utf8)) }
        }
        guard let server = try JSONConfig.server(in: text) else { return nil }
        let object = try JSONSerialization.jsonObject(with: Data(server.utf8)) as? [String: Any]
        return object?["command"] as? String
    }

    static func legacyLedger(_ home: Home, _ entries: [String: [String: String]]) throws {
        try home.write("Library/Application Support/skreenrek/agent-setup.json",
                       String(decoding: try JSONEncoder().encode(entries), as: UTF8.self))
    }

    @Test(arguments: [AgentClient.claude, .codex, .cursor])
    func missingCommandIsRepairedInPlace(_ agent: AgentClient) throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        let old = "gone/Skreenrek.app/Contents/MacOS/skreenrek"
        try home.makeExecutable(old)
        let (before, after) = agent == .codex ? ("\"m\"", "\"n\"") : ("dark", "light")
        try home.write(agent.config, agent == .codex ? "model = \"m\"\n" : "{\"theme\":\"dark\",\"mcpServers\":{\"other\":{}}}\n")
        #expect(home.installer(executable: old).run(agents: [agent]).allSatisfy { $0.success })
        #expect(try Self.command(agent, in: home.read(agent.config)) == home.file(old).path)
        // Switching installs deletes the recorded command; the user also edits an unrelated setting.
        try FileManager.default.removeItem(at: home.file("gone"))
        try home.write(agent.config, try home.read(agent.config).replacingOccurrences(of: before, with: after))
        let status = home.installer.connections().first { $0.agent == agent }
        #expect(status?.connected == false && status?.broken == true)
        #expect(status?.status == "Skreenrek moved. Connect to repair.")
        let results = home.installer.run(agents: [agent])
        #expect(results.allSatisfy { $0.success }, "\(results)")
        let repaired = try home.read(agent.config)
        #expect(try Self.command(agent, in: repaired) == home.executable.path)
        #expect(repaired.contains(after))
        #expect(home.installer.connections().first { $0.agent == agent }?.connected == true)
        // Idempotent afterwards; removal keeps the user's edit and drops ours.
        #expect(home.installer.run(agents: [agent]).allSatisfy { $0.success })
        #expect(try home.read(agent.config) == repaired)
        #expect(home.installer.run(agents: [agent], remove: true).allSatisfy { $0.success })
        let removed = try home.read(agent.config)
        #expect(!removed.contains("skreenrek") && removed.contains(after))
    }

    @Test(arguments: [AgentClient.claude, .codex, .cursor])
    func repairWithoutOtherChangesStillRemovesByteForByte(_ agent: AgentClient) throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        try home.makeExecutable("gone/skreenrek")
        let original = agent == .codex ? "# keep\nmodel = \"m\"" : "{\"mcpServers\" : {\"other\":{}}}"
        try home.write(agent.config, original)
        #expect(home.installer(executable: "gone/skreenrek").run(agents: [agent]).allSatisfy { $0.success })
        try FileManager.default.removeItem(at: home.file("gone"))
        #expect(home.installer.run(agents: [agent]).allSatisfy { $0.success })
        #expect(home.installer.run(agents: [agent], remove: true).allSatisfy { $0.success })
        #expect(try home.read(agent.config) == original)
    }

    @Test(arguments: [AgentClient.claude, .codex, .cursor])
    func userEditsToOurEntryStillRefuseRepair(_ agent: AgentClient) throws {
        for edit in ["args", "command"] {
            let home = try Home()
            defer { home.temp.cleanUp() }
            try home.makeExecutable("gone/skreenrek")
            try home.makeExecutable("mine/skreenrek")
            #expect(home.installer(executable: "gone/skreenrek").run(agents: [agent]).allSatisfy { $0.success })
            try FileManager.default.removeItem(at: home.file("gone"))
            let installed = try home.read(agent.config)
            let changed = edit == "args"
                ? installed.replacingOccurrences(of: "\"mcp\"", with: "\"custom\"")
                : installed.replacingOccurrences(of: home.file("gone/skreenrek").path, with: home.file("mine/skreenrek").path)
            #expect(changed != installed)
            try home.write(agent.config, changed)
            let results = home.installer.run(agents: [agent])
            #expect(results.map(\.message) == ["The Skreenrek connection changed after setup. Review it before reconnecting."])
            #expect(try home.read(agent.config) == changed)
        }
    }

    @Test(arguments: [AgentClient.claude, .cursor])
    func workingVersionedCommandMovesToALastingPath(_ agent: AgentClient) throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        // An older setup recorded Homebrew's opt path, and it still runs.
        let opt = "brew/opt/skreenrek/Skreenrek.app/Contents/MacOS/skreenrek"
        try home.makeExecutable(opt)
        let server = "{\"args\":[\"mcp\"],\"command\":\"\(home.file(opt).path)\"}"
        let installed = try JSONConfig.edit("{}\n", server: server)
        try home.write(agent.config, installed)
        try home.write(agent.skill, RecordWindowSkill.text)
        try Self.legacyLedger(home, [agent.rawValue: ["installedConfig": installed, "installedServer": server]])
        #expect(home.installer.connections().first { $0.agent == agent }?.connected == true)
        try FileManager.default.createDirectory(at: home.file(".local/bin"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: home.file(".local/bin/skreenrek"), withDestinationURL: home.file(opt))
        #expect(home.installer(executable: opt).run(agents: [agent]).allSatisfy { $0.success })
        #expect(try Self.command(agent, in: home.read(agent.config)) == home.file(".local/bin/skreenrek").path)
        #expect(home.installer(executable: opt).run(agents: [agent], remove: true).allSatisfy { $0.success })
        #expect(try home.read(agent.config) == "{}\n")
    }

    @Test func ledgerKeepsOnlyOurEntry() throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        let original = "{\"history\":\"\(String(repeating: "x", count: 100_000))\",\"mcpServers\":{}}\n"
        try home.write(AgentClient.claude.config, original)
        #expect(home.installer.run(agents: [.claude, .cli]).allSatisfy { $0.success })
        let ledger = try home.read("Library/Application Support/skreenrek/agent-setup.json")
        #expect(ledger.count < 2_000, "\(ledger.count) bytes")
        #expect(!ledger.contains("history") && !ledger.contains("originalConfig") && !ledger.contains("installedConfig"))
        #expect(home.installer.run(agents: [.claude], remove: true).allSatisfy { $0.success })
        #expect(try home.read(AgentClient.claude.config) == original)
    }

    @Test func formatOneLedgerIsMigratedAndRepaired() throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        let original = "{\"theme\":\"dark\",\"mcpServers\":{\"other\":{}}}"
        let gone = "/opt/homebrew/opt/skreenrek/Skreenrek.app/Contents/MacOS/skreenrek-gone"
        let server = "{\"args\":[\"mcp\"],\"command\":\"\(gone)\"}"
        let installed = try JSONConfig.edit(original, server: server)
        try home.write(AgentClient.claude.config, installed)
        try home.write(AgentClient.claude.skill, RecordWindowSkill.text)
        try FileManager.default.createDirectory(at: home.file(".local/bin"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: home.file(".local/bin/skreenrek").path, withDestinationPath: gone)
        try Self.legacyLedger(home, [
            "claude": ["originalConfig": original, "installedConfig": installed, "installedServer": server],
            "cli": ["installedConfig": "", "installedServer": gone],
        ])
        #expect(home.installer.connections().first { $0.agent == .claude }?.broken == true)
        let results = home.installer.run(agents: [.claude, .cli])
        #expect(results.allSatisfy { $0.success }, "\(results)")
        let ledger = try home.read("Library/Application Support/skreenrek/agent-setup.json")
        #expect(!ledger.contains("originalConfig") && !ledger.contains("installedConfig") && !ledger.contains("theme"))
        #expect(try Self.command(.claude, in: home.read(AgentClient.claude.config)) == home.executable.path)
        #expect(home.installer.connections().filter(\.connected).map(\.agent) == [.claude, .cli])
        #expect(home.installer.run(agents: [.claude], remove: true).allSatisfy { $0.success })
        #expect(try home.read(AgentClient.claude.config) == original)
    }

    @Test func formatOneLedgerRemovesByteForByte() throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        let original = "{\"mcpServers\" : {\"other\":{}}}"
        let server = "{\"args\":[\"mcp\"],\"command\":\"\(home.executable.path)\"}"
        let installed = try JSONConfig.edit(original, server: server)
        try home.write(AgentClient.cursor.config, installed)
        try home.write(AgentClient.cursor.skill, RecordWindowSkill.text)
        try Self.legacyLedger(home, ["cursor": ["originalConfig": original, "installedConfig": installed, "installedServer": server]])
        #expect(home.installer.run(agents: [.cursor], remove: true).allSatisfy { $0.success })
        #expect(try home.read(AgentClient.cursor.config) == original)
        #expect(!home.exists(AgentClient.cursor.skill))
    }

    @Test func commandChecksReportMissingCommands() throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        try home.makeExecutable("other/skreenrek")
        #expect(home.installer.run(agents: [.claude, .cli]).allSatisfy { $0.success })
        #expect(home.installer(executable: "other/skreenrek").run(agents: [.codex]).allSatisfy { $0.success })
        #expect(home.installer.commandChecks().map(\.ok) == [true, true])
        try FileManager.default.removeItem(at: home.file("other"))
        let checks = home.installer.commandChecks()
        #expect(checks.map(\.agent) == [.claude, .codex])
        #expect(checks[1] == AgentCommandCheck(
            agent: .codex, command: home.file("other/skreenrek").path, exists: false, executable: false))
        #expect(checks[1].hint == "Run: skreenrek setup agents")
        #expect(checks[0].hint == nil)
    }

    @Test func symlinkConfigDoesNotTouchItsTarget() throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        try home.write("original.json", "{}")
        try FileManager.default.createSymbolicLink(at: home.file(AgentClient.claude.config), withDestinationURL: home.file("original.json"))
        #expect(home.installer.run(agents: [.claude]).allSatisfy { !$0.success })
        #expect(try home.read("original.json") == "{}")
    }

    @Test func codexUserKeysAfterMarkerAreNotReparented() throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        #expect(home.installer.run(agents: [.codex]).allSatisfy { $0.success })
        let changed = try home.read(AgentClient.codex.config) + "enabled = false\n"
        try home.write(AgentClient.codex.config, changed)
        #expect(home.installer.run(agents: [.codex], remove: true).allSatisfy { !$0.success })
        #expect(try home.read(AgentClient.codex.config) == changed)
    }

    @Test func codexInlineServerTableIsNotExtendedIllegally() throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        let original = "mcp_servers = {other = {command = \"other\"}}\n"
        try home.write(AgentClient.codex.config, original)
        #expect(home.installer.run(agents: [.codex]).allSatisfy { !$0.success })
        #expect(try home.read(AgentClient.codex.config) == original)
        #expect(!home.exists(AgentClient.codex.skill))
    }

    @Test func codexCommonTOMLSyntaxPreservesEveryByte() throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        let original = #"""
        # An unrelated setup
        model = 'model'
        instructions = """
        Do the task.
        Keep going.
        """
        features = {one = true, two = false}
        [mcp_servers."other.server"]
        command = "other"
        args = [
          "a", # comment
          "b",
        ]
        [projects."/workspace"]
        trust_level = "trusted"
        """#
        try home.write(AgentClient.codex.config, original)
        #expect(home.installer.run(agents: [.codex]).allSatisfy { $0.success })
        #expect(try home.read(AgentClient.codex.config).hasPrefix(original))
        #expect(home.installer.run(agents: [.codex], remove: true).allSatisfy { $0.success })
        #expect(try home.read(AgentClient.codex.config) == original)
    }

    @Test(arguments: ["{\"mcpServers\":{\"skreenrek\":{},\"other\":{}}}",
                      "{\"mcpServers\":{\"other\":{},\"skreenrek\":{},\"last\":{}}}",
                      "{\"mcpServers\":{\"other\":{},\"skreenrek\":{}}}",
                      "{\"mcpServers\":{\"skreenrek\":{}}}"])
    func losslessJSONRemovalHandlesEveryCommaPosition(_ text: String) throws {
        let removed = try JSONConfig.edit(text, server: nil)
        #expect(try JSONConfig.server(in: removed) == nil)
        #expect(!removed.contains("skreenrek"))
        #expect(removed.contains("other") == text.contains("other"))
        #expect(removed.contains("last") == text.contains("last"))
    }
}
