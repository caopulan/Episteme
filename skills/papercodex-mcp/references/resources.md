# Paper Codex MCP Resources

Read resources when asking "what is the current state?"

```text
papercodex://papers
papercodex://papers/{paper_id}
papercodex://papers/{paper_id}/metadata
papercodex://papers/{paper_id}/full-text
papercodex://papers/{paper_id}/pages/{page}
papercodex://papers/{paper_id}/spans
papercodex://papers/{paper_id}/anchors
papercodex://papers/{paper_id}/annotations
papercodex://papers/{paper_id}/notes
papercodex://papers/{paper_id}/digest
papercodex://folders
papercodex://folders/{folder_id}
papercodex://folders/{folder_id}/papers
papercodex://tags
papercodex://tags/{tag_id}
papercodex://tags/{tag_id}/papers
papercodex://sessions/recent
papercodex://sessions/{session_id}
papercodex://sessions/{session_id}/messages
papercodex://sessions/{session_id}/workspace
papercodex://sessions/{session_id}/workspace-manifest
papercodex://sessions/{session_id}/agent-runtime
papercodex://sessions/{session_id}/prompt-contract
papercodex://app/active-context
papercodex://settings/prompt-templates
papercodex://settings/prompt-templates/{template_id}
papercodex://settings/prompt-templates/defaults
papercodex://settings/prompt-templates/tasks
papercodex://settings/prompt-templates/variables
```

Use `metadata` for organization state, `full-text` for broad reading, `spans` and `anchors` for citation-grounded claims, and `notes` or `digest` for user-authored reading memory.

For local agent runs, use `workspace-manifest` to discover session files, `agent-runtime` to see runtime links and materialization mode, and `prompt-contract` to preserve citation/output requirements.
