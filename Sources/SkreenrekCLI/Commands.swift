import ArgumentParser
import SkreenrekCore

// The design spec's CLI block, as ArgumentParser commands. They only parse: `CLI` runs them, so output, errors and
// exit codes stay the design spec's, not ArgumentParser's defaults.

struct GlobalOptions: ParsableArguments {
    @Flag(help: "Print JSON on stdout (errors as JSON on stderr).") var json = false
    @Flag(help: "Print nothing on success.") var quiet = false
    @Flag(name: .customLong("no-color"), help: "Never colour the output.") var noColor = false
}

struct SkreenrekCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "skreenrek",
        abstract: "Record a macOS window at an exact pixel size, for coding agents.",
        discussion: "Global: --json  --quiet  --no-color  --help  --version",
        version: "skreenrek \(SkreenrekVersion.current)",
        subcommands: [
            WindowsCommand.self, PickCommand.self, ResizeCommand.self, RecordCommand.self, StopCommand.self,
            DiscardCommand.self, StatusCommand.self, LastCommand.self, DoctorCommand.self, MCPCommand.self,
            DebugCommand.self,
        ])
}

struct WindowsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "windows", abstract: "List windows that can be recorded")
    @Option(help: "Only windows of this app (name or bundle ID).") var app: String?
    @OptionGroup var global: GlobalOptions
}

struct PickCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pick", abstract: "Open the picker overlay and print the chosen window")
    @OptionGroup var global: GlobalOptions
}

struct ResizeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resize", abstract: "Resize to exact pixels and read the size back")
    @Argument(help: "A window ID from `skreenrek windows`.") var window: String?
    @Option(help: "The app whose window to use (name or bundle ID).") var app: String?
    @Option(help: "With --app: a part of the window title.") var title: String?
    @Option(help: ArgumentHelp("The size in pixels.", valueName: "WxH")) var size: String
    @Flag(help: "Don't fail when the size read back isn't exact.") var allowInexact = false
    @OptionGroup var global: GlobalOptions
}

struct RecordCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "record", abstract: "Start recording (returns immediately)",
        usage: """
            skreenrek record <window> [flags]
            skreenrek record --app NAME [--title TEXT] [flags]
            skreenrek record --region X,Y,W,H [--display ID] [flags]
            """)
    @Argument(help: "A window ID from `skreenrek windows`.") var window: String?
    @Option(help: "The app whose window to record (name or bundle ID).") var app: String?
    @Option(help: "With --app: a part of the window title.") var title: String?
    @Option(help: ArgumentHelp("Record a screen region, in pixels of the display.", valueName: "X,Y,W,H"))
    var region: String?
    @Option(help: ArgumentHelp("With --region: the display (default: the main display).", valueName: "ID"))
    var display: String?
    @Option(help: ArgumentHelp("Resize the window first, in pixels.", valueName: "WxH")) var size: String?
    @Flag(help: "Record even when the size read back isn't exact.") var allowInexact = false
    @Option(help: ArgumentHelp("30 or 60 (default from Settings, otherwise 60).", valueName: "30|60")) var fps: Int?
    @Option(help: ArgumentHelp("Stop after this long: 30s, 2m, 1m30s or seconds.", valueName: "TIME"))
    var duration: String?
    @Flag(help: "Hide the cursor in the video.") var noCursor = false
    @Flag(help: "Don't write events.json.") var noEvents = false
    @Flag(help: "Don't show the recording indicator.") var noHud = false
    @Option(help: ArgumentHelp("The folder for the clip folder.", valueName: "DIR")) var out: String?
    @Option(help: ArgumentHelp("The clip folder's name instead of the app.", valueName: "SLUG")) var name: String?
    @Option(help: ArgumentHelp("Also copy the clip into this HyperFrames assets folder.", valueName: "DIR"))
    var assets: String?
    @Option(help: ArgumentHelp("h264, hevc or prores.", valueName: "h264|hevc|prores")) var codec: String?
    @Option(help: ArgumentHelp("mp4 or mov (default mp4).", valueName: "mp4|mov")) var format: String?
    @Option(help: ArgumentHelp("Compression preset (default high).", valueName: "low|medium|high|max")) var quality: String?
    @Option(help: ArgumentHelp("Average bitrate in Mbps, from 1 to 200.", valueName: "Mbps")) var bitrate: Double?
    @Flag(help: "Wait until the recording stops; Ctrl-C stops and saves.") var wait = false
    @OptionGroup var global: GlobalOptions
}

struct StopCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "stop", abstract: "Stop, write files, print paths")
    @OptionGroup var global: GlobalOptions
}

struct DiscardCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "discard", abstract: "Stop and delete the current recording")
    @OptionGroup var global: GlobalOptions
}

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status", abstract: "idle | armed | recording | writing | error")
    @OptionGroup var global: GlobalOptions
}

struct LastCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "last", abstract: "Paths of the last clip")
    @OptionGroup var global: GlobalOptions
}

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor", abstract: "Permissions, app, version, output folder")
    @OptionGroup var global: GlobalOptions
}

struct MCPCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "mcp", abstract: "Run the stdio MCP server")
}

struct DebugCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "debug", abstract: "Developer tools", shouldDisplay: false, subcommands: [PerfCommand.self])
}

struct PerfCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "perf", abstract: "Measure start time, frame pacing and finalizing against the targets")
    @Option(help: "The app whose window to record.") var app: String
    @Option(help: "With --app: a part of the window title.") var title: String?
    @Option(help: "How many starts to time.") var runs: Int = PerfPlan.standard.startRuns
    @Flag(help: "Also record one 15-minute clip.") var long = false
    @Flag(help: "Keep the clips instead of deleting them.") var keep = false
    @OptionGroup var global: GlobalOptions
}
