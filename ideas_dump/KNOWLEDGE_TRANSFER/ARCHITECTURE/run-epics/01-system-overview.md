# 01 — System Overview

## Purpose

`run-epics` is the execution layer of the AI-driven development pipeline. It sits at the end of the pipeline after tasks have been defined, enriched, and annotated with execution metadata.

Its sole job: **take a folder of well-defined tasks and drive AI agents to implement them in the correct order, as fast as possible.**

## Pipeline Position

```
/seed-prd          Generate PRD from conversation context
    │
/seed-epic         Break PRD into epics + task .md files
    │
/enrich-epic       Add implementation detail to each task
    │
/analyze-epic      Annotate tasks with dependency + parallelization metadata
    │
/run-epics  ◄──── THIS SYSTEM
    │
    ▼
    Code committed to feature branches
```

`run-epics` is a consumer, not a producer. It does not decide what tasks to run, what order makes sense, or what agent should handle each task. All of that was determined upstream and encoded into `.plan.md` sidecar files. This system reads those files and acts on them.

## Goals

1. **Process epics in order.** Epic N+1 does not start until epic N is fully complete.
2. **Within each epic, execute phases in topological order.** Phase M+1 does not start until all tasks in phase M are done.
3. **Within each phase, run parallel tasks concurrently.** Tasks marked `parallel: true` with no mutual dependencies run simultaneously in isolated git worktrees.
4. **Be resumable.** If the process crashes or is killed, re-running it must pick up from where it left off — not restart from scratch.
5. **Be observable.** Every state transition writes to the sidecar file. A human can check the status of any task at any time by reading its `.plan.md`.

## Non-Goals

- **Does not decide task order.** The `depends_on` / `blocks` fields in `.plan.md` are the authority. The system reads them; it does not compute them from code analysis.
- **Does not retry indefinitely.** One retry per failed task. After that, mark failed and continue (or abort, depending on `--on-failure` flag).
- **Does not resolve merge conflicts automatically.** When parallel worktrees produce conflicting changes, the system flags the conflict for human resolution and stops.
- **Does not create tasks.** If a task file doesn't exist, it doesn't run.
- **Does not talk to ClickUp, Jira, or any external tracker.** The file system is the only data store.

## System Boundaries

```
┌─────────────────────────────────────────────────────────┐
│                      run-epics                          │
│                                                         │
│  Inputs:                                                │
│  ─ epics/ folder path                                   │
│  ─ task .md files (implementation instructions)        │
│  ─ .plan.md sidecar files (execution metadata)         │
│                                                         │
│  Outputs:                                               │
│  ─ Code changes committed to git branches              │
│  ─ .plan.md status fields updated                      │
│  ─ Progress logs to stdout                             │
│                                                         │
│  External dependencies:                                │
│  ─ GitHub Copilot Agent SDK (CopilotClient)            │
│  ─ git (worktree management)                           │
│  ─ Copilot CLI (spawned by SDK, not directly called)   │
└─────────────────────────────────────────────────────────┘
```

## Invocation

```bash
# Via Claude Code command
/run-epics ai_docs/clickup/docs/my-project/epics/

# Direct invocation
npx tsx .claude/commands/run-epics/orchestrator.ts \
  --epics-path ai_docs/clickup/docs/my-project/epics/ \
  --on-failure skip \
  --dry-run
```

### Flags

| Flag | Default | Description |
|---|---|---|
| `--epics-path` | required | Path to the root epics folder |
| `--on-failure` | `abort` | `skip` continues to next task; `abort` stops the entire run |
| `--dry-run` | false | Print the execution plan (phase DAG) without running agents |
| `--epic` | all | Run a single named epic (e.g. `--epic phase-2-ui`) |
| `--from-task` | none | Skip all tasks before this task ID in the current epic |

## What "Done" Looks Like

A successful run produces:
- All task `.plan.md` files have `status: done`
- All feature branches have been merged back to the base branch (for parallel worktree tasks)
- A final summary printed to stdout:

```
═══════════════════════════════════════
  run-epics complete
  Epics processed: 3
  Tasks completed: 17
  Tasks skipped:   0
  Tasks failed:    0
  Duration:        14m 32s
═══════════════════════════════════════
```
