import AppKit
import Foundation
import SkreenrekCLI
import SkreenrekControl
import SkreenrekCore
import SkreenrekSystem
import SkreenrekUI

let commandLine = Array(CommandLine.arguments.dropFirst())

// Hidden: renders the menu-bar UI to PNGs at 2× in light and dark, for Designer. `--direction size13` renders the spec 13
// Size states; `--direction c` is the shipping UI too. It draws with AppKit on the main thread, so it runs here rather
// than in the CLI.
if let request = RenderUIRequest.parse(commandLine) {
    do {
        let written = try MainActor.assumeIsolated { try UIRenderer.render(request) }
        for file in written { print(file.url.path) }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("error: Couldn't render the UI: \(error)\n".utf8))
        exit(1)
    }
}

switch LaunchMode.decide(arguments: commandLine, stdinIsTTY: isatty(STDIN_FILENO) == 1) {
case .app:
    // The menu-bar app: the controller, the control socket and the menu bar (LSUIElement-style, no Dock icon).
    MainActor.assumeIsolated {
        MenuBarApp.run(
            seams: AppSeams.real(), requester: SystemPermissionRequester(),
            previews: ScreenshotWindowPreview())
    }
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
enum AppSeams {
    static func real() -> ControllerSeams {
        let clock = HostTimeClock()
        let catalog = SCWindowCatalog()
        return ControllerSeams(
            catalog: catalog, resizer: AXWindowResizer(catalog: catalog), frameSource: SCStreamFrameSource(),
            mouse: NSEventMouseSource(clock: clock), clock: clock, permissions: SystemPermissionProbe(),
            disk: VolumeDiskSpaceProbe(), picker: PickerOverlay(catalog: catalog), encoder: .requireHardware)
    }
}
