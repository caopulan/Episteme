# Paper Codex MCP Tools

Call tools when asking Paper Codex to change state.

## Papers

```text
paper.import_pdf
paper.list
paper.get
paper.search
paper.update_metadata
paper.star
paper.delete
paper.deduplicate
paper.add_to_folder
paper.remove_from_folder
paper.move_folder
paper.copy_to_folder
paper.add_tags
paper.remove_tags
paper.set_tags
paper.digest_get
paper.digest_upsert
```

Use `paper.copy_to_folder` when preserving existing folder membership. Use `paper.move_folder` when the paper should leave its current folder context.

## Folders And Tags

```text
folder.list
folder.create
folder.rename
folder.delete
folder.move
tag.list
tag.create
tag.rename
tag.delete
tag.suggest
```

Read `papercodex://folders` or `papercodex://tags` before creating new names to avoid duplicates.

## Notes, Anchors, Citations

```text
note.list
note.get
note.create
note.update
note.delete
note.create_from_anchor
anchor.list
anchor.get
anchor.search
citation.resolve
```

Prefer `note.create_from_anchor` when the note is about a selected PDF passage.

## Watched Folders And Sessions

```text
app.open_paper
app.reveal_paper
app.open_folder
app.open_tag
app.jump_to_page
app.jump_to_anchor
watched_folder.list
watched_folder.add
watched_folder.remove
watched_folder.scan
session.list_recent
session.get
session.get_workspace
reader.position_get
reader.position_set
```

App tools enqueue commands for the running Paper Codex app. Re-read `papercodex://app/active-context` after a short delay to verify the UI picked up the command.

Use `session.get_workspace` before asking an agent to inspect workspace files directly.
