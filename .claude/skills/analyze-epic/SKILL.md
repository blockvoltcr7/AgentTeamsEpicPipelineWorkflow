# Analyze Epic — Dependency & Parallelization Analysis

> Fetches tasks from a ClickUp epic, builds a dependency graph, determines which tasks can run in parallel via git worktrees, and adds execution strategy comments to each task. This is the preparation step before `/run-epic`.

## Input

- `<args>` = The ClickUp list ID containing the epic's tasks (e.g., `901711828155`)

If no argument is provided, ask the user for the ClickUp list ID.

---

## Phase 1 — Fetch & Validate

### Step 1: Fetch all tasks

Call `clickup_search` with:
- `keywords`: leave empty
- `filters.location.subcategories`: `[$list_id]`
- `filters.asset_types`: `["task"]`

Paginate with `cursor` if `next_cursor` is returned.

### Step 2: Get full task details

For each task:
1. `clickup_get_task(task_id)` → get `name`, `status`, `markdown_description`
2. `clickup_get_task_comments(task_id)` → check for existing `EXECUTION STRATEGY` comments

### Step 3: Filter and categorize

- **Skip** tasks with status `done` or `closed` — note them as completed
- **Flag** tasks that already have an `EXECUTION STRATEGY` comment — ask user: skip, overwrite, or re-analyze all
- **Warn** about tasks missing required sections (`## Type`, `## Dependencies`) — these reduce analysis accuracy

### Step 4: Validate task descriptions

For each remaining task, check for the `clickup-task-format` template sections:

| Section | Required? | Impact if Missing |
|---|---|---|
| `## Type` | Yes | Cannot map to agent — defaults to `general-purpose` |
| `## Dependencies` | Yes | Cannot build dependency graph — treated as no dependencies |
| `## Implementation` | Recommended | Reduces file overlap detection accuracy |
| `## Technical Notes` | Optional | May miss file path references |
| `## Acceptance Criteria` | Recommended | No impact on analysis, but needed by `/run-epic` |

If critical sections are missing, warn the user and suggest reformatting with the `clickup-task-format` skill before proceeding.

---

## Phase 2 — Build Dependency Graph

### Step 5: Parse dependencies

From each task's `## Dependencies` section, extract dependency references. Tasks may reference dependencies in multiple formats:

| Format | Example | How to Resolve |
|---|---|---|
| Task ID | `86e0984uq` | Direct match |
| Task number | `Task 1.1` or `1.1` | Match against task name prefix |
| Task name | `Create ghl pgSchema` | Fuzzy match against task names in the list |

Build an adjacency list: `task_id → [depends_on_task_ids]`

### Step 6: Construct the DAG

Create a directed acyclic graph:
- **Nodes**: Each task (by task_id)
- **Edges**: A → B means "B depends on A" (A must complete before B starts)
- **Reverse edges**: Track `blocks` — for each dependency edge A → B, A blocks B

### Step 7: Validate the graph

Read `.claude/skills/analyze-epic/references/dependency-analysis.md` for the detailed validation algorithm.

Checks:
1. **Cycle detection** — If found, report the cycle and stop. User must fix task descriptions.
2. **Orphan detection** — Tasks with no dependencies AND nothing depends on them. Flag for review (may be Phase 1 candidates or may be misconfigured).
3. **External references** — Dependencies pointing to task IDs not in this list. Warn but proceed (treat as already-satisfied dependencies).

---

## Phase 3 — Determine Phases & Parallelization

### Step 8: Assign phases via topological sort

```
Phase 1: Tasks with zero in-degree (no unsatisfied dependencies)
Phase 2: Tasks whose dependencies are ALL in Phase 1
Phase N: Tasks whose dependencies are ALL in Phases < N
```

Within a single phase, if tasks have no mutual dependencies, they are parallelization CANDIDATES. Actual parallelization depends on file overlap analysis (Step 9).

### Step 9: Analyze file overlap

For each pair of tasks within the same phase, determine if they can safely run in parallel.

Read `.claude/skills/analyze-epic/references/dependency-analysis.md` for the full file overlap detection algorithm.

**Three-layer detection:**

1. **Explicit paths** — Parse `## Implementation` and `## Technical Notes` for file paths mentioned
2. **Type-based inference** — Use `## Type` to infer which files the task likely modifies:

| Task Type | Likely Files Modified | Conflict Pattern |
|---|---|---|
| `Migration` | `drizzle/migrations/XXXX_*.sql` | New files (low conflict) |
| `Migration + Drizzle Schema` | Above + `lib/drizzle/schema/{table}.ts`, `lib/drizzle/schema/index.ts` | Barrel export conflict |
| `Code (Drizzle)` | `lib/drizzle/schema/*.ts`, `lib/drizzle/schema/index.ts` | Barrel export conflict |
| `Code (React)` | `components/{feature}/*.tsx`, `app/{route}/*.tsx` | Usually isolated |
| `RLS` | `drizzle/migrations/XXXX_*.sql` | New files (low conflict) |
| `Edge Function` | `supabase/functions/{name}/*.ts` | Usually isolated |

3. **Conflict zone check** — Reference the conflict zones from `.claude/skills/clickup-task-format/references/execution-strategy.md`:
   - `lib/drizzle/schema/index.ts` (barrel exports)
   - `drizzle.config.ts` (schema list)
   - `components/layout/AppSidebar.tsx` (navigation)
   - `lib/env.ts` (environment variables)
   - `app/layout.tsx` or `app/(protected)/layout.tsx` (root layouts)

   If two tasks both modify any conflict zone file → **SEQUENTIAL, never parallel**.

### Step 10: Classify task pairs

For each pair of tasks in the same phase, apply this decision:

```
IF either task depends on the other → SEQUENTIAL
ELSE IF both touch a conflict zone file → SEQUENTIAL
ELSE IF explicit file paths overlap → SEQUENTIAL (HIGH merge conflict risk)
ELSE IF type-based inferred files overlap → SEQUENTIAL (MEDIUM merge conflict risk)
ELSE → PARALLEL (safe for worktrees)
```

Assign merge conflict risk:
- **NONE**: Tasks in different phases (sequential by design)
- **LOW**: Same phase, different file types, no overlap detected
- **MEDIUM**: Same phase, type-based inference suggests possible overlap
- **HIGH**: Same phase, explicit file path overlap or both touch conflict zones

### Step 11: Assign worktree branches

For PARALLEL tasks, derive branch names:

1. **Extract epic prefix** from the list/epic name:
   - "GHL Schema Foundation" → `ghl`
   - "User Authentication" → `auth`
   - Use the first meaningful word or abbreviation

2. **Extract task number** from task name:
   - "1.4 Create webhook events migration" → `1.4`

3. **Extract short description** from task name:
   - "1.4 Create webhook events migration" → `webhook-migration`

4. **Compose branch**: `feat/{prefix}-{number}-{short-description}`
   - Example: `feat/ghl-1.4-webhook-migration`

5. **Assign worktree slots** alternating: `WORKTREE-A`, `WORKTREE-B`

For SEQUENTIAL tasks: `Worktree Assignment: MAIN BRANCH`

---

## Phase 4 — Present Analysis

### Step 12: Build and display the analysis report

Present to the user:

```markdown
# Epic Analysis: {epic_name} (List: {list_id})

## Task Summary
- Total tasks: {N} ({M} open, {K} completed)
- Tasks to analyze: {M}

## Dependency Graph
{task_number} {task_name} ({task_id})
  → depends on: {dep_names or "None"}
  → blocks: {blocked_names or "None"}
  → type: {task_type}
  → inferred files: {file_list}

## Phase Plan

### Phase {N} — {Sequential | Parallel Window M}
| Task | ID | Mode | Branch | Conflict Risk |
|---|---|---|---|---|
| {name} | {id} | SEQ/PAR | {branch or "—"} | NONE/LOW/MED/HIGH |

## Parallelization Summary
- Phases: {N}
- Parallel windows: {M} ({K} tasks parallelizable)
- Sequential tasks: {J}
- Estimated speedup: {parallel_tasks / total_tasks * 100}% of work parallelized
```

### Step 13: Get user confirmation

Ask: "Ready to add execution strategy comments to {N} tasks? (Y to proceed, or provide adjustments)"

Present options:
1. **Proceed** — Add comments as shown
2. **Adjust** — User provides corrections (e.g., "make 1.4 and 1.5 sequential")
3. **Re-analyze** — Change a parameter and re-run analysis

**Wait for explicit confirmation before proceeding.**

---

## Phase 5 — Apply Comments & Relationships

### Step 14: Add execution strategy comments

For each task, call `clickup_create_task_comment(task_id, comment_text)` using the comment template from `.claude/skills/clickup-task-format/references/execution-strategy.md`:

```
EXECUTION STRATEGY

Phase: {N} — {Sequential | Parallel Window M}
Worktree Mode: {SEQUENTIAL | PARALLEL}
Depends On: {comma-separated task_ids, or "None"}
Blocks: {comma-separated task_ids, or "None"}
Parallelizable: {YES | NO}
Parallel Partner: {task_id, or "None"}

Notes:
- {Key implementation detail from task description}
- {File overlap risk assessment}
- Merge conflict risk: {NONE | LOW | MEDIUM | HIGH}

Worktree Assignment: {MAIN BRANCH | WORKTREE-A | WORKTREE-B} (branch: {branch_name})
```

### Step 15: Create native ClickUp dependency relationships

**CRITICAL: This step creates the native ClickUp relationships that populate the Relationships field on each task.** Without this step, dependencies only exist as text in descriptions and comments but are not visible in ClickUp's dependency tracking UI.

For each edge in the dependency graph (A blocks B / B depends on A), call `clickup_add_task_dependency`:

```
clickup_add_task_dependency(
  task_id: B,           // the task that is waiting
  depends_on: A,        // the task it depends on
  type: "waiting_on"    // B is waiting on A
)
```

**Rules:**
1. Only create relationships for edges within this epic's task list (skip external dependencies)
2. Use `type: "waiting_on"` — this is the standard direction (task B is waiting on task A to complete)
3. Do NOT create duplicate relationships — if a task already has the dependency link (check `dependencies` array from `clickup_get_task`), skip it
4. Create all relationship calls in parallel for efficiency
5. Log each relationship created: `"Linked: {B.name} waiting_on {A.name}"`

**Example for a 3-task chain:**

```
Graph: 0.1.2 → 0.1.3 (0.1.3 depends on 0.1.2)

Call:
  clickup_add_task_dependency(task_id="86e0q226v", depends_on="86e0q2246", type="waiting_on")

Result in ClickUp UI:
  Task 0.1.3 shows: Relationships → Waiting on: 0.1.2
  Task 0.1.2 shows: Relationships → Blocking: 0.1.3
```

### Step 16: Report completion

```
Analysis complete. Execution strategy comments added to {N} tasks.
Native ClickUp relationships created: {R} dependency links.

Phase summary:
- Phase 1: {task_names} (Sequential)
- Phase 2: {task_names} (Parallel Window 1)
- ...

Next step: /run-epic {list_id}
```

---

## Error Handling

| Situation | Action |
|---|---|
| No list ID provided | Ask the user for the ClickUp list ID |
| `clickup_search` returns no tasks | Report "No tasks found in list {list_id}" and stop |
| Task missing `## Type` | Warn, default type to `Code`, proceed |
| Task missing `## Dependencies` | Warn, treat as no dependencies (Phase 1 candidate) |
| Circular dependency detected | Report the cycle with task names/IDs and stop |
| All tasks already have comments | Ask user: skip all, overwrite all, or selective |
| Task description not formatted | Warn, suggest running `clickup-task-format` first |
| ClickUp API error | Retry once, then report error and stop |
| Dependency relationship already exists | Skip (do not create duplicate), log as "Already linked" |

---

## References

- Dependency analysis algorithm: `.claude/skills/analyze-epic/references/dependency-analysis.md`
- Execution strategy comment template: `.claude/skills/clickup-task-format/references/execution-strategy.md`
- Conflict zones list: `.claude/skills/clickup-task-format/references/execution-strategy.md`
- Agent mapping (downstream, for reference): `.claude/skills/run-epic/references/agent-mapping.md`
- Task formatting rules (upstream): `.claude/skills/clickup-task-format/SKILL.md`
