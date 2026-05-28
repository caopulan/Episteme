import Foundation

public enum HermesRuntimeAdapterError: Error, CustomStringConvertible, Equatable {
    case unsupportedExecutable(String)

    public var description: String {
        switch self {
        case let .unsupportedExecutable(path):
            "Hermes executable is not a Python entrypoint that Paper Codex can bridge: \(path)"
        }
    }
}

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
            "--quiet",
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

    public func structuredNonInteractiveCommand(
        prompt: String,
        workspacePath: String,
        provider: String?,
        model: String?,
        skillsPath: String?
    ) throws -> AgentRuntimeCommand {
        let runtime = try Self.bridgeRuntime(for: executablePath)
        var arguments = [
            "-u",
            "-c",
            Self.bridgeScript,
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
            executablePath: runtime.pythonPath,
            arguments: arguments,
            currentDirectoryPath: workspacePath,
            environmentOverrides: [
                "PAPER_CODEX_HERMES_ROOT": runtime.installRootPath
            ]
        )
    }

    public func terminalCommand(
        workspacePath: String,
        provider: String?,
        model: String?,
        skillsPath: String?
    ) -> AgentRuntimeCommand {
        var arguments = [
            "chat",
            "--tui"
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
            currentDirectoryPath: workspacePath,
            launchMode: .pty
        )
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func bridgeRuntime(for executablePath: String) throws -> (pythonPath: String, installRootPath: String) {
        let executableURL = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath()
        let executableText = try String(contentsOf: executableURL, encoding: .utf8)
        guard let firstLine = executableText.split(separator: "\n", maxSplits: 1).first,
              firstLine.hasPrefix("#!") else {
            throw HermesRuntimeAdapterError.unsupportedExecutable(executablePath)
        }
        let shebang = firstLine.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
        let pythonPath = shebang.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        guard !pythonPath.isEmpty else {
            throw HermesRuntimeAdapterError.unsupportedExecutable(executablePath)
        }
        let pythonURL = URL(fileURLWithPath: pythonPath).standardizedFileURL
        let installRootURL = pythonURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return (pythonURL.path, installRootURL.path)
    }

    private static let bridgeScript = #"""
import argparse
import contextlib
import json
import os
import sys

event_out = sys.stdout

def emit(payload):
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), file=event_out, flush=True)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--query", required=True)
    parser.add_argument("--provider")
    parser.add_argument("--model")
    parser.add_argument("--skills")
    parser.add_argument("--source", default="papercodex")
    args = parser.parse_args()

    hermes_root = os.environ["PAPER_CODEX_HERMES_ROOT"]
    if hermes_root not in sys.path:
        sys.path.insert(0, hermes_root)
    os.environ["HERMES_SESSION_SOURCE"] = args.source

    with contextlib.redirect_stdout(sys.stderr):
        from hermes_cli.tools_config import _get_platform_tools
        from cli import (
            CLI_CONFIG,
            HermesCLI,
            _parse_skills_argument,
            build_preloaded_skills_prompt,
        )

        toolsets = sorted(_get_platform_tools(CLI_CONFIG, "cli"))
        cli = HermesCLI(
            model=args.model,
            toolsets=toolsets,
            provider=args.provider,
            compact=True,
        )
        cli.tool_progress_mode = "off"
        cli.streaming_enabled = False

        if args.skills:
            parsed_skills = _parse_skills_argument(args.skills)
            skills_prompt, loaded_skills, missing_skills = build_preloaded_skills_prompt(
                parsed_skills,
                task_id=cli.session_id,
            )
            if missing_skills:
                raise ValueError("Unknown Hermes skill(s): " + ", ".join(missing_skills))
            if skills_prompt:
                cli.system_prompt = "\n\n".join(
                    part for part in (cli.system_prompt, skills_prompt) if part
                ).strip()
                cli.preloaded_skills = loaded_skills

        if not cli._ensure_runtime_credentials():
            raise RuntimeError("Hermes credentials are not available")

        turn_route = cli._resolve_turn_agent_config(args.query)
        if not cli._init_agent(
            model_override=turn_route["model"],
            runtime_override=turn_route["runtime"],
            request_overrides=turn_route.get("request_overrides"),
        ):
            raise RuntimeError("Hermes agent initialization failed")

        def tool_progress(event_type, function_name=None, preview=None, function_args=None, **kwargs):
            if not function_name or function_name.startswith("_"):
                return
            if event_type == "tool.started":
                emit({
                    "type": "tool",
                    "state": "started",
                    "name": function_name,
                    "detail": preview or function_name,
                })
            elif event_type == "tool.completed":
                emit({
                    "type": "tool",
                    "state": "completed",
                    "name": function_name,
                    "duration": kwargs.get("duration", 0.0),
                    "is_error": bool(kwargs.get("is_error", False)),
                })

        def status(kind, message):
            if message:
                emit({"type": "status", "title": "Hermes", "detail": str(message)})

        cli.agent.quiet_mode = True
        cli.agent.suppress_status_output = True
        cli.agent.tool_progress_callback = tool_progress
        cli.agent.tool_start_callback = None
        cli.agent.tool_complete_callback = None
        cli.agent.tool_gen_callback = None
        cli.agent.stream_delta_callback = None
        cli.agent.status_callback = status
        cli.agent._print_fn = lambda message: print(message, file=sys.stderr, flush=True)

        result = cli.agent.run_conversation(
            user_message=args.query,
            conversation_history=cli.conversation_history,
        )

    response = result.get("final_response", "") if isinstance(result, dict) else str(result)
    emit({"type": "answer", "text": response})
    session_id = getattr(cli.agent, "session_id", None) or cli.session_id
    emit({"type": "session", "session_id": session_id})
    return 1 if isinstance(result, dict) and result.get("failed") else 0

if __name__ == "__main__":
    raise SystemExit(main())
"""#
}
