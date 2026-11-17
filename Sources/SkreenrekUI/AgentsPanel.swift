import Foundation
import Observation
import SkreenrekCore
import SwiftUI

/// Injected explicitly so previews and tests never discover or edit the real agent home folders.
@MainActor
@Observable
public final class AgentsPanelState {
    public private(set) var connections: [AgentConnection] = []
    public private(set) var results: [AgentSetupResult] = []
    @ObservationIgnored private let installer: AgentInstaller

    public init(installer: AgentInstaller) {
        self.installer = installer
        refresh()
    }

    public func refresh() { connections = installer.connections() }

    public func change(_ agent: AgentClient, remove: Bool) {
        results = installer.run(agents: [agent], remove: remove)
        refresh()
    }
}

struct AgentsSection: View {
    @Bindable var panel: AgentsPanelState

    var body: some View {
        Section("Agents") {
            ForEach(panel.connections) { connection in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(connection.agent.name).font(.system(size: 13))
                            Text(connection.status).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button(connection.connected ? "Remove" : "Connect") {
                            panel.change(connection.agent, remove: connection.connected)
                        }
                    }
                    .disabled(!connection.detected && !connection.connected)
                    if let result = panel.results.first(where: { $0.agent == connection.agent }) {
                        if !result.success { detail(result.message) }
                        ForEach(result.warnings, id: \.self) { detail($0) }
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    private func detail(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
