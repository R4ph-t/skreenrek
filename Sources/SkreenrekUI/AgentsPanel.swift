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

    public var rows: [AgentRowModel] {
        connections.map { connection in
            AgentRowModel(connection, result: results.first { $0.agent == connection.agent })
        }
    }
}

/// One row of the Agents tab. A setup failure or warning takes over the status line, so the row stays one height.
public struct AgentRowModel: Sendable, Hashable, Identifiable {
    public var agent: AgentClient
    public var title: String
    public var status: String
    /// The full status text, when it may not fit on the line.
    public var statusHelp: String?
    public var buttonTitle: String
    public var removes: Bool
    public var enabled: Bool
    /// Why the button is disabled.
    public var buttonHelp: String?

    public var id: AgentClient { agent }

    public init(_ connection: AgentConnection, result: AgentSetupResult?) {
        agent = connection.agent
        title = connection.agent.name
        removes = connection.connected
        buttonTitle = connection.connected ? UIStrings.Agents.remove : UIStrings.Agents.connect
        enabled = connection.detected || connection.connected
        buttonHelp = enabled ? nil : UIStrings.Agents.installFirst(connection.agent.name)
        var notes = result?.warnings ?? []
        if let result, !result.success { notes.insert(result.message, at: 0) }
        status = notes.first ?? connection.status
        statusHelp = notes.isEmpty ? nil : notes.joined(separator: "\n")
    }
}
