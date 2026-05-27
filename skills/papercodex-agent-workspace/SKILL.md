---
name: papercodex-agent-workspace
description: Use when an agent is launched inside a Paper Codex reading-session workspace and must read paper files, follow citation contracts, or coordinate app/library changes through Paper Codex MCP.
---

# Paper Codex Agent Workspace

Use this skill when your current working directory is a Paper Codex session workspace.

## First Reads

Read these local files before answering or changing anything:

```text
workspace_manifest.json
agent_instructions.md
prompt_contract.md
session.json
```

Then read only the paper files needed for the task:

```text
papers/{paper_id}/metadata.json
papers/{paper_id}/full_text.txt
papers/{paper_id}/pages.jsonl
papers/{paper_id}/spans.jsonl
papers/{paper_id}/anchors.jsonl
```

## Operating Boundary

Use workspace files for source reading, drafts, and generated artifacts.

Use MCP tools for app state changes:

- notes, digests, folders, tags, and paper metadata
- reader navigation or visual focus changes
- prompt template changes
- importing or deleting library items

Do not edit the Paper Codex SQLite database or app support files directly.

## Citation Contract

Ground paper claims with Paper Codex citation markers:

```text
[[cite:paper:{paper_id}:p{page}:b{block_index}]]
[[cite:paper:{paper_id}:p{page}:a{anchor_suffix}]]
```

Prefer `spans.jsonl` for citation-ready claims. Use `anchors.jsonl` when the user selected or saved a source passage. If a claim cannot be grounded in the workspace, say that plainly.

## MCP Discovery

When MCP is configured, discover live app state through:

```text
papercodex://app/active-context
papercodex://sessions/{session_id}/workspace-manifest
papercodex://sessions/{session_id}/agent-runtime
papercodex://sessions/{session_id}/prompt-contract
```

If `mcp.json` exists, use it as the session-local MCP configuration. If not, rely on the workspace files and ask the user before attempting app mutations.
