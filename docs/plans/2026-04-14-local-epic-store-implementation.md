# Local Epic Store Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate the `.github/skills/` epic pipeline from ClickUp-backed storage to local-file-backed storage, preserving the existing pipeline shape and orchestration model.

**Architecture:** Per-PRD epic folders under `{prd_path}/epics/{epic-name}/` containing spec files (`<NN>-<slug>.md`), plan sidecars (`<NN>-<slug>.plan.md`), and an append-only `status.log`. Five of six existing skills get rewritten; one (`push-epic-to-clickup`) is renamed to `finalize-epic`. Orchestration model is unchanged: GitHub Copilot CLI main agent acts as orchestrator, sub-agents spawn only via native `/fleet` for parallel-safe phases.

**Tech Stack:** Markdown skill files (no code), YAML frontmatter, git for rollback, GitHub Copilot CLI runtime.

**Design reference:** `docs/plans/2026-04-14-local-epic-store-design.md`

---

## Implementation Notes

- **No traditional "tests".** These are AI workflow skills, not code. "Validation" steps are: read the file back, verify required sections exist, run the skill against a sample epic at the end (Phase 6).
- **Each commit corresponds to one phase**, matching the design's auto-commit model. Within a phase, edits are atomic per-file but committed as a group at phase end.
- **Skip-on-already-done is fine.** If you re-run a task and the file is already correct, validate and move on.
- **Working directory:** all paths in this plan are relative to `/Users/samisabir-idrissi/dev/work/AgentTeamsEpicPipelineWorkflow/` unless absolute.

---

## Phase 0: Pre-flight

### Task 0.1: Verify or initialize git repository

**Files:**
- Check: `.git/` directory at repo root

**Step 1: Check current git state**

Run: `git -C /Users/samisabir-idrissi/dev/work/AgentTeamsEpicPipelineWorkflow status`
Expected: either "On branch ..." (already a repo) or "fatal: not a git repository"

**Step 2: If not a git repo, ask the user before initializing**

Ask: "This project is not currently a git repository, but the design requires git for rollback and auto-commit. May I run `git init` and create an initial commit of the current state?"

**Step 3: If user approves, init and commit baseline**

```bash
cd /Users/samisabir-idrissi/dev/work/AgentTeamsEpicPipelineWorkflow
git init
git add .
git commit -m "Baseline before local epic store migration"
```

Expected: "Initialized empty Git repository" and a commit hash.

**Step 4: If user declines, halt the plan**

Stop here. Auto-commit and rollback features cannot work without git. Report to user and exit.

---

## Phase 1: Trivial seed-epic updates

### Task 1.1: Update `seed-epic/SKILL.md` handoff text

**Files:**
- Modify: `.github/skills/seed-epic/SKILL.md`

**Step 1: Read the current handoff section**

Read lines 74–80 of `.github/skills/seed-epic/SKILL.md`. Confirm it contains:

```
After writing files, report:
- epic folder path
- epics created
- task count
- next step: `push-epic-to-clickup <epic_folder> <clickup_folder_id>`
```

**Step 2: Replace the next-step line**

Use Edit to replace exactly:

`old_string:`
```
- next step: `push-epic-to-clickup <epic_folder> <clickup_folder_id>`
```

`new_string:`
```
- next step: `finalize-epic <epic_folder>`
```

**Step 3: Verify the change**

Re-read the same lines. Confirm `finalize-epic` appears and `push-epic-to-clickup` is gone.

### Task 1.2: Update seed-epic task template dependency example

**Files:**
- Modify: `.github/skills/seed-epic/SKILL.md`

The current SKILL.md (lines 64–72) lists task sections but doesn't show a `## Dependencies` example. We need to add one explicitly so future task authors use slug syntax.

**Step 1: Read the "Write local epic files" section**

Read lines 62–72 of `.github/skills/seed-epic/SKILL.md`. Confirm it contains the section list including `## Dependencies`.

**Step 2: Append a dependency-format note after the section list**

Use Edit to add format guidance. Replace exactly:

`old_string:`
```
The task should contain actionable guidance, not just a stub.
```

`new_string:`
```
The task should contain actionable guidance, not just a stub.

For `## Dependencies`, use slug-based references — the task slug is the filename without the numeric prefix. Cross-epic refs use `<epic-folder>/<slug>`:

```
## Dependencies
- Depends On: setup-auth
- Depends On: shared-infra-epic/provision-redis
```
```

**Step 3: Verify the change**

Re-read the section. Confirm the new dependency example block is present.

### Task 1.3: Verify type-inference.md needs no changes

**Files:**
- Read-only check: `.github/skills/seed-epic/references/type-inference.md`

**Step 1: Grep for any ClickUp references**

Use Grep with pattern `clickup|ClickUp|CLICKUP` against `.github/skills/seed-epic/references/type-inference.md`.

Expected: no matches.

**Step 2: If no matches, mark this task done**

The file is already ClickUp-free. No edit needed.

**Step 3: If there ARE matches, stop and report**

Surface the matching lines to the user before proceeding — the design assumed this file was clean.

### Task 1.4: Commit Phase 1

**Step 1: Stage changes**

```bash
cd /Users/samisabir-idrissi/dev/work/AgentTeamsEpicPipelineWorkflow
git add .github/skills/seed-epic/SKILL.md
```

**Step 2: Commit**

```bash
git commit -m "Update seed-epic to hand off to finalize-epic with slug-based deps"
```

Expected: one commit, two changes (handoff line + dependency example block).

---

## Phase 2: Rename `push-epic-to-clickup` → `finalize-epic`

### Task 2.1: Create new `finalize-epic` skill directory

**Files:**
- Create: `.github/skills/finalize-epic/`
- Create: `.github/skills/finalize-epic/agents/`

**Step 1: Create directories**

```bash
mkdir -p /Users/samisabir-idrissi/dev/work/AgentTeamsEpicPipelineWorkflow/.github/skills/finalize-epic/agents
```

**Step 2: Verify they exist**

Use Glob with pattern `.github/skills/finalize-epic/**/*` — should return the two empty directories or be empty (no files yet).

### Task 2.2: Write `finalize-epic/SKILL.md`

**Files:**
- Create: `.github/skills/finalize-epic/SKILL.md`

**Step 1: Write the file with this exact content**

```markdown
---
name: finalize-epic
description: Validate a local epic folder, initialize its status log, and freeze it for execution. Use when the user is ready to lock in a drafted epic before enrichment and analysis. Replaces the old push-epic-to-clickup step in the local-only pipeline.
---

# Finalize Epic

Validate a local epic folder produced by `seed-epic`, initialize its `status.log`, regenerate the `epic-overview.md` status table, and create a checkpoint commit. This is the "freeze the spec" step that gates downstream enrichment, analysis, and execution.

## Input

Parse one argument:
- `epic_folder_path`: path to the epic folder

If it is missing, ask for it.

## Workflow

### 1. Read the epic

Read `epic-overview.md` and every `<NN>-<slug>.md` task file in the folder. Skip `*.plan.md` files (analyze-epic owns those) and `status.log` (read separately in step 5).

### 2. Validate structure

For each task file, confirm these sections exist:
- `## Type`
- `## Context`
- `## Acceptance Criteria`
- `## Dependencies` (may be empty)

Warn (do not fail) on missing `## Implementation` or `## Technical Notes` — `enrich-epic` populates those next.

If a required section is missing, hard fail with the file path and the missing section name. Do not proceed.

### 3. Validate slugs

Compute each task's slug by stripping the `^\d+-` prefix from its filename (e.g., `01-add-login.md` → `add-login`).

If two task files in this epic resolve to the same slug, hard fail and show both file paths. The user must rename one before re-running.

### 4. Validate dependencies

Parse the `## Dependencies` section of each task. Each `Depends On: <slug>` must resolve to:
- An existing task file in this epic (slug match), OR
- A `<other-epic>/<slug>` reference where the other epic folder exists at the same parent path and contains a matching slug

Detect cycles in the seed-time dependency graph using DFS coloring (WHITE/GRAY/BLACK). Hard fail on any dangling reference or cycle, showing the offending task and the unresolved or cyclic reference.

### 5. Initialize state

Check whether `status.log` exists in the epic folder:

- **If absent:** create it. Append one `nil->open` line for each task, all sharing the same ISO 8601 timestamp:

  ```
  2026-04-14T12:00:00Z setup-auth nil->open
  2026-04-14T12:00:00Z add-login nil->open
  2026-04-14T12:00:00Z add-logout nil->open
  ```

- **If present:** parse it. For each task file in the epic, check whether its slug appears in the log. If not, append a new `nil->open` line for it (this handles re-runs after new tasks are added to the epic).

Never delete or modify existing log entries. The log is append-only.

### 6. Generate the overview status table

Compute the current status of each task by reading `status.log` (last entry per slug wins; entries sorted by timestamp, not file position).

Update `epic-overview.md`. Find the block delimited by `<!-- STATUS-TABLE-START -->` and `<!-- STATUS-TABLE-END -->`. If the markers are not present, append them at the end of the file along with the table. If they are present, replace everything between them.

Table format:

```markdown
<!-- STATUS-TABLE-START — generated by run-epic, do not edit by hand -->
| #  | Slug         | Type    | Status      | Updated              |
|----|--------------|---------|-------------|----------------------|
| 01 | setup-auth   | feature | open        | 2026-04-14T12:00:00Z |
| 02 | add-login    | feature | open        | 2026-04-14T12:00:00Z |
| 03 | add-logout   | feature | open        | 2026-04-14T12:00:00Z |
<!-- STATUS-TABLE-END -->
```

Anything outside the markers is human-owned and must not be touched.

### 7. Auto-commit

Stage the epic folder and create a commit. No prompt — auto-commit is required for this skill.

```bash
git add <epic_folder_path>
git commit -m "Finalize epic: <epic_name>"
```

Skip the commit only if `git status` shows no changes in the epic folder (idempotent re-run).

### 8. Handoff

Report:
- validation results (sections checked, deps resolved, cycles checked)
- task count
- new vs existing log entries
- next step: `enrich-epic <epic_folder_path>`

## Re-run behavior

Idempotent. Re-validates everything. Adds `nil->open` entries only for new tasks. Regenerates the overview table. Auto-commits only if there is a real diff.
```

**Step 2: Verify the file was written**

Read `.github/skills/finalize-epic/SKILL.md` and confirm it contains the `name: finalize-epic` frontmatter and the 8 workflow steps.

### Task 2.3: Write `finalize-epic/agents/openai.yaml`

**Files:**
- Create: `.github/skills/finalize-epic/agents/openai.yaml`

**Step 1: Write the file with this exact content**

```yaml
interface:
  display_name: "Finalize Epic"
  short_description: "Validate a local epic folder and freeze it for execution"
  default_prompt: "Finalize this local epic folder and prepare it for enrichment"
```

**Step 2: Verify**

Read the file back. Confirm the three interface fields are present.

### Task 2.4: Delete the old `push-epic-to-clickup` skill folder

**Files:**
- Delete: `.github/skills/push-epic-to-clickup/`

**Step 1: Confirm the folder still exists and is the old version**

Read `.github/skills/push-epic-to-clickup/SKILL.md` line 2 — should say `name: push-epic-to-clickup`.

**Step 2: Remove the directory**

```bash
rm -rf /Users/samisabir-idrissi/dev/work/AgentTeamsEpicPipelineWorkflow/.github/skills/push-epic-to-clickup
```

**Step 3: Verify removal**

Use Glob with pattern `.github/skills/push-epic-to-clickup/**/*` — should return no results.

### Task 2.5: Commit Phase 2

**Step 1: Stage all changes**

```bash
cd /Users/samisabir-idrissi/dev/work/AgentTeamsEpicPipelineWorkflow
git add .github/skills/finalize-epic .github/skills/push-epic-to-clickup
```

**Step 2: Commit**

```bash
git commit -m "Replace push-epic-to-clickup with finalize-epic for local file storage"
```

Expected: one commit with adds for the new finalize-epic files and deletes for the old push-epic-to-clickup files.

---

## Phase 3: `enrich-epic` I/O swap

### Task 3.1: Update `enrich-epic/SKILL.md`

**Files:**
- Modify: `.github/skills/enrich-epic/SKILL.md`

**Step 1: Replace the description frontmatter**

`old_string:`
```
description: Enrich ClickUp epic tasks with implementation details, acceptance criteria, dependencies, and file-path guidance by cross-referencing local PRD docs and the codebase. Run before analyze-epic.
```

`new_string:`
```
description: Enrich a local epic's task files with implementation details, acceptance criteria, dependencies, and file-path guidance by cross-referencing local PRD docs and the codebase. Run after finalize-epic and before analyze-epic.
```

**Step 2: Replace the heading paragraph**

`old_string:`
```
# Enrich Epic

Upgrade ClickUp tasks from roadmap-level descriptions into implementation-ready task specs.
```

`new_string:`
```
# Enrich Epic

Upgrade local task files from roadmap-level descriptions into implementation-ready task specs.
```

**Step 3: Replace the Input section**

`old_string:`
```
## Input

Parse one argument:
- `list_id`: ClickUp list ID

If it is missing, ask for it.
```

`new_string:`
```
## Input

Parse one argument:
- `epic_folder_path`: path to the finalized epic folder

If it is missing, ask for it.

Refuse to run if `status.log` is not present in the folder — that means the epic has not been finalized. Tell the user to run `finalize-epic <epic_folder_path>` first.
```

**Step 4: Replace step 1 (Load task and PRD context)**

`old_string:`
```
### 1. Load task and PRD context

Fetch all open tasks in the list. Read the relevant local PRD docs that define:
- feature scope
- data model
- architecture
- definition of done

Use local docs as the primary source of truth, not ClickUp attachments.
```

`new_string:`
```
### 1. Load task and PRD context

Glob `<epic_folder_path>/*.md`, exclude `epic-overview.md` and `*.plan.md`. Read each spec file. Read the relevant local PRD docs that define:
- feature scope
- data model
- architecture
- definition of done

Local PRD docs are the primary source of truth.
```

**Step 5: Replace step 4 (Enrich the chosen tasks)**

`old_string:`
```
### 4. Enrich the chosen tasks

For each task, update `markdown_description` with:
- `## Type`
- `## Context`
- `## Implementation`
- `## Acceptance Criteria`
- `## Dependencies`
- `## Technical Notes`

Keep `## Implementation` concise and directive. It should point the executor to the right files and patterns, not contain the full implementation.
```

`new_string:`
```
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
```

**Step 6: Replace step 6 (Handoff)**

`old_string:`
```
### 6. Handoff

Report the enriched tasks and point the user to:
- `analyze-epic <list_id>`
```

`new_string:`
```
### 6. Auto-commit and handoff

Stage the spec files modified in this session and create a commit:

```bash
git add <epic_folder_path>/*.md
git commit -m "Enrich epic: <epic_name> (<N> tasks updated)"
```

Skip the commit only if no spec files actually changed.

Report the enriched tasks and point the user to:
- `analyze-epic <epic_folder_path>`
```

**Step 7: Verify the file**

Read the full `.github/skills/enrich-epic/SKILL.md`. Confirm:
- Description mentions "local epic"
- Input is `epic_folder_path`
- Step 1 says "Glob"
- Step 4 says "rewrite the spec file body"
- Step 6 includes the auto-commit block
- No remaining `list_id` or `markdown_description` references

### Task 3.2: Update `enrich-epic/agents/openai.yaml`

**Files:**
- Modify: `.github/skills/enrich-epic/agents/openai.yaml`

**Step 1: Replace the file content**

Use Write to overwrite the file with:

```yaml
interface:
  display_name: "Enrich Epic"
  short_description: "Turn local task files into implementation-ready specs using PRD and codebase context"
  default_prompt: "Enrich the tasks in this local epic folder with concrete implementation details"
```

**Step 2: Verify**

Read the file back. Confirm "ClickUp" is gone and "local task files" / "local epic folder" appear.

### Task 3.3: Update `enrich-epic/references/enrichment-criteria.md`

**Files:**
- Modify: `.github/skills/enrich-epic/references/enrichment-criteria.md`

**Step 1: Replace the heading paragraph**

`old_string:`
```
# Task Enrichment Criteria

Scoring rubric and analysis patterns for evaluating and enriching ClickUp task descriptions.
```

`new_string:`
```
# Task Enrichment Criteria

Scoring rubric and analysis patterns for evaluating and enriching local task file descriptions.
```

**Step 2: Replace the Dependencies section's enrichment guidance**

`old_string:`
```
**When enriching**: Review all tasks in the epic. If task A creates a table and task B adds RLS to that table, B depends on A. Use the format: `**Depends On:** Task 1.1 (task_id) — provides the ghl schema`.
```

`new_string:`
```
**When enriching**: Review all tasks in the epic. If task A creates a table and task B adds RLS to that table, B depends on A. Use slug-based format: `- Depends On: <slug>`. Cross-epic refs use `- Depends On: <epic-folder>/<slug>`. Slugs are filenames without the `^\d+-` numeric prefix.
```

**Step 3: Verify**

Grep for `clickup|ClickUp` in the file. Should return no matches. Grep for `slug-based` — should return one match in the new dependency guidance.

### Task 3.4: Commit Phase 3

```bash
cd /Users/samisabir-idrissi/dev/work/AgentTeamsEpicPipelineWorkflow
git add .github/skills/enrich-epic
git commit -m "Swap enrich-epic to read/write local task files instead of ClickUp"
```

---

## Phase 4: `analyze-epic` I/O swap + sidecar writes

### Task 4.1: Update `analyze-epic/SKILL.md`

**Files:**
- Modify: `.github/skills/analyze-epic/SKILL.md`

**Step 1: Replace the description frontmatter**

`old_string:`
```
description: Analyze a ClickUp epic to determine dependency phases, parallelization safety, and execution strategy comments for later implementation. Run before run-epic.
```

`new_string:`
```
description: Analyze a local epic folder to determine dependency phases, parallelization safety, and execution strategy plan files for later implementation. Run after enrich-epic and before run-epic.
```

**Step 2: Replace the heading paragraph**

`old_string:`
```
# Analyze Epic

Build the dependency graph for a ClickUp epic and write execution strategy comments that describe safe execution order.
```

`new_string:`
```
# Analyze Epic

Build the dependency graph for a local epic folder and write execution strategy plan files that describe safe execution order. Plan files are sidecars (`<NN>-<slug>.plan.md`) — they live next to spec files but never modify them.
```

**Step 3: Replace the Input section**

`old_string:`
```
## Input

Parse one argument:
- `list_id`: ClickUp list ID

If it is missing, ask for it.
```

`new_string:`
```
## Input

Parse one argument:
- `epic_folder_path`: path to the finalized epic folder

If it is missing, ask for it.

Refuse to run if `status.log` is not present in the folder — that means the epic has not been finalized. Tell the user to run `finalize-epic <epic_folder_path>` first.
```

**Step 4: Replace step 1 (Fetch and validate tasks)**

`old_string:`
```
### 1. Fetch and validate tasks

Read all tasks in the list plus their comments. Skip completed tasks. Warn if the tasks are missing critical sections such as `## Type` or `## Dependencies`.
```

`new_string:`
```
### 1. Read and validate tasks

Glob `<epic_folder_path>/*.md`, exclude `epic-overview.md` and `*.plan.md`. Read each spec file. Read `status.log` to identify completed tasks (last entry per slug == `done`) and skip them. Warn if any spec is missing critical sections such as `## Type` or `## Dependencies`.
```

**Step 5: Replace step 6 (Write execution strategy comments)**

`old_string:`
```
### 6. Write execution strategy comments

Add an `EXECUTION STRATEGY` comment to each analyzed task containing:
- phase
- worktree mode
- dependencies and blocks
- merge conflict risk
- branch assignment
```

`new_string:`
```
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
```

**Step 6: Replace step 7 (Handoff)**

`old_string:`
```
### 7. Handoff

Point the user to:
- `run-epic <list_id>`
```

`new_string:`
```
### 7. Handoff

Point the user to:
- `run-epic <epic_folder_path>`
```

**Step 7: Verify the file**

Read the full `.github/skills/analyze-epic/SKILL.md`. Confirm:
- Description mentions "local epic folder" and "plan files"
- Input is `epic_folder_path`
- Step 1 says "Glob"
- Step 6 says "plan file" with the YAML frontmatter format
- No remaining `list_id` or `EXECUTION STRATEGY comment` references

### Task 4.2: Update `analyze-epic/agents/openai.yaml`

**Files:**
- Modify: `.github/skills/analyze-epic/agents/openai.yaml`

**Step 1: Overwrite with**

```yaml
interface:
  display_name: "Analyze Epic"
  short_description: "Build dependency phases and parallelization guidance for a local epic"
  default_prompt: "Analyze this local epic folder and write execution strategy plan files"
```

**Step 2: Verify**

Read back. Confirm "ClickUp" is gone.

### Task 4.3: Rewrite `analyze-epic/references/dependency-analysis.md`

**Files:**
- Modify: `.github/skills/analyze-epic/references/dependency-analysis.md`

This file has the most ClickUp-isms and the broken external reference at line 144. The cleanest path is targeted edits rather than a full rewrite.

**Step 1: Replace the dependency parsing section**

`old_string:`
```
## 1. Dependency Parsing

### Extracting Dependencies from Task Descriptions

Parse the `## Dependencies` section of each task's `markdown_description`. Dependencies may appear in several formats:

```markdown
## Dependencies

- **Depends On:** Task 1.1 (`86e0984ub`) — provides the ghl pgSchema
- **Blocks:** Task 1.4 (`86e0984v8`), Task 1.5 (`86e0984va`)
```

**Parsing rules:**

1. Look for lines containing `Depends On:` or `depends on:` (case-insensitive)
2. Extract task IDs: match patterns like `86e0984uq` (alphanumeric ClickUp IDs in backticks or parentheses)
3. Extract task numbers: match patterns like `Task 1.1` or `1.1`
4. If only names are given (no IDs), fuzzy-match against task names in the current list
5. Look for `Blocks:` lines and extract the same way — these provide reverse-edge validation

### Resolving References

| Reference Type | Resolution Strategy |
|---|---|
| ClickUp task ID (`86e0984uq`) | Direct lookup in fetched task list |
| Task number (`1.1`, `Task 1.1`) | Match against task name prefix (e.g., "1.1 Create ghl pgSchema") |
| Task name (`Create ghl pgSchema`) | Case-insensitive substring match against task names |
| External ID (not in list) | Treat as already-satisfied dependency, warn user |
```

`new_string:`
```
## 1. Dependency Parsing

### Extracting Dependencies from Spec Files

Parse the `## Dependencies` section of each task's spec file (`<NN>-<slug>.md`). Expected format:

```markdown
## Dependencies
- Depends On: setup-auth
- Depends On: shared-infra-epic/provision-redis
- Blocks: add-logout
```

**Parsing rules:**

1. Look for lines containing `Depends On:` or `depends on:` (case-insensitive)
2. Extract slugs: match the token after the colon. A slug is `[a-z0-9-]+`. A cross-epic slug has the form `<epic-folder>/<slug>`.
3. Look for `Blocks:` lines and extract the same way — these provide reverse-edge validation
4. The slug is the spec filename without the `^\d+-` numeric prefix (e.g., `02-add-login.md` → `add-login`). The numeric prefix is sort-only and is not part of the identity.

### Resolving References

Build a slug index by globbing `<epic_folder_path>/*.md` (excluding `epic-overview.md` and `*.plan.md`) and computing each file's slug.

| Reference Type | Resolution Strategy |
|---|---|
| Slug (`add-login`) | Direct lookup in this epic's slug index |
| Cross-epic slug (`other-epic/add-login`) | Resolve `other-epic` as a sibling folder of this epic, then look up `add-login` in its slug index |
| Unresolved slug | Hard fail — show the offending spec file and the unresolved reference. Do not proceed. |
```

**Step 2: Update the implicit ordering section**

`old_string:`
```
### Implicit Ordering

If a task has NO `## Dependencies` section, check its name for a sequence number:
- `1.1`, `1.2`, `1.3` — sequential numbering MAY imply ordering
- However, **do NOT assume** sequential numbering means sequential dependency unless explicitly stated
- Flag these tasks for user review: "Task {name} has no `## Dependencies` section. Treating as independent (Phase 1 candidate). Is this correct?"
```

`new_string:`
```
### Implicit Ordering

If a task has NO `## Dependencies` section (or it's empty), do NOT assume the numeric filename prefix implies ordering. The numeric prefix is sort-only.

Flag the task for user review: "Task `<slug>` has no dependencies. Treating as independent (Phase 1 candidate). Is this correct?"
```

**Step 3: Update the cycle detection error message**

`old_string:`
```
**On cycle detection:**
1. Report the full cycle path: "Circular dependency: Task A → Task B → Task C → Task A"
2. Include task IDs and names for easy identification
3. Stop analysis — user must fix the task descriptions before proceeding
```

`new_string:`
```
**On cycle detection:**
1. Report the full cycle path using slugs: "Circular dependency: setup-auth → add-login → setup-auth"
2. Include the spec file path for each slug
3. Stop analysis — user must fix the spec files before proceeding
```

**Step 4: Inline the conflict zones (replacing the broken external reference)**

`old_string:`
```
#### Layer 3: Conflict Zone Check

Reference the conflict zones from `.claude/skills/clickup-task-format/references/execution-strategy.md`:

| Conflict Zone File | Why It Conflicts |
|---|---|
| `lib/drizzle/schema/index.ts` | Every new schema table must be re-exported here |
| `drizzle.config.ts` | Every new schema file must be registered here |
| `components/layout/AppSidebar.tsx` | Navigation changes affect all pages |
| `lib/env.ts` | Environment variable additions affect all modules |
| `app/layout.tsx` | Root layout changes affect entire app |
| `app/(protected)/layout.tsx` | Protected route layout changes affect all protected pages |

If two tasks in the same phase both need to modify ANY of these files → **SEQUENTIAL, no exceptions**.
```

`new_string:`
```
#### Layer 3: Conflict Zone Check

Conflict zones are files that are touched by many features and almost always cause merge conflicts when modified in parallel. The default conflict zone list (override per-project as needed):

| Conflict Zone File | Why It Conflicts |
|---|---|
| `lib/drizzle/schema/index.ts` | Every new schema table must be re-exported here |
| `drizzle.config.ts` | Every new schema file must be registered here |
| `components/layout/AppSidebar.tsx` | Navigation changes affect all pages |
| `lib/env.ts` | Environment variable additions affect all modules |
| `app/layout.tsx` | Root layout changes affect entire app |
| `app/(protected)/layout.tsx` | Protected route layout changes affect all protected pages |

If two tasks in the same phase both need to modify ANY of these files → **SEQUENTIAL, no exceptions**.

Projects with different conflict zones should override this table by editing this file directly. There is no external file to reference.
```

**Step 5: Verify**

Grep for `clickup|ClickUp` in the file — should return no matches.
Grep for `\.claude/skills/clickup-task-format` — should return no matches.
Grep for `86e0984` — should return no matches.

### Task 4.4: Commit Phase 4

```bash
cd /Users/samisabir-idrissi/dev/work/AgentTeamsEpicPipelineWorkflow
git add .github/skills/analyze-epic
git commit -m "Swap analyze-epic to slug-based deps and sidecar plan files"
```

---

## Phase 5: `run-epic` — biggest changes

### Task 5.1: Update `run-epic/SKILL.md`

**Files:**
- Modify: `.github/skills/run-epic/SKILL.md`

**Step 1: Replace the description frontmatter**

`old_string:`
```
description: Execute a ClickUp epic phase by phase using the task descriptions and execution strategy comments. Use when the user asks to run or execute an analyzed epic from a slash-command workflow in GitHub Copilot CLI. The main Copilot CLI agent should act as the orchestrator, optionally delegating bounded specialist work or using /fleet for parallel-safe phases.
```

`new_string:`
```
description: Execute a local epic folder phase by phase using its spec files, plan sidecars, and append-only status log. Use when the user asks to run or execute an analyzed epic from a slash-command workflow in GitHub Copilot CLI. The main Copilot CLI agent acts as the orchestrator, optionally delegating bounded specialist work or using /fleet for parallel-safe phases.
```

**Step 2: Replace the heading paragraph**

`old_string:`
```
# Run Epic

Execute an analyzed ClickUp epic using the task specs and execution strategy comments already attached to the tasks.
```

`new_string:`
```
# Run Epic

Execute an analyzed local epic folder using the spec files (`<NN>-<slug>.md`) and execution strategy plan sidecars (`<NN>-<slug>.plan.md`) produced by `enrich-epic` and `analyze-epic`. Status transitions are appended to `<epic_folder>/status.log` — the orchestrator is the only writer.
```

**Step 3: Replace the Input section**

`old_string:`
```
## Input

Parse one argument:
- `list_id`: ClickUp list ID

If it is missing, ask for it.
```

`new_string:`
```
## Input

Parse one argument:
- `epic_folder_path`: path to the analyzed epic folder

If it is missing, ask for it.

Refuse to run if `status.log` is not present in the folder — that means the epic has not been finalized. Tell the user to run `finalize-epic <epic_folder_path>` first.
```

**Step 4: Replace the Orchestration model section's third bullet**

`old_string:`
```
- The main agent owns the phase plan, ClickUp state, integration decisions, and phase gates.
```

`new_string:`
```
- The main agent owns the phase plan, status.log writes, integration decisions, and phase gates.
```

**Step 5: Replace step 1 (Fetch and parse the epic)**

`old_string:`
```
### 1. Fetch and parse the epic

Read every open task in the list along with:
- `markdown_description`
- execution strategy comments

If tasks do not have execution strategy comments, warn and fall back to conservative sequential execution.
```

`new_string:`
```
### 1. Read and parse the epic

Glob `<epic_folder_path>/*.md`, exclude `epic-overview.md` and `*.plan.md`. For each spec file, also read its sibling `<NN>-<slug>.plan.md` if present.

Read `status.log`. Sort entries by timestamp. For each slug, take the last entry — that's the current status. Skip slugs whose current status is `done`.

If `*.plan.md` files are missing, warn and fall back to conservative sequential execution (single task per phase, no parallelization).

**Crash recovery:** detect any slug whose current status is `in_progress` with no terminal entry. For each such slug:

1. Find the last clean checkpoint commit before the `in_progress` transition: `git log --oneline -- <epic_folder_path>` and look for a `Run epic ... phase N complete` or `Finalize epic` commit just before the `in_progress` timestamp.
2. Show the user the slug and the checkpoint commit hash.
3. Offer three options:
   - (a) mark as completed — work was actually done; append `<slug> in_progress->done` to the log
   - (b) mark as abandoned — append `<slug> in_progress->open` to the log; the task will be retried this run
   - (c) roll back — `git checkout <commit> -- <epic_folder_path>` and rerun the phase from there

Wait for the user's choice. Append the appropriate transition before continuing.
```

**Step 6: Replace step 4 (Track ClickUp state)**

`old_string:`
```
### 4. Track ClickUp state

Use the normal status flow:
- `open` -> `in progress` -> `done`

Do not mark a task `done` until its acceptance criteria are actually met.
```

`new_string:`
```
### 4. Track status via status.log

The state machine is `open -> in_progress -> done`. Every transition is a single append to `status.log`:

```
2026-04-14T14:30:00Z setup-auth open->in_progress
2026-04-14T14:52:14Z setup-auth in_progress->done
```

Append rules:
- The orchestrator is the **only writer** to `status.log`. Sub-agents spawned via `/fleet` never write to it directly — they report completion textually back to the orchestrator, who then appends.
- After every append, regenerate the `<!-- STATUS-TABLE-START -->`...`<!-- STATUS-TABLE-END -->` block in `epic-overview.md` from the log.
- Do not mark a task `done` until its acceptance criteria are actually met (verified by the orchestrator inspecting the changes against `## Acceptance Criteria` in the spec).
- If a task is blocked, append a same-state transition with a `# blocker:` note: `<slug> in_progress->in_progress # blocker: <reason>`. The task stays `in_progress`; the blocker is queryable via grep.
```

**Step 7: Add a new step 7 (Phase commit) before "Wrap up"**

`old_string:`
```
### 5. Handle blockers

If a task is blocked:
- keep it `in progress`
- summarize the blocker clearly
- stop the phase if downstream work depends on it

### 6. Wrap up
```

`new_string:`
```
### 5. Handle blockers

If a task is blocked:
- keep it `in_progress`
- append a same-state log entry with `# blocker: <reason>`
- stop the phase if downstream work depends on it

### 6. Phase commit (auto)

After every phase completes successfully (all tasks in the phase are at `done` in `status.log`, all worktrees merged and cleaned up per the lifecycle in `references/orchestration-protocol.md`), create a single phase checkpoint commit:

```bash
git add <epic_folder_path>
git commit -m "Run epic <epic_name>: phase <N> complete (<M> tasks done)"
```

One commit per phase, never per task. The phase commit is the rollback target referenced by crash recovery in step 1.

### 7. Wrap up
```

**Step 8: Verify**

Read the full `.github/skills/run-epic/SKILL.md`. Confirm:
- Description mentions "local epic folder" and "status log"
- Input is `epic_folder_path`
- Step 1 includes the crash recovery flow
- Step 4 says `status.log` and "single writer"
- Step 6 is "Phase commit (auto)"
- No remaining `list_id` references

### Task 5.2: Update `run-epic/agents/openai.yaml`

**Files:**
- Modify: `.github/skills/run-epic/agents/openai.yaml`

**Step 1: Overwrite with**

```yaml
interface:
  display_name: "Run Epic"
  short_description: "Execute an analyzed local epic phase by phase with Copilot CLI native orchestration"
  default_prompt: "Execute this analyzed local epic folder and track progress through the phases"
```

**Step 2: Verify**

Read back. Confirm "ClickUp" and "Codex-native" are gone.

### Task 5.3: Update `run-epic/references/agent-mapping.md`

**Files:**
- Modify: `.github/skills/run-epic/references/agent-mapping.md`

**Step 1: Replace the heading paragraph**

`old_string:`
```
# Agent Mapping

Maps ClickUp task `## Type` values to execution specializations.
```

`new_string:`
```
# Agent Mapping

Maps task `## Type` values (read from local spec files) to execution specializations.
```

**Step 2: Replace the matching rules item 1**

`old_string:`
```
1. **Primary match:** Keyword match against the `## Type` section of each task's `markdown_description`.
```

`new_string:`
```
1. **Primary match:** Keyword match against the `## Type` section of each task's spec file body.
```

**Step 3: Verify**

Grep for `clickup|ClickUp|markdown_description` in the file — should return no matches.

### Task 5.4: Update `run-epic/references/orchestration-protocol.md` — heading and intro

**Files:**
- Modify: `.github/skills/run-epic/references/orchestration-protocol.md`

**Step 1: Replace the intro paragraph**

`old_string:`
```
# Orchestration Protocol

Step-by-step algorithm for phase-based epic execution in GitHub Copilot CLI.

The main Copilot CLI agent is the orchestrator. It may execute work directly, delegate bounded work to subagents or custom agents, and use `/fleet` for parallel-safe phases.
```

`new_string:`
```
# Orchestration Protocol

Step-by-step algorithm for phase-based local epic execution in GitHub Copilot CLI.

The main Copilot CLI agent is the orchestrator. It may execute work directly, delegate bounded work to subagents or custom agents, and use `/fleet` for parallel-safe phases. The orchestrator is the **single writer** to the epic's `status.log` — sub-agents never write to it directly.
```

### Task 5.5: Update `run-epic/references/orchestration-protocol.md` — phase execution steps

**Files:**
- Modify: `.github/skills/run-epic/references/orchestration-protocol.md`

**Step 1: Replace step 1 (RECEIVE PHASE PLAN)**

`old_string:`
```
### 1. RECEIVE PHASE PLAN

The command passes a structured markdown phase plan. Parse it to extract:
- Phase number and mode (Parallel / Sequential) for each phase
- Task assignments: task_id, task_name, specialization, isolation mode, branch name, parallel_partner (if any)
- Full task details: markdown_description, acceptance_criteria
```

`new_string:`
```
### 1. RECEIVE PHASE PLAN

Parse the local epic folder to extract:
- Phase number and mode (Parallel / Sequential) — read from each task's `<NN>-<slug>.plan.md` frontmatter (`phase` and `worktree_mode`)
- Task assignments: slug, task_name, specialization, isolation mode, branch name — also from plan frontmatter
- Full task details: spec file body, acceptance criteria from `## Acceptance Criteria` section
- Current status per slug — from `status.log` (last entry per slug, sorted by timestamp)
```

**Step 2: Replace step 2 (FILTER COMPLETED)**

`old_string:`
```
### 2. FILTER COMPLETED

Skip any tasks already marked Done in ClickUp. If an entire phase is Done, skip to the next phase.
```

`new_string:`
```
### 2. FILTER COMPLETED

Skip any task whose current status in `status.log` is `done`. If an entire phase is `done`, skip to the next phase.
```

**Step 3: Replace step 3d (VERIFY PHASE COMPLETION)**

`old_string:`
```
#### 3d. VERIFY PHASE COMPLETION

After implementation work for the phase is complete:
1. Call `clickup_get_task(task_id)` for each task
2. Confirm status is `done`
3. Confirm the acceptance criteria are actually met in code and not only claimed as done
4. Merge worktree or parallel outputs before proceeding
```

`new_string:`
```
#### 3d. VERIFY PHASE COMPLETION

After implementation work for the phase is complete, for each task in the phase:
1. Re-read the last entry for the slug in `status.log` and confirm it is `done`
2. Confirm the acceptance criteria are actually met in the code (orchestrator inspects, not just trust the sub-agent's report)
3. Confirm any worktree spawned for the task has been merged AND cleaned up per the Worktree Lifecycle below
4. After all tasks in the phase pass, create the phase checkpoint commit
```

### Task 5.6: Replace "ClickUp Status Transitions" section

**Files:**
- Modify: `.github/skills/run-epic/references/orchestration-protocol.md`

**Step 1: Replace the section**

`old_string:`
```
## ClickUp Status Transitions

When managing task lifecycle, follow this three-state progression:

| Event | ClickUp Status |
|---|---|
| Task execution starts | Update to `in progress` |
| Task completion verified | Verify status is `done` |
| Task has a blocker | Keep as `in progress` |

The flow is always: **Open → In Progress → Done**
```

`new_string:`
```
## Status Log Transitions

When managing task lifecycle, follow this three-state progression. Every transition is a single append to `status.log`:

| Event | Log Append |
|---|---|
| Task execution starts | `<ts> <slug> open->in_progress` |
| Task completion verified | `<ts> <slug> in_progress->done` |
| Task has a blocker | `<ts> <slug> in_progress->in_progress # blocker: <reason>` |
| Task abandoned for retry | `<ts> <slug> in_progress->open` |

The flow is always: **open → in_progress → done**

After every append, regenerate the `<!-- STATUS-TABLE-START -->`...`<!-- STATUS-TABLE-END -->` block in `epic-overview.md` from the log. The log is the source of truth; the table is a hint for humans.

**Single-writer rule:** The orchestrator is the only process that ever appends to `status.log`. Sub-agents spawned via `/fleet` report completion textually to the orchestrator, who then writes the transition. This eliminates any append race.
```

### Task 5.7: Add new "Worktree Lifecycle" subsection

**Files:**
- Modify: `.github/skills/run-epic/references/orchestration-protocol.md`

**Step 1: Insert the new section after the existing "Worktree Decision Rules" section**

`old_string:`
```
Additionally, if the execution strategy comment specifies `Worktree Mode: PARALLEL`, use worktree-style isolation regardless of conflict risk level when running tasks in parallel.

## Delegation Prompt Template
```

`new_string:`
```
Additionally, if the plan file frontmatter specifies `worktree_mode: parallel`, use worktree-style isolation regardless of conflict risk level when running tasks in parallel.

## Worktree Lifecycle

For each parallel-safe task spawned in a worktree, the orchestrator follows this exact sequence. Order matters — the status log append must come AFTER cleanup, so a half-merged worktree never produces a premature `done`.

1. **Spawn**
   ```bash
   git worktree add ../<epic-name>-<slug> <branch>
   ```
   Dispatch the sub-agent with the worktree path and the task's spec + plan content via the Delegation Prompt Template below.

2. **Wait for completion report.** Sub-agent reports done/blocked/failed textually. Sub-agent does NOT touch `status.log`.

3. **Verify acceptance criteria.** Orchestrator inspects the worktree's changes against the spec's `## Acceptance Criteria`. Don't trust the sub-agent's claim; verify.

4. **Merge.** Orchestrator merges the worktree's branch back into the parent branch. On conflict: resolve in main agent or escalate to the user.

5. **Cleanup.**
   ```bash
   git worktree remove ../<epic-name>-<slug>
   git branch -d <branch>
   ```
   If cleanup itself fails (locked worktree, dirty index), warn but do not fail the task — the work is merged. Tell the user the worktree path and let them clean manually.

6. **Append to `status.log`.** Only now does the orchestrator write the `<slug> in_progress->done` transition. After append, regenerate the overview status table.

7. **Phase commit.** Once ALL parallel tasks in the phase have completed steps 1–6, create the single phase checkpoint commit:
   ```bash
   git add <epic_folder_path>
   git commit -m "Run epic <epic_name>: phase <N> complete (<M> tasks done)"
   ```

## Delegation Prompt Template
```

### Task 5.8: Update the delegation prompt template

**Files:**
- Modify: `.github/skills/run-epic/references/orchestration-protocol.md`

**Step 1: Replace the template body**

`old_string:`
```
Use this template when delegating a bounded task to a specialist subagent or custom agent:

```
You are working on Task {task_number}: {task_name}.
ClickUp Task ID: {task_id}

## Full Task Description

{markdown_description}

## Your Instructions

1. Implement the work described in the task description
2. Follow the acceptance criteria exactly
3. Use Supabase MCP tools (`apply_migration`, `execute_sql`) for database migrations
4. When ALL acceptance criteria are met:
   a. Report completion with a concise integration summary
   b. Only mark the task `done` if the workflow explicitly delegates ClickUp state updates to you
5. If you encounter blockers, report them immediately with details
```
```

`new_string:`
```
Use this template when delegating a bounded task to a specialist subagent or custom agent:

```
You are working on Task {task_number}: {task_name}.
Slug: {slug}
Spec file: {spec_path}
Worktree: {worktree_path}

## Full Task Description

{spec_body}

## Your Instructions

1. Implement the work described in the spec body
2. Follow the acceptance criteria in `## Acceptance Criteria` exactly
3. Use Supabase MCP tools (`apply_migration`, `execute_sql`) for database migrations
4. When ALL acceptance criteria are met, report completion with a concise integration summary
5. **Do NOT write to `status.log`.** Status transitions are owned exclusively by the orchestrator. Report your completion (or blocker) textually; the orchestrator will append the log entry after verifying your work and cleaning up the worktree.
6. If you encounter blockers, report them immediately with details
```
```

### Task 5.9: Update the error recovery table

**Files:**
- Modify: `.github/skills/run-epic/references/orchestration-protocol.md`

**Step 1: Replace the entire error recovery table**

`old_string:`
```
## Error Recovery

| Scenario | Action |
|---|---|
| Delegated work reports blocker | Send debugging guidance, check if task deps are actually met |
| Parallel phase drifts from the plan | Collapse back to sequential execution |
| ClickUp MCP call fails | Retry once, then escalate to user |
| Worktree merge conflict | Resolve in the main agent or escalate to the user |
| All delegated work in a phase is stuck | Escalate to user with summary of blockers |
```

`new_string:`
```
## Error Recovery

| Scenario | Action |
|---|---|
| Delegated work reports blocker | Send debugging guidance, check if task deps are actually met. Append same-state log entry with `# blocker: <reason>` |
| Parallel phase drifts from the plan | Collapse back to sequential execution |
| Status log append fails | Check disk/permissions. Never retry blindly (could double-append). Escalate to user |
| Worktree merge conflict | Resolve in the main agent or escalate to the user |
| Worktree cleanup fails after successful merge | Warn user with the worktree path. Leave it in place. Continue (the task IS done — work is merged) |
| Plan files (`*.plan.md`) missing | Warn and fall back to conservative sequential execution |
| Status log corrupted (unparseable lines) | Skip unparseable lines with a warning. Last-good-entry-per-slug wins. Never crash |
| Crash mid-task: `in_progress` with no terminal entry | Prompt user with the three-option recovery flow (completed / abandoned / rollback) |
| All delegated work in a phase is stuck | Escalate to user with summary of blockers |
```

**Step 2: Verify the entire file**

Grep for `clickup|ClickUp|clickup_get_task` in the file — should return no matches.
Grep for `Worktree Lifecycle` — should return one match (the new section heading).
Grep for `status.log` — should return multiple matches.

### Task 5.10: Create `run-epic/references/rollback.md`

**Files:**
- Create: `.github/skills/run-epic/references/rollback.md`

**Step 1: Write the file**

```markdown
# Rolling Back an Epic

Git is the rollback mechanism for the local epic store. Every meaningful checkpoint is an auto-commit:

- `Finalize epic: <name>` — produced by `finalize-epic`
- `Enrich epic: <name> (<N> tasks updated)` — produced by `enrich-epic`
- `Run epic <name>: phase <N> complete (<M> tasks done)` — produced by `run-epic` after each successful phase

## Rolling Back to a Previous State

To return an epic to an earlier state:

```bash
# 1. Find the checkpoint commit you want to return to
git log --oneline -- <epic_folder>

# 2. Restore just the epic folder to that commit (does NOT touch other files)
git checkout <commit> -- <epic_folder>

# 3. Resume by re-running run-epic — it reads status.log and resumes
#    from wherever the rolled-back state left off
```

## When to Roll Back

| Scenario | Rollback Target |
|---|---|
| Phase 4 produced bad code that broke phase 1–3 work | Last `phase 3 complete` commit |
| Enrichment overwrote good manual edits | Last `Finalize epic` commit, then re-run enrich-epic with different choices |
| Crash mid-execution (offered automatically by run-epic) | Last clean checkpoint before the `in_progress` transition |
| Want to redo analysis with different conflict zones | Last `Enrich epic` commit, then re-run analyze-epic |

## What Roll Back Does NOT Do

- It does NOT undo source code changes outside the epic folder. If a phase modified files in `src/`, those changes remain. Use `git checkout <commit> -- <other-paths>` separately if needed.
- It does NOT delete worktrees that were created during the rolled-back work. List them with `git worktree list` and clean up manually.
- It does NOT rewrite history. The original commits remain in `git log`; rollback creates a new state on top of them.
```

**Step 2: Verify**

Read the file back. Confirm it has the three checkpoint types and the `git checkout <commit> -- <epic_folder>` pattern.

### Task 5.11: Commit Phase 5

```bash
cd /Users/samisabir-idrissi/dev/work/AgentTeamsEpicPipelineWorkflow
git add .github/skills/run-epic
git commit -m "Rewrite run-epic for local status log, worktree lifecycle, and rollback"
```

---

## Phase 6: End-to-end smoke test

This phase validates the rewritten skills by running them against a tiny sample epic. The smoke test is intentionally minimal — one PRD with two tasks — to verify the pipeline plumbing without burning a lot of time.

### Task 6.1: Create a sample PRD

**Files:**
- Create: `tmp/smoke-test-prd/README.md`
- Create: `tmp/smoke-test-prd/implementation-phases.md`

**Step 1: Create the directory**

```bash
mkdir -p /Users/samisabir-idrissi/dev/work/AgentTeamsEpicPipelineWorkflow/tmp/smoke-test-prd
```

**Step 2: Write `README.md`**

```markdown
# Smoke Test PRD

Trivial PRD used to validate the local-epic-store pipeline end to end.

## Goal

Add a hello-world endpoint and a tiny test for it.
```

**Step 3: Write `implementation-phases.md`**

```markdown
# Implementation Phases

## Phase 1: Hello world

| Task | Description |
|---|---|
| Add hello endpoint | Create a `/hello` route that returns `"world"` |
| Add hello test | Add a unit test that hits `/hello` and asserts the response |
```

### Task 6.2: Run `seed-epic` against the sample PRD

**Step 1: Invoke seed-epic**

In your Copilot CLI session, invoke:

```
/seed-epic tmp/smoke-test-prd
```

**Step 2: Confirm the creation plan**

When seed-epic shows the creation plan, confirm.

**Step 3: Verify outputs**

Use Glob with pattern `tmp/smoke-test-prd/epics/**/*.md`. Expected files:
- `tmp/smoke-test-prd/epics/epic-overview.md`
- `tmp/smoke-test-prd/epics/hello-world/epic-overview.md`
- `tmp/smoke-test-prd/epics/hello-world/01-add-hello-endpoint.md`
- `tmp/smoke-test-prd/epics/hello-world/02-add-hello-test.md`

(Exact slugs depend on seed-epic's naming choices — verify the *count* of files and the presence of `epic-overview.md`.)

**Step 4: Verify dependency syntax in the second task**

Read `tmp/smoke-test-prd/epics/hello-world/02-add-hello-test.md` (or whichever task the test depends on). Confirm `## Dependencies` uses slug syntax (`Depends On: add-hello-endpoint`) and not the old ClickUp ID format.

If seed-epic still emits the old format, that's a regression in Task 1.2 — go back and fix.

### Task 6.3: Run `finalize-epic` against the sample epic

**Step 1: Invoke finalize-epic**

```
/finalize-epic tmp/smoke-test-prd/epics/hello-world
```

**Step 2: Verify status.log was created**

Read `tmp/smoke-test-prd/epics/hello-world/status.log`. Expected: two lines, one per task, both `nil->open`, both with the same ISO 8601 timestamp.

**Step 3: Verify the overview table was generated**

Read `tmp/smoke-test-prd/epics/hello-world/epic-overview.md`. Expected: contains `<!-- STATUS-TABLE-START -->` and `<!-- STATUS-TABLE-END -->` markers with a markdown table between them showing both tasks at status `open`.

**Step 4: Verify auto-commit happened**

```bash
git log --oneline -1 -- tmp/smoke-test-prd/epics/hello-world
```

Expected: a commit message matching `Finalize epic: hello-world` (or whatever the epic name is).

**Step 5: Re-run finalize-epic to verify idempotency**

```
/finalize-epic tmp/smoke-test-prd/epics/hello-world
```

Expected: no new log entries (both slugs already present), no new commit (no diff), and a "nothing to do" report.

### Task 6.4: Smoke test cleanup decision

**Step 1: Decide whether to keep the smoke test artifacts**

Ask the user: "The smoke test created `tmp/smoke-test-prd/`. Keep it as a regression fixture, or delete it?"

**Step 2a: If keep**

Move it to a more permanent location and commit:

```bash
mkdir -p tests/fixtures
mv tmp/smoke-test-prd tests/fixtures/smoke-test-prd
git add tests/fixtures/smoke-test-prd
git rm -r --cached tmp/smoke-test-prd 2>/dev/null || true
git commit -m "Add smoke-test-prd as regression fixture"
```

**Step 2b: If delete**

```bash
rm -rf /Users/samisabir-idrissi/dev/work/AgentTeamsEpicPipelineWorkflow/tmp/smoke-test-prd
git add -u
git commit -m "Clean up smoke test artifacts"
```

### Task 6.5: Final verification

**Step 1: Confirm no remaining ClickUp references in skill files**

Use Grep with pattern `clickup|ClickUp|CLICKUP|markdown_description|list_id|clickup_get_task` against `.github/skills/`.

Expected matches:
- ZERO in any of the 6 skill folders' SKILL.md, references/*.md, or agents/openai.yaml files
- The only acceptable surviving reference is `clickup-provisioning-actions.ts` in `enrich-epic/references/enrichment-criteria.md` — that's a codebase example file path, not a ClickUp tool reference. Leave it alone.

**Step 2: If any unexpected matches remain, halt and surface them**

Report matching files and line numbers to the user. Do not call the migration done.

**Step 3: Final commit**

If everything is clean, no further commit needed — Phase 6 is verification, not modification.

Report to the user:
- Phases 0–5 complete: 5 skills updated, 1 skill renamed, 1 new references file added
- Phase 6 smoke test result: pass / fail
- Total commits: 1 baseline + 5 phase commits + (0 or 1) smoke test cleanup commit

---

## Out of scope (do not do in this plan)

These are intentionally NOT part of this plan and should be raised separately if needed:

- Implementation of skills against custom non-Copilot-CLI runtimes
- Building tooling to migrate existing ClickUp epics into local format
- A web UI or dashboard for the local store
- Multi-user collaboration features (single-user model is the design)
- A "push to GitHub Issues / Linear" alternate destination

---

## Plan Complete

Plan saved to `docs/plans/2026-04-14-local-epic-store-implementation.md`.

Two execution options:

1. **Subagent-Driven (this session)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Parallel Session (separate)** — Open a new session in this directory with executing-plans, batch execution with checkpoints.

Which approach?
