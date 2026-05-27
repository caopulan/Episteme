import Foundation

public struct CommandAgentRuntime: Sendable {
    public init() {}

    public static func sanitizedProcessEnvironment(
        workingDirectoryURL: URL,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        environmentOverrides: [String: String] = [:]
    ) -> [String: String] {
        var environment = baseEnvironment
        environment["PWD"] = workingDirectoryURL.standardizedFileURL.path
        environment.removeValue(forKey: "OLDPWD")
        for (key, value) in environmentOverrides {
            environment[key] = value
        }
        return environment
    }

    public func runStreaming(
        command: AgentRuntimeCommand,
        eventLogURL: URL? = nil,
        runHandle: AgentRunHandle? = nil,
        onStdoutData: @escaping @Sendable (Data) -> [AgentRunEvent],
        onStderrData: @escaping @Sendable (Data) -> [AgentRunEvent],
        finish: @escaping @Sendable () -> (stdout: String, stderr: String, events: [AgentRunEvent]),
        onEvent: @escaping @Sendable (AgentRunEvent) -> Void
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executablePath)
        process.arguments = command.arguments
        configure(process, command: command)

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            while true {
                let data = output.fileHandleForReading.availableData
                if data.isEmpty {
                    break
                }
                for event in onStdoutData(data) {
                    onEvent(event)
                }
            }
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            while true {
                let data = error.fileHandleForReading.availableData
                if data.isEmpty {
                    break
                }
                for event in onStderrData(data) {
                    onEvent(event)
                }
            }
            group.leave()
        }

        try process.run()
        runHandle?.setProcess(process)
        process.waitUntilExit()
        runHandle?.clearProcess(process)
        group.wait()

        let result = finish()
        for event in result.events {
            onEvent(event)
        }
        if let eventLogURL {
            try result.stdout.write(to: eventLogURL, atomically: true, encoding: .utf8)
        }
        if process.terminationStatus != 0 {
            throw CodexCLIError.processFailed(status: process.terminationStatus, stderr: result.stderr)
        }
        return result.stdout
    }

    private func configure(_ process: Process, command: AgentRuntimeCommand) {
        let workingDirectoryURL = command.currentDirectoryPath
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        let standardizedWorkingDirectoryURL = workingDirectoryURL.standardizedFileURL
        process.currentDirectoryURL = standardizedWorkingDirectoryURL
        process.environment = Self.sanitizedProcessEnvironment(
            workingDirectoryURL: standardizedWorkingDirectoryURL,
            environmentOverrides: command.environmentOverrides
        )
    }
}
