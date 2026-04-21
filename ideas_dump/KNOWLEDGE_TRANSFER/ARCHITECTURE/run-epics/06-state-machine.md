# 06 — State Machine & Crash Recovery

## Task Status State Machine

Every task has a `status` field in its `.plan.md` sidecar. Status transitions are strictly forward-only — with one exception: `in_progress → open` is allowed only by `recovery.ts` on startup, when a prior session cannot be resumed.

```
                    ┌─────────────────────────────────────┐
                    │           recovery.ts only           │
                    │   (if resumeSession fails on boot)   │
                    └─────────────────────────────────────┘
                                     │
                                     ▼
   ┌──────┐   orchestrator   ┌─────────────┐   agent done   ┌──────┐
   │ open │ ────────────────► in_progress  │ ──────────────► done  │
   └──────┘  marks in_progress└─────────────┘                └──────┘
                                     │
                              agent error      ┌────────┐
                              or timeout ─────► failed  │
                                               └────────┘
                                                    │
                              --on-failure=skip      │   ┌─────────┐
                              (orchestrator) ─────────┴──► skipped │
                                                          └─────────┘
```

### Transition table

| From | To | Who | When |
|---|---|---|---|
| `open` | `in_progress` | `phase-runner.ts` | Task spawned, session created |
| `in_progress` | `done` | `phase-runner.ts` | `session.task_complete` received, `sendAndWait` resolved |
| `in_progress` | `failed` | `phase-runner.ts` | Agent error, timeout, or `sendAndWait` resolved without `task_complete` |
| `in_progress` | `open` | `recovery.ts` | Startup scan: `resumeSession` failed for this session ID |
| `failed` | `skipped` | `orchestrator.ts` | `--on-failure=skip` flag set and retry count exhausted |

### Invariants

1. **Forward-only except recovery.** No code other than `recovery.ts` may set status to a "lower" state.
2. **`done` is terminal.** A task with `status: done` is never re-executed. The orchestrator skips it.
3. **`failed` triggers retry.** Before marking a task permanently failed, the orchestrator retries once (if `retry_count < 1`). On retry, the sidecar is updated: `retry_count += 1`, `status → open`, then immediately back to `in_progress` as the task is re-spawned.
4. **`skipped` means "acknowledged failure."** The orchestrator moved on. A skipped task means downstream tasks that depend on it may also be skipped or may fail.

---

## Crash Recovery Protocol

`recovery.ts` runs at orchestrator startup, before any agents are spawned. It reads all `.plan.md` files across all epics in the run and handles orphaned in-progress tasks from a prior crashed run.

```typescript
// recovery.ts
export async function recoverOrphanedTasks(
  client: CopilotClient,
  epicsPaths: string[],
): Promise<void> {

  const allPlans = await findAllPlanFiles(epicsPaths);
  const inProgress = allPlans.filter(p => p.plan.status === "in_progress");

  for (const task of inProgress) {
    if (task.plan.session_id) {
      const resumed = await tryResumeSession(client, task);
      if (resumed) {
        console.log(`[recovery] Resumed session for ${task.taskId}`);
        // Session is live — phase-runner will pick it up
        continue;
      }
    }
    // Can't resume — reset to open
    sidecarManager.writePlan(task.planPath, {
      status: "open",
      session_id: null,
      started_at: null,
    });
    console.log(`[recovery] Reset ${task.taskId} → open (session not resumable)`);
  }
}

async function tryResumeSession(
  client: CopilotClient,
  task: Task,
): Promise<boolean> {
  try {
    await client.resumeSession(task.plan.session_id!);
    return true;
  } catch {
    return false;
  }
}
```

### What happens to resumed sessions

If a session resumes successfully, the agent picks up where it left off. The orchestrator does not re-send the task prompt — the session has the full conversation history. The orchestrator simply waits for the existing session to complete.

However: the normal `phase-runner.ts` execution path spawns new sessions via `spawnTaskSession()`. Resuming a session requires different handling. The orchestrator must track which tasks have live resumed sessions and not attempt to spawn them again.

```typescript
// In epic-executor.ts, after recovery:
const resumedSessionIds = new Set(
  recoveredTasks
    .filter(t => t.plan.status === "in_progress") // still in_progress = resumed
    .map(t => t.plan.session_id!)
);

// In phase-runner.ts, skip tasks with active sessions:
if (task.plan.status === "in_progress" && task.plan.session_id) {
  // Session is already live from recovery — attach and wait
  const session = await client.getSession(task.plan.session_id);
  await session.waitForIdle();
} else {
  // Normal spawn
  await spawnTaskSession(client, task, epicOverview, worktreePath);
}
```

---

## Atomic Sidecar Writes

All writes to `.plan.md` files go through `sidecarManager`, which writes atomically:

```typescript
// sidecar-manager.ts
export function writePlan(planPath: string, updates: Partial<PlanMetadata>): void {
  const current = readPlan(planPath);
  const updated = { ...current, ...updates };

  const yamlContent = yaml.dump(updated);
  const body = extractMarkdownBody(planPath); // content below --- ... ---
  const newContent = `---\n${yamlContent}---\n\n${body}`;

  const tmpPath = planPath + ".tmp";
  fs.writeFileSync(tmpPath, newContent, "utf8");
  fs.renameSync(tmpPath, planPath); // atomic on POSIX
}
```

`fs.renameSync` is atomic on POSIX systems. If the process crashes between `writeFileSync` and `renameSync`, the original `.plan.md` is untouched — only the `.tmp` file is lost. A leftover `.tmp` file is safe to delete on next startup.

### Write failure policy

If a sidecar write fails (disk full, permissions, etc.), the orchestrator logs the error but does NOT abort the agent's work. The agent's code output is more valuable than the metadata. The risk is that the task will appear as `in_progress` on the next run (since the `done` write failed), triggering a recovery attempt. The recovery will find a dead session and reset to `open`, causing a re-run. This is acceptable — it's better to re-run a completed task than to lose code output.

---

## Retry Logic

```typescript
// In phase-runner.ts
async function runTaskWithRetry(
  client: CopilotClient,
  task: Task,
  epicOverview: string,
  maxRetries: number = 1,
): Promise<void> {

  let attempts = task.plan.retry_count; // resume from last known count

  while (attempts <= maxRetries) {
    try {
      await runTask(client, task, epicOverview);
      return; // success
    } catch (err) {
      attempts++;
      sidecarManager.writePlan(task.planPath, {
        retry_count: attempts,
        error: err.message,
      });

      if (attempts > maxRetries) {
        sidecarManager.markFailed(task.planPath, err.message);
        throw err; // let phase-runner handle --on-failure
      }

      console.warn(`[retry] Task ${task.taskId} failed, attempt ${attempts}/${maxRetries + 1}`);
    }
  }
}
```

A single retry is the default. Retrying more than once rarely helps — if an agent failed twice on the same task, the task likely has a problem that more attempts won't fix (bad instructions, unreachable file, model confusion on ambiguous prompt). Log and move on.

---

## Resumability Across Runs

The combination of `status` fields and `session_id` means the orchestrator can always answer: "What work is left to do?" by reading the sidecar files.

```
Run 1: tasks 01, 02, 03 queued
  01 → done
  02 → in_progress (crash at t=4min)
  03 → open

Run 2: recovery.ts scans
  01 → done         → skip
  02 → in_progress  → attempt resumeSession
                      fails (session expired) → reset to open
  03 → open         → skip (not yet reached in phase order)

  Execution resumes:
  Phase 1: 01 → already done, skip
  Phase 2: 02 → spawn fresh, 03 → spawn fresh (both parallel)
```

This behavior makes `run-epics` idempotent: running it twice produces the same end state, with already-completed tasks skipped.
