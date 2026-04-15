---
name: analyze-epic
description: Analyze a local epic folder to determine dependency phases, parallelization safety, and execution strategy plan files for later implementation. Run after enrich-epic and before run-epic.
---

# Analyze Epic

Build the dependency graph for a local epic folder and write execution strategy plan files that describe safe execution order. Plan files are sidecars (`<NN>-<slug>.plan.md`) — they live next to spec files but never modify them.

## Input

Parse one argument:
- `epic_folder_path`: path to the finalized epic folder

If it is missing, ask for it.

Refuse to run if `status.log` is not present in the folder — that means the epic has not been finalized. Tell the user to run `finalize-epic <epic_folder_path>` first.

## Workflow

### 1. Read and validate tasks

Glob `<epic_folder_path>/*.md`, exclude `epic-overview.md` and `*.plan.md`. Read each spec file. Read `status.log` to identify completed tasks (last entry per slug == `done`) and skip them. Warn if any spec is missing critical sections such as `## Type` or `## Dependencies`.

### 2. Build the DAG

Parse dependencies from task descriptions and resolve them to task IDs. Detect:
- cycles
- orphans
- external references

Stop if there is a cycle.

### 3. Assign phases

Topologically sort the DAG into execution phases.

### 4. Analyze conflict risk

Use `references/dependency-analysis.md` plus the task descriptions to determine:
- explicit file overlap
- inferred file overlap
- shared conflict zones

Classify tasks as parallel-safe or sequential.

### 5. Present the analysis

Show:
- dependency graph summary
- phase plan
- parallel windows
- branch/worktree suggestions

Wait for confirmation before writing comments.

### 6. Write execution strategy plan files

For each analyzed task, write a sidecar plan file at `<epic_folder_path>/<NN>-<slug>.plan.md`. Use `Write` (overwrite-safe) — this skill is the only writer for `*.plan.md` files, so re-running cleanly replaces previous plans without touching specs.

Plan file format — YAML frontmatter for the structured fields run-epic reads, then a free-text body for human-readable rationale:

```markdown
---
phase: 2
worktree_mode: parallel
conflict_risk: high
branch: feat/add-login
depends_on: [setup-auth]
blocks: [add-logout]
---

# Execution Strategy — add-login

Phase 2, parallel-safe with `add-password-reset`. High conflict risk because both
touch `src/auth/session.ts`; use isolated worktree and merge before phase 3.
```

Frontmatter field semantics:
- `phase`: integer, 1-indexed, from topological sort
- `worktree_mode`: `parallel` | `sequential` | `main`
- `conflict_risk`: `none` | `low` | `medium` | `high`
- `branch`: branch name from the algorithm in `references/dependency-analysis.md`
- `depends_on`: list of slugs this task depends on (within this epic only)
- `blocks`: list of slugs this task blocks (within this epic only)

### 7. Handoff

Point the user to:
- `run-epic <epic_folder_path>`

## References

- `references/dependency-analysis.md`
