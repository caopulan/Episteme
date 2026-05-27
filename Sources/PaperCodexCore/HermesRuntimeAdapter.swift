import Foundation

public struct HermesRuntimeAdapter: Sendable {
    public var executablePath: String

    public init(executablePath: String) {
        self.executablePath = executablePath
    }

    public static func findExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> String {
        try AgentRuntimeExecutableResolver.executablePath(
            named: "hermes",
            additionalPaths: [
                "/opt/homebrew/bin/hermes",
                "/usr/local/bin/hermes",
                "~/.local/bin/hermes"
            ],
            environment: environment,
            fileManager: fileManager
        )
    }

    public func nonInteractiveCommand(
        prompt: String,
        workspacePath: String,
        provider: String?,
        model: String?,
        skillsPath: String?
    ) -> AgentRuntimeCommand {
        var arguments = [
            "chat",
            "--query", prompt
        ]
        if let provider = normalized(provider) {
            arguments += ["--provider", provider]
        }
        if let model = normalized(model) {
            arguments += ["--model", model]
        }
        if let skillsPath = normalized(skillsPath) {
            arguments += ["--skills", skillsPath]
        }
        arguments += ["--source", "papercodex"]
        return AgentRuntimeCommand(
            executablePath: executablePath,
            arguments: arguments,
            currentDirectoryPath: workspacePath
        )
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
