# Dark Factory Implementation Guide

Concrete, copy-paste-ready patterns. For the architecture, see [blueprint.md](blueprint.md).

## Minimal viable dark factory (Node.js)

```typescript
import { CopilotClient, approveAll } from "@github/copilot-sdk";

async function processEpic(epic: { id: string; tasks: Task[] }) {
  const client = new CopilotClient();

  try {
    for (const task of epic.tasks) {
      await processTask(client, task);
    }
  } finally {
    await client.stop();
  }
}

async function processTask(client: CopilotClient, task: Task) {
  const session = await client.createSession({
    sessionId: `epic-${task.epicId}-task-${task.id}`,
    model: "gpt-5",
    onPermissionRequest: approveAll,
    infiniteSessions: { enabled: true },
    customAgents: [
      {
        name: "worker",
        tools: ["view", "edit", "create_file", "bash", "grep", "glob"],
        prompt: "You complete the task. Call task_complete when done.",
        infer: false,
      },
    ],
  });

  await session.rpc.mode.set({ mode: "autopilot" });
  await session.rpc.agent.select({ name: "worker" });

  const done = new Promise<string>((resolve) => {
    session.on("session.task_complete", (e) => resolve(e.data.summary ?? ""));
  });

  await session.send({
    prompt: buildPrompt(task),
  });

  const summary = await done;
  console.log(`[task ${task.id}] done: ${summary}`);

  await session.disconnect();
}

function buildPrompt(task: Task): string {
  return `
# Task ${task.id}: ${task.title}

${task.description}

## Acceptance criteria
${task.criteria.map(c => `- ${c}`).join("\n")}

Complete all criteria. When done, call task_complete with a brief summary.
`.trim();
}
```

## Adding role-scoped agents

```typescript
const researcherAgent = {
  name: "researcher",
  displayName: "Research Agent",
  description: "Analyzes code without making changes",
  tools: ["grep", "glob", "view"],
  prompt: "You are a code researcher. You never modify files.",
  infer: true,
};

const editorAgent = {
  name: "editor",
  displayName: "Editor Agent",
  description: "Makes targeted code changes",
  tools: ["view", "edit", "create_file"],
  prompt: "You make surgical code changes. You do not run tests or shell commands.",
  infer: true,
};

const verifierAgent = {
  name: "verifier",
  displayName: "Verifier Agent",
  description: "Runs tests and verifies correctness",
  tools: ["bash", "view"],
  prompt: "You run tests and report pass/fail. You do not modify code.",
  infer: true,
};

const session = await client.createSession({
  // ...
  customAgents: [researcherAgent, editorAgent, verifierAgent],
});
```

With `infer: true`, the runtime auto-routes to the right agent based on what the model is trying to do.

## Parallel task execution

```typescript
const tasks = await queue.getPending(10);

await Promise.all(tasks.map(task => processTask(client, task)));
```

All sessions multiplex over one CLI subprocess. For very high concurrency, spin up multiple `CopilotClient` instances (one per CLI process).

## Safe rollback with fork

```typescript
async function processRiskyTask(session: CopilotSession, task: Task) {
  // Fork before running the risky step
  const { sessionId: backupId } = await client.rpc.sessions.fork({
    sessionId: session.sessionId,
  });

  try {
    await session.send({ prompt: "Refactor the auth module" });
    const done = await waitForComplete(session);

    if (!done.success) throw new Error("task failed");

    // Success — cleanup backup
    await client.deleteSession(backupId);
    return done;
  } catch (err) {
    // Roll back: discard current, resume backup
    await session.delete();
    const restored = await client.resumeSession(backupId, {
      onPermissionRequest: approveAll,
    });

    await restored.rpc.mode.set({ mode: "autopilot" });
    return { success: false, session: restored };
  }
}
```

## S3-backed sessionFs

```typescript
import { S3Client, GetObjectCommand, PutObjectCommand, DeleteObjectCommand } from "@aws-sdk/client-s3";

const s3 = new S3Client({ region: "us-east-1" });
const BUCKET = "copilot-sessions";

function makeSessionFsHandler(sessionId: string) {
  const key = (path: string) => `${sessionId}${path}`;

  return {
    readFile: async ({ path }) => {
      const res = await s3.send(new GetObjectCommand({ Bucket: BUCKET, Key: key(path) }));
      const content = await res.Body!.transformToString("utf8");
      return { content };
    },

    writeFile: async ({ path, content }) => {
      await s3.send(new PutObjectCommand({ Bucket: BUCKET, Key: key(path), Body: content }));
    },

    appendFile: async ({ path, content }) => {
      // S3 doesn't support append natively — read, concat, write
      let existing = "";
      try {
        const res = await s3.send(new GetObjectCommand({ Bucket: BUCKET, Key: key(path) }));
        existing = await res.Body!.transformToString("utf8");
      } catch {}
      await s3.send(new PutObjectCommand({ Bucket: BUCKET, Key: key(path), Body: existing + content }));
    },

    exists: async ({ path }) => {
      try {
        await s3.send(new HeadObjectCommand({ Bucket: BUCKET, Key: key(path) }));
        return { exists: true };
      } catch {
        return { exists: false };
      }
    },

    stat: async ({ path }) => {
      const res = await s3.send(new HeadObjectCommand({ Bucket: BUCKET, Key: key(path) }));
      return {
        stats: {
          size: res.ContentLength!,
          isFile: true,
          isDirectory: false,
          mtime: res.LastModified!.toISOString(),
        },
      };
    },

    mkdir: async () => {
      // S3 has no real directories; no-op
    },

    readdir: async ({ path }) => {
      const res = await s3.send(new ListObjectsV2Command({
        Bucket: BUCKET,
        Prefix: key(path),
      }));
      return { entries: (res.Contents ?? []).map(o => o.Key!.slice(key(path).length)) };
    },

    readdirWithTypes: async ({ path }) => {
      const { entries } = await this.readdir({ path });
      return { entries: entries.map(name => ({ name, isFile: true, isDirectory: false })) };
    },

    rm: async ({ path }) => {
      await s3.send(new DeleteObjectCommand({ Bucket: BUCKET, Key: key(path) }));
    },

    rename: async ({ oldPath, newPath }) => {
      // S3 has no native rename — copy + delete
      await s3.send(new CopyObjectCommand({
        Bucket: BUCKET,
        CopySource: `${BUCKET}/${key(oldPath)}`,
        Key: key(newPath),
      }));
      await s3.send(new DeleteObjectCommand({ Bucket: BUCKET, Key: key(oldPath) }));
    },
  };
}

const client = new CopilotClient({
  sessionFs: {
    initialCwd: "/work",
    sessionStatePath: "/work/state",
    conventions: "posix",
  },
});
```

## Cost monitoring per task

```typescript
async function processTask(client: CopilotClient, task: Task) {
  const session = await client.createSession({...});

  const done = new Promise<{ summary: string }>((resolve) =>
    session.on("session.task_complete", (e) => resolve({ summary: e.data.summary })),
  );

  await session.send({ prompt: buildPrompt(task) });
  const { summary } = await done;

  // Capture cost before disconnect
  const metrics = await session.rpc.usage.getMetrics();

  await db.insert("task_metrics", {
    task_id: task.id,
    session_id: session.sessionId,
    cost_usd: metrics.totalPremiumRequestCost,
    tokens_in: metrics.lastCallInputTokens,
    tokens_out: metrics.lastCallOutputTokens,
    api_duration_ms: metrics.totalApiDurationMs,
    model: metrics.currentModel,
    summary,
  });

  await session.disconnect();
}
```

## Retry with resume

```typescript
async function processWithResume(task: Task, maxAttempts = 3) {
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const session = attempt === 1
        ? await client.createSession({ sessionId: `task-${task.id}`, ... })
        : await client.resumeSession(`task-${task.id}`, { onPermissionRequest: approveAll });

      await session.rpc.mode.set({ mode: "autopilot" });

      const result = await runSession(session, task);
      await session.disconnect();
      return result;
    } catch (err) {
      console.warn(`[task ${task.id}] attempt ${attempt} failed: ${err}`);
      if (attempt === maxAttempts) throw err;
      await sleep(2 ** attempt * 1000);   // exponential backoff
    }
  }
}
```

## Dead-letter queue pattern

```typescript
async function processTaskWithDLQ(task: Task) {
  try {
    await processTask(task);
    await queue.ack(task);
  } catch (err) {
    if (err.transient) {
      await queue.nack(task);   // requeue
    } else {
      await dlq.push(task, err);   // permanent failure
    }
  }
}
```

## Timeout enforcement

```typescript
async function processTaskWithTimeout(task: Task, timeoutMs = 30 * 60 * 1000) {
  const session = await client.createSession({...});

  const done = new Promise<string>((resolve) =>
    session.on("session.task_complete", (e) => resolve(e.data.summary)),
  );

  const timeout = new Promise<never>((_, reject) =>
    setTimeout(() => reject(new Error("timeout")), timeoutMs),
  );

  await session.send({ prompt: buildPrompt(task) });

  try {
    return await Promise.race([done, timeout]);
  } finally {
    await session.disconnect();
  }
}
```

## Observability events

```typescript
const session = await client.createSession({
  hooks: {
    onSessionStart: async (input, inv) => {
      metrics.incr("session.start", { source: input.source });
      metrics.recordSession(inv.sessionId, { taskId: task.id });
    },

    onPreToolUse: async (input, inv) => {
      metrics.incr("tool.invoke", { tool: input.toolName });
    },

    onPostToolUse: async (input, inv) => {
      metrics.histogram("tool.duration_ms", input.durationMs, { tool: input.toolName });
    },

    onErrorOccurred: async (input, inv) => {
      metrics.incr("session.error", { context: input.errorContext });
      logger.error({ taskId: task.id, input }, "session error");
    },

    onSessionEnd: async (input, inv) => {
      metrics.incr("session.end");
    },
  },
  // ...
});

session.on("subagent.completed", (e) => {
  metrics.histogram("subagent.duration_ms", e.data.durationMs, {
    agent: e.data.agentName,
  });
  metrics.histogram("subagent.tokens", e.data.totalTokens, {
    agent: e.data.agentName,
  });
});
```

## Concurrent task fleet

```typescript
const workerPool = Array.from({ length: 4 }, () => new CopilotClient({
  cliUrl: "tcp://localhost:3000",
}));

await Promise.all(workerPool.map(c => c.start()));

const taskQueue = await queue.getPending(100);

let workerIdx = 0;
const results = await Promise.all(
  taskQueue.map(task => {
    const worker = workerPool[workerIdx++ % workerPool.length];
    return processTask(worker, task);
  }),
);
```

Each worker = one `CopilotClient` = independent connection to the shared headless CLI.

## Python variant (for the Python-inclined)

```python
import asyncio
from copilot import CopilotClient, PermissionHandler

async def process_task(client, task):
    session = await client.create_session(
        session_id=f"task-{task.id}",
        model="gpt-5",
        on_permission_request=PermissionHandler.approve_all,
        infinite_sessions={"enabled": True},
        custom_agents=[
            {"name": "worker", "tools": [...], "prompt": "..."}
        ],
    )

    await session.rpc.mode.set(mode="autopilot")

    done = asyncio.Event()
    summary_ref = [None]

    @session.on("session.task_complete")
    def on_done(event):
        summary_ref[0] = event.data.summary
        done.set()

    await session.send(prompt=build_prompt(task))
    await done.wait()

    metrics = await session.rpc.usage.get_metrics()
    await db.record_cost(task.id, metrics)

    await session.disconnect()
    return summary_ref[0]


async def main():
    async with CopilotClient() as client:
        tasks = await queue.get_pending()
        await asyncio.gather(*(process_task(client, t) for t in tasks))

asyncio.run(main())
```

## Go variant (for production-grade services)

```go
func processTask(ctx context.Context, client *copilot.Client, task Task) error {
    session, err := client.CreateSession(ctx, copilot.SessionConfig{
        SessionID: fmt.Sprintf("task-%s", task.ID),
        Model: "gpt-5",
        OnPermissionRequest: copilot.PermissionHandler.ApproveAll,
        InfiniteSessions: &copilot.InfiniteSessionsConfig{ Enabled: true },
        CustomAgents: []copilot.CustomAgentConfig{...},
    })
    if err != nil {
        return err
    }
    defer session.Disconnect(ctx)

    if err := session.RPC.Mode.Set(ctx, copilot.ModeSetRequest{ Mode: "autopilot" }); err != nil {
        return err
    }

    done := make(chan string, 1)
    session.On("session.task_complete", func(e copilot.SessionEvent) {
        done <- e.Data.Summary
    })

    if err := session.Send(ctx, copilot.SendOptions{ Prompt: buildPrompt(task) }); err != nil {
        return err
    }

    select {
    case summary := <-done:
        log.Printf("task %s done: %s", task.ID, summary)
    case <-ctx.Done():
        return ctx.Err()
    }

    metrics, _ := session.RPC.Usage.GetMetrics(ctx)
    db.RecordCost(task.ID, metrics)
    return nil
}
```

## See also

- [blueprint.md](blueprint.md) — architecture
- [../04-advanced/session-modes.md](../04-advanced/session-modes.md) — autopilot details
- [../04-advanced/session-filesystem-provider.md](../04-advanced/session-filesystem-provider.md) — sessionFs
- [../02-core-concepts/infinite-sessions-and-compaction.md](../02-core-concepts/infinite-sessions-and-compaction.md)
