---
name: run-epic
description: Execute a local epic folder phase by phase using its spec files, plan sidecars, and append-only status log. Use when the user asks to run or execute an analyzed epic from a slash-command workflow in GitHub Copilot CLI. The main Copilot CLI agent acts as the orchestrator, optionally delegating bounded specialist work or using /fleet for parallel-safe phases.
---

# Run Epic

Execute an analyzed local epic folder using the spec files (`<NN>-<slug>.md`) and execution strategy plan sidecars (`<NN>-<slug>.plan.md`) produced by `enrich-epic` and `analyze-epic`. Status transitions are appended to `<epic_folder>/status.log` — the orchestrator is the only writer.

This skill is the workflow entrypoint. It should work when invoked directly from a project-scoped slash-command or skill prompt. It does not require a custom agent to be usable.

## Input

Parse one argument:
- `epic_folder_path`: path to the analyzed epic folder

If it is missing, ask for it.

Refuse to run if `status.log` is not present in the folder — that means the epic has not been finalized. Tell the user to run `finalize-epic <epic_folder_path>` first.

## Orchestration model

In GitHub Copilot CLI, the main agent should act as the orchestrator for this workflow.

- The main agent owns the phase plan, status.log writes, integration decisions, and phase gates.
- The main agent may execute work itself.
- The main agent may delegate bounded specialist tasks to subagents or custom agents when helpful.
- Use `/fleet` only for tasks that are already marked parallel-safe by the epic analysis.
- Do not rely on Claude-style team primitives or teammate-specific APIs.

If a future custom agent is added for this workflow, that agent should reference and follow this skill rather than replacing it.

## Workflow

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

### 2. Build the phase plan

Group tasks by phase and determine for each task:
- inferred execution specialization from `references/agent-mapping.md`
- isolation mode
- branch/worktree suggestion

Show the plan to the user and wait for confirmation before starting execution.

### 3. Execute phase by phase

For each phase:
- update tasks to `in progress`
- implement the tasks following their descriptions and acceptance criteria
- keep the phase sequential unless the phase is parallel-safe and the main agent chooses to use subagents or `/fleet`
- if worktrees are used, merge carefully before moving to the next phase

When delegating:
- delegate only bounded tasks with clear ownership
- keep write scopes disjoint where possible
- avoid delegating blocking work if the next step immediately depends on the result
- preserve the main agent as the single integration point for phase completion

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

After all executable tasks finish:
- verify task statuses
- summarize completed work, skipped work, and blockers

## Slash-command usage

This skill is intended to be invoked directly from a project-scoped Copilot CLI workflow. Typical usage patterns:

- Ask Copilot to "run epic `<epic_folder_path>`"
- Invoke the skill from a slash-command or skill picker
- Optionally pair it with a future custom orchestrator agent that references this skill

The skill remains the source of truth for the workflow.

## References

- `references/agent-mapping.md`
- `references/orchestration-protocol.md`
