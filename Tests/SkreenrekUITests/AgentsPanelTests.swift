import Foundation
@testable import SkreenrekCore
import SkreenrekUI
import Testing

@Suite struct AgentsPanelTests {
    private static func connection(
        _ agent: AgentClient, detected: Bool = true, connected: Bool = false
    ) -> AgentConnection {
        AgentConnection(agent: agent, detected: detected, connected: connected, broken: false)
    }

    @Test func aConnectedAgentOffersRemove() {
        let row = AgentRowModel(Self.connection(.codex, connected: true), result: nil)
        #expect(row.title == "Codex")
        #expect(row.status == "Connected")
        #expect(row.buttonTitle == "Remove")
        #expect(row.removes)
        #expect(row.enabled)
        #expect(row.buttonHelp == nil)
    }

    @Test func anAgentThatIsNotInstalledSaysToInstallItFirst() {
        let row = AgentRowModel(Self.connection(.cursor, detected: false), result: nil)
        #expect(row.status == "Not installed")
        #expect(row.buttonTitle == "Connect")
        #expect(!row.enabled)
        #expect(row.buttonHelp == "Install Cursor first.")
    }

    @Test func aSetupProblemTakesOverTheStatusLine() {
        let failed = AgentSetupResult(agent: .codex, success: false, message: "Couldn't write.", warnings: ["Later."])
        let row = AgentRowModel(Self.connection(.codex), result: failed)
        #expect(row.status == "Couldn't write.")
        #expect(row.statusHelp == "Couldn't write.\nLater.")
        let warned = AgentSetupResult(agent: .codex, success: true, message: "Done.", warnings: ["Restart it."])
        #expect(AgentRowModel(Self.connection(.codex), result: warned).status == "Restart it.")
        let clean = AgentSetupResult(agent: .codex, success: true, message: "Done.", warnings: [])
        #expect(AgentRowModel(Self.connection(.codex), result: clean).status == "Found ~/.codex")
    }

    @Test func statusesAndButtonsUseTheSharedInstaller() async throws {
        try await onMain("agent Settings rows") {
            let home = FileManager.default.temporaryDirectory.appendingPathComponent("skreenrek-agents-ui-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: home) }
            // A real executable, so the connection reads as working.
            let executable = home.appendingPathComponent("app/skreenrek")
            try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: executable.path, contents: Data(), attributes: [.posixPermissions: 0o755])
            let installer = AgentInstaller(home: home, executablePath: executable.path, path: "")
            let agents = AgentsPanelState(installer: installer)
            #expect(agents.connections.first { $0.agent == .codex }?.status == "Found ~/.codex")
            #expect(agents.connections.first { $0.agent == .cursor }?.detected == false)
            agents.change(.codex, remove: false)
            #expect(agents.results.allSatisfy { $0.success })
            #expect(agents.connections.first { $0.agent == .codex }?.status == "Connected")
            agents.change(.codex, remove: true)
            #expect(agents.results.allSatisfy { $0.success })
            #expect(agents.connections.first { $0.agent == .codex }?.status == "Found ~/.codex")
        }
    }
}
