import AppKit
import Foundation
import SkreenrekControl
import SkreenrekCore
import SkreenrekSystem

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments == ["--version"] {
    print("skreenrek \(SkreenrekVersion.current)")
    exit(0)
}

// Hidden: runs the app headless (the controller and the control socket with the real seams) until the menu-bar UI
// arrives in 08.
if arguments == ["app"] {
    MainActor.assumeIsolated { HeadlessApp.run() }
}

FileHandle.standardError.write(Data("usage: skreenrek --version\n".utf8))
exit(2)

@MainActor
enum HeadlessApp {
    static func run() -> Never {
        let clock = HostTimeClock()
        let seams = ControllerSeams(
            catalog: SCWindowCatalog(), resizer: AXWindowResizer(), frameSource: SCStreamFrameSource(),
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
