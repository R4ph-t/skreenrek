import Foundation
import SkreenrekControl
import SkreenrekCore
import Testing

@Suite struct SetupAgentsTests {
    @Test func explicitAgentsAndJSONWithoutLaunchingTheApp() async throws {
        let harness = CLIHarness()
        defer { harness.stop() }
        let result = try await harness.run(["--json", "setup", "agents", "--claude", "--codex", "--cursor"])
        #expect(result.code == 0, "\(result)")
        let entries = try JSONDecoder().decode([AgentSetupResult].self, from: Data(result.out.utf8))
        #expect(entries.map(\.agent) == [.claude, .codex, .cursor])
        #expect(entries.allSatisfy { $0.success })
        #expect(result.err.isEmpty)
        let removed = try await harness.run(["setup", "agents", "--claude", "--codex", "--cursor", "--remove"])
        #expect(removed.code == 0)
        #expect(removed.out == "✓ Claude Code · Removed\n✓ Codex · Removed\n✓ Cursor · Removed\n")
    }

    @Test func detectionAndCLILinkWarning() async throws {
        let harness = CLIHarness()
        defer { harness.stop() }
        try FileManager.default.createDirectory(at: harness.temp.root.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        let detected = try await harness.run(["setup", "agents"])
        #expect(detected.code == 0)
        #expect(detected.out == "✓ Codex · Connected\n")
        let cli = try await harness.run(["setup", "agents", "--cli"])
        #expect(cli.code == 0)
        #expect(cli.out == "✓ Command-line tool · Connected\n")
        #expect(cli.err.contains("~/.local/bin isn't on PATH"))
    }

    @Test func parseFailureIsPerAgentAndExitOne() async throws {
        let harness = CLIHarness()
        defer { harness.stop() }
        let config = harness.temp.root.appendingPathComponent(".claude.json")
        try Data("invalid".utf8).write(to: config)
        let result = try await harness.run(["setup", "agents", "--claude", "--cursor", "--json"])
        #expect(result.code == 1)
        let entries = try JSONDecoder().decode([AgentSetupResult].self, from: Data(result.out.utf8))
        #expect(entries.map(\.success) == [false, true])
        #expect(try String(contentsOf: config, encoding: .utf8) == "invalid")
        let human = try await harness.run(["setup", "agents", "--claude"])
        #expect(human.code == 1)
        #expect(human.out.hasPrefix("✗ Claude Code · "))
    }

    /// An executable file inside the harness home.
    static func executable(_ harness: CLIHarness, _ path: String) throws -> URL {
        let url = harness.temp.root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: [.posixPermissions: 0o755])
        return url
    }

    static func claudeCommand(_ harness: CLIHarness) throws -> String? {
        let data = try Data(contentsOf: harness.temp.root.appendingPathComponent(".claude.json"))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let servers = object?["mcpServers"] as? [String: Any]
        return (servers?["skreenrek"] as? [String: Any])?["command"] as? String
    }

    @Test func recordsTheLinkOnPathNotTheVersionedExecutable() async throws {
        let harness = CLIHarness()
        defer { harness.stop() }
        // A formula install: bin/skreenrek links into the Cellar.
        let cellar = try Self.executable(harness, "brew/Cellar/skreenrek/1.0.0/Skreenrek.app/Contents/MacOS/skreenrek")
        let bin = harness.temp.root.appendingPathComponent("brew/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("skreenrek"), withDestinationURL: cellar)
        let result = try await harness.run(
            ["setup", "agents", "--claude"], variables: ["PATH": "/nowhere:\(bin.path)"], executablePath: cellar.path)
        #expect(result.code == 0, "\(result)")
        #expect(try Self.claudeCommand(harness) == bin.appendingPathComponent("skreenrek").path)
    }

    @Test func setupRepairsAMovedCommandAndDoctorReportsIt() async throws {
        let harness = try CLIHarness().start()
        defer { harness.stop() }
        let old = try Self.executable(harness, "old/skreenrek")
        let setup = try await harness.run(
            ["setup", "agents", "--claude", "--codex"], variables: ["PATH": "/nowhere"], executablePath: old.path)
        #expect(setup.code == 0, "\(setup)")
        let healthy = try await harness.run(["doctor"], variables: ["PATH": "/nowhere"])
        #expect(healthy.out.contains("✓ Claude Code        ~/old/skreenrek\n"), "\(healthy)")
        #expect(healthy.out.contains("✓ Codex              ~/old/skreenrek\n"))

        try FileManager.default.removeItem(at: old)
        let broken = try await harness.run(["doctor"], variables: ["PATH": "/nowhere"])
        #expect(broken.code == 0)
        #expect(broken.out.contains(
            "✗ Claude Code        ~/old/skreenrek is missing. Run: skreenrek setup agents\n"), "\(broken)")
        #expect(broken.out.contains("✗ Codex              ~/old/skreenrek is missing. Run: skreenrek setup agents\n"))
        let json = try await harness.run(["doctor", "--json"], variables: ["PATH": "/nowhere"])
        _ = try json.decode(DoctorBody.self) // Existing fields stay.
        let agents = try #require(try json.json()["agents"] as? [[String: Any]])
        #expect(agents.map { $0["agent"] as? String } == ["claude", "codex"])
        #expect(agents.allSatisfy { $0["exists"] as? Bool == false && $0["executable"] as? Bool == false })
        #expect(agents.allSatisfy { $0["command"] as? String == old.path })
        #expect(agents.allSatisfy { $0["hint"] as? String == "Run: skreenrek setup agents" })

        let new = try Self.executable(harness, "new/skreenrek")
        let repaired = try await harness.run(
            ["setup", "agents", "--claude", "--codex"], variables: ["PATH": "/nowhere"], executablePath: new.path)
        #expect(repaired.code == 0, "\(repaired)")
        #expect(repaired.out == "✓ Claude Code · Connected\n✓ Codex · Connected\n")
        #expect(try Self.claudeCommand(harness) == new.path)
        let fixed = try await harness.run(["doctor", "--json"], variables: ["PATH": "/nowhere"])
        let checks = try #require(try fixed.json()["agents"] as? [[String: Any]])
        #expect(checks.allSatisfy { $0["executable"] as? Bool == true && $0["hint"] == nil })
    }

    @Test func doctorWithoutConnectedAgentsHasAnEmptyAgentsList() async throws {
        let harness = try CLIHarness().start()
        defer { harness.stop() }
        let json = try await harness.run(["doctor", "--json"], variables: ["PATH": "/nowhere"])
        #expect(try json.json()["agents"] as? [Any] != nil)
        #expect((try json.json()["agents"] as? [Any])?.isEmpty == true)
    }

    @Test func helpAndUsage() async throws {
        let harness = CLIHarness()
        defer { harness.stop() }
        let help = try await harness.run(["setup", "agents", "--help"])
        #expect(help.code == 0)
        for flag in ["--claude", "--codex", "--cursor", "--cli", "--remove", "--json"] { #expect(help.out.contains(flag)) }
        let bad = try await harness.run(["setup", "agents", "--bad", "--json"])
        #expect(bad.code == 2)
        #expect(try bad.jsonError()["hint"] as? String == "Run: skreenrek setup agents --help")
    }
}
