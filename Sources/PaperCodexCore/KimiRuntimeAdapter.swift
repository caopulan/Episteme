import Foundation

public struct KimiStreamParsedLine: Equatable, Sendable {
    public var event: CodexRunEvent?
    public var finalAnswer: String?
    public var sessionID: String?

    public init(event: CodexRunEvent?, finalAnswer: String?, sessionID: String?) {
        self.event = event
        self.finalAnswer = finalAnswer
        self.sessionID = sessionID
    }
}

public enum KimiStreamEventParser {
    public static func parseLine(_ line: String) throws -> CodexRunEvent? {
        try parseResultLine(line).event
    }

    public static func parseResultLine(_ line: String) throws -> KimiStreamParsedLine {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return KimiStreamParsedLine(event: nil, finalAnswer: nil, sessionID: nil)
        }
        guard let data = trimmed.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return KimiStreamParsedLine(
                event: CodexRunEvent(kind: .raw, title: "Kimi CLI", detail: trimmed),
                finalAnswer: nil,
                sessionID: nil
            )
        }

        let role = stringValue(named: "role", in: json)
        let type = stringValue(named: "type", in: json)
        if role == "assistant" {
            if let toolEvent = toolCallEvent(in: json) {
                return KimiStreamParsedLine(event: toolEvent, finalAnswer: nil, sessionID: nil)
            }
            let content = stringValue(named: "content", in: json) ?? ""
            return KimiStreamParsedLine(
                event: CodexRunEvent(kind: .answer, title: "Kimi CLI", detail: content),
                finalAnswer: content,
                sessionID: nil
            )
        }
        if role == "tool" {
            let name = stringValue(named: "name", in: json) ?? "Kimi tool"
            let content = stringValue(named: "content", in: json) ?? "Tool result"
            return KimiStreamParsedLine(
                event: CodexRunEvent(kind: .tool, title: name, detail: content),
                finalAnswer: nil,
                sessionID: nil
            )
        }
        if role == "meta", type == "session.resume_hint" {
            let sessionID = stringValue(named: "session_id", in: json)
            let detail = stringValue(named: "content", in: json)
                ?? sessionID.map { "Kimi CLI session \($0)" }
                ?? "Kimi CLI session updated"
            return KimiStreamParsedLine(
                event: CodexRunEvent(kind: .status, title: "Kimi CLI", detail: detail),
                finalAnswer: nil,
                sessionID: sessionID
            )
        }

        let title = type ?? role ?? "Kimi CLI"
        return KimiStreamParsedLine(
            event: CodexRunEvent(kind: .raw, title: title, detail: compactJSONString(json) ?? trimmed),
            finalAnswer: nil,
            sessionID: nil
        )
    }

    private static func toolCallEvent(in json: [String: Any]) -> CodexRunEvent? {
        guard let calls = json["tool_calls"] as? [[String: Any]],
              let first = calls.first else {
            return nil
        }
        let function = first["function"] as? [String: Any]
        let name = stringValue(named: "name", in: function) ?? stringValue(named: "name", in: first) ?? "Kimi tool"
        let detail = stringValue(named: "arguments", in: function)
            ?? stringValue(named: "content", in: json)
            ?? "Tool call"
        return CodexRunEvent(kind: .tool, title: name, detail: detail)
    }

    private static func stringValue(named key: String, in value: Any?) -> String? {
        guard let dictionary = value as? [String: Any],
              let raw = dictionary[key] else {
            return nil
        }
        if let string = raw as? String, !string.isEmpty {
            return string
        }
        return nil
    }

    private static func compactJSONString(_ value: Any?) -> String? {
        guard let value,
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }
}

public struct KimiRuntimeAdapter: Sendable {
    public var executablePath: String

    public init(executablePath: String) {
        self.executablePath = executablePath
    }

    public static func findExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> String {
        try AgentRuntimeExecutableResolver.executablePath(
            named: "kimi",
            additionalPaths: [
                "/opt/homebrew/bin/kimi",
                "/usr/local/bin/kimi",
                "~/.local/bin/kimi"
            ],
            environment: environment,
            fileManager: fileManager
        )
    }

    public func nonInteractiveCommand(
        prompt: String,
        workspacePath: String,
        sessionID: String?,
        modelID: String?,
        skillsPath: String?
    ) -> AgentRuntimeCommand {
        var arguments: [String] = []
        if let sessionID = normalized(sessionID) {
            arguments += ["--session", sessionID]
        }
        if let modelID = normalized(modelID) {
            arguments += ["--model", modelID]
        }
        arguments += [
            "--prompt", prompt,
            "--output-format", "stream-json"
        ]
        if let skillsPath = normalized(skillsPath) {
            arguments += ["--skills-dir", skillsPath]
        }
        return AgentRuntimeCommand(
            executablePath: executablePath,
            arguments: arguments,
            currentDirectoryPath: workspacePath
        )
    }

    public func terminalCommand(
        workspacePath: String,
        sessionID: String?,
        modelID: String?,
        skillsPath: String?
    ) -> AgentRuntimeCommand {
        var arguments: [String] = []
        if let sessionID = normalized(sessionID) {
            arguments += ["--session", sessionID]
        }
        if let modelID = normalized(modelID) {
            arguments += ["--model", modelID]
        }
        if let skillsPath = normalized(skillsPath) {
            arguments += ["--skills-dir", skillsPath]
        }
        return AgentRuntimeCommand(
            executablePath: executablePath,
            arguments: arguments,
            currentDirectoryPath: workspacePath,
            launchMode: .pty
        )
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
