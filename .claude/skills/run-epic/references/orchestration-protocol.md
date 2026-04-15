# Orchestration Protocol

Step-by-step algorithm for phase-based epic execution with agent teams.

## Phase Execution Protocol

### 1. RECEIVE PHASE PLAN

The command passes a structured markdown phase plan. Parse it to extract:
- Phase number and mode (Parallel / Sequential) for each phase
- Task assignments: task_id, task_name, agent_type, isolation mode, branch name, parallel_partner (if any)
- Full task details: markdown_description, acceptance_criteria

### 2. FILTER COMPLETED

Skip any tasks already marked Done in ClickUp. If an entire phase is Done, skip to the next phase.

### 3. FOR EACH PHASE (in order)

#### 3a. SPAWN TEAMMATES

For each task in this phase:
1. Look up the assigned `agent_type` from the phase plan
2. Determine isolation:
   - If isolation = `worktree` → use `Task` tool with `isolation: "worktree"` and the branch name from the plan
   - If isolation = `main` → use `Task` tool without isolation (teammate works on current branch)
3. Pass the teammate a spawn prompt using the Teammate Spawn Prompt Template below

#### 3b. CREATE INTERNAL TASKS

Use `TaskCreate` for each spawned task to track progress within the agent team's shared task list. Assign to the teammate by name.

#### 3c. MONITOR

- Watch for teammate messages (delivered automatically via SendMessage)
- Provide guidance if a teammate asks for help
- If a teammate is stuck for more than 2 message rounds, consider:
  1. Sending additional context or debugging guidance
  2. Reassigning the task
  3. Escalating to the user

#### 3d. WAIT FOR COMPLETION

Teammates message the team lead when they finish. The orchestrator:
1. Receives completion messages automatically (no polling)
2. Marks the internal task as completed via `TaskUpdate`

#### 3e. VERIFY IN CLICKUP

After receiving all completion messages for a phase:
1. Call `clickup_get_task(task_id)` for each task
2. Confirm status is `done`
3. If a task says "done" in message but ClickUp is not updated, message the teammate to update it

#### 3f. PROCEED

All tasks in this phase verified Done → move to next phase.

### 4. CLEANUP

After all phases complete:
1. Send `shutdown_request` to each teammate via `SendMessage`
2. Wait for shutdown confirmations
3. Call `TeamDelete` to clean up team resources

## ClickUp Status Transitions

When managing task lifecycle, follow this three-state progression:

| Event | ClickUp Status |
|---|---|
| Teammate spawned for a task | Update to `in progress` |
| Teammate reports completion | Verify status is `done` |
| Teammate reports blocker | Keep as `in progress` |

The flow is always: **Open → In Progress → Done**

## Worktree Decision Rules

Read the `Merge conflict risk` from the execution strategy comment's `Notes:` section:

| Risk Level | Action |
|---|---|
| `HIGH` | Spawn with `isolation: "worktree"` using branch name from plan |
| `MEDIUM` | Spawn with `isolation: "worktree"` using branch name from plan |
| `LOW` | Teammate works on current branch (no worktree) |
| `NONE` | Teammate works on current branch (no worktree) |
| Not specified | Default to current branch (safe default) |

Additionally, if the execution strategy comment specifies `Worktree Mode: PARALLEL`, spawn with worktree isolation regardless of conflict risk level — the parallelism itself requires isolation.

## Teammate Spawn Prompt Template

Use this template when spawning each teammate via the `Task` tool:

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
   a. Update the ClickUp task status to Done: use clickup_update_task(task_id, status="done")
   b. Message the team lead: "Task {task_number} complete. All acceptance criteria met."
5. If you encounter blockers, message the team lead immediately with details
```

## Error Recovery

| Scenario | Action |
|---|---|
| Teammate reports blocker | Send debugging guidance, check if task deps are actually met |
| Teammate goes idle without completing | Send a nudge message asking for status |
| ClickUp MCP call fails | Retry once, then escalate to user |
| Worktree merge conflict | Ask teammate to resolve, or escalate to user |
| All teammates stuck in a phase | Escalate to user with summary of blockers |
