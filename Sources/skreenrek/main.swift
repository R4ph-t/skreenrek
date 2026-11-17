import Foundation
import SkreenrekCore
import SkreenrekSystem

// The CLI parser arrives in 06. Until then: `--version`, or usage and exit 2.
let arguments = Array(CommandLine.arguments.dropFirst())

if arguments == ["--version"] {
    print("skreenrek \(SkreenrekVersion.current)")
    exit(SkreenrekExitCode.success.rawValue)
}

FileHandle.standardError.write(Data("usage: skreenrek --version\n".utf8))
exit(SkreenrekExitCode.usage.rawValue)
