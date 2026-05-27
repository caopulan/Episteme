# Paper Codex MCP Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a real local MCP service that starts with Paper Codex, exposes typed paper-library resources/tools/prompts, manages prompt templates as first-class settings, and ships an agent skill document explaining safe usage.

**Architecture:** `PaperCodexCore` owns MCP protocol handling, prompt-template persistence, and repository-backed paper operations. `PaperCodexApp` owns app lifecycle integration and supplies active-reader/app-command context. A local HTTP JSON-RPC endpoint writes its connection metadata under the Paper Codex support root so other local agents can connect.

**Tech Stack:** Swift 6.2, Foundation, Darwin sockets, existing SQLite-backed `PaperRepository`, JSON-RPC-compatible MCP methods.

---

### Task 1: Test MCP protocol and prompt-template behavior

**Files:**
- Modify: `Package.swift`
- Create: `Tests/PaperCodexCoreTests/PaperCodexMCPTests.swift`

- [x] Use the existing `PaperCodexCoreChecks` executable because this toolchain does not provide `XCTest`.
- [x] Add checks that verify `tools/list`, `resources/read`, `prompt_template.validate`, `prompt_template.preview_render`, app command queuing, and HTTP `/mcp` initialization fail before implementation and pass after implementation.

### Task 2: Add typed prompt-template storage

**Files:**
- Create: `Sources/PaperCodexCore/PromptTemplateStore.swift`

- [x] Store prompt templates in a JSON file under the support root.
- [x] Provide default task templates, default-task mapping, validation, and preview rendering.
- [x] Avoid broad catch-all setting mutation APIs; expose typed prompt-template operations.

### Task 3: Add MCP protocol service and local HTTP transport

**Files:**
- Create: `Sources/PaperCodexCore/PaperCodexMCPService.swift`
- Create: `Sources/PaperCodexCore/PaperCodexMCPServer.swift`

- [x] Implement JSON-RPC methods for initialize, resources, resource templates, tools, and prompts.
- [x] Implement repository-backed paper, folder, tag, note, anchor, session, and prompt-template resources/tools.
- [x] Implement a local HTTP `/mcp` endpoint and `/health`, with token protection and connection metadata.

### Task 4: Start MCP service with the app

**Files:**
- Modify: `Sources/PaperCodexApp/AppModel.swift`

- [x] Start the MCP server after repository migration succeeds.
- [x] Stop it when `AppModel` deinitializes.
- [x] Provide active-context snapshots and app-navigation command queue hooks where UI state is needed.

### Task 5: Add agent skill documentation

**Files:**
- Create: `skills/papercodex-mcp/SKILL.md`
- Create: `skills/papercodex-mcp/references/tools.md`
- Create: `skills/papercodex-mcp/references/resources.md`
- Create: `skills/papercodex-mcp/references/prompt-templates.md`
- Create: `skills/papercodex-mcp/references/safety.md`

- [x] Explain when to read resources versus call tools.
- [x] Document safe workflows for current-paper operations, tags/folders, notes, and prompt-template edits.
- [x] Require validation/preview for prompt templates and dry-run for destructive or batch operations.

### Task 6: Verify and commit

**Files:**
- Verify all changed files.

- [x] Run the focused `swift run PaperCodexCoreChecks mcp` check.
- [x] Run `swift run PaperCodexCoreChecks`.
- [x] Run `swift build`.
- [x] Rebuild and launch `/Users/chunqiu/Applications/PaperCodex.app`, then verify `/health` and `/mcp initialize`.
- [ ] Commit with a conventional message.
