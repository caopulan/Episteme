# Prompt Templates

Prompt templates are first-class typed settings.

Supported tasks:

```text
paper_reading
paper_summary
paper_digest
tag_suggestion
note_generation
compare_papers
literature_review
figure_explanation
method_extraction
experiment_extraction
limitation_analysis
citation_grounding
chat_system_prompt
```

Tools:

```text
prompt_template.create
prompt_template.rename
prompt_template.duplicate
prompt_template.replace_body
prompt_template.set_variables
prompt_template.set_default_for_task
prompt_template.enable
prompt_template.disable
prompt_template.archive
prompt_template.preview_render
prompt_template.validate
```

Safe edit loop:

1. Read `papercodex://settings/prompt-templates/{template_id}`.
2. Draft the new body with explicit `{{variable_name}}` placeholders.
3. Call `prompt_template.preview_render`.
4. Call `prompt_template.validate`.
5. Call `prompt_template.replace_body`.
6. Call `prompt_template.preview_render` and `prompt_template.validate` again.

Do not change a default template for a task until the user has made clear that the change should affect future runs of that task.
