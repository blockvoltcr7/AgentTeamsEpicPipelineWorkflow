---
name: seed-epic
description: Parse a local PRD into local epic and task markdown files for review before anything is finalized. Use when the user asks to seed an epic from a PRD, break a PRD into tasks, or generate local epic files from an implementation roadmap.
---

# Seed Epic

Read a PRD and create local `epics/` markdown artifacts that can be reviewed before the epic is finalized.

## Input

Parse one argument:
- `prd_path`: path to the PRD directory

If it is missing, ask for it.

## Output

Write:
- `{prd_path}/epics/epic-overview.md`
- one subfolder per epic or phase
- one `epic-overview.md` per epic folder
- numbered task markdown files in each epic folder

Nothing is finalized in this stage — `finalize-epic` handles that next.

## Workflow

### 1. Read the full PRD

Read `README.md`, the implementation phases page, and the other relevant PRD pages needed to understand:
- scope
- task boundaries
- dependencies
- acceptance criteria

Do not treat the roadmap as final truth. Evaluate it critically.

### 2. Restructure for execution

You may:
- split oversized tasks
- merge trivial tasks
- add missing tasks
- reorder tasks
- split or merge epics

Every structural change should have a concrete reason tied to execution quality.

Use `references/type-inference.md` to infer task types.

### 3. Present a creation plan

Before writing files, show:
- epic folders to be created
- tasks per epic
- major changes from the PRD roadmap
- cross-epic dependencies

Wait for confirmation before writing.

### 4. Write local epic files

Each task file should be self-contained enough for later enrichment and execution. Include these sections:
- `## Type`
- `## Context`
- `## Implementation`
- `## Acceptance Criteria`
- `## Dependencies`
- `## Technical Notes`

The task should contain actionable guidance, not just a stub.

For `## Dependencies`, use slug-based references — the task slug is the filename without the numeric prefix. Cross-epic refs use `<epic-folder>/<slug>`:

```
## Dependencies
- Depends On: setup-auth
- Depends On: shared-infra-epic/provision-redis
```

### 5. Handoff

After writing files, report:
- epic folder path
- epics created
- task count
- next step: `finalize-epic <epic_folder>`

## References

- `references/type-inference.md`
