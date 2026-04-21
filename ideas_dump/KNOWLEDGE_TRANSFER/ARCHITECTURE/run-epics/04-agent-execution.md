# 04 — Agent Execution

## The Execution Model

Each task maps to one AI agent session. The orchestrator spawns the session, sends the task content as the initial prompt, waits for the agent to signal completion, then tears down the session. The agent never runs longer than its task requires.

The GitHub Copilot Agent SDK is the execution engine. It handles:
- Spawning the Copilot CLI subprocess
- Routing messages between the orchestrator and the agent
- Providing the built-in tools (`bash`, `view`, `edit`, `create_file`, `grep`, `glob`)
- Enforcing `task_complete` via autopilot mode nudging

---

## One `CopilotClient`, Many Sessions

This is the critical architectural constraint.

```
CopilotClient  (one instance, one CLI process, entire run)
    │
    ├── session: run-epics-phase1-01-create-schema   (sequential)
    │
    ├── session: run-epics-phase2-02-add-rls         (parallel)  ─┐
    ├── session: run-epics-phase2-03-api-route       (parallel)  ─┤ Promise.all
    │                                                             ─┘
    └── session: run-epics-phase3-04-seed-data       (sequential)
```

**Why one client:** The `CopilotClient` spawns the Copilot CLI as a child process. Multiple clients = multiple CLI processes = multiplied memory, auth handshake overhead, and port allocation. The SDK is designed for one client with concurrent sessions on top of it.

**Session concurrency:** The SDK multiplexes sessions over a single JSON-RPC connection to the CLI. From the CLI's perspective, multiple sessions are just concurrent agent loops. From the orchestrator's perspective, each session is an independent `Promise<void>` that resolves when the agent finishes.

---

## Agent Registry

`agent-registry.ts` maps `agent_type` strings to `CustomAgentConfig` objects. These are the specialist personas available to tasks.

```typescript
// agent-registry.ts

export const AGENT_REGISTRY: Record<string, CustomAgentConfig> = {

  "schema-architect": {
    name: "schema-architect",
    displayName: "Schema Architect",
    description: "Creates database schemas, Drizzle ORM files, and migrations",
    tools: ["view", "edit", "create_file", "bash", "grep", "glob"],
    prompt: `You are a database schema specialist. You design and implement 
             database schemas using Drizzle ORM. You follow the existing 
             patterns in lib/drizzle/schema/. You always update barrel exports 
             when creating new schema files.`,
  },

  "rls-specialist": {
    name: "rls-specialist",
    displayName: "RLS Specialist",
    description: "Writes Row Level Security policies for Supabase/PostgreSQL",
    tools: ["view", "edit", "create_file", "bash", "grep", "glob"],
    prompt: `You are a Row Level Security specialist. You write RLS policies 
             that are performant, secure, and follow the existing policy 
             patterns in this codebase.`,
  },

  "api-builder": {
    name: "api-builder",
    displayName: "API Builder",
    description: "Builds Next.js server actions and API routes",
    tools: ["view", "edit", "create_file", "bash", "grep", "glob"],
    prompt: `You are a Next.js API specialist. You build server actions and 
             API routes following the patterns in app/actions/. You handle 
             auth guards, error responses, and type safety.`,
  },

  "ui-engineer": {
    name: "ui-engineer",
    displayName: "UI Engineer",
    description: "Builds React components and Next.js pages",
    tools: ["view", "edit", "create_file", "bash", "grep", "glob"],
    prompt: `You are a React/Next.js UI specialist. You build components 
             following the patterns in components/ and app/(protected)/. 
             You use Tailwind CSS and shadcn/ui components.`,
  },

  "integration-specialist": {
    name: "integration-specialist",
    displayName: "Integration Specialist",
    description: "Handles external API integrations and edge functions",
    tools: ["view", "edit", "create_file", "bash", "grep", "glob"],
    prompt: `You are an integration specialist. You build Supabase Edge 
             Functions and external API integrations.`,
  },

  "general-purpose": {
    name: "general-purpose",
    displayName: "General Purpose",
    description: "Fallback agent for tasks that don't match a specialist",
    tools: ["view", "edit", "create_file", "bash", "grep", "glob"],
    prompt: `You are a full-stack TypeScript developer. Implement the task 
             as described.`,
  },

};
```

### Agent type resolution

```typescript
export function resolveAgentConfig(agentType: string): CustomAgentConfig {
  return AGENT_REGISTRY[agentType] ?? AGENT_REGISTRY["general-purpose"];
}
```

Unknown `agent_type` values fall back to `general-purpose` with a warning logged. This prevents the orchestrator from crashing on a task with a typo in `agent_type`.

---

## Session Creation

Each task gets a fresh session with a deterministic, human-readable session ID:

```typescript
async function spawnTaskSession(
  client: CopilotClient,
  task: Task,
  epicOverview: string,
  worktreePath: string | null,
): Promise<void> {

  const sessionId = buildSessionId(task);
  // "run-epics-phase-1-foundation-01-create-schema-1713484800000"

  const agentConfig = resolveAgentConfig(task.plan.agent_type);

  const session = await client.createSession({
    sessionId,
    model: "claude-sonnet-4-6",
    workingDirectory: worktreePath ?? process.cwd(),

    // Pre-select the specialist agent
    customAgents: [agentConfig],
    agent: agentConfig.name,

    // Load skills declared in .plan.md
    skillDirectories: [
      path.resolve(".claude/skills"),
      path.resolve(".claude/commands/run-epics/skills"),
    ],

    // Headless — approve all tool calls
    onPermissionRequest: async () => ({ kind: "approved" }),

    // System context: inject epic overview
    systemMessage: {
      content: buildSystemPrompt(epicOverview, task),
    },
  });

  // Store session ID in sidecar for crash recovery
  sidecarManager.markInProgress(task.planPath, sessionId);

  // Listen for task_complete before sending
  let taskCompleted = false;
  session.on("session.task_complete", () => { taskCompleted = true; });

  // Send task content and wait for session.idle
  await session.sendAndWait({
    prompt: task.content,
    mode: "autopilot",
  });

  // Assess outcome
  if (taskCompleted) {
    sidecarManager.markDone(task.planPath);
  } else {
    sidecarManager.markFailed(task.planPath, "Agent completed without calling task_complete");
  }

  await session.disconnect();
}
```

### System prompt construction

```typescript
function buildSystemPrompt(epicOverview: string, task: Task): string {
  return `
## Epic Context

${epicOverview}

## Your Role

You are implementing task ${task.taskId} in epic ${task.plan.epic}.
Your agent type is: ${task.plan.agent_type}.

## Completion Signal

When you have fully implemented the task and all acceptance criteria in the 
task description are met, you MUST call task_complete with a one-sentence 
summary. Do not call task_complete until the implementation is complete.

If you encounter a blocker you cannot resolve, call task_complete with 
"BLOCKED: {reason}" as the summary so the orchestrator can mark this task 
for human review.
  `.trim();
}
```

---

## Autopilot Mode and the Nudge

Sessions are created with `mode: "autopilot"`. In autopilot mode, if the agent's tool-use loop ends without calling `task_complete`, the Copilot CLI automatically injects a nudge message:

```
You have not called task_complete yet. Please continue working on the task 
until all acceptance criteria are met, then call task_complete.
```

This is enforced by the CLI's internal loop logic — the SDK has no way to disable it in autopilot mode. This is intentional: it prevents agents from silently stopping mid-task. The nudge will fire up to a configurable number of times before the CLI gives up.

The practical effect: an agent that "finishes" before actually completing the task will be prompted to continue. The `sendAndWait()` call in the orchestrator blocks until `session.idle` fires, which only happens after the nudge cycle completes or `task_complete` is called.

---

## Completion Detection

There are two signals the orchestrator monitors:

| Signal | Meaning | Action |
|---|---|---|
| `session.task_complete` | Agent explicitly declared done | `markDone`, collect summary |
| `session.idle` (without `task_complete`) | Agent loop ended, but no completion signal | Check for `session.error`; if none, mark failed with "no task_complete signal" |
| `session.error` | Runtime error in the agent loop | `markFailed` with error message |
| Timeout (configured per-task) | `sendAndWait()` exceeded timeout | `session.abort()`, `markFailed` with "timeout" |

```typescript
// In phase-runner.ts — the Promise wrapping a task execution
async function runTask(client: CopilotClient, task: Task, epicOverview: string): Promise<void> {
  const timeout = 10 * 60 * 1000; // 10 minutes per task

  try {
    await withTimeout(
      spawnTaskSession(client, task, epicOverview, null),
      timeout,
      `Task ${task.taskId} exceeded ${timeout / 60000} minute timeout`
    );
  } catch (err) {
    sidecarManager.markFailed(task.planPath, err.message);
    if (orchestratorConfig.onFailure === "abort") throw err;
    // else: log and continue
  }
}
```

---

## Skill Preloading

Skills listed in a task's `.plan.md` `skills` field are preloaded into the agent's session via `skillDirectories`. The session discovers and activates skills automatically from those directories.

```
.claude/skills/
├── drizzle-database/
│   └── SKILL.md          ← loaded if skills: ["drizzle-database"]
├── rls-policies/
│   └── SKILL.md
└── edge-functions/
    └── SKILL.md
```

Skills give the agent domain-specific context (existing patterns, naming conventions, file locations) without inflating the system prompt for every task. A schema task gets Drizzle knowledge. An RLS task gets policy pattern knowledge. An API task gets server action patterns.

---

## Session ID Convention

```
run-epics-{epic-name}-{task-id}-{unix-timestamp-ms}
```

Examples:
- `run-epics-phase-1-foundation-01-create-schema-1713484800000`
- `run-epics-phase-2-ui-03-add-dashboard-page-1713485400000`

The timestamp component ensures uniqueness across retries (each retry gets a new session ID). The prefix enables listing all sessions from a specific epic run via `client.listSessions()` with prefix filtering for cleanup or audit.
