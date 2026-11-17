import ArgumentParser
import Foundation
import SkreenrekControl
import SkreenrekCore
import Synchronization

/// The `skreenrek` command line: a `gh`-style client of the running app. Human output by default, `--json` for
/// agents, errors on stderr with a `hint:`, and the design spec's exit codes.
public enum CLI {
    static let globalFlags: Set<String> = ["--json", "--quiet", "--no-color"]

    /// Runs one invocation (arguments without the executable) and returns the exit code.
    public static func run(_ arguments: [String], environment: CLIEnvironment) async -> Int32 {
        let arguments = hoistGlobalFlags(arguments)
        let parsed: any ParsableCommand
        do {
            parsed = try SkreenrekCommand.parseAsRoot(arguments)
        } catch {
            return parseFailure(error, arguments: arguments, environment: environment)
        }
        guard let carrier = parsed as? any GlobalOptionsCarrier else {
            // `help`, `--help` on a group, or a group alone (`skreenrek`, `skreenrek debug`): ArgumentParser's own
            // `run()` throws the help request, which prints like `--help`.
            var command = parsed
            do {
                try command.run()
                return 0
            } catch {
                return parseFailure(error, arguments: arguments, environment: environment)
            }
        }
        let global = carrier.global
        let mode = OutputMode(
            json: global.json, quiet: global.quiet, noColor: global.noColor, environment: environment)
        let runner = Runner(environment: environment, mode: mode)
        do {
            return try await runner.run(parsed)
        } catch {
            return runner.report(CLIError.body(for: error))
        }
    }

    /// `--json`, `--quiet` and `--no-color` before the command name move after it, so `skreenrek --json windows`
    /// works like `skreenrek windows --json`.
    static func hoistGlobalFlags(_ arguments: [String]) -> [String] {
        var leading: [String] = []
        var rest = arguments[...]
        while let first = rest.first, globalFlags.contains(first) {
            leading.append(first)
            rest = rest.dropFirst()
        }
        guard !leading.isEmpty, !rest.isEmpty else { return arguments }
        // After the command (and `debug perf`'s subcommand), before any `--` terminator.
        var command = Array(rest.prefix(1))
        rest = rest.dropFirst()
        if command == ["debug"], let sub = rest.first, !sub.hasPrefix("-") {
            command.append(sub)
            rest = rest.dropFirst()
        }
        return command + leading + rest
    }

    /// Help and `--version` print on stdout and exit 0; anything else is a usage error (exit 2, not ArgumentParser's 64).
    private static func parseFailure(_ error: any Error, arguments: [String], environment: CLIEnvironment) -> Int32 {
        let code = SkreenrekCommand.exitCode(for: error)
        if code == .success {
            let message = SkreenrekCommand.fullMessage(for: error)
            if !message.isEmpty { environment.stdout.write(message + "\n") }
            return 0
        }
        var message = SkreenrekCommand.message(for: error).trimmingCharacters(in: .whitespacesAndNewlines)
        if message.hasPrefix("Error: ") { message.removeFirst("Error: ".count) }
        if let last = message.last, !".!?:".contains(last) { message += "." }
        let body = ErrorBody(
            code: "usage", message: message, hint: "Run: skreenrek \(commandPath(arguments)) --help".replacingOccurrences(
                of: "skreenrek  --help", with: "skreenrek --help"),
            exit: 2)
        let mode = OutputMode(
            json: arguments.contains("--json"), quiet: false, noColor: arguments.contains("--no-color"),
            environment: environment)
        return Runner(environment: environment, mode: mode).report(body)
    }

    /// The subcommand the arguments name (`record`, `debug perf`), or "" when none.
    static func commandPath(_ arguments: [String]) -> String {
        let names = SkreenrekCommand.configuration.subcommands.compactMap { $0.configuration.commandName }
        guard let first = arguments.first(where: { !$0.hasPrefix("-") }), names.contains(first) else { return "" }
        if first == "debug", let index = arguments.firstIndex(of: "debug"), arguments.count > index + 1,
            arguments[index + 1] == "perf"
        {
            return "debug perf"
        }
        return first
    }
}

/// The commands that take `--json --quiet --no-color`.
protocol GlobalOptionsCarrier {
    var global: GlobalOptions { get }
}

extension WindowsCommand: GlobalOptionsCarrier {}
extension PickCommand: GlobalOptionsCarrier {}
extension ResizeCommand: GlobalOptionsCarrier {}
extension RecordCommand: GlobalOptionsCarrier {}
extension StopCommand: GlobalOptionsCarrier {}
extension DiscardCommand: GlobalOptionsCarrier {}
extension StatusCommand: GlobalOptionsCarrier {}
extension LastCommand: GlobalOptionsCarrier {}
extension DoctorCommand: GlobalOptionsCarrier {}
extension PerfCommand: GlobalOptionsCarrier {}

/// Runs one parsed command against the app.
struct Runner: Sendable {
    let environment: CLIEnvironment
    let mode: OutputMode

    var format: HumanFormat { HumanFormat(style: Style(enabled: mode.color), home: environment.home.path) }
    var connector: AppConnector { AppConnector(environment: environment) }

    func run(_ command: any ParsableCommand) async throws -> Int32 {
        switch command {
        case let c as WindowsCommand: return try await windows(c)
        case is PickCommand: return try await pick()
        case let c as ResizeCommand: return try await resize(c)
        case let c as RecordCommand: return try await record(c)
        case is StopCommand: return try await stop()
        case is DiscardCommand: return try await discard()
        case is StatusCommand: return try await status()
        case is LastCommand: return try await last()
        case is DoctorCommand: return try await doctor()
        case let c as PerfCommand: return try await perf(c)
        default: throw SkreenrekError.internal(message: "\(type(of: command)) isn't a command this CLI runs.")
        }
    }

    // MARK: - Output

    /// Writes stdout text unless `--quiet`.
    func say(_ text: String) {
        guard !mode.quiet, !text.isEmpty else { return }
        environment.stdout.write(text)
    }

    /// Writes one JSON document on stdout unless `--quiet`.
    func sayJSON<T: Encodable>(_ value: T) throws {
        guard !mode.quiet else { return }
        environment.stdout.write(try SkreenrekJSON.string(value) + "\n")
    }

    /// Human text, or the JSON body with `--json`.
    func emit<T: Encodable>(_ value: T, human: (HumanFormat) -> String) throws {
        if mode.json {
            try sayJSON(value)
        } else {
            say(human(format))
        }
    }

    /// Prints an error on stderr (`error:` + `hint:`, or the JSON envelope) and returns its exit code.
    func report(_ body: ErrorBody) -> Int32 {
        if mode.json {
            let line = (try? SkreenrekJSON.string(ErrorEnvelope(error: body))) ?? #"{"error":{"code":"internal"}}"#
            environment.stderr.write(line + "\n")
        } else {
            environment.stderr.write(HumanFormat(style: Style(enabled: mode.errorColor), home: "").error(body))
        }
        return body.exit
    }

    // MARK: - Commands

    private func windows(_ c: WindowsCommand) async throws -> Int32 {
        let client = try await connector.connect()
        let body = try await client.call(.windows, params: WindowsParams(app: c.app), as: WindowsBody.self)
        try emit(body) { $0.windows(body) }
        return 0
    }

    private func pick() async throws -> Int32 {
        let client = try await connector.connect()
        let body = try await client.call(.pick, params: PickParams(), as: PickBody.self)
        try emit(body) { $0.pick(body) }
        return 0
    }

    private func resize(_ c: ResizeCommand) async throws -> Int32 {
        let ref = try WindowRef.parse(id: c.window, app: c.app, title: c.title)
        let size = try Values.size(c.size)
        let client = try await connector.connect()
        let params = ResizeParams(
            windowId: ref.windowId, app: ref.app, title: ref.title, width: size.width, height: size.height,
            allowInexact: c.allowInexact ? true : nil)
        let readback = try await client.call(.resize, params: params, as: Readback.self)
        try emit(readback) { $0.resize(readback) }
        return 0
    }

    /// The `record.start` params from the flags. Every check runs before anything is sent.
    func startParams(_ c: RecordCommand) throws -> StartParams {
        let ref = try WindowRef.parse(id: c.window, app: c.app, title: c.title)
        var params = StartParams(windowId: ref.windowId, app: ref.app, title: ref.title)
        if let region = c.region {
            guard ref.isEmpty else {
                throw SkreenrekError.usage(
                    message: "Pass a window or --region, not both.", hint: "Drop the window, or drop --region.")
            }
            guard c.size == nil else {
                throw SkreenrekError.usage(
                    message: "A region already has its size, so it can't be resized.",
                    hint: "Drop --size, or record a window.")
            }
            params.region = try Values.region(region)
            params.displayId = try c.display.map(Values.display)
        } else if c.display != nil {
            throw SkreenrekError.usage(message: "--display only works with --region.", hint: "Add --region X,Y,W,H.")
        }
        if let size = c.size {
            let parsed = try Values.size(size)
            params.width = parsed.width
            params.height = parsed.height
        }
        params.allowInexact = c.allowInexact ? true : nil
        params.fps = try c.fps.map(Values.fps)
        params.durationSeconds = try c.duration.map(Values.duration)
        params.cursor = c.noCursor ? false : nil
        params.events = c.noEvents ? false : nil
        params.hud = c.noHud ? false : nil
        let home = environment.home
        let cwd = environment.currentDirectory
        params.outDir = c.out.map { Values.folder($0, home: home, base: cwd) }
        params.assetsDir = c.assets.map { Values.folder($0, home: home, base: cwd) }
        params.name = c.name
        params.codec = try c.codec.map(Values.codec)
        return params
    }

    private func record(_ c: RecordCommand) async throws -> Int32 {
        let params = try startParams(c)
        // Ctrl-C is caught from before the start, so it never leaves a recording running without this command.
        let interrupts = c.wait ? environment.interrupts.interrupts() : nil
        let client = try await connector.connect()
        let start = try await client.call(.recordStart, params: params, as: StartBody.self)
        if mode.json {
            if !c.wait { try sayJSON(start) }
        } else {
            say((start.readback.map(format.recordReadback) ?? "") + format.recording(start))
        }
        guard let interrupts else { return 0 }
        return try await waitForEnd(of: start, client: client, interrupts: interrupts)
    }

    /// `--wait`: blocks until the recording stops (stop, duration, failure). Ctrl-C stops and saves, prints the stop
    /// output and exits 130.
    private func waitForEnd(of start: StartBody, client: ControlClient, interrupts: AsyncStream<Void>) async throws
        -> Int32
    {
        let (end, interrupted) = try await awaitEnd(of: start, client: client, interrupts: interrupts)
        switch end {
        case .saved(let body):
            try emit(body) { $0.saved(body) }
        case .discarded:
            try emit(DiscardBody()) { $0.discarded() }
        }
        return interrupted ? SkreenrekError.interrupted.exitCode : 0
    }

    /// Waits on its own connection until the recording `start` began ends. Each element of `interrupts` sends a stop
    /// on `client`; the wait then answers with what that stop saved. Returns whether an interrupt came first.
    func awaitEnd(of start: StartBody, client: ControlClient, interrupts: AsyncStream<Void>?) async throws
        -> (EndBody, interrupted: Bool)
    {
        let waiter = try await connector.connect()
        let interrupted = InterruptFlag()
        let outcome: Result<EndBody, any Error> = await withTaskGroup(of: Result<EndBody, any Error>?.self) { group in
            group.addTask {
                do {
                    return .success(try await waiter.call(.recordWait, as: EndBody.self))
                } catch {
                    return .failure(error)
                }
            }
            if let interrupts {
                group.addTask {
                    for await _ in interrupts {
                        interrupted.set()
                        _ = try? await client.send(.recordStop)
                        return nil
                    }
                    return nil
                }
            }
            var result: Result<EndBody, any Error> = .failure(CancellationError())
            while let next = await group.next() {
                if let next {
                    result = next
                    group.cancelAll()
                }
            }
            return result
        }
        switch outcome {
        case .success(let body):
            return (body, interrupted.isSet)
        case .failure(let error):
            return (try await endAfterWaitFailed(error, start: start, client: client), interrupted.isSet)
        }
    }

    /// `record.wait` said "not recording": the recording ended before the wait arrived. Its outcome is in `status`.
    private func endAfterWaitFailed(_ error: any Error, start: StartBody, client: ControlClient) async throws
        -> EndBody
    {
        guard let remote = error as? ControlRemoteError,
            remote.body == SkreenrekError.wrongState(.notRecording).body
        else { throw error }
        let status = try await client.call(.status, as: StatusBody.self)
        if let error = status.error { throw CLIError(body: error) }
        if let last = status.lastClip, last.recording.id == start.recordingId { return .saved(last) }
        return .discarded
    }

    private func stop() async throws -> Int32 {
        let client = try await connector.connect()
        let body = try await client.call(.recordStop, as: StopBody.self)
        try emit(body) { $0.saved(body) }
        return 0
    }

    private func discard() async throws -> Int32 {
        let client = try await connector.connect()
        let body = try await client.call(.recordDiscard, as: DiscardBody.self)
        try emit(body) { $0.discarded() }
        return 0
    }

    private func status() async throws -> Int32 {
        let client = try await connector.connect()
        let body = try await client.call(.status, as: StatusBody.self)
        try emit(body) { $0.status(body) }
        return 0
    }

    private func last() async throws -> Int32 {
        let client = try await connector.connect()
        let body = try await client.call(.last, as: StopBody.self)
        try emit(body) { $0.saved(body) }
        return 0
    }
}

/// Set once Ctrl-C arrived.
private final class InterruptFlag: Sendable {
    private let value = Mutex(false)
    func set() { value.withLock { $0 = true } }
    var isSet: Bool { value.withLock { $0 } }
}
