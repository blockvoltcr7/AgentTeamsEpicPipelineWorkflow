# Orchestration Protocol

Step-by-step algorithm for phase-based local epic execution in GitHub Copilot CLI.

The main Copilot CLI agent is the orchestrator. It may execute work directly, delegate bounded work to background sub-agents via the `task` tool (`mode: "background"`), or delegate to custom agents when appropriate. For parallel-safe phases, the orchestrator **must** spawn background sub-agents — it must not collapse to sequential execution. The orchestrator is the **single writer** to the epic's `status.log` — sub-agents never write to it directly.

## Phase Execution Protocol

### 1. RECEIVE PHASE PLAN

Parse the local epic folder to extract:
- Phase number and mode (Parallel / Sequential) — read from each task's `<NN>-<slug>.plan.md` frontmatter (`phase` and `worktree_mode`)
- Task assignments: slug, task_name, specialization, isolation mode, branch name — also from plan frontmatter
- Full task details: spec file body, acceptance criteria from `## Acceptance Criteria` section
- Current status per slug — from `status.log` (last entry per slug, sorted by timestamp)

### 2. FILTER COMPLETED

Skip any task whose current status in `status.log` is `done`. If an entire phase is `done`, skip to the next phase.

### 3. FOR EACH PHASE (in order)

#### 3a. CHOOSE EXECUTION MODE

For each task in this phase:
1. Look up the assigned specialization from the phase plan
2. Determine isolation:
   - If isolation = `worktree`, use the suggested branch and keep integration explicit
   - If isolation = `main`, execute on the current branch
3. Determine execution mode — **this rule is mandatory, not optional:**
   - If **any** task in the phase has `worktree_mode: parallel` in its plan frontmatter, OR the phase mode is `Parallel`: the orchestrator **must** spawn a background sub-agent for each parallel-safe task via the `task` tool with `mode: "background"` and `agent_type: "general-purpose"` (or a matching specialist agent). Sequential execution is not an acceptable fallback for parallel phases.
   - If **all** tasks in the phase are sequential: execute tasks directly in the main agent, one at a time.
   - If only **some** tasks in a phase are parallel-safe: spawn background sub-agents for the parallel-safe subset; execute the remainder directly.

#### 3b. START THE PHASE

Before execution starts:
1. Mark each task selected for execution as `in progress`
2. Record which tasks are being handled directly vs delegated
3. Keep the background sub-agent scope limited to the safe parallel window only — do not include sequential tasks in the parallel batch

#### 3c. MONITOR AND INTEGRATE

- Watch for blockers or integration issues
- Provide guidance when delegated work needs clarification
- Keep the main agent responsible for cross-task coherence, status.log writes, and merge decisions
- If a delegated task is stuck, either:
  1. provide more context
  2. pull the work back into the main agent
  3. escalate to the user

#### 3d. VERIFY PHASE COMPLETION

After implementation work for the phase is complete, for each task in the phase:
1. Re-read the last entry for the slug in `status.log` and confirm it is `done`
2. Confirm the acceptance criteria are actually met in the code (orchestrator inspects, not just trust the sub-agent's report)
3. Confirm any worktree spawned for the task has been merged AND cleaned up per the Worktree Lifecycle below
4. After all tasks in the phase pass, create the phase checkpoint commit

#### 3e. PROCEED

All tasks in this phase verified Done → move to next phase.

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

**Single-writer rule:** The orchestrator is the only process that ever appends to `status.log`. Background sub-agents spawned via the `task` tool report completion textually to the orchestrator, who then writes the transition. This eliminates any append race.

## Worktree Decision Rules

Read the `Merge conflict risk` from the execution strategy comment's `Notes:` section:

| Risk Level | Action |
|---|---|
| `HIGH` | Use worktree isolation and explicit integration before the next phase |
| `MEDIUM` | Prefer worktree isolation |
| `LOW` | Current branch is usually acceptable unless the phase is parallelized |
| `NONE` | Current branch is acceptable |
| Not specified | Default to current branch (safe default) |

Additionally, if the plan file frontmatter specifies `worktree_mode: parallel`, use worktree-style isolation regardless of conflict risk level when running tasks in parallel.

## Worktree Lifecycle

For each parallel-safe task spawned in a worktree, the orchestrator follows this exact sequence. Order matters — the status log append must come AFTER cleanup, so a half-merged worktree never produces a premature `done`.

1. **Spawn**
   ```bash
   git worktree add ../<epic-name>-<slug> <branch>
   ```
   Dispatch the sub-agent using the `task` tool with `mode: "background"`. Pass the worktree path and the task's spec + plan content via the Delegation Prompt Template below. Do **not** run this work inline or in the main agent — the point of the worktree spawn is parallel execution.

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
