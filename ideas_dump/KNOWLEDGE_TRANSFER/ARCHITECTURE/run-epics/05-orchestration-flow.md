# 05 — Orchestration Flow

## Full System Sequence

```
/run-epics epics/
    │
    ▼
orchestrator.ts
    │
    ├─ 1. Parse CLI args, validate epics path exists
    │
    ├─ 2. recovery.ts — scan all .plan.md files
    │     ├─ status=in_progress + session_id → attempt resumeSession()
    │     │   ├─ resume succeeds → keep in_progress, session continues
    │     │   └─ resume fails   → reset to open
    │     └─ status=in_progress + no session_id → reset to open
    │
    ├─ 3. CopilotClient.start()
    │
    ├─ 4. Discover epic folders: glob("phase-*/", {cwd: epicsPath})
    │     Sort lexicographically → ["phase-1-foundation", "phase-2-ui", "phase-3-integrations"]
    │
    └─ 5. For each epic (sequential — epic N+1 waits for epic N to finish):
          │
          ▼
          EpicExecutor
              │
              ├─ A. Read epic-overview.md (passed to all agents as context)
              │
              ├─ B. dag-builder.ts
              │     ├─ Glob all *.plan.md in epic folder
              │     ├─ Parse YAML frontmatter from each
              │     ├─ Build adjacency list from depends_on fields
              │     ├─ Validate: no cycles, all refs resolve
              │     ├─ Kahn's topological sort → Phase[]
              │     └─ Write phase numbers back to .plan.md sidecars
              │
              ├─ C. Filter done tasks (status=done → skip)
              │
              └─ D. For each Phase (sequential — phase N+1 waits for phase N):
                    │
                    ▼
                    PhaseRunner
                        │
                        ├─ Sequential tasks: for..of loop
                        │     ├─ sidecarManager.markInProgress(task, sessionId)
                        │     ├─ spawnTaskSession(client, task, epicOverview)
                        │     │   ├─ client.createSession({...})
                        │     │   ├─ session.on("session.task_complete")
                        │     │   ├─ session.sendAndWait({prompt: task.content, mode: "autopilot"})
                        │     │   └─ session.disconnect()
                        │     └─ sidecarManager.markDone/markFailed(task)
                        │
                        └─ Parallel tasks: Promise.all([...])
                              │
                              ├─ For each parallel task (all launched simultaneously):
                              │   ├─ worktreeManager.createWorktree(branch, baseBranch)
                              │   ├─ sidecarManager.markInProgress(task, sessionId)
                              │   ├─ spawnTaskSession(client, task, epicOverview, worktreePath)
                              │   └─ sidecarManager.markDone/markFailed(task)
                              │
                              └─ [PHASE GATE: await Promise.all resolves]
                                    │
                                    └─ After all parallel tasks settle:
                                          worktreeManager.mergeAll(parallelTasks)
                                          ─ fast-forward merge if possible
                                          ─ flag conflict for human if not
```

---

## Phase Gate Detail

The phase gate is the `await Promise.all(...)` call in `phase-runner.ts`. It ensures:

1. All parallel tasks in phase N are done (or failed/skipped) before phase N+1 begins
2. Worktree branches from parallel tasks are merged back before sequential tasks in the next phase run

```typescript
// phase-runner.ts — parallel phase execution
async function runParallelPhase(
  client: CopilotClient,
  tasks: Task[],
  epicOverview: string,
  baseBranch: string,
): Promise<void> {

  // Assign worktree branches before spawning
  for (const task of tasks) {
    const branch = `feat/${task.plan.epic}-${task.taskId}`;
    sidecarManager.writePlan(task.planPath, { worktree_branch: branch });
    task.plan.worktree_branch = branch;
  }

  // Spawn all parallel agents simultaneously
  const promises = tasks.map(task =>
    runTaskInWorktree(client, task, epicOverview, baseBranch)
  );

  // PHASE GATE: wait for all to settle (never throws — each catches its own errors)
  const results = await Promise.allSettled(promises);

  // Report any failures before merging
  for (let i = 0; i < results.length; i++) {
    if (results[i].status === "rejected") {
      const task = tasks[i];
      console.error(`[FAILED] Task ${task.taskId}: ${results[i].reason}`);
    }
  }

  // Merge worktrees for completed tasks
  const completedTasks = tasks.filter(t => t.plan.status === "done");
  await worktreeManager.mergeAll(completedTasks, baseBranch);
}
```

Note the use of `Promise.allSettled` instead of `Promise.all`. A failure in one parallel task should not abort the other parallel tasks in the same phase. All tasks run to completion (or failure), then the phase gate resolves, and the orchestrator decides whether to continue to phase N+1 based on the `--on-failure` flag.

---

## Epic Gate

The epic gate is implicit in the `for...of` loop over epics in `orchestrator.ts`:

```typescript
// orchestrator.ts — epic loop
for (const epicPath of sortedEpicPaths) {
  const epic = await buildEpic(epicPath);
  await epicExecutor.run(client, epic); // awaited — epic N+1 waits here
  console.log(`[DONE] Epic: ${epic.epicName}`);
}
```

`epicExecutor.run()` is async and returns only after all phases in the epic have completed (or the first phase failure with `--on-failure=abort`).

---

## Progress Output

The orchestrator emits structured progress logs to stdout at each major state transition:

```
[run-epics] Starting: 3 epics found
[run-epics] ─────────────────────────────────────
[run-epics] Epic 1/3: phase-1-foundation (4 tasks, 2 phases)
[run-epics]   Phase 1/2: 1 sequential task
[run-epics]     → [01-create-schema] schema-architect  starting...
[run-epics]     ✓ [01-create-schema] done (2m 14s)
[run-epics]   Phase 2/2: 2 parallel tasks
[run-epics]     → [02-add-rls]       rls-specialist    starting (worktree: feat/phase-1-02-add-rls)
[run-epics]     → [03-add-api-route] api-builder       starting (worktree: feat/phase-1-03-add-api-route)
[run-epics]     ✓ [02-add-rls]       done (1m 47s)
[run-epics]     ✓ [03-add-api-route] done (3m 02s)
[run-epics]   ↳ Phase 2 complete. Merging worktrees...
[run-epics]   ↳ Merged feat/phase-1-02-add-rls → main (fast-forward)
[run-epics]   ↳ Merged feat/phase-1-03-add-api-route → main (fast-forward)
[run-epics] ✓ Epic 1/3: phase-1-foundation complete (6m 03s)
[run-epics] ─────────────────────────────────────
[run-epics] Epic 2/3: phase-2-ui (6 tasks, 3 phases)
...
```

---

## Dry Run Mode

With `--dry-run`, the orchestrator builds the DAG and prints the execution plan without spawning any agents or modifying any files:

```
[dry-run] Epic 1/3: phase-1-foundation
  Phase 1 (sequential):
    01-create-schema  [schema-architect]  depends_on: []
  Phase 2 (parallel):
    02-add-rls        [rls-specialist]   depends_on: [01-create-schema]  branch: feat/phase-1-02-add-rls
    03-add-api-route  [api-builder]      depends_on: [01-create-schema]  branch: feat/phase-1-03-add-api-route
  Phase 3 (sequential):
    04-seed-data      [general-purpose]  depends_on: [02-add-rls, 03-add-api-route]

[dry-run] Total: 3 epics, 10 phases, 17 tasks (6 parallel, 11 sequential)
[dry-run] No agents were spawned.
```

Dry run exits with code 0. It is safe to run at any time without side effects.

---

## Module Dependency Map

```
run-epics.md (Claude Code command)
    │ invokes
    ▼
orchestrator.ts
    ├── uses: recovery.ts
    ├── uses: sidecar-manager.ts
    ├── creates: CopilotClient (SDK)
    └── creates: EpicExecutor
                    │
                    ├── uses: dag-builder.ts
                    │         └── uses: sidecar-manager.ts (read)
                    │
                    └── creates: PhaseRunner
                                    │
                                    ├── uses: sidecar-manager.ts (write)
                                    ├── uses: agent-registry.ts
                                    ├── uses: worktree-manager.ts
                                    └── creates: CopilotClient sessions (SDK)
```

All modules import `sidecar-manager.ts` for state reads/writes. `sidecar-manager.ts` has no dependencies on other orchestrator modules — it only depends on `js-yaml` and Node `fs`.

---

## Timing Characteristics

| Operation | Typical Duration |
|---|---|
| `CopilotClient.start()` | 1–3 seconds (CLI spawn + auth) |
| `client.createSession()` | 200–500ms |
| Sequential task (simple schema) | 2–5 minutes |
| Sequential task (complex component) | 5–15 minutes |
| Parallel phase (2 tasks) | max(task-A, task-B) duration |
| Worktree create | < 1 second |
| Worktree merge (fast-forward) | < 1 second |
| Worktree merge (with conflict) | blocked — human intervention |

For an epic with 10 tasks and good parallelization, expect 3–4x speedup over pure sequential execution.
