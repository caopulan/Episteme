# Agent Runtime Decoupling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor Paper Codex so the app owns paper management, visualization, session workspaces, MCP, and agent-facing skills, while the right-side research assistant can run multiple local agent backends instead of being hard-bound to Codex.

**Architecture:** Treat Paper Codex as two cooperating local systems. The app data plane is SwiftUI + SQLite + PDFKit + `PaperCodexMCPService`; humans operate it through the UI and agents operate it through MCP/skills. The AI execution plane is a generic local agent runtime that receives a session workspace, prompt contract, MCP connection, and runtime profile, then launches Codex, Claude Code, Hermes, OpenClaw, pi, or another TUI-capable command through a common adapter interface.

**Tech Stack:** Swift 6.2, SwiftUI, PDFKit, SQLite3, Foundation/Darwin process and PTY APIs, local HTTP MCP, existing `PaperCodexCoreChecks`, built app bundle at `/Users/chunqiu/Applications/PaperCodex.app`, local CLIs (`codex`, `claude`, `hermes`, `openclaw`, `pi`).

---

## Current Evidence

- `PaperCodexMCPService` and `PaperCodexMCPServer` already start with the app and expose library, note, prompt-template, and active-context resources/tools.
- `SessionWorkspaceManager` already writes per-session `papers/{paper_id}/original.pdf`, `full_text.txt`, `pages.jsonl`, `spans.jsonl`, `anchors.jsonl`, `metadata.json`, and `prompt_contract.md`.
- `PromptBuilder` currently builds a Codex-shaped prompt and uses `{{workspace_path}}`.
- `AgentRuntime` exists, but its protocol method is still `runCodexTurn`, its event/result types are Codex-named, and `CodexAgentRuntime` is the only backend.
- `AppModel` still stores `PaperSession.codexSessionID`, runs Discover enrichment directly through `CodexCLI`, and exposes Codex-specific settings in `SettingsView`/`ChatView`.
- Local CLI/auth inspection on 2026-05-27:
  - `codex` is available at `/Users/chunqiu/.local/bin/codex`, version `codex-cli 0.133.0-alpha.1`.
  - `claude` is available at `/Users/chunqiu/.local/bin/claude`, version `2.1.150 (Claude Code)`, and `claude auth status` reports logged in through `claude.ai`.
  - `hermes` is available at `/Users/chunqiu/.local/bin/hermes`; status shows Kimi configured and Hermes Gateway running.
  - `openclaw` is available at `/opt/homebrew/bin/openclaw`; `openclaw models status --json` resolves default `kimi-coding/k2p5` to `kimi/k2p5`, has Kimi API-key auth, and has OpenAI Codex OAuth.
  - `pi` is available at `/Users/chunqiu/.local/bin/pi`; it supports `--system-prompt`, `--append-system-prompt`, `--skill`, `--session-dir`, `--mode`, `--provider`, `--model`, and provider API-key env vars. `pi --list-models kimi` currently returns no direct Kimi model, so Kimi validation should go through OpenClaw or Hermes unless pi model config is updated.

## Requirement Map

- App/MCP split:
  - Paper Codex remains the local paper manager and visual UI.
  - Agents mutate/read app state only through MCP or session workspace files.
  - Skill docs explain how non-app agents should use the MCP and workspace contract.
- Session workspace:
  - Every reading session has a durable workspace with paper files or symlinks, metadata, extracted source text, prompt contracts, MCP connection files, and runtime logs.
  - Workspace content is runtime-neutral and can be consumed by Codex, Claude Code, Hermes, OpenClaw, Kimi, or pi.
- Runtime decoupling:
  - Replace Codex-only naming and assumptions with generic agent runtime profiles.
  - Support non-interactive command adapters first for deterministic tests.
  - Support TUI-capable agents through a PTY-backed runtime surface in the right panel.
- Prompt injection:
  - Store reusable prompt templates by purpose, not by runtime.
  - Render runtime-specific launch instructions while preserving a common citation/output contract.
- Auth/provider compatibility:
  - Do not build a new secret vault in Paper Codex.
  - Reuse each CLI/gateway's own auth when possible.
  - Use OpenClaw or pi as optional provider/auth routers where they are stronger than direct CLI auth.
- Verification:
  - Final acceptance requires real local smoke tests with Codex, Claude Code, and Kimi.
  - Kimi should be verified through the strongest available local route; current evidence points to OpenClaw `kimi-coding/k2p5` or Hermes Kimi.

---

## File Structure

### Core runtime model

- Create: `Sources/PaperCodexCore/AgentRuntimeProfile.swift`
  - Runtime profile definitions, backend kind, launch mode, prompt injection mode, MCP support mode, resume support, output parser choice, and capability flags.
- Create: `Sources/PaperCodexCore/AgentRuntimeCommand.swift`
  - Command builder result: executable path, args, environment overrides, current directory, output files, PTY/non-PTY mode.
- Create: `Sources/PaperCodexCore/AgentRuntimeAdapter.swift`
  - Generic adapter protocol replacing `runCodexTurn` with `runTurn`.
- Create: `Sources/PaperCodexCore/CommandAgentRuntime.swift`
  - Non-interactive process runner shared by Codex/Claude/Hermes/OpenClaw/pi adapters.
- Modify: `Sources/PaperCodexCore/AgentRuntime.swift`
  - Rename Codex-specific request/result/event-facing concepts or provide backward-compatible typealiases during migration.
- Modify: `Sources/PaperCodexCore/CodexAgentRuntime.swift`
  - Convert to one adapter under the generic runtime interface.
- Modify: `Sources/PaperCodexCore/CodexCLI.swift`
  - Keep Codex-specific argument parsing here, but remove generic process-running responsibilities after `CommandAgentRuntime` lands.

### Workspace and prompt contract

- Create: `Sources/PaperCodexCore/AgentWorkspaceManifest.swift`
  - Typed manifest for workspace files, paper paths, MCP endpoint metadata, prompt contract paths, runtime logs, and copy/symlink mode.
- Create: `Sources/PaperCodexCore/AgentPromptTemplate.swift`
  - Runtime-neutral template model and renderer for citation/output contracts.
- Modify: `Sources/PaperCodexCore/SessionWorkspaceManager.swift`
  - Write `workspace_manifest.json`, `agent_instructions.md`, `mcp.json`, `AGENTS.md`, `CLAUDE.md`, and runtime-specific prompt snippets.
  - Add a file-materialization mode: `.copyPDF` and `.symlinkPDF`, defaulting to copy for current behavior.
- Modify: `Sources/PaperCodexCore/PromptBuilder.swift`
  - Split source-grounding contract rendering from Codex launch prompt rendering.

### Concrete adapters

- Create: `Sources/PaperCodexCore/CodexRuntimeAdapter.swift`
  - Builds current `codex exec` and `codex exec resume` commands with app-local MCP injection.
- Create: `Sources/PaperCodexCore/ClaudeCodeRuntimeAdapter.swift`
  - Builds `claude --print` / `claude --output-format stream-json` and `claude` PTY commands.
  - Uses `--system-prompt`, `--append-system-prompt`, `--add-dir`, `--mcp-config`, and `--session-id` when available.
- Create: `Sources/PaperCodexCore/HermesRuntimeAdapter.swift`
  - Builds `hermes chat --query` for non-interactive runs and `hermes --tui` / `hermes chat --tui` for PTY runs.
  - Uses `--provider`, `--model`, `--skills`, and session resume flags.
- Create: `Sources/PaperCodexCore/OpenClawRuntimeAdapter.swift`
  - Builds `openclaw agent --local --json --session-id --message` for deterministic runs.
  - Uses `openclaw tui` as the PTY target when the UI launches an interactive agent.
  - Treats Kimi verification as `openclaw agent --local --json --message ...` with default model `kimi-coding/k2p5` unless settings select another Kimi route.
- Create: `Sources/PaperCodexCore/PiRuntimeAdapter.swift`
  - Builds `pi -p --mode json --session-dir ... --system-prompt ...` and interactive `pi` PTY runs.
  - Allows `--provider`, `--model`, `--skill`, `--prompt-template`, and `--append-system-prompt`.

### App integration

- Create: `Sources/PaperCodexApp/AgentRuntimeStore.swift`
  - Published runtime profiles, selected chat runtime, selected enrichment runtime, profile diagnostics, and UI draft state.
- Create: `Sources/PaperCodexApp/AgentTerminalView.swift`
  - PTY-backed terminal panel for TUI runtimes.
- Create: `Sources/PaperCodexApp/AgentRunCoordinator.swift`
  - App-level orchestration for starting, resuming, stopping, and logging agent runs.
- Modify: `Sources/PaperCodexApp/AppModel.swift`
  - Delegate agent selection, run lifecycle, and diagnostics to `AgentRuntimeStore`/`AgentRunCoordinator`.
  - Replace direct Discover `CodexCLI` calls with a selected enrichment runtime.
  - Preserve current Codex behavior as the default profile until other profiles are validated.
- Modify: `Sources/PaperCodexApp/ChatView.swift`
  - Replace Codex-only controls with runtime profile selector, run mode selector (`Chat` / `Terminal`), status, and stop controls.
- Modify: `Sources/PaperCodexApp/SettingsView.swift`
  - Add an “Agent Runtimes” section with per-runtime enablement, executable path/status, auth status summary, model/provider settings, and MCP injection mode.

### Data model and migration

- Modify: `Sources/PaperCodexCore/Models.swift`
  - Add generic session runtime fields while keeping `codexSessionID` readable for migration.
  - Proposed fields:
    - `defaultRuntimeID: String?`
    - `runtimeSessionLinksJSON: String?`
    - `workspaceMaterializationMode: String?`
- Modify: `Sources/PaperCodexCore/PaperRepository.swift`
  - Add migration for generic runtime session links.
  - Read old `codexSessionID` into a `codex` runtime link.
- Modify: `Sources/PaperCodexCore/PaperCodexMCPService.swift`
  - Expose runtime-neutral session resources: selected runtime, workspace manifest, session agent links, and prompt contracts.

### Skill and plugin docs

- Modify: `skills/papercodex-mcp/SKILL.md`
  - Teach agents to prefer MCP for app state, workspace files for source reading, and citation contract for answers.
- Create: `skills/papercodex-agent-workspace/SKILL.md`
  - Runtime-neutral instructions for Codex/Claude/Hermes/OpenClaw/pi when launched inside a Paper Codex session workspace.
- Modify: `.codex-plugin` or plugin generation docs if present
  - Include the new workspace skill and clarify update behavior.

### Checks and validation

- Modify: `Sources/PaperCodexCoreChecks/main.swift`
  - Add focused checks:
    - `agent-runtime-profiles`
    - `agent-command-builders`
    - `agent-workspace-manifest`
    - `agent-session-migration`
    - `agent-runtime-source`
- Add scripts if needed:
  - `scripts/agent-runtime-smoke.sh`
  - It should create or reuse a fixture session workspace and run Codex, Claude Code, and Kimi-route smoke prompts with no app DB mutation.

---

## Task 1: Lock The Runtime-Neutral Contract

**Files:**
- Create: `Sources/PaperCodexCore/AgentRuntimeProfile.swift`
- Create: `Sources/PaperCodexCore/AgentWorkspaceManifest.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] Write failing checks for default runtime profiles:
  - `codex` profile is enabled when `codex` is discoverable.
  - `claude-code` profile maps to `claude`.
  - `hermes` profile maps to `hermes`.
  - `openclaw-kimi` profile maps to `openclaw`.
  - `pi` profile maps to `pi`.
  - Each profile declares whether it supports non-interactive, PTY, MCP config injection, resume, and structured output.
- [ ] Write failing checks for `AgentWorkspaceManifest`:
  - manifest includes `session_id`, `workspace_path`, `mcp_config_path`, `prompt_contract_path`, `agent_instructions_path`, paper entries, and materialization mode.
  - manifest paper entries include `paper_id`, `original_pdf`, `full_text`, `pages_jsonl`, `spans_jsonl`, `anchors_jsonl`, `metadata_json`.
- [ ] Implement the model structs with explicit `Codable`, `Equatable`, and `Sendable` conformance.
- [ ] Run:

```bash
swift run PaperCodexCoreChecks agent-runtime-profiles
swift run PaperCodexCoreChecks agent-workspace-manifest
```

- [ ] Commit:

```bash
git add Sources/PaperCodexCore/AgentRuntimeProfile.swift Sources/PaperCodexCore/AgentWorkspaceManifest.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "feat: define generic agent runtime contracts"
```

## Task 2: Upgrade Session Workspaces Into Agent Workspaces

**Files:**
- Modify: `Sources/PaperCodexCore/SessionWorkspaceManager.swift`
- Modify: `Sources/PaperCodexCore/PromptBuilder.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] Write failing checks proving `writeWorkspace` writes:
  - `workspace_manifest.json`
  - `agent_instructions.md`
  - `mcp.json`
  - `AGENTS.md`
  - `CLAUDE.md`
  - existing `prompt_contract.md`
- [ ] Add `WorkspaceMaterializationMode` with `.copyPDF` and `.symlinkPDF`.
- [ ] Preserve default copy behavior so current reader/chat behavior does not change.
- [ ] Write `mcp.json` from the current app-local endpoint when one is passed to `writeWorkspace`; write a placeholder-free file only when endpoint metadata is available.
- [ ] Split `PromptBuilder` so `PromptBuilder.renderSourceGroundingContract(...)` can be reused by all runtimes.
- [ ] Run:

```bash
swift run PaperCodexCoreChecks workspace
swift run PaperCodexCoreChecks prompt
swift run PaperCodexCoreChecks agent-workspace-manifest
```

- [ ] Commit:

```bash
git add Sources/PaperCodexCore/SessionWorkspaceManager.swift Sources/PaperCodexCore/PromptBuilder.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "feat: write runtime-neutral agent workspaces"
```

## Task 3: Replace Codex-Only Runtime Protocols With Generic Agent Runtime

**Files:**
- Modify: `Sources/PaperCodexCore/AgentRuntime.swift`
- Create: `Sources/PaperCodexCore/AgentRuntimeCommand.swift`
- Create: `Sources/PaperCodexCore/CommandAgentRuntime.swift`
- Modify: `Sources/PaperCodexCore/CodexAgentRuntime.swift`
- Modify: `Sources/PaperCodexCore/CodexCLI.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] Write failing checks that `AgentRuntime` exposes `runTurn`, not only `runCodexTurn`.
- [ ] Add `AgentRunRequest`, `AgentRunResult`, `AgentRunEvent`, and compatibility typealiases for the current UI during migration.
- [ ] Move generic `Process` streaming, cancellation, event-log writing, and environment handling into `CommandAgentRuntime`.
- [ ] Keep Codex JSONL parsing in `CodexCLI` or `CodexRuntimeAdapter`; do not force other runtimes to emit Codex-shaped JSON.
- [ ] Run:

```bash
swift run PaperCodexCoreChecks codex
swift run PaperCodexCoreChecks agent-command-builders
swift build
```

- [ ] Commit:

```bash
git add Sources/PaperCodexCore/AgentRuntime.swift Sources/PaperCodexCore/AgentRuntimeCommand.swift Sources/PaperCodexCore/CommandAgentRuntime.swift Sources/PaperCodexCore/CodexAgentRuntime.swift Sources/PaperCodexCore/CodexCLI.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "refactor: generalize agent runtime execution"
```

## Task 4: Add Command Builders For Codex, Claude Code, Hermes, OpenClaw/Kimi, And Pi

**Files:**
- Create: `Sources/PaperCodexCore/CodexRuntimeAdapter.swift`
- Create: `Sources/PaperCodexCore/ClaudeCodeRuntimeAdapter.swift`
- Create: `Sources/PaperCodexCore/HermesRuntimeAdapter.swift`
- Create: `Sources/PaperCodexCore/OpenClawRuntimeAdapter.swift`
- Create: `Sources/PaperCodexCore/PiRuntimeAdapter.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] Write failing command-builder checks:
  - Codex start/resume keeps current `codex exec --json --enable image_generation -C <workspace>` behavior and app-local MCP `-c mcp_servers...`.
  - Claude Code non-interactive command uses `claude --print --output-format stream-json --system-prompt <contract> --add-dir <workspace> --mcp-config <workspace>/mcp.json`.
  - Hermes non-interactive command uses `hermes chat --query <prompt> --provider <provider> --model <model> --skills <skill-path> --source papercodex`.
  - OpenClaw/Kimi non-interactive command uses `openclaw agent --local --json --session-id <id> --message <prompt>`, with model selection coming from OpenClaw config or an explicit profile field.
  - pi non-interactive command uses `pi -p --mode json --session-dir <workspace>/agent-sessions/pi --system-prompt <contract> --append-system-prompt <workspace>/agent_instructions.md`.
- [ ] Implement adapters without running live model calls in unit checks.
- [ ] Add executable discovery helpers that read `$PATH` plus known app locations, following existing `CodexCLI.findCodexExecutable` style.
- [ ] Run:

```bash
swift run PaperCodexCoreChecks agent-command-builders
swift run PaperCodexCoreChecks codex
```

- [ ] Commit:

```bash
git add Sources/PaperCodexCore/CodexRuntimeAdapter.swift Sources/PaperCodexCore/ClaudeCodeRuntimeAdapter.swift Sources/PaperCodexCore/HermesRuntimeAdapter.swift Sources/PaperCodexCore/OpenClawRuntimeAdapter.swift Sources/PaperCodexCore/PiRuntimeAdapter.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "feat: add local agent runtime adapters"
```

## Task 5: Add Generic Runtime Settings And Diagnostics

**Files:**
- Create: `Sources/PaperCodexApp/AgentRuntimeStore.swift`
- Modify: `Sources/PaperCodexApp/AppModel.swift`
- Modify: `Sources/PaperCodexApp/SettingsView.swift`
- Modify: `Sources/PaperCodexApp/ChatView.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] Add `AgentRuntimeStore` with:
  - selected chat runtime ID
  - selected enrichment runtime ID
  - enabled runtime IDs
  - model/provider overrides per runtime
  - executable diagnostics per runtime
  - auth summary strings from safe local commands
- [ ] Keep Codex selected by default for existing users.
- [ ] Add Settings “Agent Runtimes” section:
  - profile list
  - enable switch
  - executable status
  - auth status
  - model/provider fields when applicable
  - MCP injection mode
- [ ] Replace ChatView Codex-only labels with runtime-neutral labels while preserving current layout density.
- [ ] Run:

```bash
swift run PaperCodexCoreChecks ui-layout-source
swift build
```

- [ ] Commit:

```bash
git add Sources/PaperCodexApp/AgentRuntimeStore.swift Sources/PaperCodexApp/AppModel.swift Sources/PaperCodexApp/SettingsView.swift Sources/PaperCodexApp/ChatView.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "feat: add agent runtime settings"
```

## Task 6: Move Chat And Discover Runs Onto The Generic Runtime

**Files:**
- Create: `Sources/PaperCodexApp/AgentRunCoordinator.swift`
- Modify: `Sources/PaperCodexApp/AppModel.swift`
- Modify: `Sources/PaperCodexApp/DiscoverView.swift`
- Modify: `Sources/PaperCodexApp/ChatView.swift`
- Modify: `Sources/PaperCodexCore/Models.swift`
- Modify: `Sources/PaperCodexCore/PaperRepository.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] Add repository migration for generic runtime session links.
- [ ] Preserve legacy `codexSessionID` reads and write a Codex runtime link for old sessions.
- [ ] Move chat run orchestration from `AppModel.runCodex`/`runCodexTurn` into `AgentRunCoordinator`.
- [ ] Replace Discover direct `CodexCLI` enrichment with the selected enrichment runtime.
- [ ] Keep image generation routed to Codex until another runtime proves equivalent generated-image filesystem behavior.
- [ ] Run:

```bash
swift run PaperCodexCoreChecks agent-session-migration
swift run PaperCodexCoreChecks codex-recovery
swift run PaperCodexCoreChecks generated-images
swift run PaperCodexCoreChecks local-discover-engine
swift build
```

- [ ] Commit:

```bash
git add Sources/PaperCodexApp/AgentRunCoordinator.swift Sources/PaperCodexApp/AppModel.swift Sources/PaperCodexApp/DiscoverView.swift Sources/PaperCodexApp/ChatView.swift Sources/PaperCodexCore/Models.swift Sources/PaperCodexCore/PaperRepository.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "refactor: route app AI runs through agent runtimes"
```

## Task 7: Add PTY-Backed TUI Mode In The Reader Panel

**Files:**
- Create: `Sources/PaperCodexApp/AgentTerminalView.swift`
- Create: `Sources/PaperCodexCore/LocalPTYProcess.swift`
- Modify: `Sources/PaperCodexApp/ChatView.swift`
- Modify: `Sources/PaperCodexApp/AppModel.swift`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] Add a PTY process wrapper using Darwin `openpty`/`posix_spawn` or an equivalent safe Foundation-compatible path.
- [ ] Add terminal buffer, input forwarding, resize handling, stop/terminate, and output log persistence under `workspace/turns/`.
- [ ] Add right-panel mode selector:
  - `Chat` for non-interactive turn execution and persisted chat messages.
  - `Terminal` for TUI-capable agents running inside the session workspace.
- [ ] Make Codex, Claude Code, Hermes, OpenClaw, and pi launchable in Terminal mode when their profiles declare `supportsPTY`.
- [ ] Run:

```bash
swift run PaperCodexCoreChecks agent-runtime-source
swift build
scripts/build-app-bundle.sh
```

- [ ] Verify in installed app:
  - open a paper session
  - choose Terminal mode
  - launch `claude` or `pi` in the session workspace
  - type a harmless prompt
  - stop the process cleanly

- [ ] Commit:

```bash
git add Sources/PaperCodexApp/AgentTerminalView.swift Sources/PaperCodexCore/LocalPTYProcess.swift Sources/PaperCodexApp/ChatView.swift Sources/PaperCodexApp/AppModel.swift Sources/PaperCodexCoreChecks/main.swift
git commit -m "feat: support tui agent sessions"
```

## Task 8: Expand MCP And Skills For Agent Operation

**Files:**
- Modify: `Sources/PaperCodexCore/PaperCodexMCPService.swift`
- Modify: `skills/papercodex-mcp/SKILL.md`
- Create: `skills/papercodex-agent-workspace/SKILL.md`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`

- [ ] Add MCP resources:
  - `papercodex://sessions/{session_id}/workspace-manifest`
  - `papercodex://sessions/{session_id}/agent-runtime`
  - `papercodex://sessions/{session_id}/prompt-contract`
- [ ] Add MCP tools only for app state operations, not for launching arbitrary local commands.
- [ ] Update skill docs:
  - use MCP for app/library/note/folder/tag actions
  - use workspace files for source reading
  - cite only with approved citation markers
  - call app navigation tools only when the user wants visual focus changes
- [ ] Run:

```bash
swift run PaperCodexCoreChecks mcp
```

- [ ] Commit:

```bash
git add Sources/PaperCodexCore/PaperCodexMCPService.swift skills/papercodex-mcp/SKILL.md skills/papercodex-agent-workspace/SKILL.md Sources/PaperCodexCoreChecks/main.swift
git commit -m "feat: expose agent workspace contracts through mcp"
```

## Task 9: Add Local Smoke Test Script For Codex, Claude Code, And Kimi

**Files:**
- Create: `scripts/agent-runtime-smoke.sh`
- Modify: `Sources/PaperCodexCoreChecks/main.swift`
- Modify: `README.md`
- Modify: `README.zh-CN.md`

- [ ] Script behavior:
  - detect `codex`, `claude`, `openclaw`, `hermes`, and `pi`
  - read the live Paper Codex MCP metadata when the app is running
  - create or reuse a safe fixture session workspace
  - run a small prompt asking each runtime to return a JSON object containing:
    - `runtime`
    - `workspace_seen`
    - `citation_contract_seen`
    - `mcp_endpoint_seen`
  - default Kimi route: `openclaw agent --local --json` because local OpenClaw currently resolves default Kimi to `kimi-coding/k2p5`
  - optional Kimi route: Hermes Kimi when `hermes status` shows Kimi configured
- [ ] The script must not modify library papers, folders, tags, or notes unless explicitly passed a write-test flag.
- [ ] Add docs explaining the runtime matrix and how to run smoke tests.
- [ ] Run:

```bash
swift run PaperCodexCoreChecks
swift build
scripts/build-app-bundle.sh
scripts/agent-runtime-smoke.sh --codex --claude --kimi-openclaw
```

- [ ] Commit:

```bash
git add scripts/agent-runtime-smoke.sh Sources/PaperCodexCoreChecks/main.swift README.md README.zh-CN.md
git commit -m "test: add multi-agent runtime smoke checks"
```

## Task 10: Final Installed-App Verification

**Files:**
- Modify only if failures reveal real defects.

- [ ] Run full source/build checks:

```bash
swift run PaperCodexCoreChecks
swift build
git diff --check
scripts/build-app-bundle.sh
```

- [ ] Relaunch `/Users/chunqiu/Applications/PaperCodex.app`.
- [ ] Verify app/MCP:
  - `~/Library/Application Support/PaperCodex/mcp/server.json` exists.
  - `/health` returns 200.
  - `/mcp initialize` returns server name `paper-codex`.
- [ ] Verify UI:
  - Settings shows Agent Runtimes and Paper Codex MCP status.
  - Reader right panel can switch between Chat and Terminal modes.
  - Existing Codex chat still returns source-grounded answers.
- [ ] Verify local runtimes:
  - Codex: non-interactive chat run succeeds in the session workspace.
  - Claude Code: non-interactive chat run succeeds in the session workspace and sees prompt contract/MCP config.
  - Kimi: OpenClaw/Kimi route succeeds in the session workspace and sees prompt contract/MCP config.
- [ ] Verify no regression:
  - Library import/folder/tag/note actions still work.
  - Discover fetch and enrichment still work with selected runtime.
  - Generated image flow still uses Codex unless a replacement has been explicitly validated.
- [ ] Commit final fixes:

```bash
git add <changed files>
git commit -m "feat: decouple paper codex agent runtime"
```

---

## Design Decisions

- **Do not make Paper Codex an auth vault.** Store runtime preferences and safe status summaries; let Codex, Claude Code, Hermes, OpenClaw, and pi own their auth files/tokens.
- **Use OpenClaw as the first Kimi validation route.** Local evidence shows OpenClaw has `kimi-coding/k2p5` configured with Kimi auth. Direct `kimi` CLI is not present, and pi currently does not list Kimi models.
- **Keep Codex image generation special until proven otherwise.** Current generated-image behavior relies on Codex JSONL, workspace files, and `GeneratedImageCollector`.
- **Prefer runtime-neutral workspace contracts over runtime-specific prompts.** Runtime-specific adapters should only decide command flags and prompt injection mechanics.
- **Keep app mutation behind MCP.** Session workspaces are for reading and generated artifacts; app/library changes should go through typed MCP tools.
- **Support both command and TUI modes.** Deterministic non-interactive adapters are needed for tests; PTY mode is needed to satisfy the user-facing “any TUI agent” goal.

## Risk Register

- **PTY complexity:** SwiftUI terminal rendering and PTY resize/input handling can regress keyboard behavior. Mitigation: isolate in `LocalPTYProcess` and `AgentTerminalView`, test with harmless local commands before real agents.
- **Auth drift:** Claude/Hermes/OpenClaw/pi auth status can change independently. Mitigation: diagnostics should surface current status without assuming permanent availability.
- **MCP config incompatibility:** Codex, Claude, Hermes, OpenClaw, and pi consume MCP/plugins differently. Mitigation: adapters own injection mechanics; common workspace writes `mcp.json` and skills for all.
- **Session migration:** Old `codexSessionID` must not be lost. Mitigation: migration keeps legacy field and mirrors it into generic runtime links.
- **Discover enrichment semantics:** Existing enrichment expects concise JSON-ish output. Mitigation: keep Codex as default enrichment runtime until command-parser checks pass for other adapters.
- **Image generation:** Other agents may not produce local image artifacts in the same shape. Mitigation: keep image generation routed to Codex until equivalent behavior is verified.

## Completion Criteria

- `PaperCodexCoreChecks` includes runtime-profile, command-builder, workspace-manifest, migration, MCP, and UI source checks.
- Installed app starts MCP and writes valid endpoint metadata.
- A real reader session workspace includes runtime-neutral manifest, prompt contract, MCP config, and agent instructions.
- The right panel supports at least:
  - current chat transcript mode
  - PTY terminal mode for TUI agents
- Codex, Claude Code, and Kimi route all pass local smoke tests on this machine.
- Existing Library, Reader, Discover, MCP, prompt-template, and generated-image workflows still pass their current checks.
