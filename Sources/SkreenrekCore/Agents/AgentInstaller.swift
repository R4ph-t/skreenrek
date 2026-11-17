import CryptoKit
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
    /// Our entry is unchanged, but the command it runs is missing or no longer executable. Connect repairs it.
    public let broken: Bool
    public var id: AgentClient { agent }
    public var status: String {
        if connected { return "Connected" }
        if broken { return "Skreenrek moved. Connect to repair." }
        if agent == .cli { return "Links skreenrek into ~/.local/bin" }
        return detected ? "Found ~/.\(agent.rawValue)" : "Not installed"
    }
}

/// One connected agent's recorded command, as `skreenrek doctor` checks it.
public struct AgentCommandCheck: Codable, Sendable, Equatable {
    public let agent: AgentClient
    public let command: String
    public let exists: Bool
    public let executable: Bool
    /// The fix, only when the command can't run.
    public let hint: String?
    public var ok: Bool { exists && executable }

    public init(agent: AgentClient, command: String, exists: Bool, executable: Bool) {
        self.agent = agent
        self.command = command
        self.exists = exists
        self.executable = executable
        hint = exists && executable ? nil : "Run: skreenrek setup agents"
    }
}

/// The file checks behind the command written into agent configs. Injected so the choice is unit-testable.
public struct CommandFiles: Sendable {
    /// The path (after symlinks) is a regular file.
    public var exists: @Sendable (String) -> Bool
    /// The path (after symlinks) is a regular file this user can execute.
    public var isExecutable: @Sendable (String) -> Bool
    /// The path with every symlink resolved.
    public var resolve: @Sendable (String) -> String

    public init(
        exists: @escaping @Sendable (String) -> Bool, isExecutable: @escaping @Sendable (String) -> Bool,
        resolve: @escaping @Sendable (String) -> String
    ) {
        self.exists = exists
        self.isExecutable = isExecutable
        self.resolve = resolve
    }

    public static let system = CommandFiles(
        exists: { path in
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && !directory.boolValue
        },
        isExecutable: { path in
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && !directory.boolValue
                && FileManager.default.isExecutableFile(atPath: path)
        },
        resolve: { URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardized.path })
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
    public let files: CommandFiles
    private var fm: FileManager { .default }
    private var directory: URL { home.appendingPathComponent("Library/Application Support/skreenrek") }
    private var ledgerURL: URL { directory.appendingPathComponent("agent-setup.json") }

    /// The ledger keeps only what setup owns: our entry as written, the skill that was there before, and the exact
    /// bytes setup inserted (enough to undo them while the config is otherwise unchanged).
    private struct Entry: Codable {
        /// Our MCP entry (JSON object text or the TOML marker block), or the CLI link's target, exactly as written.
        var installedServer: String
        var originalSkill: Data?
        var insertion: Insertion?
        // Format 1 kept both whole configs. Read to migrate, never written.
        var originalConfig: String?
        var installedConfig: String?

        init(installedServer: String, originalSkill: Data? = nil, insertion: Insertion? = nil) {
            self.installedServer = installedServer
            self.originalSkill = originalSkill
            self.insertion = insertion
        }
    }

    /// Setup's edit is a single insertion. Undo it only when the whole config still has the digest it had right
    /// after setup, so a byte-exact restore never drops later user edits.
    private struct Insertion: Codable, Equatable {
        var offset: Int
        var bytes: Data
        var digest: String

        init?(original: String, installed: String) {
            let old = Array(original.utf8), new = Array(installed.utf8)
            guard new.count > old.count else { return nil }
            var prefix = 0
            while prefix < old.count && old[prefix] == new[prefix] { prefix += 1 }
            var suffix = 0
            while suffix < old.count - prefix && old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
            guard prefix + suffix == old.count else { return nil }
            offset = prefix
            bytes = Data(new[prefix..<(new.count - suffix)])
            digest = Self.digest(installed)
        }

        func undo(_ text: String) -> String? {
            guard Self.digest(text) == digest else { return nil }
            var current = Array(text.utf8)
            let range = offset..<(offset + bytes.count)
            guard range.upperBound <= current.count, Data(current[range]) == bytes else { return nil }
            current.removeSubrange(range)
            return String(decoding: current, as: UTF8.self)
        }

        static func digest(_ text: String) -> String {
            SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }
    private typealias Ledger = [String: Entry]

    public init(home: URL, executablePath: String, path: String, files: CommandFiles = .system) {
        self.home = home.standardizedFileURL
        self.executablePath = executablePath
        self.path = path
        self.files = files
    }

    // MARK: - The command agents run

    /// Where the cask installs the app.
    public static let applicationsExecutable = "/Applications/Skreenrek.app/Contents/MacOS/skreenrek"

    /// Homebrew's Cellar and opt paths change or vanish when the install changes (an upgrade, formula to cask).
    public static func isVersioned(_ path: String) -> Bool {
        if path.hasPrefix("/opt/homebrew/opt/") || path.hasPrefix("/usr/local/opt/") { return true }
        let parts = (path as NSString).pathComponents
        if parts.contains("Cellar") { return true }
        return parts.indices.contains { $0 > 1 && parts[$0] == "opt" && $0 + 1 < parts.count && parts[$0 + 1] == "skreenrek" }
    }

    /// The path agents should run: a `skreenrek` in `searchPath` that resolves to this executable, else the app in
    /// /Applications when it is this executable, else this executable, else the app in /Applications. Never a
    /// versioned Homebrew path (`isVersioned`) and never `excluding`. Nil when nothing stable is left.
    public static func stableCommand(
        executablePath: String, searchPath: [String], files: CommandFiles, excluding: String? = nil
    ) -> String? {
        let me = files.resolve(executablePath)
        func stable(_ path: String) -> Bool { !isVersioned(path) && path != excluding }
        for directory in searchPath where directory.hasPrefix("/") {
            let candidate = (directory as NSString).appendingPathComponent("skreenrek")
            if stable(candidate), files.isExecutable(candidate), files.resolve(candidate) == me { return candidate }
        }
        let app = applicationsExecutable
        if stable(app), files.isExecutable(app), files.resolve(app) == me { return app }
        if stable(me) { return me }
        if stable(app), files.isExecutable(app) { return app }
        return nil
    }

    /// `PATH`, then where Homebrew and `setup agents --cli` link the command. The app's own PATH is often minimal.
    private var searchPath: [String] {
        path.split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", home.appendingPathComponent(".local/bin").path]
    }

    private func command(excluding: String? = nil) throws -> String {
        guard let command = Self.stableCommand(
            executablePath: executablePath, searchPath: searchPath, files: files, excluding: excluding)
        else {
            throw AgentSetupError(
                "Couldn't find a lasting path to skreenrek. Move Skreenrek.app to /Applications, or put skreenrek on PATH, then retry.")
        }
        return command
    }

    /// The command recorded in our entry.
    private static func recordedCommand(_ agent: AgentClient, _ entry: Entry) -> String? {
        switch agent {
        case .cli:
            return entry.installedServer
        case .codex:
            guard let line = entry.installedServer.split(separator: "\n").first(where: { $0.hasPrefix("command = ") })
            else { return nil }
            return try? JSONDecoder().decode(String.self, from: Data(line.dropFirst("command = ".count).utf8))
        case .claude, .cursor:
            let object = try? JSONSerialization.jsonObject(with: Data(entry.installedServer.utf8)) as? [String: Any]
            return object?["command"] as? String
        }
    }

    private func serverText(_ agent: AgentClient, command: String) throws -> String {
        if agent == .codex { return try TOMLConfig.server(command: command) }
        let data = try JSONSerialization.data(
            withJSONObject: ["command": command, "args": ["mcp"]], options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Status

    public func connections() -> [AgentConnection] {
        let ledger = try? load()
        return AgentClient.allCases.map { agent in
            let detected = agent == .cli || fm.fileExists(atPath: home.appendingPathComponent(".\(agent.rawValue)").path)
            let intact = ledger?[agent.rawValue].map { entry in
                (try? isInstalled(agent, entry: entry)) == true
            } ?? false
            let broken = intact && ledger?[agent.rawValue].flatMap { Self.recordedCommand(agent, $0) }
                .map { !files.isExecutable($0) } ?? false
            return AgentConnection(agent: agent, detected: detected, connected: intact && !broken, broken: broken)
        }
    }

    /// Each connected agent's recorded command, and whether it still runs. The CLI link isn't an agent.
    public func commandChecks() -> [AgentCommandCheck] {
        guard let ledger = try? load() else { return [] }
        return AgentClient.allCases.filter { $0 != .cli }.compactMap { agent in
            guard let entry = ledger[agent.rawValue], let command = Self.recordedCommand(agent, entry) else { return nil }
            return AgentCommandCheck(
                agent: agent, command: command, exists: files.exists(command), executable: files.isExecutable(command))
        }
    }

    // MARK: - Setup and removal

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
            let (loaded, legacy) = try loadLedger()
            var ledger = loaded
            if legacy { try save(ledger) } // Drop format 1's whole-config copies now.
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
            if let original {
                config = try entry.insertion?.undo(original) ?? removingServer(agent, text: original, entry: entry)
            } else {
                config = nil // Don't recreate a config the user deleted after setup.
            }
            newSkill = entry.originalSkill
            updated.removeValue(forKey: agent.rawValue)
        } else if let entry {
            guard try isInstalled(agent, entry: entry), let original else {
                throw AgentSetupError("The Skreenrek connection changed after setup. Review it before reconnecting.")
            }
            // Our entry is unchanged. Keep a working, lasting command byte-for-byte (backups and ledger included);
            // repoint a missing or versioned one in place.
            let recorded = Self.recordedCommand(agent, entry)
            let works = recorded.map(files.isExecutable) ?? false
            if works, let recorded, !Self.isVersioned(recorded) { return }
            let command: String
            do { command = try self.command() } catch { if works { return } else { throw error } }
            guard command != recorded else { return }
            let server = try serverText(agent, command: command)
            let repaired: String
            if agent == .codex, let range = try TOMLConfig.block(in: original) {
                repaired = original.replacingCharacters(in: range, with: server)
                try TOMLConfig.validate(repaired)
            } else {
                repaired = try JSONConfig.edit(original, server: server)
            }
            config = repaired
            newSkill = skill
            var entry = entry
            entry.installedServer = server
            entry.insertion = entry.insertion?.undo(original).flatMap { Insertion(original: $0, installed: repaired) }
            updated[agent.rawValue] = entry
        } else {
            guard skill == nil else {
                throw AgentSetupError("A record-window skill already exists. Leave it unchanged and move it before connecting.")
            }
            let server = try serverText(agent, command: try command())
            let base: String
            let installedConfig: String
            if agent == .codex {
                guard try !TOMLConfig.hasServer(original ?? ""), try TOMLConfig.block(in: original ?? "") == nil else {
                    throw AgentSetupError("A skreenrek MCP server already exists. Leave it unchanged and remove it before connecting.")
                }
                base = original ?? ""
                installedConfig = base + (base.isEmpty || base.hasSuffix("\n") ? "" : "\n") + server
                try TOMLConfig.validate(installedConfig)
            } else {
                guard try JSONConfig.server(in: original ?? "{}") == nil else {
                    throw AgentSetupError("A skreenrek MCP server already exists. Leave it unchanged and remove it before connecting.")
                }
                base = original ?? "{}\n"
                installedConfig = try JSONConfig.edit(base, server: server)
            }
            config = installedConfig
            newSkill = Data(RecordWindowSkill.text.utf8)
            updated[agent.rawValue] = Entry(
                installedServer: server, originalSkill: skill,
                insertion: Insertion(original: base, installed: installedConfig))
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

    /// Our entry (and skill) are still exactly what setup wrote.
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
        var repairing = false
        if remove {
            guard let entry else { return }
            guard target == entry.installedServer else { throw changedServer() }
            try fm.removeItem(at: url)
            updated.removeValue(forKey: AgentClient.cli.rawValue)
        } else if let entry, let target, target == entry.installedServer {
            // Our link. Keep it while it works from a lasting path; repoint it when its target moved.
            let works = files.isExecutable(url.path)
            if works && !Self.isVersioned(target) { return }
            let real: String
            do { real = try command(excluding: url.path) } catch { if works { return } else { throw error } }
            guard real != target else { return }
            try fm.removeItem(at: url)
            try fm.createSymbolicLink(atPath: url.path, withDestinationPath: real)
            updated[AgentClient.cli.rawValue] = Entry(installedServer: real)
            repairing = true
        } else {
            guard !exists(url) else {
                throw AgentSetupError("~/.local/bin/skreenrek already exists. Leave it unchanged and move it before linking.")
            }
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let real = try command(excluding: url.path)
            try fm.createSymbolicLink(atPath: url.path, withDestinationPath: real)
            updated[AgentClient.cli.rawValue] = Entry(installedServer: real)
        }
        do { try save(updated); ledger = updated }
        catch {
            if remove || repairing, let target {
                if repairing { try fm.removeItem(at: url) }
                try fm.createSymbolicLink(atPath: url.path, withDestinationPath: target)
            } else { try fm.removeItem(at: url) }
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
    private func load() throws -> Ledger { try loadLedger().ledger }
    /// Reads either format. Format 1 entries become insertions; `legacy` says the file still needs rewriting.
    private func loadLedger() throws -> (ledger: Ledger, legacy: Bool) {
        try safe(ledgerURL)
        guard let data = try readData(ledgerURL) else { return ([:], false) }
        var ledger = try JSONDecoder().decode(Ledger.self, from: data)
        var legacy = false
        for (key, entry) in ledger where entry.installedConfig != nil || entry.originalConfig != nil {
            legacy = true
            var migrated = Entry(installedServer: entry.installedServer, originalSkill: entry.originalSkill)
            if key != AgentClient.cli.rawValue, let installed = entry.installedConfig {
                let base = entry.originalConfig ?? (key == AgentClient.codex.rawValue ? "" : "{}\n")
                migrated.insertion = Insertion(original: base, installed: installed)
            }
            ledger[key] = migrated
        }
        return (ledger, legacy)
    }
    private func save(_ ledger: Ledger) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try write(encoder.encode(ledger), to: ledgerURL)
    }
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
