# 02 — Data Model

## Overview

The data model has two layers:
1. **Task content** — the `.md` file, written by humans or `/seed-epic`. Contains what to build.
2. **Task execution metadata** — the `.plan.md` sidecar, written by `/analyze-epic` and updated at runtime by the orchestrator. Contains how and when to build it.

Keeping these separate is a deliberate design choice. The task content must remain readable and editable by humans. The execution metadata is machine-authored and machine-updated — mixing them would make both harder to work with.

---

## Epic Folder Structure

```
epics/
├── epic-overview.md                    ← Human-readable project map
├── phase-1-foundation/
│   ├── epic-overview.md                ← Epic-level context for agents
│   ├── 01-create-schema.md             ← Task content
│   ├── 01-create-schema.plan.md        ← Task execution metadata (sidecar)
│   ├── 02-add-rls.md
│   ├── 02-add-rls.plan.md
│   ├── 03-add-api-route.md
│   └── 03-add-api-route.plan.md
├── phase-2-ui/
│   ├── epic-overview.md
│   └── ...
└── phase-3-integrations/
    └── ...
```

**Naming contract:**
- Epic folders: `phase-{N}-{slug}` — lexicographic sort determines execution order
- Task files: `{NN}-{slug}.md` — two-digit zero-padded, numbered within each epic
- Sidecar files: exact same name as task file, `.plan.md` extension

---

## The `.plan.md` Sidecar Schema

```yaml
---
# ── Identity ──────────────────────────────────────────────
task_id: "01-create-schema"          # Stem of the paired .md filename (no extension)
phase: 1                             # Execution phase assigned by topological sort (1-indexed)
epic: "phase-1-foundation"           # Parent epic folder name

# ── Dependency Graph ──────────────────────────────────────
parallel: false                      # true = safe to run concurrently in a worktree
depends_on: []                       # task_ids this task must wait on (same epic only)
blocks: ["02-add-rls"]               # task_ids that cannot start until this completes

# ── Agent Assignment ──────────────────────────────────────
agent_type: "schema-architect"       # Key into agent-registry.ts
skills: ["drizzle-database"]         # Skill names preloaded into the agent's session

# ── Worktree (parallel tasks only) ────────────────────────
worktree_branch: null                # Set by orchestrator at spawn time for parallel tasks
                                     # e.g. "feat/phase1-01-create-schema"

# ── Runtime State (written by orchestrator) ───────────────
status: "open"                       # open | in_progress | done | failed | skipped
started_at: null                     # ISO 8601 — set when status → in_progress
completed_at: null                   # ISO 8601 — set when status → done | failed | skipped
session_id: null                     # Copilot SDK session ID — enables resumeSession() on crash
retry_count: 0                       # Incremented on each retry attempt
error: null                          # Error message or stack trace if status = failed
---

<!-- Human notes and run logs below — not parsed by orchestrator -->
<!-- Example: "2026-04-18: Agent got confused by the schema import. Clarified in task file." -->
```

---

## Field Contracts

### Identity Fields

| Field | Type | Who writes it | Constraint |
|---|---|---|---|
| `task_id` | `string` | `/analyze-epic` | Must match the stem of the paired `.md` filename exactly |
| `phase` | `integer` | Orchestrator (dag-builder) | 1-indexed; computed from topological sort, not manually assigned |
| `epic` | `string` | `/analyze-epic` | Must match the parent folder name exactly |

### Dependency Fields

| Field | Type | Who writes it | Constraint |
|---|---|---|---|
| `parallel` | `boolean` | `/analyze-epic` | If `true`, `worktree_branch` will be set before spawn |
| `depends_on` | `string[]` | `/analyze-epic` | References `task_id` values within the same epic only. Cross-epic deps are not supported — enforce via epic ordering instead. |
| `blocks` | `string[]` | `/analyze-epic` | Inverse of `depends_on`. The DAG builder uses only `depends_on` as its source of truth. `blocks` is maintained for human readability. |

**Why `blocks` is redundant but kept:** When a human reads a task file, they want to know immediately what they're blocking. Forcing them to grep all other tasks for `depends_on` references is friction. The orchestrator ignores `blocks` — but it's useful for humans and for `/analyze-epic` to validate bidirectional consistency.

### Agent Fields

| Field | Type | Who writes it | Constraint |
|---|---|---|---|
| `agent_type` | `string` | `/analyze-epic` | Must resolve to a key in `agent-registry.ts`. Unknown types fall back to `general-purpose`. |
| `skills` | `string[]` | `/analyze-epic` | Each value must correspond to a folder in `.claude/skills/`. Invalid skills are silently ignored (logged but not fatal). |
| `worktree_branch` | `string \| null` | Orchestrator | Null for sequential tasks. Set to `"feat/{epic-slug}-{task_id}"` by `phase-runner.ts` immediately before spawning a parallel agent. |

### Runtime State Fields

| Field | Type | Who writes it | Constraint |
|---|---|---|---|
| `status` | `enum` | Orchestrator | Forward-only state machine. See [06-state-machine.md](./06-state-machine.md) for transitions. |
| `started_at` | `ISO 8601 \| null` | Orchestrator | Set atomically with `status → in_progress` |
| `completed_at` | `ISO 8601 \| null` | Orchestrator | Set atomically with `status → done \| failed \| skipped` |
| `session_id` | `string \| null` | Orchestrator | Stored so `recovery.ts` can attempt `client.resumeSession(sessionId)` after a crash |
| `retry_count` | `integer` | Orchestrator | Max retries is 1 by default. After max, status → failed. |
| `error` | `string \| null` | Orchestrator | The error message from the SDK event or exception. Truncated to 2000 chars. |

---

## TypeScript Types

These types live in `orchestrator.ts` and are shared across all modules:

```typescript
export type TaskStatus = "open" | "in_progress" | "done" | "failed" | "skipped";

export interface PlanMetadata {
  // Identity
  task_id: string;
  phase: number;
  epic: string;

  // Dependency graph
  parallel: boolean;
  depends_on: string[];
  blocks: string[];

  // Agent assignment
  agent_type: string;
  skills: string[];
  worktree_branch: string | null;

  // Runtime state
  status: TaskStatus;
  started_at: string | null;
  completed_at: string | null;
  session_id: string | null;
  retry_count: number;
  error: string | null;
}

export interface Task {
  taskId: string;
  mdPath: string;          // absolute path to .md file
  planPath: string;        // absolute path to .plan.md file
  content: string;         // raw content of .md file (prompt to agent)
  plan: PlanMetadata;
}

export interface Phase {
  phaseNumber: number;
  sequential: Task[];      // run in array order, one at a time
  parallel: Task[];        // run concurrently via Promise.all
}

export interface Epic {
  epicName: string;
  epicPath: string;
  overviewContent: string; // content of epic-overview.md (passed to agents as context)
  phases: Phase[];
}
```

---

## Sidecar File Lifecycle

```
/analyze-epic creates .plan.md
  status: "open"
  phase: 2
  parallel: true
  depends_on: ["01-create-schema"]
  agent_type: "rls-specialist"
        │
        ▼
orchestrator starts, recovery.ts scans all .plan.md files
  ─ status=open       → nothing to do
  ─ status=in_progress, session_id present → attempt resumeSession
  ─ status=in_progress, no session_id     → reset to open
        │
        ▼
phase-runner spawns agent
  status: "in_progress"
  started_at: "2026-04-18T10:00:00Z"
  session_id: "run-epics-phase-1-02-add-rls-1713484800000"
        │
        ▼
agent calls task_complete, sendAndWait resolves
  status: "done"
  completed_at: "2026-04-18T10:04:23Z"
```

---

## Example: A 3-Task Epic

**`01-create-schema.plan.md`** — foundation task, must go first:
```yaml
---
task_id: "01-create-schema"
phase: 1
epic: "phase-1-foundation"
parallel: false
depends_on: []
blocks: ["02-add-rls", "03-add-api-route"]
agent_type: "schema-architect"
skills: ["drizzle-database"]
worktree_branch: null
status: "open"
started_at: null
completed_at: null
session_id: null
retry_count: 0
error: null
---
```

**`02-add-rls.plan.md`** — depends on schema, can run in parallel with 03:
```yaml
---
task_id: "02-add-rls"
phase: 2
epic: "phase-1-foundation"
parallel: true
depends_on: ["01-create-schema"]
blocks: []
agent_type: "rls-specialist"
skills: []
worktree_branch: null
status: "open"
---
```

**`03-add-api-route.plan.md`** — depends on schema, can run in parallel with 02:
```yaml
---
task_id: "03-add-api-route"
phase: 2
epic: "phase-1-foundation"
parallel: true
depends_on: ["01-create-schema"]
blocks: []
agent_type: "api-builder"
skills: ["drizzle-database"]
worktree_branch: null
status: "open"
---
```

This produces:
- **Phase 1:** `01-create-schema` (sequential, runs alone)
- **Phase 2:** `02-add-rls` + `03-add-api-route` (parallel, run concurrently in worktrees)
