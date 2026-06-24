import Foundation
import PaperCodexCore

struct AgentChatTurnContext {
    var papers: [Paper]
    var pagesByPaperID: [String: [PageIndex]]
    var spansByPaperID: [String: [Span]]
    var anchorsByPaperID: [String: [PaperCodexCore.Anchor]]
    var selectedAnchors: [PaperCodexCore.Anchor]
}

struct AgentChatTurnRequest {
    var content: String
    var session: PaperSession
    var context: AgentChatTurnContext
    var runtimeProfile: AgentRuntimeProfile
    var codexSystemPrompt: String
    var languageMode: PaperCodexLanguageMode
    var mcpEndpoint: PaperCodexMCPEndpoint?
    var mcpServers: [CodexMCPServerConfig]
    var modelOverride: String
    var providerOverride: String
    var reasoningEffort: CodexReasoningEffort
    var prefersWorkspaceImageOutput: Bool
}

struct AgentChatTurnResult {
    var updatedSession: PaperSession
    var message: ChatMessage
    var stdout: String
    var lastMessage: String
    var generatedImages: [URL]
    var tokenUsage: CodexTokenUsage?
}

struct AgentDiscoverEnrichmentRequest {
    var prompt: String
    var arxivID: String
    var workspaceURL: URL
    var outputURL: URL
    var eventLogURL: URL
    var runtimeProfile: AgentRuntimeProfile
    var modelOverride: String
    var providerOverride: String
    var reasoningEffort: CodexReasoningEffort
    var modelIdentity: String
    var runHandle: AgentRunHandle
}

struct AgentDiscoverEnrichmentResult {
    var enrichment: DiscoverPaperEnrichment
    var tokenUsage: CodexTokenUsage?
}

@MainActor
final class AgentRunCoordinator {
    private let workspaceManager: SessionWorkspaceManager
    private let codexRuntime: any AgentRuntime
    private let commandRuntime = CommandAgentRuntime()

    init(
        workspaceManager: SessionWorkspaceManager = SessionWorkspaceManager(),
        codexRuntime: any AgentRuntime = CodexAgentRuntime()
    ) {
        self.workspaceManager = workspaceManager
        self.codexRuntime = codexRuntime
    }

    func runChatTurn(
        _ request: AgentChatTurnRequest,
        runHandle: AgentRunHandle,
        onEvent: @escaping @Sendable (AgentRunEvent) -> Void
    ) async throws -> AgentChatTurnResult {
        let effectiveRuntimeProfile = request.prefersWorkspaceImageOutput
            ? (AgentRuntimeProfile.defaultProfile(id: "codex") ?? request.runtimeProfile)
            : request.runtimeProfile

        onEvent(
            CodexRunEvent(
                kind: .status,
                title: "Context",
                detail: "Loaded \(request.context.papers.count) paper(s), \(request.context.spansByPaperID.values.flatMap { $0 }.count) indexed span(s), \(request.context.selectedAnchors.count) selected source anchor(s)"
            )
        )

        try workspaceManager.writeWorkspace(
            session: request.session,
            papers: request.context.papers,
            pagesByPaperID: request.context.pagesByPaperID,
            spansByPaperID: request.context.spansByPaperID,
            anchorsByPaperID: request.context.anchorsByPaperID,
            mcpEndpoint: request.mcpEndpoint,
            materializationMode: request.session.workspaceMaterializationMode
        )
        onEvent(CodexRunEvent(kind: .status, title: "Workspace", detail: "Wrote session workspace at \(request.session.workspacePath)"))

        let prompt = PromptBuilder().buildPrompt(
            request: PromptRequest(
                userMessage: request.content,
                workspacePath: request.session.workspacePath,
                papers: request.context.papers,
                selectedAnchors: request.context.selectedAnchors,
                relevantSpans: [],
                systemPromptTemplate: request.codexSystemPrompt,
                languageMode: request.languageMode
            )
        )
        onEvent(CodexRunEvent(kind: .status, title: "Prompt", detail: "Built grounded prompt and started \(effectiveRuntimeProfile.displayName)"))

        let runResult = try await runAgentTurn(
            prompt: prompt,
            session: request.session,
            runtimeProfile: effectiveRuntimeProfile,
            modelOverride: request.modelOverride,
            providerOverride: request.providerOverride,
            reasoningEffort: request.reasoningEffort,
            prefersWorkspaceImageOutput: request.prefersWorkspaceImageOutput,
            mcpServers: effectiveRuntimeProfile.id == "codex" ? request.mcpServers : [],
            runHandle: runHandle,
            onEvent: onEvent
        )

        if !runResult.generatedImages.isEmpty {
            onEvent(
                CodexRunEvent(
                    kind: .answer,
                    title: "Image",
                    detail: "Generated \(runResult.generatedImages.count) image\(runResult.generatedImages.count == 1 ? "" : "s")"
                )
            )
        }

        var updatedSession = request.session
        if let threadID = runResult.threadID, !request.prefersWorkspaceImageOutput {
            updatedSession.defaultRuntimeID = effectiveRuntimeProfile.id
            updatedSession.setRuntimeSessionID(threadID, for: effectiveRuntimeProfile.id)
        }
        updatedSession.updatedAt = Date()

        let message = ChatMessage(
            id: UUID().uuidString.lowercased(),
            sessionID: request.session.id,
            role: .codex,
            content: Self.messageContent(
                lastMessage: runResult.lastMessage,
                stdout: runResult.stdout,
                generatedImages: runResult.generatedImages
            ),
            createdAt: Date()
        )

        return AgentChatTurnResult(
            updatedSession: updatedSession,
            message: message,
            stdout: runResult.stdout,
            lastMessage: runResult.lastMessage,
            generatedImages: runResult.generatedImages,
            tokenUsage: runResult.tokenUsage
        )
    }

    func runDiscoverEnrichment(_ request: AgentDiscoverEnrichmentRequest) async throws -> AgentDiscoverEnrichmentResult {
        try FileManager.default.createDirectory(at: request.workspaceURL, withIntermediateDirectories: true)
        let runResult: AgentRunResult
        if request.runtimeProfile.backend == .codex {
            let executable = try CodexRuntimeAdapter.findExecutable()
            let command = CodexRuntimeAdapter(executablePath: executable).startCommand(
                prompt: request.prompt,
                workspacePath: request.workspaceURL.path,
                outputLastMessagePath: request.outputURL.path,
                modelOverride: request.modelOverride,
                reasoningEffort: request.reasoningEffort
            )
            let stdout = try await runPlainCommand(
                command,
                eventLogURL: request.eventLogURL,
                runHandle: request.runHandle,
                runtimeName: request.runtimeProfile.displayName
            ) { _ in }
            runResult = AgentRunResult(
                stdout: stdout,
                lastMessage: try String(contentsOf: request.outputURL, encoding: .utf8),
                threadID: CodexCLI.parseThreadID(from: stdout),
                generatedImages: [],
                tokenUsage: CodexCLI.aggregateTokenUsage(from: stdout)
            )
        } else if request.runtimeProfile.backend == .kimiCLI {
            let command = try kimiStructuredCommand(
                prompt: request.prompt,
                session: PaperSession(
                    id: "discover-\(request.arxivID)",
                    title: "Discover Processing",
                    paperIDs: [],
                    codexSessionID: nil,
                    defaultRuntimeID: request.runtimeProfile.id,
                    workspacePath: request.workspaceURL.path,
                    createdAt: Date(),
                    updatedAt: Date()
                ),
                runtimeProfile: request.runtimeProfile,
                modelOverride: request.modelOverride
            )
            let run = try await runKimiStreamCommand(
                command,
                eventLogURL: request.eventLogURL,
                runHandle: request.runHandle
            ) { _ in }
            runResult = run
        } else {
            let command = try nonCodexCommand(
                prompt: request.prompt,
                session: PaperSession(
                    id: "discover-\(request.arxivID)",
                    title: "Discover Processing",
                    paperIDs: [],
                    codexSessionID: nil,
                    defaultRuntimeID: request.runtimeProfile.id,
                    workspacePath: request.workspaceURL.path,
                    createdAt: Date(),
                    updatedAt: Date()
                ),
                runtimeProfile: request.runtimeProfile,
                modelOverride: request.modelOverride,
                providerOverride: request.providerOverride,
                existingSessionID: nil
            )
            let stdout = try await runPlainCommand(
                command,
                eventLogURL: request.eventLogURL,
                runHandle: request.runHandle,
                runtimeName: request.runtimeProfile.displayName
            ) { _ in }
            runResult = AgentRunResult(
                stdout: stdout,
                lastMessage: stdout,
                threadID: nil,
                generatedImages: [],
                tokenUsage: nil
            )
        }
        let parsed = try DiscoverEnrichmentParser.parse(
            runResult.lastMessage,
            arxivID: request.arxivID,
            modelIdentity: request.modelIdentity,
            generatedAt: Date()
        )
        return AgentDiscoverEnrichmentResult(enrichment: parsed, tokenUsage: runResult.tokenUsage)
    }

    private func runAgentTurn(
        prompt: String,
        session: PaperSession,
        runtimeProfile: AgentRuntimeProfile,
        modelOverride: String,
        providerOverride: String,
        reasoningEffort: CodexReasoningEffort,
        prefersWorkspaceImageOutput: Bool,
        mcpServers: [CodexMCPServerConfig],
        runHandle: AgentRunHandle,
        onEvent: @escaping @Sendable (AgentRunEvent) -> Void
    ) async throws -> AgentRunResult {
        if runtimeProfile.backend == .codex {
            return try await codexRuntime.runTurn(
                AgentRunRequest(
                    runtimeProfileID: runtimeProfile.id,
                    prompt: prompt,
                    workspacePath: session.workspacePath,
                    existingSessionID: session.runtimeSessionID(for: runtimeProfile.id),
                    modelOverride: modelOverride,
                    reasoningEffort: reasoningEffort,
                    prefersWorkspaceImageOutput: prefersWorkspaceImageOutput,
                    runModeDescription: codexRunModeDescription(
                        reasoningEffort: reasoningEffort,
                        modelOverride: modelOverride,
                        prefersWorkspaceImageOutput: prefersWorkspaceImageOutput
                    ),
                    mcpServers: mcpServers
                ),
                runHandle: runHandle,
                onEvent: onEvent
            )
        }

        if runtimeProfile.backend == .hermes {
            let command = try hermesStructuredCommand(
                prompt: prompt,
                session: session,
                runtimeProfile: runtimeProfile,
                modelOverride: modelOverride,
                providerOverride: providerOverride
            )
            let eventLogURL = URL(fileURLWithPath: session.workspacePath, isDirectory: true)
                .appendingPathComponent("turns", isDirectory: true)
                .appendingPathComponent("\(UUID().uuidString.lowercased())-\(runtimeProfile.id)-events.jsonl")
            return try await runHermesBridgeCommand(
                command,
                eventLogURL: eventLogURL,
                runHandle: runHandle,
                onEvent: onEvent
            )
        }

        if runtimeProfile.backend == .kimiCLI {
            let command = try kimiStructuredCommand(
                prompt: prompt,
                session: session,
                runtimeProfile: runtimeProfile,
                modelOverride: modelOverride
            )
            let eventLogURL = URL(fileURLWithPath: session.workspacePath, isDirectory: true)
                .appendingPathComponent("turns", isDirectory: true)
                .appendingPathComponent("\(UUID().uuidString.lowercased())-\(runtimeProfile.id)-events.jsonl")
            return try await runKimiStreamCommand(
                command,
                eventLogURL: eventLogURL,
                runHandle: runHandle,
                onEvent: onEvent
            )
        }

        let command = try nonCodexCommand(
            prompt: prompt,
            session: session,
            runtimeProfile: runtimeProfile,
            modelOverride: modelOverride,
            providerOverride: providerOverride,
            existingSessionID: session.runtimeSessionID(for: runtimeProfile.id)
        )
        let eventLogURL = URL(fileURLWithPath: session.workspacePath, isDirectory: true)
            .appendingPathComponent("turns", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString.lowercased())-\(runtimeProfile.id).log")
        let stdout = try await runPlainCommand(
            command,
            eventLogURL: eventLogURL,
            runHandle: runHandle,
            runtimeName: runtimeProfile.displayName,
            onEvent: onEvent
        )
        return AgentRunResult(
            stdout: stdout,
            lastMessage: stdout,
            threadID: nil,
            generatedImages: [],
            tokenUsage: nil
        )
    }

    private func hermesStructuredCommand(
        prompt: String,
        session: PaperSession,
        runtimeProfile: AgentRuntimeProfile,
        modelOverride: String,
        providerOverride: String
    ) throws -> AgentRuntimeCommand {
        let workspaceURL = URL(fileURLWithPath: session.workspacePath, isDirectory: true)
        let modelID = modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerID = providerOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let executable = try HermesRuntimeAdapter.findExecutable()
        return try HermesRuntimeAdapter(executablePath: executable).structuredNonInteractiveCommand(
            prompt: prompt,
            workspacePath: session.workspacePath,
            provider: providerID.isEmpty ? nil : providerID,
            model: modelID.isEmpty ? runtimeProfile.defaultModelID : modelID,
            skillsPath: workspaceURL.appendingPathComponent("skills/papercodex-agent-workspace", isDirectory: true).path
        )
    }

    private func kimiStructuredCommand(
        prompt: String,
        session: PaperSession,
        runtimeProfile: AgentRuntimeProfile,
        modelOverride: String
    ) throws -> AgentRuntimeCommand {
        let workspaceURL = URL(fileURLWithPath: session.workspacePath, isDirectory: true)
        let modelID = modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let executable = try KimiRuntimeAdapter.findExecutable()
        return KimiRuntimeAdapter(executablePath: executable).nonInteractiveCommand(
            prompt: prompt,
            workspacePath: session.workspacePath,
            sessionID: session.runtimeSessionID(for: runtimeProfile.id),
            modelID: modelID.isEmpty ? runtimeProfile.defaultModelID : modelID,
            skillsPath: workspaceURL.appendingPathComponent("skills/papercodex-agent-workspace", isDirectory: true).path
        )
    }

    private func nonCodexCommand(
        prompt: String,
        session: PaperSession,
        runtimeProfile: AgentRuntimeProfile,
        modelOverride: String,
        providerOverride: String,
        existingSessionID: String?
    ) throws -> AgentRuntimeCommand {
        let workspaceURL = URL(fileURLWithPath: session.workspacePath, isDirectory: true)
        let mcpConfigPath = workspaceURL.appendingPathComponent("mcp.json").path
        let agentInstructionsPath = workspaceURL.appendingPathComponent("agent_instructions.md").path
        let modelID = modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerID = providerOverride.trimmingCharacters(in: .whitespacesAndNewlines)

        switch runtimeProfile.backend {
        case .codex:
            let executable = try CodexRuntimeAdapter.findExecutable()
            return CodexRuntimeAdapter(executablePath: executable).startCommand(
                prompt: prompt,
                workspacePath: session.workspacePath,
                outputLastMessagePath: nil,
                modelOverride: modelID,
                reasoningEffort: .default
            )
        case .claudeCode:
            let executable = try ClaudeCodeRuntimeAdapter.findExecutable()
            return ClaudeCodeRuntimeAdapter(executablePath: executable).nonInteractiveCommand(
                prompt: prompt,
                workspacePath: session.workspacePath,
                systemPrompt: "Use the Episteme citation contract and workspace files.",
                mcpConfigPath: FileManager.default.fileExists(atPath: mcpConfigPath) ? mcpConfigPath : nil
            )
        case .hermes:
            let executable = try HermesRuntimeAdapter.findExecutable()
            return HermesRuntimeAdapter(executablePath: executable).nonInteractiveCommand(
                prompt: prompt,
                workspacePath: session.workspacePath,
                provider: providerID.isEmpty ? nil : providerID,
                model: modelID.isEmpty ? runtimeProfile.defaultModelID : modelID,
                skillsPath: workspaceURL.appendingPathComponent("skills/papercodex-agent-workspace", isDirectory: true).path
            )
        case .kimiCLI:
            let executable = try KimiRuntimeAdapter.findExecutable()
            return KimiRuntimeAdapter(executablePath: executable).nonInteractiveCommand(
                prompt: prompt,
                workspacePath: session.workspacePath,
                sessionID: existingSessionID,
                modelID: modelID.isEmpty ? runtimeProfile.defaultModelID : modelID,
                skillsPath: workspaceURL.appendingPathComponent("skills/papercodex-agent-workspace", isDirectory: true).path
            )
        case .openClawKimi:
            let executable = try OpenClawRuntimeAdapter.findExecutable()
            return OpenClawRuntimeAdapter(executablePath: executable).nonInteractiveCommand(
                prompt: prompt,
                workspacePath: session.workspacePath,
                sessionID: existingSessionID ?? session.id,
                modelID: modelID.isEmpty ? runtimeProfile.defaultModelID : modelID
            )
        case .pi:
            let executable = try PiRuntimeAdapter.findExecutable()
            return PiRuntimeAdapter(executablePath: executable).nonInteractiveCommand(
                prompt: prompt,
                workspacePath: session.workspacePath,
                systemPrompt: "Use Episteme citations.",
                agentInstructionsPath: FileManager.default.fileExists(atPath: agentInstructionsPath) ? agentInstructionsPath : nil
            )
        }
    }

    private func runHermesBridgeCommand(
        _ command: AgentRuntimeCommand,
        eventLogURL: URL,
        runHandle: AgentRunHandle,
        onEvent: @escaping @Sendable (AgentRunEvent) -> Void
    ) async throws -> AgentRunResult {
        let buffer = HermesBridgeRunBuffer()
        let stdout = try await Task.detached(priority: .userInitiated) {
            try self.commandRuntime.runStreaming(
                command: command,
                eventLogURL: eventLogURL,
                runHandle: runHandle,
                onStdoutData: { buffer.appendStdout($0) },
                onStderrData: { buffer.appendStderr($0) },
                finish: { buffer.finish() },
                onEvent: onEvent
            )
        }.value
        return AgentRunResult(
            stdout: stdout,
            lastMessage: buffer.finalAnswer ?? "",
            threadID: buffer.sessionID,
            generatedImages: [],
            tokenUsage: nil
        )
    }

    private func runKimiStreamCommand(
        _ command: AgentRuntimeCommand,
        eventLogURL: URL,
        runHandle: AgentRunHandle,
        onEvent: @escaping @Sendable (AgentRunEvent) -> Void
    ) async throws -> AgentRunResult {
        let buffer = KimiStreamRunBuffer()
        let stdout = try await Task.detached(priority: .userInitiated) {
            try self.commandRuntime.runStreaming(
                command: command,
                eventLogURL: eventLogURL,
                runHandle: runHandle,
                onStdoutData: { buffer.appendStdout($0) },
                onStderrData: { buffer.appendStderr($0) },
                finish: { buffer.finish() },
                onEvent: onEvent
            )
        }.value
        return AgentRunResult(
            stdout: stdout,
            lastMessage: buffer.finalAnswer ?? "",
            threadID: buffer.sessionID,
            generatedImages: [],
            tokenUsage: nil
        )
    }

    private func runPlainCommand(
        _ command: AgentRuntimeCommand,
        eventLogURL: URL,
        runHandle: AgentRunHandle,
        runtimeName: String,
        onEvent: @escaping @Sendable (AgentRunEvent) -> Void
    ) async throws -> String {
        let buffer = AgentPlainRunBuffer(runtimeName: runtimeName)
        return try await Task.detached(priority: .userInitiated) {
            try self.commandRuntime.runStreaming(
                command: command,
                eventLogURL: eventLogURL,
                runHandle: runHandle,
                onStdoutData: { buffer.appendStdout($0) },
                onStderrData: { buffer.appendStderr($0) },
                finish: { buffer.finish() },
                onEvent: onEvent
            )
        }.value
    }

    private static func messageContent(lastMessage: String, stdout: String, generatedImages: [URL]) -> String {
        let imageMarkdown = GeneratedImageCollector.markdown(for: generatedImages)
        let trimmedLastMessage = lastMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedLastMessage.isEmpty {
            return imageMarkdown.isEmpty ? stdout : imageMarkdown
        }
        guard !imageMarkdown.isEmpty else {
            return lastMessage
        }
        let missingImageMarkdown = imageMarkdown
            .components(separatedBy: "\n\n")
            .filter { !lastMessage.contains($0) }
            .joined(separator: "\n\n")
        guard !missingImageMarkdown.isEmpty else {
            return lastMessage
        }
        return "\(lastMessage)\n\n\(missingImageMarkdown)"
    }

    private func codexRunModeDescription(
        reasoningEffort: CodexReasoningEffort,
        modelOverride: String,
        prefersWorkspaceImageOutput: Bool
    ) -> String {
        var parts: [String] = []
        if prefersWorkspaceImageOutput {
            parts.append("Image generation enabled")
        }
        let trimmedModel = modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty {
            parts.append("Model \(trimmedModel)")
        }
        parts.append(reasoningEffort == .default ? "default thinking" : "\(reasoningEffort.displayName) thinking")
        return parts.joined(separator: " · ")
    }
}

private final class HermesBridgeRunBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    private var stdoutRemainder = ""
    private var stderrRemainder = ""
    private var parsedFinalAnswer: String?
    private var parsedSessionID: String?

    var finalAnswer: String? {
        lock.lock()
        defer { lock.unlock() }
        return parsedFinalAnswer
    }

    var sessionID: String? {
        lock.lock()
        defer { lock.unlock() }
        return parsedSessionID
    }

    func appendStdout(_ data: Data) -> [AgentRunEvent] {
        guard !data.isEmpty else {
            return []
        }
        let text = String(decoding: data, as: UTF8.self)
        let lines: [String]
        lock.lock()
        stdoutData.append(data)
        stdoutRemainder += text
        lines = Self.consumeLines(from: &stdoutRemainder)
        lock.unlock()
        return lines.compactMap(parseLine)
    }

    func appendStderr(_ data: Data) -> [AgentRunEvent] {
        guard !data.isEmpty else {
            return []
        }
        let text = String(decoding: data, as: UTF8.self)
        let lines: [String]
        lock.lock()
        stderrData.append(data)
        stderrRemainder += text
        lines = Self.consumeLines(from: &stderrRemainder)
        lock.unlock()
        return lines
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { CodexRunEvent(kind: .terminal, title: "Hermes log", detail: $0) }
    }

    func finish() -> (stdout: String, stderr: String, events: [AgentRunEvent]) {
        let stdoutRemainderSnapshot: String
        let stderrRemainderSnapshot: String
        let stdout: String
        let stderr: String
        lock.lock()
        stdoutRemainderSnapshot = stdoutRemainder
        stderrRemainderSnapshot = stderrRemainder
        stdout = String(decoding: stdoutData, as: UTF8.self)
        stderr = String(decoding: stderrData, as: UTF8.self)
        lock.unlock()

        var events: [AgentRunEvent] = []
        if !stdoutRemainderSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let event = parseLine(stdoutRemainderSnapshot) {
            events.append(event)
        }
        let trimmedStderrRemainder = stderrRemainderSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStderrRemainder.isEmpty {
            events.append(CodexRunEvent(kind: .terminal, title: "Hermes log", detail: trimmedStderrRemainder))
        }
        return (stdout, stderr, events)
    }

    private func parseLine(_ line: String) -> AgentRunEvent? {
        guard let parsed = try? HermesBridgeEventParser.parseResultLine(line) else {
            return CodexRunEvent(kind: .raw, title: "Hermes", detail: line)
        }
        lock.lock()
        if let finalAnswer = parsed.finalAnswer {
            parsedFinalAnswer = finalAnswer
        }
        if let sessionID = parsed.sessionID {
            parsedSessionID = sessionID
        }
        lock.unlock()
        return parsed.event
    }

    private static func consumeLines(from buffer: inout String) -> [String] {
        var lines: [String] = []
        while let newline = buffer.firstIndex(where: { $0.isNewline }) {
            lines.append(String(buffer[..<newline]))
            buffer.removeSubrange(...newline)
        }
        return lines
    }
}

private final class KimiStreamRunBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    private var stdoutRemainder = ""
    private var stderrRemainder = ""
    private var parsedFinalAnswer: String?
    private var parsedSessionID: String?

    var finalAnswer: String? {
        lock.lock()
        defer { lock.unlock() }
        return parsedFinalAnswer
    }

    var sessionID: String? {
        lock.lock()
        defer { lock.unlock() }
        return parsedSessionID
    }

    func appendStdout(_ data: Data) -> [AgentRunEvent] {
        guard !data.isEmpty else {
            return []
        }
        let text = String(decoding: data, as: UTF8.self)
        let lines: [String]
        lock.lock()
        stdoutData.append(data)
        stdoutRemainder += text
        lines = Self.consumeLines(from: &stdoutRemainder)
        lock.unlock()
        return lines.compactMap(parseLine)
    }

    func appendStderr(_ data: Data) -> [AgentRunEvent] {
        guard !data.isEmpty else {
            return []
        }
        let text = String(decoding: data, as: UTF8.self)
        let lines: [String]
        lock.lock()
        stderrData.append(data)
        stderrRemainder += text
        lines = Self.consumeLines(from: &stderrRemainder)
        lock.unlock()
        return lines
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { CodexRunEvent(kind: .terminal, title: "Kimi CLI log", detail: $0) }
    }

    func finish() -> (stdout: String, stderr: String, events: [AgentRunEvent]) {
        let stdoutRemainderSnapshot: String
        let stderrRemainderSnapshot: String
        let stdout: String
        let stderr: String
        lock.lock()
        stdoutRemainderSnapshot = stdoutRemainder
        stderrRemainderSnapshot = stderrRemainder
        stdout = String(decoding: stdoutData, as: UTF8.self)
        stderr = String(decoding: stderrData, as: UTF8.self)
        lock.unlock()

        var events: [AgentRunEvent] = []
        if !stdoutRemainderSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let event = parseLine(stdoutRemainderSnapshot) {
            events.append(event)
        }
        let trimmedStderrRemainder = stderrRemainderSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStderrRemainder.isEmpty {
            events.append(CodexRunEvent(kind: .terminal, title: "Kimi CLI log", detail: trimmedStderrRemainder))
        }
        return (stdout, stderr, events)
    }

    private func parseLine(_ line: String) -> AgentRunEvent? {
        guard let parsed = try? KimiStreamEventParser.parseResultLine(line) else {
            return CodexRunEvent(kind: .raw, title: "Kimi CLI", detail: line)
        }
        lock.lock()
        if let finalAnswer = parsed.finalAnswer {
            parsedFinalAnswer = finalAnswer
        }
        if let sessionID = parsed.sessionID {
            parsedSessionID = sessionID
        }
        lock.unlock()
        return parsed.event
    }

    private static func consumeLines(from buffer: inout String) -> [String] {
        var lines: [String] = []
        while let newline = buffer.firstIndex(where: { $0.isNewline }) {
            lines.append(String(buffer[..<newline]))
            buffer.removeSubrange(...newline)
        }
        return lines
    }
}

private final class AgentPlainRunBuffer: @unchecked Sendable {
    private let runtimeName: String
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    private var stdoutRemainder = ""
    private var stderrRemainder = ""

    init(runtimeName: String) {
        self.runtimeName = runtimeName
    }

    func appendStdout(_ data: Data) -> [AgentRunEvent] {
        guard !data.isEmpty else {
            return []
        }
        let text = String(decoding: data, as: UTF8.self)
        let lines: [String]
        lock.lock()
        stdoutData.append(data)
        stdoutRemainder += text
        lines = Self.consumeLines(from: &stdoutRemainder)
        lock.unlock()
        return lines
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { CodexRunEvent(kind: .terminal, title: runtimeName, detail: $0) }
    }

    func appendStderr(_ data: Data) -> [AgentRunEvent] {
        guard !data.isEmpty else {
            return []
        }
        let text = String(decoding: data, as: UTF8.self)
        let lines: [String]
        lock.lock()
        stderrData.append(data)
        stderrRemainder += text
        lines = Self.consumeLines(from: &stderrRemainder)
        lock.unlock()
        return lines
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { CodexRunEvent(kind: .terminal, title: "\(runtimeName) log", detail: $0) }
    }

    func finish() -> (stdout: String, stderr: String, events: [AgentRunEvent]) {
        let stdoutRemainderSnapshot: String
        let stderrRemainderSnapshot: String
        let stdout: String
        let stderr: String
        lock.lock()
        stdoutRemainderSnapshot = stdoutRemainder
        stderrRemainderSnapshot = stderrRemainder
        stdout = String(decoding: stdoutData, as: UTF8.self)
        stderr = String(decoding: stderrData, as: UTF8.self)
        lock.unlock()

        var events: [AgentRunEvent] = []
        let trimmedStdoutRemainder = stdoutRemainderSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStdoutRemainder.isEmpty {
            events.append(CodexRunEvent(kind: .terminal, title: runtimeName, detail: trimmedStdoutRemainder))
        }
        let trimmedStderrRemainder = stderrRemainderSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStderrRemainder.isEmpty {
            events.append(CodexRunEvent(kind: .terminal, title: "\(runtimeName) log", detail: trimmedStderrRemainder))
        }
        return (stdout, stderr, events)
    }

    private static func consumeLines(from buffer: inout String) -> [String] {
        var lines: [String] = []
        while let newline = buffer.firstIndex(where: { $0.isNewline }) {
            lines.append(String(buffer[..<newline]))
            buffer.removeSubrange(...newline)
        }
        return lines
    }
}
