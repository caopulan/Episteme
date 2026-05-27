---
name: papercodex-mcp
description: Use when an agent needs to read, organize, annotate, or configure the local Paper Codex paper library through its MCP service, including adding papers, moving folders, tagging, notes, anchors, sessions, and prompt templates.
---

# Paper Codex MCP

Use this skill when working with the local Paper Codex MCP service.

## Core Rule

Resources are read-only state views. Tools perform mutations or app actions.

Start every current-paper workflow by reading:

```text
papercodex://app/active-context
```

Then read specific paper/folder/tag/note resources before calling tools that change them.

## Required Workflow

1. Read active context or the explicit paper resource.
2. Read current folders/tags/notes before changing them.
3. Use tools only for the smallest intended change.
4. Re-read the relevant resource after mutation to verify the result.
5. For paper facts, ground claims in `full-text`, `spans`, `anchors`, or session workspace files.

## Agent Workspaces

For a reading session, prefer these resources before operating from a local agent terminal:

```text
papercodex://sessions/{session_id}/workspace-manifest
papercodex://sessions/{session_id}/agent-runtime
papercodex://sessions/{session_id}/prompt-contract
```

Use workspace files for source reading and generated artifacts. Use MCP tools for app state changes such as notes, folders, tags, paper metadata, reader navigation, and prompt templates.

## Prompt Templates

Prompt templates are typed settings. Never call or invent a generic `settings.update`.

When changing prompt templates:

1. Read `papercodex://settings/prompt-templates`.
2. Call `prompt_template.preview_render` with representative variables.
3. Call `prompt_template.validate`.
4. Only then call `prompt_template.replace_body`, `set_variables`, or `set_default_for_task`.
5. Preview and validate again after the change.

## Safety

Destructive tools require explicit confirmation. For delete or batch operations, inspect the dry-run response first and only repeat with `confirm=true` when the user explicitly requested the operation.

For detailed tool/resource names, load only the needed reference:

- `references/resources.md` for resource URIs.
- `references/tools.md` for tool names and arguments.
- `references/prompt-templates.md` for prompt-template workflows.
- `references/safety.md` for destructive and batch-operation rules.
