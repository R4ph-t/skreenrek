import SkreenrekCore

extension Runner {
    func setupAgents(_ command: SetupAgentsCommand) throws -> Int32 {
        let installer = AgentInstaller(
            home: environment.home, executablePath: environment.executablePath, path: environment.variables["PATH"] ?? "")
        let results = installer.run(agents: command.agents, remove: command.remove)
        if mode.json {
            say(try SkreenrekJSON.string(results) + "\n")
        } else {
            for result in results {
                say("\(result.success ? "✓" : "✗") \(result.agent.name) · \(result.message)\n")
                for warning in result.warnings { environment.stderr.write("warning: \(warning)\n") }
            }
        }
        return results.allSatisfy { $0.success } ? 0 : 1
    }
}
