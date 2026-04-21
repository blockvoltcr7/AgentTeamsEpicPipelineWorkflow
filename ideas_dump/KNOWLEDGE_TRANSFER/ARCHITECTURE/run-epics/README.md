# run-epics — Architecture Documentation

> **Author perspective:** AI Harness Engineer  
> **Last updated:** 2026-04-18  
> **Status:** Approved for implementation

## What This Is

`run-epics` is a file-based autonomous epic execution system. It reads a folder of epics (each epic is a folder of task markdown files), determines the correct execution order from their dependency metadata, and drives a team of specialist AI sub-agents to implement each task — sequentially or in parallel — using the GitHub Copilot Agent SDK as the execution engine.

There is no external task tracker. ClickUp, Jira, Linear — none of it. The task files on disk are the source of truth. The system is designed to run headlessly in CI or locally, resume from crashes, and produce real code changes as output.

## Why This Architecture

The core insight is that **task dependency graphs are DAGs, and DAGs have a well-known optimal execution strategy**: topological sort into phases, then within each phase run independent tasks concurrently. The only question is how to operationalize that in an AI agent system.

The answer is:

- **The sidecar `.plan.md` file** is the execution contract between the human who designed the tasks and the machine that runs them. It carries the dependency graph, the agent assignment, and the live execution state.
- **The Copilot Agent SDK** is the execution engine. It provides the sub-agent primitives (`createSession`, `sendAndWait`, worktree isolation) that map directly onto "run this task in isolation."
- **`Promise.all` on a shared `CopilotClient`** is the parallel execution mechanism. One CLI process, many concurrent sessions.

## Document Index

| # | Document | What It Covers |
|---|---|---|
| [01](./01-system-overview.md) | System Overview | Goals, non-goals, system boundaries, pipeline position |
| [02](./02-data-model.md) | Data Model | `.plan.md` sidecar schema, Epic and Task types, field contracts |
| [03](./03-dag-and-scheduling.md) | DAG & Scheduling | Dependency graph construction, topological sort, phase assignment, conflict zones |
| [04](./04-agent-execution.md) | Agent Execution | Agent registry, spawn protocol, skill preloading, completion signals |
| [05](./05-orchestration-flow.md) | Orchestration Flow | Full execution sequence with diagrams, phase gates, epic gates |
| [06](./06-state-machine.md) | State Machine | Task status transitions, crash recovery, resume protocol |
| [07](./07-worktree-isolation.md) | Worktree Isolation | Git worktree strategy, branch naming, merge protocol |
| [08](./08-implementation-plan.md) | Implementation Plan | Build sequence, file structure, task breakdown with code |

## Quick Mental Model

```
Input:  epics/ folder (markdown task files + .plan.md sidecars)
        │
        ▼
        dag-builder       reads depends_on/blocks → topological sort → Phase[]
        │
        ▼
        phase-runner      sequential tasks: one-at-a-time sessions
                          parallel tasks:   Promise.all([session-A, session-B, ...])
        │
        ▼
        sub-agents        each runs in a git worktree (if parallel)
                          reads task .md, implements, calls task_complete
        │
        ▼
Output: code changes committed to feature branches, .plan.md status fields updated
```

## Key Design Decisions (Summary)

| Decision | Choice |
|---|---|
| Task metadata format | YAML frontmatter sidecar (`.plan.md`) |
| Orchestrator runtime | TypeScript script (`npx tsx orchestrator.ts`) invoked by a Claude Code command |
| Parallel wait strategy | SDK `sendAndWait()` + `session.task_complete` event — no polling |
| State persistence | Sidecar `status` field with atomic write — enables crash recovery |
| Agent isolation | Git worktrees per parallel task — prevents branch conflicts |
| One vs many CLI processes | One `CopilotClient`, many `createSession()` calls — single CLI process |

## File Location

```
os-hq-platform/
├── .claude/
│   ├── commands/
│   │   ├── run-epics.md              ← /run-epics Claude Code command
│   │   └── run-epics/
│   │       ├── orchestrator.ts
│   │       ├── epic-executor.ts
│   │       ├── dag-builder.ts
│   │       ├── phase-runner.ts
│   │       ├── agent-registry.ts
│   │       ├── sidecar-manager.ts
│   │       ├── worktree-manager.ts
│   │       └── recovery.ts
│   └── skills/
│       └── (specialist agent skills)
└── docs/
    └── architecture/
        └── run-epics/               ← You are here
```
