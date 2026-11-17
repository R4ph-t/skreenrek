import Foundation
import SkreenrekControl
import SkreenrekCore

/// Where the CLI writes text: stdout or stderr. Real: `FileHandleOutput`. Tests: a buffer.
public protocol TextOutput: Sendable {
    func write(_ text: String)
}

/// Writes to a file handle (stdout or stderr) as it goes.
public struct FileHandleOutput: TextOutput {
    private let handle: FileHandle

    public init(_ handle: FileHandle) {
        self.handle = handle
    }

    public func write(_ text: String) {
        handle.write(Data(text.utf8))
    }
}

/// Everything the CLI touches outside itself. `main.swift` passes the real ones; tests pass buffers and fakes.
public struct CLIEnvironment: Sendable {
    public var stdout: any TextOutput
    public var stderr: any TextOutput
    public var stdoutIsTTY: Bool
    public var stderrIsTTY: Bool
    /// The process environment (`NO_COLOR`, `PATH`).
    public var variables: [String: String]
    public var home: URL
    /// Relative `--out` and `--assets` folders resolve against it: the app runs elsewhere.
    public var currentDirectory: URL
    public var socketPath: URL
    /// The running executable's path, as exec'd (symlinks are resolved by the CLI).
    public var executablePath: String
    public var launcher: any AppLauncher
    public var interrupts: any InterruptSource
    /// Times the wait for a launched app; nothing else.
    public var clock: any HostClock
    /// How long a launched app has to answer `hello`.
    public var launchTimeout: TimeInterval
    /// Runs `debug perf`'s recordings and reads their clips; nil uses the app and `AVAssetReader`.
    public var perf: PerfSeams?

    public init(
        stdout: any TextOutput, stderr: any TextOutput, stdoutIsTTY: Bool, stderrIsTTY: Bool,
        variables: [String: String], home: URL, currentDirectory: URL, socketPath: URL, executablePath: String,
        launcher: any AppLauncher, interrupts: any InterruptSource, clock: any HostClock,
        launchTimeout: TimeInterval = AppConnector.launchTimeout, perf: PerfSeams? = nil
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.stdoutIsTTY = stdoutIsTTY
        self.stderrIsTTY = stderrIsTTY
        self.variables = variables
        self.home = home
        self.currentDirectory = currentDirectory
        self.socketPath = socketPath
        self.executablePath = executablePath
        self.launcher = launcher
        self.interrupts = interrupts
        self.clock = clock
        self.launchTimeout = launchTimeout
        self.perf = perf
    }
}

/// `--json --quiet --no-color` resolved against the terminal and `NO_COLOR`.
public struct OutputMode: Sendable, Hashable {
    public var json: Bool
    public var quiet: Bool
    /// ANSI colour on stdout.
    public var color: Bool
    /// ANSI colour on stderr.
    public var errorColor: Bool

    /// Colour only when the stream is a TTY, `--no-color` isn't set and `NO_COLOR` is unset.
    public init(json: Bool, quiet: Bool, noColor: Bool, environment: CLIEnvironment) {
        self.json = json
        self.quiet = quiet
        let allowed = !noColor && environment.variables["NO_COLOR"] == nil
        color = allowed && environment.stdoutIsTTY
        errorColor = allowed && environment.stdoutIsTTY && environment.stderrIsTTY
    }
}
