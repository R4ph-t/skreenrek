import Foundation
import SkreenrekCore
import SkreenrekUI
import Testing

@Suite struct AgentsPanelTests {
    @Test func statusesAndButtonsUseTheSharedInstaller() async throws {
        try await onMain("agent Settings rows") {
            let home = FileManager.default.temporaryDirectory.appendingPathComponent("skreenrek-agents-ui-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: home) }
            let installer = AgentInstaller(home: home, executablePath: home.appendingPathComponent("app/skreenrek").path, path: "")
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
