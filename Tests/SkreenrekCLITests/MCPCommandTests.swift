import Foundation
import SkreenrekCLI
import SkreenrekControl
import SkreenrekCore
import SkreenrekTesting
import Testing

/// `skreenrek mcp` runs the stdio server on the CLI's stdin and stdout.
@Suite(.timeLimit(.minutes(2))) struct MCPCommandTests {
    @Test func mcpServesStdinUntilItClosesWithOnlyProtocolOnStdout() async throws {
        let h = try CLIHarness().start()
        defer { h.stop() }
        let lines = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","#
                + #""capabilities":{},"clientInfo":{"name":"codex-mcp-client","version":"0.1"}}}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"skreenrek_status"}}"#,
        ]
        let out = OutputBuffer()
        let err = OutputBuffer()
        var env = h.environment(stdout: out, stderr: err)
        env.input = {
            AsyncStream { continuation in
                for line in lines { continuation.yield(Data(line.utf8)) }
                continuation.finish()
            }
        }
        let environment = env
        let code = try await within("skreenrek mcp") { await CLI.run(["mcp"], environment: environment) }
        #expect(code == 0)
        let responses = out.contents.split(separator: "\n").map(String.init)
        #expect(responses.count == 2, "\(out.contents)")
        #expect(responses.first?.contains(#""protocolVersion":"2025-03-26""#) == true)
        #expect(responses.last?.hasPrefix(#"{"id":2,"jsonrpc":"2.0","result":{"content":[{"text":"{\"error\":null"#)
            == true, "\(responses.last ?? "")")
        #expect(err.contents.contains("MCP server ready on stdio"))
    }

    @Test func mcpIsListedInTheHelp() async throws {
        let h = CLIHarness()
        defer { h.temp.cleanUp() }
        let help = try await h.run(["--help"])
        #expect(help.out.contains("Run the stdio MCP server"))
    }
}
