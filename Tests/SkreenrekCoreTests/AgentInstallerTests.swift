import Foundation
@testable import SkreenrekCore
import Testing

@Suite struct AgentInstallerTests {
    struct Home {
        let temp: TempFolder
        var url: URL { temp.url.resolvingSymlinksInPath() }
        var installer: AgentInstaller {
            AgentInstaller(home: url, executablePath: url.appendingPathComponent("Skreenrek.app/Contents/MacOS/skreenrek").path,
                           path: url.appendingPathComponent(".local/bin").path)
        }
        init() throws { temp = try TempFolder("agents") }
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

    @Test func cliLinkAndPathWarning() throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        let installer = AgentInstaller(home: home.url, executablePath: home.file("Skreenrek.app/Contents/MacOS/skreenrek").path, path: "/usr/bin")
        let result = installer.run(agents: [.cli])
        #expect(result.count == 1 && result[0].success)
        #expect(result[0].warnings == ["~/.local/bin isn't on PATH. Add it to PATH to run skreenrek."])
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: home.file(AgentClient.cli.config).path) == AgentInstaller.stableExecutable(installer.executablePath))
        #expect(home.installer.run(agents: [.cli])[0].warnings.isEmpty)
        #expect(home.installer.run(agents: [.cli], remove: true).allSatisfy { $0.success })
        try home.write(AgentClient.cli.config, "user executable")
        #expect(home.installer.run(agents: [.cli]).allSatisfy { !$0.success })
        #expect(try home.read(AgentClient.cli.config) == "user executable")
    }

    @Test func stableBrewPathAndSymlinkResolution() throws {
        let home = try Home()
        defer { home.temp.cleanUp() }
        let executable = home.file("brew/Cellar/skreenrek/0.1.0/Skreenrek.app/Contents/MacOS/skreenrek")
        try home.write("brew/Cellar/skreenrek/0.1.0/Skreenrek.app/Contents/MacOS/skreenrek", "binary")
        let stable = home.file("brew/opt/skreenrek/Skreenrek.app/Contents/MacOS/skreenrek").path
        #expect(AgentInstaller.stableExecutable(executable.path) == stable)
        try FileManager.default.createSymbolicLink(atPath: home.file("command").path, withDestinationPath: executable.path)
        #expect(AgentInstaller.stableExecutable(home.file("command").path) == stable)
        #expect(AgentInstaller.stableExecutable(home.file("app/skreenrek").path) == home.file("app/skreenrek").path)
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
