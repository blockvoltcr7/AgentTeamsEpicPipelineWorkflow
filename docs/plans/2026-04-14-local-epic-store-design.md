# Local Epic Store — Replacing ClickUp with Local File Storage

**Date:** 2026-04-14
**Status:** Design approved, ready for implementation planning
**Scope:** `.github/skills/` epic pipeline

---

## Context

The `.github/skills/` epic pipeline currently has 5 of its 6 skills tightly coupled to ClickUp:

```
seed-prd → seed-epic → push-epic-to-clickup → enrich-epic → analyze-epic → run-epic
```

ClickUp acts as four things at once: task store, dependency graph, comment thread for execution metadata, and a status state machine. Only `seed-prd` and `seed-epic` are ClickUp-free today.

We need to deploy this pipeline in organizations that don't have ClickUp access. The replacement must:

- Keep the same pipeline shape and the same skill responsibilities
- Use only local files in the project
- Be backed by git for change tracking and rollback (single-user model — git is **not** the sync layer)
- Preserve the orchestrator-spawns-fleet model for parallel-safe phases via GitHub Copilot CLI native `/fleet` (not Claude teammate APIs)

## Decisions

Five structural decisions, in the order they were made:

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Sync model | Git for change tracking and rollback only. Single user. | Simpler than multi-user; rollback is the value, not collaboration. |
| 2 | Task identity | Slug-based (filename minus `^\d+-` prefix). Numeric prefix is sort-only. | Matches existing seed-epic convention with one tweak; grep-friendly; no opaque ID ceremony. |
| 3 | Spec ↔ plan separation | Sidecar `<NN>-<slug>.plan.md` per task | 1:1 mirror of ClickUp's description/comment split; physically prevents re-analysis from corrupting enriched specs. |
| 4 | Status state machine | Append-only `status.log` per epic, last-entry-per-slug wins | Free audit history; tiny diffs; trivial parser; safe under crash. |
| 5 | `push-epic-to-clickup` replacement | New skill `finalize-epic` in the same pipeline slot | Preserves the explicit "freeze the spec" checkpoint between drafting and execution. |

## Directory Layout

Per-PRD epic folders stay where `seed-epic` already puts them: under `{prd_path}/epics/`.

```
{prd_path}/epics/
├── epic-overview.md                   ← seed-time: index of all epics in this PRD
└── auth-epic/                         ← one folder per epic
    ├── epic-overview.md               ← title, summary, generated status table at bottom
    ├── status.log                     ← append-only state machine (only run-epic writes here)
    ├── 01-setup-auth.md               ← spec  (written by seed, edited by enrich)
    ├── 01-setup-auth.plan.md          ← plan  (written by analyze, rewritten on re-analyze)
    ├── 02-add-login.md
    ├── 02-add-login.plan.md
    ├── 03-add-logout.md
    └── 03-add-logout.plan.md
```

Three load-bearing properties:

1. **`status.log` is the only file `run-epic` writes to.** Spec files and plan files are read-only during execution.
2. **`.plan.md` files only exist after `analyze-epic` has run.** Their absence is a meaningful signal — `run-epic` warns and falls back to conservative sequential execution.
3. **`epic-overview.md` has a generated status table** delimited by HTML comments, regenerated from `status.log` on every status append. The log is truth; the table is a hint for humans.

## File Formats

### Spec file — `<NN>-<slug>.md`

No frontmatter. Body sections only. The only change from today is `## Dependencies` syntax — slug-based, with optional `epic-folder/` prefix for cross-epic references:

```markdown
# Add Login

## Type
feature

## Context
...

## Implementation
...

## Acceptance Criteria
- [ ] User can log in with email + password
- [ ] Session persists across reloads

## Dependencies
- Depends On: setup-auth
- Depends On: shared-infra-epic/provision-redis

## Technical Notes
Effort: M
Priority: high
```

`Effort` and `Priority` stay in `## Technical Notes` as plain lines (matching how `push-epic-to-clickup` parses them today).

### Plan file — `<NN>-<slug>.plan.md`

YAML frontmatter for structured fields `run-epic` reads, plus a free-text body for human-readable rationale. Frontmatter lives here (not on spec files) because plans are machine-generated and machine-consumed; specs are human-edited.

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

### Status log — `status.log`

One event per line. Plain text, space-delimited, ISO 8601 timestamp. Last entry per slug wins. Blockers are same-state transitions with a trailing `#` note.

```
2026-04-14T12:00:00Z setup-auth nil->open
2026-04-14T12:00:00Z add-login nil->open
2026-04-14T12:00:00Z add-logout nil->open
2026-04-14T14:30:00Z setup-auth open->in_progress
2026-04-14T14:52:14Z setup-auth in_progress->done
2026-04-14T14:52:30Z add-login open->in_progress
2026-04-14T15:14:02Z add-login in_progress->in_progress # blocker: waiting on API key from ops
2026-04-14T15:48:11Z add-login in_progress->done
```

Plain text over JSONL because: (a) humans grep this file during debugging, (b) git diffs stay readable, (c) the parser is `split(' ', 3)`.

The parser sorts entries by timestamp before computing current state. File position is meaningless for correctness.

### Epic overview — `epic-overview.md`

Human-authored top, machine-regenerated table at the bottom delimited by HTML comments. Anything outside the markers is human-owned and never touched:

```markdown
# Auth Epic

Goal: ship email/password auth with session persistence.

## Scope
...

<!-- STATUS-TABLE-START — generated by run-epic, do not edit by hand -->
| #  | Slug         | Type    | Status      | Updated              |
|----|--------------|---------|-------------|----------------------|
| 01 | setup-auth   | feature | done        | 2026-04-14T14:52:14Z |
| 02 | add-login    | feature | in_progress | 2026-04-14T15:14:02Z |
| 03 | add-logout   | feature | open        | —                    |
<!-- STATUS-TABLE-END -->
```

## Skill Changes

### Summary

| Skill | Change scale | What changes |
|---|---|---|
| `seed-prd` | None | Already ClickUp-free |
| `seed-epic` | Trivial | Update task template's `## Dependencies` example to slug syntax; change handoff text to `finalize-epic` |
| `push-epic-to-clickup` | **Renamed → `finalize-epic`** | New role: validate locally and freeze the spec |
| `enrich-epic` | I/O swap | `list_id` → `epic_folder_path`; read/write `*.md` files instead of ClickUp tasks |
| `analyze-epic` | I/O swap + sidecar writes | `list_id` → `epic_folder_path`; write `*.plan.md` files; dependency parser switches to slug matching |
| `run-epic` | Logic + I/O | `list_id` → `epic_folder_path`; status state machine moves to `status.log`; explicit worktree lifecycle |

### `finalize-epic` (replaces `push-epic-to-clickup`)

**Input:** `epic_folder_path` only.

**Workflow:**

1. **Read the epic.** Load `epic-overview.md` and every `<NN>-<slug>.md` task file.
2. **Validate structure.** Each task must have `## Type`, `## Context`, `## Acceptance Criteria`, `## Dependencies`. Warn-not-fail on missing `## Implementation` / `## Technical Notes` (enrich-epic populates them next).
3. **Validate slugs.** No two task files in this epic may resolve to the same slug. Hard fail on duplicates with both file paths shown.
4. **Validate dependencies.** Every `Depends On: <slug>` must resolve to an existing task file in this epic or a referenced epic folder. Detect cycles in the seed-time DAG. Hard fail on dangling refs or cycles.
5. **Initialize state.** Create `status.log` if absent. Seed it with `nil->open` lines for each task. If re-running, only append entries for tasks not already present.
6. **Generate the overview status table.** Write the `<!-- STATUS-TABLE-START -->`...`<!-- STATUS-TABLE-END -->` block.
7. **Auto-commit.** `git add` the epic folder and commit with `Finalize epic: <name>`. (No prompt; commit is automatic per design decision.)
8. **Handoff.** Report validation results, task count, and next step: `enrich-epic <epic_folder_path>`.

**Re-run behavior:** Idempotent. Re-validates everything. Adds `nil->open` entries only for new tasks. Auto-commits only if there's a real diff.

### `enrich-epic` — I/O swap

Existing 6-step workflow stays intact. Only step 1 ("Load task and PRD context") and step 4 ("Enrich the chosen tasks") change their I/O target:

- **Step 1:** `Glob` for `<epic_folder>/*.md`, exclude `epic-overview.md` and `*.plan.md`. Read each.
- **Step 4:** For each chosen task, `Edit` the spec file in place. Replace the body wholesale (matching today's `markdown_description` overwrite semantics).
- **Auto-commit** at the end of the enrichment session with `Enrich epic: <name> (<N> tasks updated)`.

**What it never touches:** `*.plan.md` (don't exist yet at this point), `status.log` (every task is still `open`), `epic-overview.md` (enrichment doesn't change structure).

The scoring rubric (Critical / Needs Enrichment / Adequate), the user interaction, and the cross-check pass are unchanged. References file (`enrichment-criteria.md`) needs only a one-word edit ("ClickUp tasks" → "task files").

### `analyze-epic` — I/O swap + sidecar writes

- **Dependency parser:** today it grep-matches ClickUp ID patterns like `86e0984uq` inside backticks; locally it grep-matches slugs against the set of known task filenames in the epic. Cross-epic refs require a folder lookup. Cycle/orphan/external-ref detection is unchanged.
- **Output:** instead of writing a ClickUp comment per task, write `<NN>-<slug>.plan.md` per task with the YAML frontmatter format above.
- **Re-run safety:** because plans live in sidecars, re-analyze just `Write`s the `.plan.md` files. Spec files are never touched. The current "surgical comment replacement" logic disappears — that's a real simplification.
- `references/dependency-analysis.md` needs its parsing examples rewritten and the broken external reference to `.claude/skills/clickup-task-format/...` either repointed or inlined.

### `run-epic` — biggest behavior change

This is the only skill where the state machine lives, so it's the only one with non-trivial new logic.

- **Status read:** parse `status.log`, sort by timestamp, group by slug, take last entry per slug. Tasks at `done` are skipped.
- **Status write:** every transition is a single `append` to `status.log`. After each append, regenerate the status table block in `epic-overview.md` from the log.
- **Phase plan:** read `*.plan.md` frontmatter for `phase`, `worktree_mode`, `conflict_risk`, `branch`. Group by phase. Present to user, wait for confirmation. Same as today.
- **Blocker handling:** append `<slug> in_progress->in_progress # blocker: <reason>`.
- **Auto-commit at phase boundaries:** after every phase completes successfully (worktrees merged, cleaned up, status.log appended), commit with `Run epic <name>: phase <N> complete (<M> tasks done)`. One commit per phase, never per task.
- **Crash recovery:** on startup, detect any `in_progress` slug without a terminal entry. Show the user the last clean checkpoint commit and offer:
  - (a) mark as completed — work was actually done
  - (b) mark as abandoned — append `in_progress->open`, retry later
  - (c) roll back to the checkpoint commit and rerun this phase
- **Error recovery table** (in `references/orchestration-protocol.md`) loses the row "ClickUp MCP call fails → retry once, escalate." Replaced with: "Status log append fails → check disk/permissions, never retry blindly." Adds: "Worktree cleanup fails after successful merge → warn user with worktree path, leave in place, continue (task is done)."
- **`clickup_get_task` calls** in the orchestration protocol are replaced with status log re-reads. Verification of "is the task actually done" stays the same — read the spec's `## Acceptance Criteria`, check the work, then append `done`.

## Worktree Lifecycle for Parallel Sub-Agents

The orchestration model is **unchanged** from today: the root agent (GitHub Copilot CLI main agent) is the orchestrator, and sub-agents are spawned only when the analyzer marked a phase parallel-safe, and only via Copilot CLI's native `/fleet`. No Claude teammate APIs.

What changes is that with local `status.log` we have to be explicit about two rules the ClickUp model enforced implicitly.

### Rule 1: Single writer to `status.log` — always the orchestrator

Sub-agents spawned via `/fleet` **never append to `status.log` directly**. They report completion textually back to the orchestrator. The orchestrator is the only process that ever writes to the log. This eliminates any append race between parallel sub-agents.

The delegation prompt template in `orchestration-protocol.md` is updated to say explicitly: "Do not write to status.log. Report your completion (or blocker) textually to the orchestrator. The orchestrator owns all status transitions."

### Rule 2: Explicit worktree lifecycle — spawn, merge, cleanup, log

For each parallel-safe task spawned in a worktree, the orchestrator follows this exact sequence:

1. **Spawn** — `git worktree add ../{epic-name}-{slug} {branch}` and dispatch the sub-agent with the worktree path and the task's spec + plan content.
2. **Wait for completion report** — sub-agent reports done/blocked/failed textually. Sub-agent does not touch `status.log`.
3. **Verify acceptance criteria** — orchestrator inspects the worktree's changes against the spec's `## Acceptance Criteria`.
4. **Merge** — orchestrator merges the worktree's branch back into the parent branch. Conflicts: resolve in main agent or escalate to user.
5. **Cleanup** — `git worktree remove ../{epic-name}-{slug}` and `git branch -d {branch}`. If cleanup itself fails, warn but don't fail the task — the work is merged, leave a note for the user to clean manually.
6. **Append to `status.log`** — only now does the orchestrator write the `in_progress->done` transition. Order matters: log append happens AFTER successful merge AND cleanup, so a half-merged worktree never produces a premature `done`.
7. **Phase commit** — once ALL parallel tasks in the phase have completed steps 1–6, the orchestrator creates the single phase checkpoint commit.

This sequence lives in `run-epic/references/orchestration-protocol.md` as a new "Worktree Lifecycle" subsection. Existing protocol sections (worktree decision rules, delegation template, error recovery) stay.

## Edge Cases & Error Handling

### Crash mid-execution — task stuck at `in_progress`

`run-epic` crashes mid-task. The log shows `<slug> open->in_progress` with no following terminal entry.

**Handling:** on next invocation, run-epic detects this and prompts the user with the three-option recovery flow described in the `run-epic` section above. No automatic recovery — the user is the source of truth for "did the work actually happen."

### Duplicate slugs across files in the same epic

Two files like `01-add-login.md` and `07-add-login.md` produce the same slug.

**Handling:** `finalize-epic` step 3 hard-fails until duplicates are resolved. Both file paths are shown.

### Dangling dependencies discovered after finalize

Someone deletes or renames a task file after `finalize-epic` passed.

**Handling:** both `analyze-epic` and `run-epic` re-validate the dependency graph at startup. Hard fail on dangling refs. Recovery is "re-run finalize-epic" or restore the file.

### Idempotency of re-runs

| Skill | Re-run behavior |
|---|---|
| `seed-epic` | Refuses to overwrite an existing epic folder unless `--force` is passed |
| `finalize-epic` | Idempotent. Re-validates everything. Adds `nil->open` log entries only for new tasks. Regenerates overview table. Auto-commits only if there's a real diff |
| `enrich-epic` | Replaces spec body wholesale per chosen task. Auto-commits the resulting diff. Lost manual edits recoverable via git |
| `analyze-epic` | Rewrites `*.plan.md` files. Spec files untouched by physical impossibility |
| `run-epic` | Idempotent against `status.log`. Tasks at `done` are skipped. Mid-epic resume works |

### Smaller cases

- **Missing `status.log`** when running enrich/analyze/run → "epic not finalized — run `finalize-epic <epic_folder>` first." Strict gate.
- **Missing `*.plan.md`** when running run-epic → warn and fall back to conservative sequential execution.
- **Lenient log parser** → unparseable lines in `status.log` are skipped with a warning, never crash. Last-good-entry-per-slug wins.
- **Atomic log appends** → write + read-back-tail verification. Never retry a partial append (could double-write).

## Rollback Pattern

Git's role in this design is **change tracking and rollback only**. To return an epic to an earlier state:

```
git log --oneline -- {epic_folder}        # find the checkpoint commit
git checkout <commit> -- {epic_folder}    # restore just the epic folder
# Resume by re-running run-epic — it reads status.log and resumes
# from wherever the rolled-back state left off.
```

Every checkpoint commit (`Finalize epic`, `Enrich epic`, `Run epic phase N complete`) is a valid rollback target. This pattern lives in a new `run-epic/references/rollback.md`.

## What Doesn't Change

Worth being explicit about, because it shrinks the perceived scope:

- All 6 skills' high-level workflows (numbered steps) stay structurally identical
- The user-facing interaction model stays identical (present plan → wait for confirmation → execute → report)
- Agent-mapping rules (`## Type` → specialization) in `run-epic/references/agent-mapping.md` are unchanged except for one sentence
- Worktree decision rules (the conflict-risk → action table) are unchanged
- Phase execution protocol structure is unchanged (only "Worktree Lifecycle" subsection is added)
- Delegation prompt template is unchanged (only one sentence added: "Do not write to status.log")
- `agents/openai.yaml` files just need their `short_description` and `default_prompt` strings updated to drop the word "ClickUp"

## Out of Scope

- Multi-user collaboration on the same epic (single-user model — git is for rollback, not sync)
- Migration tooling for epics that already live in ClickUp (this design is for new orgs without ClickUp; existing ClickUp epics stay where they are)
- A "push to GitHub Issues / Linear / other remote" alternate destination (YAGNI — no concrete target system requested)
- A web UI or dashboard for the local store (markdown + git history is the UI)
