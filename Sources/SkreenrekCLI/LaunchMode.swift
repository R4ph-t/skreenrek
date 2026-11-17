/// How one binary tells an app launch from a terminal call.
public enum LaunchMode: Sendable, Hashable {
    /// Run the menu-bar app.
    case app
    /// Print the help.
    case help
    /// Run the CLI with these arguments.
    case cli([String])

    /// No arguments and stdin not a TTY (a Finder or `open` launch) → the app; `skreenrek app` → the app; no
    /// arguments in a terminal → the help; anything else → the CLI. A `-psn_…` argument (old LaunchServices) counts as
    /// no argument.
    public static func decide(arguments: [String], stdinIsTTY: Bool) -> LaunchMode {
        let arguments = arguments.filter { !$0.hasPrefix("-psn_") }
        if arguments == ["app"] { return .app }
        if arguments.isEmpty { return stdinIsTTY ? .help : .app }
        return .cli(arguments)
    }
}
