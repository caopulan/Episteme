# Safety Rules

Do not call destructive tools casually.

These operations require confirmation or an explicit user request:

```text
paper.delete
folder.delete
tag.delete
note.delete
paper.set_tags
paper.move_folder
prompt_template.archive
prompt_template.set_default_for_task
```

For deletes, first call the tool without `confirm=true` and inspect the response. Repeat with `confirm=true` only when the user explicitly wants the operation.

For batch organization, read the current paper metadata first and summarize the exact paper IDs, source folders, target folders, and tag changes before applying.

Never invent paper IDs, folder IDs, tag IDs, span IDs, or anchor IDs. Search or read resources first.
