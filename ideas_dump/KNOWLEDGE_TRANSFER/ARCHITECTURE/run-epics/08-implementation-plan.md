# 08 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `run-epics` orchestration system that processes epic folders sequentially, runs tasks in dependency order, and spawns parallel sub-agents for concurrent tasks.

**Architecture:** TypeScript orchestrator invoked via a Claude Code command. One `CopilotClient` for the entire run. DAG-based scheduling with phase gates. Atomic sidecar writes for crash recovery.

**Tech Stack:** TypeScript, `tsx` runtime, `js-yaml` for frontmatter parsing, GitHub Copilot Agent SDK (`@github/copilot-sdk`), `gray-matter` for YAML frontmatter, Node.js `fs`, `path`, `child_process` (via `execFileNoThrow`).

---

## File Structure

```
os-hq-platform/
├── .claude/
│   ├── commands/
│   │   ├── run-epics.md                  ← Claude Code command entry point
│   │   └── run-epics/
│   │       ├── orchestrator.ts           ← Entry point: arg parsing, client lifecycle, epic loop
│   │       ├── epic-executor.ts          ← Per-epic: DAG build, phase iteration
│   │       ├── dag-builder.ts            ← Topological sort, cycle detection, phase assignment
│   │       ├── phase-runner.ts           ← Sequential loop + Promise.allSettled for parallel
│   │       ├── agent-registry.ts         ← agent_type → CustomAgentConfig mapping
│   │       ├── sidecar-manager.ts        ← Atomic read/write of .plan.md YAML frontmatter
│   │       ├── worktree-manager.ts       ← git worktree create/merge/remove via execFileNoThrow
│   │       ├── recovery.ts              ← Startup: reset stale in_progress, clean stale worktrees
│   │       └── types.ts                 ← Shared TypeScript types (PlanMetadata, Task, Phase, Epic)
│   └── skills/
│       ├── drizzle-database/SKILL.md
│       ├── rls-policies/SKILL.md
│       └── edge-functions/SKILL.md
└── docs/
    └── architecture/
        └── run-epics/                    ← This documentation
```

---

## Task 1: Shared Types

**Files:**
- Create: `.claude/commands/run-epics/types.ts`

- [ ] **Step 1: Write the types file**

```typescript
// types.ts
export type TaskStatus = "open" | "in_progress" | "done" | "failed" | "skipped";

export interface PlanMetadata {
  task_id: string;
  phase: number;
  epic: string;
  parallel: boolean;
  depends_on: string[];
  blocks: string[];
  agent_type: string;
  skills: string[];
  worktree_branch: string | null;
  status: TaskStatus;
  started_at: string | null;
  completed_at: string | null;
  session_id: string | null;
  retry_count: number;
  error: string | null;
}

export interface Task {
  taskId: string;
  mdPath: string;
  planPath: string;
  content: string;
  plan: PlanMetadata;
}

export interface Phase {
  phaseNumber: number;
  sequential: Task[];
  parallel: Task[];
}

export interface Epic {
  epicName: string;
  epicPath: string;
  overviewContent: string;
  phases: Phase[];
}

export interface MergeResult {
  merged: string[];
  conflicts: string[];
}

export interface OrchestratorConfig {
  epicsPath: string;
  onFailure: "abort" | "skip";
  dryRun: boolean;
  epicFilter?: string;
  fromTask?: string;
}
```

- [ ] **Step 2: Commit**

```bash
git add .claude/commands/run-epics/types.ts
git commit -m "feat(run-epics): add shared TypeScript types"
```

---

## Task 2: Sidecar Manager

**Files:**
- Create: `.claude/commands/run-epics/sidecar-manager.ts`
- Test: (inline validation — read what you wrote, verify round-trip)

- [ ] **Step 1: Install dependencies**

```bash
cd os-hq-platform && npm install gray-matter
```

- [ ] **Step 2: Write sidecar-manager.ts**

```typescript
// sidecar-manager.ts
import matter from "gray-matter";
import * as fs from "fs";
import * as path from "path";
import type { PlanMetadata, TaskStatus } from "./types.js";

export function planPathFromMdPath(mdPath: string): string {
  return mdPath.replace(/\.md$/, ".plan.md");
}

export function readPlan(planPath: string): PlanMetadata {
  const raw = fs.readFileSync(planPath, "utf8");
  const { data } = matter(raw);
  return data as PlanMetadata;
}

export function writePlan(planPath: string, updates: Partial<PlanMetadata>): void {
  const raw = fs.readFileSync(planPath, "utf8");
  const parsed = matter(raw);
  const updated = { ...parsed.data, ...updates };

  const newContent = matter.stringify(parsed.content, updated);
  const tmpPath = planPath + ".tmp";

  fs.writeFileSync(tmpPath, newContent, "utf8");
  fs.renameSync(tmpPath, planPath); // atomic on POSIX
}

export function markInProgress(planPath: string, sessionId: string): void {
  writePlan(planPath, {
    status: "in_progress",
    started_at: new Date().toISOString(),
    session_id: sessionId,
  });
}

export function markDone(planPath: string): void {
  writePlan(planPath, {
    status: "done",
    completed_at: new Date().toISOString(),
  });
}

export function markFailed(planPath: string, error: string): void {
  writePlan(planPath, {
    status: "failed",
    completed_at: new Date().toISOString(),
    error: error.slice(0, 2000),
  });
}

export function findAllPlanFiles(rootPath: string): string[] {
  const results: string[] = [];
  for (const entry of fs.readdirSync(rootPath, { withFileTypes: true })) {
    const full = path.join(rootPath, entry.name);
    if (entry.isDirectory()) results.push(...findAllPlanFiles(full));
    else if (entry.name.endsWith(".plan.md")) results.push(full);
  }
  return results;
}
```

- [ ] **Step 3: Verify round-trip manually**

Create a test sidecar `test.plan.md` with status `open`, call `markInProgress`, read it back, assert `status === "in_progress"`. Delete test file.

- [ ] **Step 4: Commit**

```bash
git add .claude/commands/run-epics/sidecar-manager.ts
git commit -m "feat(run-epics): add atomic sidecar manager"
```

---

## Task 3: DAG Builder

**Files:**
- Create: `.claude/commands/run-epics/dag-builder.ts`

- [ ] **Step 1: Write dag-builder.ts**

```typescript
// dag-builder.ts
import * as fs from "fs";
import * as path from "path";
import * as sidecarManager from "./sidecar-manager.js";
import type { Task, Phase } from "./types.js";

export class CycleError extends Error {
  constructor(cycle: string[]) {
    super(`Dependency cycle detected: ${cycle.join(" → ")}`);
  }
}

export function buildDag(epicPath: string, taskFiles: string[]): Phase[] {
  const tasks: Task[] = taskFiles.map(mdPath => {
    const planPath = sidecarManager.planPathFromMdPath(mdPath);
    const plan = sidecarManager.readPlan(planPath);
    return {
      taskId: plan.task_id,
      mdPath,
      planPath,
      content: fs.readFileSync(mdPath, "utf8"),
      plan,
    };
  });

  const taskMap = new Map(tasks.map(t => [t.taskId, t]));

  // Validate all depends_on references resolve
  for (const task of tasks) {
    for (const dep of task.plan.depends_on) {
      if (!taskMap.has(dep)) {
        throw new Error(
          `Task "${task.taskId}" has depends_on: ["${dep}"] but no task with that ID exists in ${epicPath}`
        );
      }
    }
  }

  // Kahn's algorithm
  const inDegree = new Map<string, number>();
  const dependents = new Map<string, string[]>();

  for (const task of tasks) {
    inDegree.set(task.taskId, task.plan.depends_on.length);
    for (const dep of task.plan.depends_on) {
      const list = dependents.get(dep) ?? [];
      list.push(task.taskId);
      dependents.set(dep, list);
    }
  }

  const phases: Phase[] = [];
  const remaining = new Set(tasks.map(t => t.taskId));

  while (remaining.size > 0) {
    const ready = [...remaining].filter(id => inDegree.get(id) === 0);

    if (ready.length === 0) {
      throw new CycleError(findCycle(remaining, inDegree, dependents));
    }

    const readyTasks = ready.map(id => taskMap.get(id)!);
    phases.push({
      phaseNumber: phases.length + 1,
      sequential: readyTasks.filter(t => !t.plan.parallel),
      parallel: readyTasks.filter(t => t.plan.parallel),
    });

    for (const id of ready) {
      remaining.delete(id);
      for (const dep of dependents.get(id) ?? []) {
        inDegree.set(dep, inDegree.get(dep)! - 1);
      }
    }
  }

  return phases;
}

function findCycle(
  remaining: Set<string>,
  inDegree: Map<string, number>,
  dependents: Map<string, string[]>,
): string[] {
  // DFS from first node in remaining to find the cycle path
  const visited = new Set<string>();
  const path: string[] = [];

  function dfs(node: string): string[] | null {
    if (path.includes(node)) return [...path.slice(path.indexOf(node)), node];
    if (visited.has(node)) return null;
    visited.add(node);
    path.push(node);
    for (const next of dependents.get(node) ?? []) {
      if (remaining.has(next)) {
        const cycle = dfs(next);
        if (cycle) return cycle;
      }
    }
    path.pop();
    return null;
  }

  return dfs([...remaining][0]) ?? [...remaining];
}
```

- [ ] **Step 2: Validate with a 3-task chain**

Build a test epic folder with 3 plan files: `01` → `02` and `03` (both depend on `01`, both `parallel: true`). Call `buildDag`. Assert:
- `phases.length === 2`
- `phases[0].sequential[0].taskId === "01"`
- `phases[1].parallel` has 2 tasks

- [ ] **Step 3: Validate cycle detection**

Add a plan file where `02` depends on `03` and `03` depends on `02`. Assert `buildDag` throws `CycleError`.

- [ ] **Step 4: Commit**

```bash
git add .claude/commands/run-epics/dag-builder.ts
git commit -m "feat(run-epics): DAG builder with Kahn topological sort and cycle detection"
```

---

## Task 4: Agent Registry

**Files:**
- Create: `.claude/commands/run-epics/agent-registry.ts`

- [ ] **Step 1: Write agent-registry.ts**

```typescript
// agent-registry.ts
export interface CustomAgentConfig {
  name: string;
  displayName: string;
  description: string;
  tools: string[];
  prompt: string;
}

export const AGENT_REGISTRY: Record<string, CustomAgentConfig> = {
  "schema-architect": {
    name: "schema-architect",
    displayName: "Schema Architect",
    description: "Creates database schemas, Drizzle ORM files, and SQL migrations",
    tools: ["view", "edit", "create_file", "bash", "grep", "glob"],
    prompt: "You are a database schema specialist. You design Drizzle ORM schemas and SQL migrations. Follow patterns in lib/drizzle/schema/. Always update barrel exports when creating new schema files.",
  },
  "rls-specialist": {
    name: "rls-specialist",
    displayName: "RLS Specialist",
    description: "Writes Row Level Security policies for Supabase/PostgreSQL",
    tools: ["view", "edit", "create_file", "bash", "grep", "glob"],
    prompt: "You are a Row Level Security specialist for Supabase/PostgreSQL. Write secure, performant RLS policies following existing policy patterns in this codebase.",
  },
  "api-builder": {
    name: "api-builder",
    displayName: "API Builder",
    description: "Builds Next.js server actions and API routes",
    tools: ["view", "edit", "create_file", "bash", "grep", "glob"],
    prompt: "You are a Next.js API specialist. Build server actions and API routes following patterns in app/actions/. Handle auth guards, error responses, and type safety.",
  },
  "ui-engineer": {
    name: "ui-engineer",
    displayName: "UI Engineer",
    description: "Builds React components and Next.js pages",
    tools: ["view", "edit", "create_file", "bash", "grep", "glob"],
    prompt: "You are a React/Next.js UI specialist. Build components following patterns in components/ and app/(protected)/. Use Tailwind CSS and shadcn/ui.",
  },
  "integration-specialist": {
    name: "integration-specialist",
    displayName: "Integration Specialist",
    description: "Handles external API integrations and Supabase Edge Functions",
    tools: ["view", "edit", "create_file", "bash", "grep", "glob"],
    prompt: "You are an integration specialist. Build Supabase Edge Functions and external API integrations following existing patterns.",
  },
  "general-purpose": {
    name: "general-purpose",
    displayName: "General Purpose",
    description: "Fallback agent for unrecognized task types",
    tools: ["view", "edit", "create_file", "bash", "grep", "glob"],
    prompt: "You are a full-stack TypeScript developer. Implement the task as described, following existing patterns in the codebase.",
  },
};

export function resolveAgentConfig(agentType: string): CustomAgentConfig {
  const config = AGENT_REGISTRY[agentType];
  if (!config) {
    console.warn(`[agent-registry] Unknown agent_type "${agentType}" — falling back to general-purpose`);
    return AGENT_REGISTRY["general-purpose"];
  }
  return config;
}
```

- [ ] **Step 2: Commit**

```bash
git add .claude/commands/run-epics/agent-registry.ts
git commit -m "feat(run-epics): agent registry with 5 specialist types"
```

---

## Task 5: Worktree Manager

**Files:**
- Create: `.claude/commands/run-epics/worktree-manager.ts`

- [ ] **Step 1: Write worktree-manager.ts**

```typescript
// worktree-manager.ts
import * as path from "path";
import * as fs from "fs";
import { execFileNoThrow } from "../../utils/execFileNoThrow.js";
import type { MergeResult } from "./types.js";

const WORKTREE_ROOT = ".git/worktrees/run-epics";

export async function createWorktree(branch: string, baseBranch: string): Promise<string> {
  const slug = branch.replace(/\//g, "-");
  const worktreePath = path.resolve(WORKTREE_ROOT, slug);

  if (await branchExists(branch)) {
    await removeWorktree(branch, false);
  }

  fs.mkdirSync(path.resolve(WORKTREE_ROOT), { recursive: true });

  const result = await execFileNoThrow("git", [
    "worktree", "add", worktreePath, "-b", branch, baseBranch
  ]);

  if (result.status !== 0) {
    throw new Error(`Failed to create worktree for ${branch}: ${result.stderr}`);
  }

  return worktreePath;
}

export async function removeWorktree(branch: string, deleteBranch: boolean): Promise<void> {
  const slug = branch.replace(/\//g, "-");
  const worktreePath = path.resolve(WORKTREE_ROOT, slug);

  await execFileNoThrow("git", ["worktree", "remove", worktreePath, "--force"]);
  if (deleteBranch) {
    await execFileNoThrow("git", ["branch", "-d", branch]);
  }
}

export async function branchExists(branch: string): Promise<boolean> {
  const result = await execFileNoThrow("git", ["branch", "--list", branch]);
  return result.stdout.trim().length > 0;
}

export async function mergeAll(branches: string[], baseBranch: string): Promise<MergeResult> {
  const merged: string[] = [];
  const conflicts: string[] = [];

  await execFileNoThrow("git", ["checkout", baseBranch]);

  for (const branch of branches) {
    const result = await execFileNoThrow("git", ["merge", "--ff-only", branch]);
    if (result.status === 0) {
      merged.push(branch);
      await removeWorktree(branch, true);
    } else {
      conflicts.push(branch);
      console.error(`[worktree] Conflict merging ${branch}: ${result.stderr}`);
    }
  }

  return { merged, conflicts };
}
```

- [ ] **Step 2: Commit**

```bash
git add .claude/commands/run-epics/worktree-manager.ts
git commit -m "feat(run-epics): git worktree manager using execFileNoThrow"
```

---

## Task 6: Recovery Module

**Files:**
- Create: `.claude/commands/run-epics/recovery.ts`

- [ ] **Step 1: Write recovery.ts**

```typescript
// recovery.ts
import * as sidecarManager from "./sidecar-manager.js";
import * as worktreeManager from "./worktree-manager.js";

export async function recoverOrphanedTasks(
  epicsPaths: string[],
  resumeSession: (sessionId: string) => Promise<boolean>,
): Promise<void> {
  const allPlanFiles = epicsPaths.flatMap(sidecarManager.findAllPlanFiles);
  const inProgress = allPlanFiles.filter(p => {
    const plan = sidecarManager.readPlan(p);
    return plan.status === "in_progress";
  });

  for (const planPath of inProgress) {
    const plan = sidecarManager.readPlan(planPath);
    let resumed = false;

    if (plan.session_id) {
      try {
        resumed = await resumeSession(plan.session_id);
      } catch {
        resumed = false;
      }
    }

    if (!resumed) {
      sidecarManager.writePlan(planPath, {
        status: "open",
        session_id: null,
        started_at: null,
      });
      console.log(`[recovery] Reset ${plan.task_id} → open`);
    } else {
      console.log(`[recovery] Resumed session for ${plan.task_id}`);
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add .claude/commands/run-epics/recovery.ts
git commit -m "feat(run-epics): startup recovery for crashed in-progress tasks"
```

---

## Task 7: Phase Runner

**Files:**
- Create: `.claude/commands/run-epics/phase-runner.ts`

- [ ] **Step 1: Write phase-runner.ts**

```typescript
// phase-runner.ts
import * as path from "path";
import * as sidecarManager from "./sidecar-manager.js";
import * as worktreeManager from "./worktree-manager.js";
import { resolveAgentConfig } from "./agent-registry.js";
import type { Phase, Task, OrchestratorConfig } from "./types.js";

function buildSessionId(task: Task): string {
  return `run-epics-${task.plan.epic}-${task.taskId}-${Date.now()}`;
}

function buildSystemPrompt(epicOverview: string, task: Task): string {
  return `## Epic Context\n\n${epicOverview}\n\n## Your Role\n\nYou are implementing task ${task.taskId} in epic ${task.plan.epic}.\nAgent type: ${task.plan.agent_type}.\n\n## Completion Signal\n\nWhen all acceptance criteria are met, call task_complete with a one-sentence summary. If blocked, call task_complete with "BLOCKED: {reason}".`;
}

async function spawnTaskSession(
  client: any,
  task: Task,
  epicOverview: string,
  worktreePath: string | null,
): Promise<void> {
  const sessionId = buildSessionId(task);
  const agentConfig = resolveAgentConfig(task.plan.agent_type);

  const session = await client.createSession({
    sessionId,
    workingDirectory: worktreePath ?? process.cwd(),
    customAgents: [agentConfig],
    agent: agentConfig.name,
    skillDirectories: [
      path.resolve(".claude/skills"),
      path.resolve(".claude/commands/run-epics/skills"),
    ],
    onPermissionRequest: async () => ({ kind: "approved" }),
    systemMessage: { content: buildSystemPrompt(epicOverview, task) },
  });

  sidecarManager.markInProgress(task.planPath, sessionId);

  let taskCompleted = false;
  session.on("session.task_complete", () => { taskCompleted = true; });

  await session.sendAndWait({ prompt: task.content, mode: "autopilot" });

  if (taskCompleted) {
    sidecarManager.markDone(task.planPath);
  } else {
    sidecarManager.markFailed(task.planPath, "Agent completed without task_complete signal");
  }

  await session.disconnect();
}

export async function runPhase(
  client: any,
  phase: Phase,
  epicOverview: string,
  config: OrchestratorConfig,
  baseBranch: string,
): Promise<void> {
  console.log(`[run-epics]   Phase ${phase.phaseNumber}: ${phase.sequential.length} sequential, ${phase.parallel.length} parallel`);

  // Sequential tasks — one at a time
  for (const task of phase.sequential) {
    if (task.plan.status === "done") {
      console.log(`[run-epics]     ↷ [${task.taskId}] already done, skipping`);
      continue;
    }
    console.log(`[run-epics]     → [${task.taskId}] ${task.plan.agent_type}`);
    try {
      await spawnTaskSession(client, task, epicOverview, null);
      console.log(`[run-epics]     ✓ [${task.taskId}] done`);
    } catch (err: any) {
      sidecarManager.markFailed(task.planPath, err.message);
      if (config.onFailure === "abort") throw err;
      console.error(`[run-epics]     ✗ [${task.taskId}] failed: ${err.message}`);
    }
  }

  // Parallel tasks — Promise.allSettled
  if (phase.parallel.length > 0) {
    const pendingParallel = phase.parallel.filter(t => t.plan.status !== "done");

    for (const task of pendingParallel) {
      const branch = `feat/${task.plan.epic}-${task.taskId}`;
      sidecarManager.writePlan(task.planPath, { worktree_branch: branch });
      task.plan.worktree_branch = branch;
    }

    const promises = pendingParallel.map(async task => {
      console.log(`[run-epics]     → [${task.taskId}] ${task.plan.agent_type} (worktree: ${task.plan.worktree_branch})`);
      const worktreePath = await worktreeManager.createWorktree(task.plan.worktree_branch!, baseBranch);
      await spawnTaskSession(client, task, epicOverview, worktreePath);
      console.log(`[run-epics]     ✓ [${task.taskId}] done`);
    });

    // PHASE GATE
    const results = await Promise.allSettled(promises);

    for (let i = 0; i < results.length; i++) {
      if (results[i].status === "rejected") {
        const task = pendingParallel[i];
        sidecarManager.markFailed(task.planPath, (results[i] as PromiseRejectedResult).reason?.message ?? "unknown");
        if (config.onFailure === "abort") throw new Error(`Task ${task.taskId} failed`);
      }
    }

    // Merge worktrees
    const completedBranches = pendingParallel
      .filter(t => t.plan.worktree_branch && sidecarManager.readPlan(t.planPath).status === "done")
      .map(t => t.plan.worktree_branch!);

    if (completedBranches.length > 0) {
      const { conflicts } = await worktreeManager.mergeAll(completedBranches, baseBranch);
      if (conflicts.length > 0 && config.onFailure === "abort") {
        throw new Error(`Merge conflicts in branches: ${conflicts.join(", ")}`);
      }
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add .claude/commands/run-epics/phase-runner.ts
git commit -m "feat(run-epics): phase runner with sequential loop and parallel Promise.allSettled"
```

---

## Task 8: Epic Executor + Orchestrator

**Files:**
- Create: `.claude/commands/run-epics/epic-executor.ts`
- Create: `.claude/commands/run-epics/orchestrator.ts`
- Create: `.claude/commands/run-epics.md`

- [ ] **Step 1: Write epic-executor.ts**

```typescript
// epic-executor.ts
import * as fs from "fs";
import * as path from "path";
import { buildDag } from "./dag-builder.js";
import { runPhase } from "./phase-runner.js";
import * as sidecarManager from "./sidecar-manager.js";
import type { Epic, OrchestratorConfig } from "./types.js";

export async function runEpic(
  client: any,
  epic: Epic,
  config: OrchestratorConfig,
  baseBranch: string,
): Promise<void> {
  console.log(`[run-epics] Epic: ${epic.epicName} (${epic.phases.reduce((a, p) => a + p.sequential.length + p.parallel.length, 0)} tasks)`);

  // Write computed phase numbers back to sidecars
  for (const phase of epic.phases) {
    for (const task of [...phase.sequential, ...phase.parallel]) {
      sidecarManager.writePlan(task.planPath, { phase: phase.phaseNumber });
    }
  }

  for (const phase of epic.phases) {
    await runPhase(client, phase, epic.overviewContent, config, baseBranch);
  }
}

export function buildEpic(epicPath: string): Epic {
  const epicName = path.basename(epicPath);
  const overviewPath = path.join(epicPath, "epic-overview.md");
  const overviewContent = fs.existsSync(overviewPath)
    ? fs.readFileSync(overviewPath, "utf8")
    : `Epic: ${epicName}`;

  const taskFiles = fs.readdirSync(epicPath)
    .filter(f => f.endsWith(".md") && !f.endsWith(".plan.md") && f !== "epic-overview.md")
    .sort()
    .map(f => path.join(epicPath, f));

  const phases = buildDag(epicPath, taskFiles);

  return { epicName, epicPath, overviewContent, phases };
}
```

- [ ] **Step 2: Write orchestrator.ts**

```typescript
// orchestrator.ts
import * as fs from "fs";
import * as path from "path";
import { CopilotClient } from "@github/copilot-sdk";
import { recoverOrphanedTasks } from "./recovery.js";
import { buildEpic, runEpic } from "./epic-executor.js";
import type { OrchestratorConfig } from "./types.js";

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const config: OrchestratorConfig = {
    epicsPath: args.find(a => !a.startsWith("--")) ?? "",
    onFailure: args.includes("--on-failure=skip") ? "skip" : "abort",
    dryRun: args.includes("--dry-run"),
    epicFilter: args.find(a => a.startsWith("--epic="))?.split("=")[1],
  };

  if (!config.epicsPath || !fs.existsSync(config.epicsPath)) {
    console.error("Usage: orchestrator.ts <epics-path> [--on-failure=skip] [--dry-run]");
    process.exit(1);
  }

  const epicFolders = fs.readdirSync(config.epicsPath, { withFileTypes: true })
    .filter(e => e.isDirectory() && e.name.startsWith("phase-"))
    .sort((a, b) => a.name.localeCompare(b.name))
    .map(e => path.join(config.epicsPath, e.name))
    .filter(p => !config.epicFilter || path.basename(p) === config.epicFilter);

  if (config.dryRun) {
    for (const epicPath of epicFolders) {
      const epic = buildEpic(epicPath);
      console.log(`[dry-run] ${epic.epicName}`);
      for (const phase of epic.phases) {
        console.log(`  Phase ${phase.phaseNumber}:`);
        for (const t of phase.sequential) console.log(`    SEQ  ${t.taskId} [${t.plan.agent_type}]`);
        for (const t of phase.parallel)   console.log(`    PAR  ${t.taskId} [${t.plan.agent_type}]`);
      }
    }
    return;
  }

  const client = new CopilotClient();
  await client.start();

  await recoverOrphanedTasks(
    epicFolders,
    async (sessionId) => { try { await client.resumeSession(sessionId); return true; } catch { return false; } }
  );

  const baseBranch = "main";

  for (const epicPath of epicFolders) {
    const epic = buildEpic(epicPath);
    await runEpic(client, epic, config, baseBranch);
    console.log(`[run-epics] ✓ Epic complete: ${epic.epicName}`);
  }

  await client.stop();
  console.log("[run-epics] All epics complete.");
}

main().catch(err => {
  console.error("[run-epics] Fatal:", err.message);
  process.exit(1);
});
```

- [ ] **Step 3: Write run-epics.md Claude Code command**

```markdown
---
description: Execute epics from a local folder using AI sub-agents. Processes epics in order, runs tasks sequentially or in parallel based on .plan.md metadata.
argument-hint: <path-to-epics-folder>
---

Run the epic execution orchestrator.

Usage: /run-epics <epics-folder-path>

Flags:
  --on-failure=skip   Continue past failed tasks (default: abort)
  --dry-run           Print execution plan without running agents
  --epic=<name>       Run only the named epic folder

This command executes:
  npx tsx .claude/commands/run-epics/orchestrator.ts "$ARGUMENTS"
```

- [ ] **Step 4: Commit**

```bash
git add .claude/commands/run-epics/epic-executor.ts .claude/commands/run-epics/orchestrator.ts .claude/commands/run-epics.md
git commit -m "feat(run-epics): orchestrator, epic executor, and Claude Code command entry point"
```

---

## Task 9: End-to-End Validation

- [ ] **Step 1: Create synthetic test epic**

```bash
mkdir -p /tmp/test-epics/phase-1-test
```

Create `01-task-a.md` (content: "Create a file called output-a.txt with content 'done-a'")
Create `01-task-a.plan.md`:
```yaml
---
task_id: "01-task-a"
phase: 1
epic: "phase-1-test"
parallel: false
depends_on: []
blocks: ["02-task-b"]
agent_type: "general-purpose"
skills: []
worktree_branch: null
status: "open"
started_at: null
completed_at: null
session_id: null
retry_count: 0
error: null
---
```

Repeat for `02-task-b.md` with `depends_on: ["01-task-a"]` and `03-task-c.md` / `04-task-d.md` with both parallel and depending on `02-task-b`.

- [ ] **Step 2: Run dry-run**

```bash
npx tsx .claude/commands/run-epics/orchestrator.ts /tmp/test-epics --dry-run
```

Expected output shows 3 phases with correct sequential/parallel grouping.

- [ ] **Step 3: Run live**

```bash
npx tsx .claude/commands/run-epics/orchestrator.ts /tmp/test-epics
```

Verify all `.plan.md` files end with `status: done`.

- [ ] **Step 4: Final commit**

```bash
git add .
git commit -m "feat(run-epics): complete orchestration system with DAG scheduling, parallel agents, and crash recovery"
```
