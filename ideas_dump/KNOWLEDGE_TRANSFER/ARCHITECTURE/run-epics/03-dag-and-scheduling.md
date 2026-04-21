# 03 — DAG & Scheduling

## The Problem

Tasks within an epic have dependencies. Some tasks can only start after others finish. Some tasks have no dependencies on each other and can run concurrently. The orchestrator needs to determine the optimal execution order before it spawns a single agent.

The correct data structure for this is a **Directed Acyclic Graph (DAG)**. The correct algorithm for ordering it is a **topological sort**.

## Why a DAG

A DAG captures the partial order of tasks:
- Edge A → B means "B depends on A" (A must complete before B starts)
- Tasks with no edge between them have no ordering constraint — they are parallelization candidates
- If the graph has a cycle, the task definitions are contradictory (task A depends on B, B depends on A) — this is a fatal error that must stop execution before any agent runs

## Building the DAG

`dag-builder.ts` reads all `.plan.md` files in an epic folder and constructs an adjacency list:

```
task_id → Set<task_id>   (depends_on: task B depends on task A)
```

### Input validation

Before building the graph, validate:

1. **All `depends_on` references resolve** — every task ID in `depends_on` must correspond to an actual `.plan.md` file in the same epic folder. Unknown references are a fatal error (not a warning).

2. **No self-references** — `depends_on: ["01-create-schema"]` on `01-create-schema.plan.md` is a cycle of length 1. Catch explicitly with a better error message than the cycle detector produces.

3. **Bidirectional consistency** — if task B has `depends_on: ["01-create-schema"]`, then task A should have `blocks: ["02-add-rls"]`. Warn (not fatal) if they're inconsistent. The `depends_on` field is the authority; `blocks` is informational.

---

## Topological Sort: Kahn's Algorithm

Kahn's algorithm is used because it:
- Detects cycles as a natural side effect (if tasks remain after the sort, there's a cycle)
- Assigns phase numbers as it processes layers
- Is easy to reason about and implement correctly

```typescript
function topologicalSort(tasks: Task[]): Phase[] {
  // Build in-degree map: how many unresolved dependencies does each task have?
  const inDegree = new Map<string, number>();
  const dependents = new Map<string, string[]>(); // A → [tasks that depend on A]

  for (const task of tasks) {
    inDegree.set(task.taskId, task.plan.depends_on.length);
    for (const dep of task.plan.depends_on) {
      const list = dependents.get(dep) ?? [];
      list.push(task.taskId);
      dependents.set(dep, list);
    }
  }

  const phases: Phase[] = [];
  let remaining = new Set(tasks.map(t => t.taskId));

  while (remaining.size > 0) {
    // Tasks with zero in-degree are ready to run
    const ready = [...remaining].filter(id => inDegree.get(id) === 0);

    if (ready.length === 0) {
      // Cycle detected — find and report it
      throw new CycleError(findCycle(remaining, inDegree));
    }

    // Split ready tasks into sequential and parallel
    const readyTasks = ready.map(id => taskMap.get(id)!);
    const phase: Phase = {
      phaseNumber: phases.length + 1,
      sequential: readyTasks.filter(t => !t.plan.parallel),
      parallel:   readyTasks.filter(t => t.plan.parallel),
    };
    phases.push(phase);

    // Remove ready tasks and update in-degrees
    for (const id of ready) {
      remaining.delete(id);
      for (const dependent of dependents.get(id) ?? []) {
        inDegree.set(dependent, inDegree.get(dependent)! - 1);
      }
    }
  }

  return phases;
}
```

### Phase assignment rules

A task is assigned to phase N when all of its dependencies are in phases < N:

```
Phase 1: tasks with zero in-degree (no dependencies)
Phase 2: tasks whose ALL dependencies are in Phase 1
Phase N: tasks whose ALL dependencies are in phases < N
```

Within a single phase, tasks with `parallel: false` go into `sequential[]` and tasks with `parallel: true` go into `parallel[]`.

---

## The Phase Structure

```
Epic: phase-1-foundation
│
├── Phase 1 (sequential)
│   └── 01-create-schema        no deps, parallel: false
│
├── Phase 2 (mixed)
│   ├── sequential: []
│   └── parallel: [02-add-rls, 03-add-api-route]
│         both depend only on 01, no mutual dep, parallel: true
│
└── Phase 3 (sequential)
    └── 04-seed-data            depends on 02 AND 03, parallel: false
```

### Execution order within a phase

Within the `sequential[]` array, tasks run in their array order (which is the order they appeared in the topological sort, which is the order the DAG builder encountered them — typically filesystem sort order `01-`, `02-`, etc.).

Within the `parallel[]` array, all tasks run simultaneously via `Promise.all`. Order within the array is irrelevant.

---

## Cycle Detection

If the topological sort terminates with tasks still in `remaining`, there is a cycle. Report the cycle path clearly before throwing:

```
CycleError: Dependency cycle detected in epic phase-1-foundation

  02-add-rls → 03-add-api-route → 02-add-rls

Fix: task 03-add-api-route has depends_on: ["02-add-rls"] but 
     02-add-rls has depends_on: ["03-add-api-route"]. 
     These tasks cannot depend on each other.
```

Finding the actual cycle in the remaining subgraph: do a DFS from any node in `remaining`, tracking the path. The first back-edge found is the cycle.

---

## Parallelization Rules

Not every task marked `parallel: true` should actually run in parallel. The `parallel` field is the author's assertion from `/analyze-epic`. The orchestrator trusts it — it does not perform static file analysis.

**What the orchestrator does verify:**

1. **Mutual dependency check** — if two tasks in the same phase both appear in each other's `depends_on` (impossible by construction since they'd be in different phases), they cannot be parallel. This is caught by the DAG builder, not the parallel scheduler.

2. **Worktree branch uniqueness** — two parallel tasks cannot share the same `worktree_branch`. If they do (a bug in `/analyze-epic`), the second task's worktree creation fails. Detect this before spawning and error clearly.

**What the orchestrator trusts the author on:**

- That the tasks don't modify the same files
- That the tasks don't depend on shared mutable state at runtime

If two parallel tasks both modify `lib/drizzle/schema/index.ts`, there will be a merge conflict after the phase completes. The worktree-manager's merge step surfaces this. See [07-worktree-isolation.md](./07-worktree-isolation.md).

---

## Phase Numbers Written Back to Sidecars

After the DAG is built and phases are assigned, `epic-executor.ts` writes the computed `phase` number back to each `.plan.md` sidecar before any agent is spawned. This serves two purposes:

1. **Observability** — a human looking at `.plan.md` files can see which phase each task is in
2. **Resume support** — on a rerun, the orchestrator can skip to the right phase without re-sorting

Phase numbers from existing sidecars are **ignored during a fresh build** — the DAG is always recomputed from `depends_on` fields. This means if you change a dependency, re-running will pick it up correctly without manually updating phase numbers.

---

## Visual Example

```
Task graph (arrows = "depends on"):

  01-create-schema
        │
        ├──────────────────┐
        ▼                  ▼
  02-add-rls         03-add-api-route
  (parallel)         (parallel)
        │                  │
        └─────────┬────────┘
                  ▼
           04-seed-data
           (sequential)


Topological sort output:

  Phase 1: [01-create-schema]          sequential
  Phase 2: [02-add-rls, 03-api-route]  parallel
  Phase 3: [04-seed-data]              sequential


Execution timeline:

  t=0    Phase 1: ─── 01-create-schema ───┐
  t=4min                                  │ PHASE GATE
  t=4min Phase 2: ─── 02-add-rls ───────┐ │
         (concurrent)                   │ │
         Phase 2: ─── 03-api-route ────┐│ │
  t=7min                               ││ │ PHASE GATE
  t=7min Phase 3: ─── 04-seed-data ───┘┘ │
  t=9min EPIC DONE ───────────────────────┘
```
