import AppKit
import Foundation
import SkreenrekCLI
import SkreenrekControl
import SkreenrekCore
import SkreenrekSystem

switch LaunchMode.decide(arguments: Array(CommandLine.arguments.dropFirst()), stdinIsTTY: isatty(STDIN_FILENO) == 1) {
case .app:
    // The headless app (the controller and the control socket with the real seams) until the menu-bar UI arrives in
    // 08.
    MainActor.assumeIsolated { HeadlessApp.run() }
case .help:
    runCLI(["--help"])
case .cli(let arguments):
    runCLI(arguments)
}

/// Runs the CLI on the concurrency pool and exits with its code; the main thread parks in `dispatchMain()`.
func runCLI(_ arguments: [String]) -> Never {
    let environment = CLIEnvironment.live()
    Task.detached {
        let code = await CLI.run(arguments, environment: environment)
        exit(code)
    }
    dispatchMain()
}

extension CLIEnvironment {
    /// The real terminal, process environment, socket, launcher and Ctrl-C.
    static func live() -> CLIEnvironment {
        let fm = FileManager.default
        return CLIEnvironment(
            stdout: FileHandleOutput(.standardOutput), stderr: FileHandleOutput(.standardError),
            stdoutIsTTY: isatty(STDOUT_FILENO) == 1, stderrIsTTY: isatty(STDERR_FILENO) == 1,
            variables: ProcessInfo.processInfo.environment, home: fm.homeDirectoryForCurrentUser,
            currentDirectory: URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true),
            socketPath: ControlPaths.socketURL(), executablePath: executablePath(), launcher: WorkspaceAppLauncher(),
            interrupts: SignalInterruptSource(), clock: HostTimeClock())
    }

    /// The path this process was exec'd from (a symlink stays a symlink; the CLI resolves it).
    private static func executablePath() -> String {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size) + 1)
        guard _NSGetExecutablePath(&buffer, &size) == 0 else { return CommandLine.arguments[0] }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

@MainActor
enum HeadlessApp {
    static func run() -> Never {
        let clock = HostTimeClock()
        let catalog = SCWindowCatalog()
        let seams = ControllerSeams(
            catalog: catalog, resizer: AXWindowResizer(catalog: catalog), frameSource: SCStreamFrameSource(),
            mouse: NSEventMouseSource(clock: clock), clock: clock, permissions: SystemPermissionProbe(),
            disk: VolumeDiskSpaceProbe(), encoder: .requireHardware)
        let host = HeadlessHost(seams: seams)
        do {
            try host.start()
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(host) { app.run() }
        exit(0)
    }
}
