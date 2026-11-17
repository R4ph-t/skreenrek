import Foundation
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
