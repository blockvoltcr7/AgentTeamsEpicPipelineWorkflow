# Execution Strategy Comment Template

## Comment Template

Add this comment to every task in the OS HQ Dashboard folder:

```
EXECUTION STRATEGY

Phase: [1 | 2 | 3 | ...] — [Sequential | Parallel Window N]
Worktree Mode: [SEQUENTIAL | PARALLEL]
Depends On: [Task IDs that must be Done, or "None"]
Blocks: [Task IDs waiting on this one]
Parallelizable: [YES | NO]
Parallel Partner: [Task ID that runs simultaneously, if parallel]

Notes:
- [Key implementation detail]
- [File overlap risk assessment]
- [Merge conflict risk: NONE | LOW | MEDIUM | HIGH]

Worktree Assignment: [MAIN BRANCH | WORKTREE-A | WORKTREE-B] (branch: feat/ghl-X.X-description)
```

## Decision Rules

### Before Starting a Task

1. Fetch the task: `clickup_get_task(task_id)`
2. Read its comments: `clickup_get_task_comments(task_id)`
3. Find the execution strategy comment
4. Apply these rules:

| Worktree Mode | Action |
|---------------|--------|
| `SEQUENTIAL` | Work on the main feature branch. Do NOT create a worktree. |
| `PARALLEL` | Create a git worktree with the branch name from Worktree Assignment. |
| No strategy comment | Treat as **SEQUENTIAL** (safe default). |

### Before Marking Parallel

Two tasks can be marked PARALLEL only if:
- They share the same `Depends On` (both unblocked at the same time)
- They do NOT modify the same files (zero file overlap)
- Neither depends on the other

### Common Conflict Zones (Never Parallel)

These files are shared infrastructure. Two tasks that both modify any of these must be SEQUENTIAL:

- `lib/drizzle/schema/index.ts` (barrel exports)
- `drizzle.config.ts` (schema list)
- `components/layout/AppSidebar.tsx` (navigation)
- `lib/env.ts` (environment variables)
- `app/layout.tsx` or `app/(protected)/layout.tsx` (root layouts)

### Parallel Completion Protocol

When finishing a parallel task:
1. Mark task `Done` in ClickUp
2. Check if the `Parallel Partner` task is also `Done`
3. If both done: merge both worktree branches to the feature branch
4. Next phase's tasks are now unblocked

### When Creating New Tasks

Always add an execution strategy comment immediately after creation:
1. Determine which phase the task belongs to
2. Identify `Depends On` and `Blocks` by reading the roadmap or epic plan
3. Check for file overlap with sibling tasks to determine if PARALLEL is safe
4. Assign worktree branch name if parallel
