import Darwin
import Foundation

public enum AgentClient: String, CaseIterable, Codable, Sendable, Identifiable {
    case claude, codex, cursor, cli
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .cli: "Command-line tool"
        }
    }
    var config: String {
        switch self {
        case .claude: ".claude.json"
        case .codex: ".codex/config.toml"
        case .cursor: ".cursor/mcp.json"
        case .cli: ".local/bin/skreenrek"
        }
    }
    var skill: String { ".\(rawValue)/skills/record-window/SKILL.md" }
}

public struct AgentSetupResult: Codable, Sendable {
    public let agent: AgentClient
    public let success: Bool
    public let message: String
    public let warnings: [String]
}

public struct AgentConnection: Sendable, Identifiable {
    public let agent: AgentClient
    public let detected: Bool
    public let connected: Bool
    public var id: AgentClient { agent }
    public var status: String {
        if connected { return "Connected" }
        if agent == .cli { return "Links skreenrek into ~/.local/bin" }
        return detected ? "Found ~/.\(agent.rawValue)" : "Not installed"
    }
}

struct AgentSetupError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Shared by CLI, Settings and onboarding. All user paths are relative to the explicitly supplied home.
/// Ownership records let removal distinguish installed content from later user edits; backups are never consumed.
public struct AgentInstaller: Sendable {
    public let home: URL
    public let executablePath: String
    public let path: String
    private var fm: FileManager { .default }
    private var directory: URL { home.appendingPathComponent("Library/Application Support/skreenrek") }
    private var ledgerURL: URL { directory.appendingPathComponent("agent-setup.json") }

    private struct Entry: Codable {
        var originalConfig: String?
        var installedConfig: String
        var originalSkill: Data?
        var installedServer: String
    }
    private typealias Ledger = [String: Entry]

    public init(home: URL, executablePath: String, path: String) {
        self.home = home.standardizedFileURL
        self.executablePath = executablePath
        self.path = path
    }

    /// Homebrew's opt link survives Cellar version changes. Resolve any CLI symlinks first.
    public static func stableExecutable(_ executablePath: String) -> String {
        let resolved = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath().standardized.path
        let parts = (resolved as NSString).pathComponents
        if let cellar = parts.firstIndex(of: "Cellar"), parts.count > cellar + 3,
           parts[cellar + 1] == "skreenrek" {
            return NSString.path(withComponents: Array(parts[..<cellar]) + ["opt", "skreenrek"] + parts[(cellar + 3)...])
        }
        return resolved
    }

    public func connections() -> [AgentConnection] {
        let ledger = try? load()
        return AgentClient.allCases.map { agent in
            let detected = agent == .cli || fm.fileExists(atPath: home.appendingPathComponent(".\(agent.rawValue)").path)
            let connected = ledger?[agent.rawValue].map { entry in
                (try? isInstalled(agent, entry: entry)) == true
            } ?? false
            return AgentConnection(agent: agent, detected: detected, connected: connected)
        }
    }

    /// Empty selection means detected agents; --cli alone only links the CLI. Removal includes owned, vanished agents.
    public func run(agents: [AgentClient] = [], remove: Bool = false) -> [AgentSetupResult] {
        let owned = remove && agents.isEmpty ? (try? load()) ?? [:] : [:]
        let selected = agents.isEmpty
            ? connections().filter { $0.agent != .cli && ($0.detected || owned[$0.agent.rawValue] != nil) }.map(\.agent)
            : AgentClient.allCases.filter(agents.contains)
        guard !selected.isEmpty else { return [] }
        do {
            try safe(directory)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let lockURL = directory.appendingPathComponent("agent-setup.lock")
            try safe(lockURL)
            let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else { throw AgentSetupError("Couldn't open the agent setup lock. Check folder access and retry.") }
            defer { close(descriptor) }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                throw AgentSetupError("Agent setup is already running. Wait for it to finish and retry.")
            }
            defer { flock(descriptor, LOCK_UN) }
            var ledger = try load()
            return selected.map { agent in
                do {
                    try change(agent, remove: remove, ledger: &ledger)
                    let warning = agent == .cli && !remove && !path.split(separator: ":", omittingEmptySubsequences: false)
                        .contains(Substring(home.appendingPathComponent(".local/bin").path))
                        ? ["~/.local/bin isn't on PATH. Add it to PATH to run skreenrek."] : []
                    return AgentSetupResult(agent: agent, success: true, message: remove ? "Removed" : "Connected", warnings: warning)
                } catch {
                    return AgentSetupResult(agent: agent, success: false, message: error.localizedDescription, warnings: [])
                }
            }
        } catch {
            return selected.map { AgentSetupResult(agent: $0, success: false, message: error.localizedDescription, warnings: []) }
        }
    }

    private func change(_ agent: AgentClient, remove: Bool, ledger: inout Ledger) throws {
        let configURL = home.appendingPathComponent(agent.config)
        try safe(configURL)
        if agent == .cli { try link(configURL, remove: remove, ledger: &ledger); return }
        let skillURL = home.appendingPathComponent(agent.skill)
        try safe(skillURL)
        let original = try read(configURL)
        let skill = try readData(skillURL)
        let entry = ledger[agent.rawValue]
        // Parse even on removal, before touching the skill. Malformed files always stay untouched.
        if agent == .codex { try TOMLConfig.validate(original ?? "") }
        else { _ = try JSONConfig.server(in: original ?? "{}") }

        let config: String?
        let newSkill: Data?
        var updated = ledger
        if remove {
            guard let entry else { return }
            guard skill == Data(RecordWindowSkill.text.utf8) || skill == entry.originalSkill else {
                throw AgentSetupError("The record-window skill changed after setup. Leave it unchanged and remove its changes manually.")
            }
            if original == nil {
                config = nil // Don't recreate a config the user deleted after setup.
            } else if original == entry.installedConfig {
                config = entry.originalConfig ?? (agent == .codex ? "" : "{}\n")
            } else {
                config = try removingServer(agent, text: original ?? "", entry: entry)
            }
            newSkill = entry.originalSkill
            updated.removeValue(forKey: agent.rawValue)
        } else {
            if let entry {
                guard try isInstalled(agent, entry: entry) else {
                    throw AgentSetupError("The Skreenrek connection changed after setup. Review it before reconnecting.")
                }
                return // byte-for-byte idempotent, including backups and ownership records
            }
            guard skill == nil else {
                throw AgentSetupError("A record-window skill already exists. Leave it unchanged and move it before connecting.")
            }
            let command = Self.stableExecutable(executablePath)
            let server: String
            let installedConfig: String
            if agent == .codex {
                guard try !TOMLConfig.hasServer(original ?? ""), try TOMLConfig.block(in: original ?? "") == nil else {
                    throw AgentSetupError("A skreenrek MCP server already exists. Leave it unchanged and remove it before connecting.")
                }
                server = try TOMLConfig.server(command: command)
                let text = original ?? ""
                installedConfig = text + (text.isEmpty || text.hasSuffix("\n") ? "" : "\n") + server
                try TOMLConfig.validate(installedConfig)
            } else {
                guard try JSONConfig.server(in: original ?? "{}") == nil else {
                    throw AgentSetupError("A skreenrek MCP server already exists. Leave it unchanged and remove it before connecting.")
                }
                let data = try JSONSerialization.data(withJSONObject: ["command": command, "args": ["mcp"]], options: [.sortedKeys, .withoutEscapingSlashes])
                server = String(decoding: data, as: UTF8.self)
                installedConfig = try JSONConfig.edit(original ?? "{}\n", server: server)
            }
            config = installedConfig
            newSkill = Data(RecordWindowSkill.text.utf8)
            updated[agent.rawValue] = Entry(originalConfig: original, installedConfig: installedConfig, originalSkill: skill, installedServer: server)
        }
        // Prepare both backups before editing either artifact. Keep originals on any failed transaction.
        try backup(configURL)
        try backup(skillURL)
        do {
            if original != config, let config { try write(Data(config.utf8), to: configURL) }
            if newSkill != skill { try replace(newSkill, at: skillURL) }
            try save(updated)
            ledger = updated
        } catch {
            try replace(original.map { Data($0.utf8) }, at: configURL)
            try replace(skill, at: skillURL)
            throw error
        }
    }

    private func removingServer(_ agent: AgentClient, text: String, entry: Entry) throws -> String {
        if agent == .codex {
            guard let range = try TOMLConfig.block(in: text) else {
                if try !TOMLConfig.hasServer(text) { return text }
                throw changedServer()
            }
            guard String(text[range]) == entry.installedServer, TOMLConfig.canRemove(text, range: range) else {
                throw changedServer()
            }
            var result = text
            result.removeSubrange(range)
            return result
        }
        guard let server = try JSONConfig.server(in: text) else { return text }
        guard JSONConfig.equal(server, entry.installedServer) else { throw changedServer() }
        return try JSONConfig.edit(text, server: nil)
    }

    private func changedServer() -> AgentSetupError {
        AgentSetupError("The skreenrek MCP server changed after setup. Leave it unchanged and remove it manually.")
    }

    private func isInstalled(_ agent: AgentClient, entry: Entry) throws -> Bool {
        let url = home.appendingPathComponent(agent.config)
        try safe(url)
        if agent == .cli { return (try? fm.destinationOfSymbolicLink(atPath: url.path)) == entry.installedServer }
        let skillURL = home.appendingPathComponent(agent.skill)
        try safe(skillURL)
        guard try readData(skillURL) == Data(RecordWindowSkill.text.utf8), let text = try read(url) else { return false }
        if agent == .codex {
            guard let range = try TOMLConfig.block(in: text) else { return false }
            return String(text[range]) == entry.installedServer
        }
        return try JSONConfig.server(in: text).map { JSONConfig.equal($0, entry.installedServer) } ?? false
    }

    private func link(_ url: URL, remove: Bool, ledger: inout Ledger) throws {
        let entry = ledger[AgentClient.cli.rawValue]
        let target = try? fm.destinationOfSymbolicLink(atPath: url.path)
        var updated = ledger
        if remove {
            guard let entry else { return }
            guard target == entry.installedServer else { throw changedServer() }
            try fm.removeItem(at: url)
            updated.removeValue(forKey: AgentClient.cli.rawValue)
        } else {
            if let entry, target == entry.installedServer { return }
            guard !exists(url) else {
                throw AgentSetupError("~/.local/bin/skreenrek already exists. Leave it unchanged and move it before linking.")
            }
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let real = Self.stableExecutable(executablePath)
            try fm.createSymbolicLink(atPath: url.path, withDestinationPath: real)
            updated[AgentClient.cli.rawValue] = Entry(originalConfig: nil, installedConfig: "", originalSkill: nil, installedServer: real)
        }
        do { try save(updated); ledger = updated }
        catch {
            if remove, let target { try fm.createSymbolicLink(atPath: url.path, withDestinationPath: target) }
            else { try fm.removeItem(at: url) }
            throw error
        }
    }

    /// Symlink files aren't overwritten; parent symlinks must still resolve inside the supplied home.
    private func safe(_ url: URL) throws {
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardized.path
        let root = home.resolvingSymlinksInPath().standardized.path
        guard parent == root || parent.hasPrefix(root + "/") else {
            throw AgentSetupError("The agent path leaves the home folder. Move it inside the home folder before connecting.")
        }
        if url.path != home.appendingPathComponent(AgentClient.cli.config).path,
           (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil {
            throw AgentSetupError("The agent file is a symbolic link. Leave it unchanged and use a regular file before connecting.")
        }
    }

    private func exists(_ url: URL) -> Bool {
        fm.fileExists(atPath: url.path) || (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil
    }
    private func readData(_ url: URL) throws -> Data? { exists(url) ? try Data(contentsOf: url) : nil }
    private func read(_ url: URL) throws -> String? {
        guard let data = try readData(url) else { return nil }
        guard String(data: data, encoding: .utf8) != nil else {
            throw AgentSetupError("The agent config isn't UTF-8. Leave it unchanged and save it as UTF-8 before connecting.")
        }
        // String(data:encoding:) strips a leading BOM. Decode the validated bytes without changing them.
        return String(decoding: data, as: UTF8.self)
    }
    private func load() throws -> Ledger {
        try safe(ledgerURL)
        return try readData(ledgerURL).map { try JSONDecoder().decode(Ledger.self, from: $0) } ?? [:]
    }
    private func save(_ ledger: Ledger) throws { try write(JSONEncoder().encode(ledger), to: ledgerURL) }
    private func backup(_ url: URL) throws {
        guard exists(url) else { return }
        let backup = URL(fileURLWithPath: url.path + ".skreenrek-backup")
        try safe(backup)
        if !exists(backup) { try fm.copyItem(at: url, to: backup) }
    }
    private func replace(_ data: Data?, at url: URL) throws {
        if let data { try write(data, to: url) }
        else if exists(url) { try fm.removeItem(at: url) }
    }
    private func write(_ data: Data, to url: URL) throws {
        let mode = (try? fm.attributesOfItem(atPath: url.path)[.posixPermissions]) ?? 0o600
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }
}
