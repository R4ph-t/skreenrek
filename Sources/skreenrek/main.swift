import Foundation
import SkreenrekCore
import SkreenrekSystem

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments == ["--version"] {
    print("skreenrek \(SkreenrekVersion.current)")
    exit(0)
}

FileHandle.standardError.write(Data("usage: skreenrek --version\n".utf8))
exit(2)
