---
name: enrich-epic
description: Enrich a local epic's task files with implementation details, acceptance criteria, dependencies, and file-path guidance by cross-referencing local PRD docs and the codebase. Run after finalize-epic and before analyze-epic.
---

# Enrich Epic

Upgrade local task files from roadmap-level descriptions into implementation-ready task specs.

## Input

Parse one argument:
- `epic_folder_path`: path to the finalized epic folder

If it is missing, ask for it.

Refuse to run if `status.log` is not present in the folder — that means the epic has not been finalized. Tell the user to run `finalize-epic <epic_folder_path>` first.

## Workflow

### 1. Load task and PRD context

Glob `<epic_folder_path>/*.md`, exclude `epic-overview.md` and `*.plan.md`. Read each spec file. Read the relevant local PRD docs that define:
- feature scope
- data model
- architecture
- definition of done

Local PRD docs are the primary source of truth.

### 2. Score task quality

Evaluate each task with `references/enrichment-criteria.md` and classify it as:
- Critical
- Needs Enrichment
- Adequate

### 3. Present the assessment

Show the quality table and ask whether to enrich all tasks or a selected subset.

### 4. Enrich the chosen tasks

For each chosen task, rewrite the spec file body wholesale (replace, not merge). The new body must include:
- `## Type`
- `## Context`
- `## Implementation`
- `## Acceptance Criteria`
- `## Dependencies`
- `## Technical Notes`

Keep `## Implementation` concise and directive. It should point the executor to the right files and patterns, not contain the full implementation.

Never touch `*.plan.md` files (analyze-epic owns them, and they don't exist yet at this stage). Never touch `status.log` (every task is still `open` at enrichment time). Never touch `epic-overview.md` (enrichment doesn't change structure).

If the user is concerned about losing manual edits to a task body, the previous version is recoverable via `git log` and `git checkout` — every enrichment session creates an auto-commit.

### 5. Cross-check consistency

After updating tasks, do a quick pass for:
- dependency consistency
- PRD terminology drift
- missing shared-file notes

### 6. Auto-commit and handoff

Stage the spec files modified in this session and create a commit:

```bash
git add <epic_folder_path>/*.md
git commit -m "Enrich epic: <epic_name> (<N> tasks updated)"
```

Skip the commit only if no spec files actually changed.

Report the enriched tasks and point the user to:
- `analyze-epic <epic_folder_path>`

## References

- `references/enrichment-criteria.md`
