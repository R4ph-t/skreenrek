import Foundation
import SkreenrekControl
import SkreenrekCore

extension Runner {
    /// One line per check (Screen Recording, Accessibility, the app's version and that it runs, the output folder,
    /// the CLI path, the socket) with ✓ or ✗ and a fix. Exit 3 when Screen Recording is missing, 1 when the app
    /// can't be reached, else 0.
    func doctor() async throws -> Int32 {
        let body: DoctorBody
        do {
            let client = try await connector.connect()
            body = try await client.call(.doctor, as: DoctorBody.self)
        } catch {
            let failure = CLIError.body(for: error)
            if mode.json { return report(failure) }
            say(doctorLines(body: nil, appFailure: failure))
            return failure.exit
        }
        if mode.json {
            try sayJSON(body)
        } else {
            say(doctorLines(body: body, appFailure: nil))
        }
        return body.permissions.screenRecording == .allowed ? 0 : SkreenrekError.permissionDenied(.screenRecording)
            .exitCode
    }

    /// The doctor report. Without a body (the app couldn't be reached) only the app, CLI and socket lines show.
    func doctorLines(body: DoctorBody?, appFailure: ErrorBody?) -> String {
        let f = format
        typealias Line = (ok: Bool, label: String, detail: String)
        var lines: [Line] = []
        if let body {
            let sr = body.permissions.screenRecording == .allowed
            lines.append((
                sr, "Screen Recording",
                sr ? "Allowed"
                    : "Not allowed. Allow it in System Settings › Privacy & Security › Screen & System Audio "
                        + "Recording."
            ))
            let ax = body.permissions.accessibility == .allowed
            lines.append((
                ax, "Accessibility",
                ax ? "Allowed"
                    : "Not allowed. Allow it in System Settings › Privacy & Security › Accessibility for exact sizes."
            ))
            let sameVersion = body.version == SkreenrekVersion.current
            lines.append((
                sameVersion, "Skreenrek app",
                sameVersion
                    ? "\(body.version), running"
                    : "\(body.version), running, but this command is \(SkreenrekVersion.current). Quit and reopen "
                        + "Skreenrek."
            ))
            let folder = f.tilde(body.outputFolder.path)
            lines.append((
                body.outputFolder.writable, "Output folder",
                body.outputFolder.writable
                    ? folder : "\(folder) isn't writable. Choose another folder in Settings, or pass --out DIR."
            ))
        } else {
            let detail = appFailure.map { "\($0.message) \($0.hint)" } ?? "Not running."
            lines.append((false, "Skreenrek app", detail))
        }
        let cli = commandLineTool()
        lines.append((cli.onPath, "Command-line tool", cli.detail))
        let socket = f.tilde(body?.socket ?? environment.socketPath.path)
        lines.append((body != nil, "Socket", body != nil ? socket : "Nothing answers at \(socket)."))
        let width = lines.map(\.label.count).max() ?? 0
        return lines.map { f.doctorLine(ok: $0.ok, label: $0.label, detail: $0.detail, labelWidth: width) }.joined()
    }

    /// This executable, and whether `skreenrek` on `PATH` runs it.
    func commandLineTool() -> (onPath: Bool, detail: String) {
        let me = URL(fileURLWithPath: environment.executablePath).resolvingSymlinksInPath().path
        let dirs = (environment.variables["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in dirs where !dir.isEmpty {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent("skreenrek")
            guard FileManager.default.isExecutableFile(atPath: candidate.path) else { continue }
            if candidate.resolvingSymlinksInPath().path == me { return (true, format.tilde(candidate.path)) }
        }
        return (
            false,
            "\(format.tilde(me)) isn't on your PATH as skreenrek. Link it: ln -s \"\(me)\" ~/.local/bin/skreenrek"
        )
    }
}
