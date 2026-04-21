# Session Fork and Fleet (Experimental)

Two experimental APIs for advanced multi-agent orchestration.

## Session fork

**`sessions.fork(sessionId, toEventId?)`** creates a branch of a session — a copy of its history up to a specific event, returning a new `sessionId`.

### Why this exists

Custom agents are persona switches. Concurrent `createSession()` gives independent sessions with no shared history. Neither lets you say: "From this exact point in time, try two different strategies and pick the winner."

Fork does that.

### API

```typescript
const result = await client.rpc.sessions.fork({
  sessionId: "parent-session-id",
  toEventId: "event_abc123",   // optional; fork up to (and including) this event
});

// result: { sessionId: "new-forked-session-id" }
```

If `toEventId` is omitted, forks the entire current history.

### Use cases

#### 1. A/B test two agent strategies

```typescript
// Parent session reaches an interesting decision point
const checkpoint = await session.getLastEventId();

// Fork twice
const { sessionId: branchA } = await client.rpc.sessions.fork({
  sessionId: session.sessionId,
  toEventId: checkpoint,
});
const { sessionId: branchB } = await client.rpc.sessions.fork({
  sessionId: session.sessionId,
  toEventId: checkpoint,
});

// Resume each with different prompts
const sA = await client.resumeSession(branchA, {...});
const sB = await client.resumeSession(branchB, {...});

await Promise.all([
  sA.sendAndWait({ prompt: "Refactor using approach X" }),
  sB.sendAndWait({ prompt: "Refactor using approach Y" }),
]);

// Compare results, keep the winner
```

#### 2. Safe rollback before a destructive operation

```typescript
const snapshot = await session.getLastEventId();

// Fork as "safety copy"
const { sessionId: backup } = await client.rpc.sessions.fork({
  sessionId: session.sessionId,
  toEventId: snapshot,
});

// Now try the risky thing
try {
  await session.sendAndWait({ prompt: "Migrate database schema" });
  // Success — optionally delete backup
  await client.deleteSession(backup);
} catch (err) {
  // Something went wrong. Abandon current session, resume the backup.
  await session.delete();
  session = await client.resumeSession(backup, {...});
}
```

#### 3. Parallel exploration trees

Tree-of-thought style: explore multiple hypotheses, each a fork, and converge on the best.

### What fork copies

- All persisted events up to `toEventId`
- Persisted state (active agent, plan file, workspace files)
- Compaction state

What fork does NOT copy:
- Ephemeral events (deltas, capabilities, progress)
- Registered tool/hook handlers (reprovide on resume)
- Live connections (the fork is disk-only until resumed)

### Forking is not free

Each fork doubles disk usage for the session's workspace. Use deliberately, clean up unused branches.

## Fleet mode

**`session.fleet.start(prompt?)`** starts a multi-agent fleet — the runtime's own orchestration primitive for coordinated multi-agent work.

### API

```typescript
const result = await session.rpc.fleet.start({
  prompt: "Implement the entire OAuth flow",
});
// result: { started: true }
```

Fleet mode is **distinct from**:
- Custom agents (persona switches in one session)
- Concurrent sessions (independent work)
- Fork (branching history)

It is Copilot's own internal multi-agent runtime, exposed as an API. Details are sparse in public docs — treat as highly experimental.

### What fleet likely does

Based on the schema and event types:

- Spawns multiple internal agent workers coordinated by a planner
- Emits richer sub-agent events than standalone custom agents
- Uses `session.fleet.*` namespace for lifecycle
- Integrates with `session.mode.set("plan")` for approval gates

### What we don't know

- Exact coordination protocol between fleet members
- How fleet agents share or isolate context
- Cost model — single metered session, or one per fleet member
- Fleet-specific events beyond `session.fleet.*`

### Use case

Until fleet mode stabilizes, for multi-agent work prefer:

1. Single session with `customAgents` + `infer: true` (auto-routing)
2. Multiple concurrent sessions with your own orchestrator (explicit routing)
3. `sessions.fork` for branch-and-merge patterns

When fleet mode matures, it will likely replace option 1 and 2 for complex workflows.

## Protocol-level stability

Both `sessions.fork` and `session.fleet.*` are marked experimental in the schema. The SDK wrappers may rename, change signatures, or remove them. Guard with:

```typescript
try {
  await client.rpc.sessions.fork(...);
} catch (err) {
  if (err.code === "METHOD_NOT_FOUND") {
    // Fallback path
  }
}
```

## Runtime skill / MCP / extension management (also experimental)

Alongside fork and fleet, these experimental APIs let you mutate session state at runtime:

```typescript
await session.rpc.skills.list();
await session.rpc.skills.enable({ name: "deploy-edge" });
await session.rpc.skills.disable({ name: "legacy-thing" });
await session.rpc.skills.reload();

await session.rpc.mcp.list();
await session.rpc.mcp.enable({ serverName: "postgres" });
await session.rpc.mcp.disable({ serverName: "postgres" });
await session.rpc.mcp.reload();

await session.rpc.extensions.list();
await session.rpc.extensions.enable({ id: "ext-123" });
await session.rpc.extensions.disable({ id: "ext-123" });
await session.rpc.extensions.reload();

await session.rpc.plugins.list();   // read-only
```

These are useful for dynamic capability management but change shape often. Treat as internal.

## See also

- [hidden-rpc-methods.md](hidden-rpc-methods.md) — full list of experimental RPCs
- [../06-dark-factory/blueprint.md](../06-dark-factory/blueprint.md) — using fork for safe rollback
- [../02-core-concepts/agents-and-subagents.md](../02-core-concepts/agents-and-subagents.md) — custom agents for comparison
