# Hidden / Experimental RPC Methods

These RPC methods exist in the protocol spec (`go/rpc/generated_rpc.go`, `nodejs/src/generated/rpc.ts`) but are not prominently featured in the public documentation. Use with care — APIs marked experimental may change.

## Server-scoped hidden methods

### `ping`

```typescript
await client.rpc.ping({ message: "hello?" });
// returns { message, timestamp, protocolVersion }
```

Health check. Use for liveness probing.

### `sessions.fork` (experimental)

Branch a session at an event. See [session-fork-and-fleet.md](session-fork-and-fleet.md).

```typescript
await client.rpc.sessions.fork({
  sessionId: "parent",
  toEventId: "event_123",   // optional
});
// returns { sessionId: "forked-id" }
```

### `mcp.config.*`

Runtime management of global MCP config:

```typescript
await client.rpc.mcp.config.list();
await client.rpc.mcp.config.add({ name, config });
await client.rpc.mcp.config.update({ name, config });
await client.rpc.mcp.config.remove({ name });
```

### `mcp.discover`

```typescript
await client.rpc.mcp.discover({ workingDirectory: "/path/to/repo" });
// returns { servers: DiscoveredMcpServer[] }
```

Auto-find MCP config files in a directory.

### `skills.*`

```typescript
await client.rpc.skills.discover({ projectPaths, skillDirectories });
await client.rpc.skills.config.setDisabledSkills({ disabledSkills: ["skill-a"] });
```

### `sessionFs.setProvider`

```typescript
await client.rpc.sessionFs.setProvider({
  initialCwd: "/virtual",
  sessionStatePath: "/virtual/state",
  conventions: "posix",
});
// returns { success: boolean }
```

Must be called before any sessions exist.

### `account.getQuota`

```typescript
await client.rpc.account.getQuota();
// returns {
//   quotaSnapshots: {
//     premium_interactive: {
//       entitlementRequests,
//       usedRequests,
//       remainingPercentage,
//       overage,
//       overageAllowedWithExhaustedQuota,
//       resetDate,
//     },
//   },
// }
```

Quota observability. Critical for dark factory cost management.

### `models.list` and `tools.list`

```typescript
await client.rpc.models.list();
// returns { models: [{ id, name, capabilities, policy, billing, supportedReasoningEfforts, defaultReasoningEffort }] }

await client.rpc.tools.list({ model: "gpt-5" });
// returns { tools: [{ name, namespacedName, description, parameters, instructions }] }
```

## Session-scoped hidden methods

### `session.mode.*`

```typescript
await session.rpc.mode.get();
await session.rpc.mode.set({ mode: "interactive" | "plan" | "autopilot" });
```

See [session-modes.md](session-modes.md).

### `session.name.*`

```typescript
await session.rpc.name.get();   // returns { name: string | null }
await session.rpc.name.set({ name: "My Session" });   // 1-100 chars
```

Session titles for UIs.

### `session.plan.*`

```typescript
await session.rpc.plan.read();     // returns { exists, content, path }
await session.rpc.plan.update({ content: "..." });
await session.rpc.plan.delete();
```

See [session-modes.md](session-modes.md).

### `session.model.*`

```typescript
await session.rpc.model.getCurrent();
// returns { modelId: string | null }

await session.rpc.model.switchTo({
  modelId: "claude-sonnet-4.5",
  reasoningEffort: "high",
  modelCapabilities: {
    supports: {
      vision: true,
      reasoningEffort: true,
    },
    limits: {
      max_prompt_tokens: 180000,
      max_output_tokens: 8192,
      max_context_window_tokens: 200000,
      vision: {
        supported_media_types: ["image/png", "image/jpeg"],
        max_prompt_images: 10,
        max_prompt_image_size: 20 * 1024 * 1024,
      },
    },
  },
});
```

The `modelCapabilities` override lets you force the CLI to treat a model as having certain traits — useful for BYOK setups where the model's advertised capabilities don't match reality.

### `session.workspaces.*`

```typescript
await session.rpc.workspaces.getWorkspace();
// returns { workspace: { id, cwd, git_root, repository, host_type, branch, ... } | null }

await session.rpc.workspaces.listFiles();
// returns { files: string[] }

await session.rpc.workspaces.readFile({ path: "src/main.ts" });
// returns { content: string }

await session.rpc.workspaces.createFile({ path: "new.txt", content: "..." });
```

Workspace-level file operations outside the agent loop.

### `session.instructions.getSources`

```typescript
await session.rpc.instructions.getSources();
// returns {
//   sources: [
//     {
//       id, label, sourcePath, content, type, location,
//       applyTo,  // glob pattern
//       description,
//     },
//   ],
// }
```

List all instruction sources currently applied. Useful for debugging "why did the agent do X?"

### `session.fleet.start` (experimental)

```typescript
await session.rpc.fleet.start({ prompt: "Implement OAuth" });
// returns { started: true }
```

See [session-fork-and-fleet.md](session-fork-and-fleet.md).

### `session.agent.*` (experimental)

```typescript
await session.rpc.agent.list();
await session.rpc.agent.getCurrent();
await session.rpc.agent.select({ name: "researcher" });
await session.rpc.agent.deselect();
await session.rpc.agent.reload();
```

### `session.skills.*` (experimental)

```typescript
await session.rpc.skills.list();
await session.rpc.skills.enable({ name: "deploy" });
await session.rpc.skills.disable({ name: "legacy" });
await session.rpc.skills.reload();
```

### `session.mcp.*` (experimental)

Runtime MCP management per session:

```typescript
await session.rpc.mcp.list();
await session.rpc.mcp.enable({ serverName: "postgres" });
await session.rpc.mcp.disable({ serverName: "postgres" });
await session.rpc.mcp.reload();
```

### `session.plugins.list` (experimental)

```typescript
await session.rpc.plugins.list();
// returns { plugins: [{ name, marketplace, version, enabled }] }
```

Read-only plugin inventory.

### `session.extensions.*` (experimental)

```typescript
await session.rpc.extensions.list();
await session.rpc.extensions.enable({ id });
await session.rpc.extensions.disable({ id });
await session.rpc.extensions.reload();
```

### `session.tools.handlePendingToolCall`

Internal — the SDK uses this to feed tool results back to the CLI. You typically don't call it directly, but it's exposed.

```typescript
await session.rpc.tools.handlePendingToolCall({
  requestId: "...",
  result: "string or ToolCallResult object",
  error: "optional error message",
});
// returns { success: boolean }
```

### `session.commands.handlePendingCommand`

Similar — internal, fed by command handlers.

### `session.ui.*`

```typescript
// Trigger elicitation from your code
await session.rpc.ui.elicitation({
  message: "Pick a file",
  requestedSchema: { type: "object", properties: { file: { type: "string" } } },
});
// returns { action: "accept"|"decline"|"cancel", content: { file: "..." } }

// Respond to pending elicitation requests
await session.rpc.ui.handlePendingElicitation({
  requestId,
  result: { action: "accept", content: {...} },
});
```

### `session.permissions.handlePendingPermissionRequest`

Internal; the SDK plumbs this for your `onPermissionRequest` handler.

### `session.log`

Inject a log message into the session event stream:

```typescript
await session.log({
  message: "Deployment started",
  level: "info" | "warning" | "error",
  ephemeral: false,                    // true = not persisted
  url: "https://dashboard/...",        // optional link
});
// returns { eventId: string }
```

Useful for surfacing external events to the agent's context.

### `session.shell` methods

Direct shell invocation (separate from the `bash` tool):

```typescript
const result = await session.rpc.shell.run({
  command: "npm run build",
  cwd: "/repo",
  timeout: 120000,
});
// result.processId

// Later:
await session.rpc.shell.kill({ processId: result.processId, signal: "SIGTERM" });
// returns { killed: boolean }
```

(The RPC method name is literally `session.shell.exec` in the protocol; shown here as `.run` to avoid confusion.) Use when you want to trigger shell commands from your orchestration code without going through the agent loop.

### `session.history.*` (experimental)

Manual context management:

```typescript
await session.rpc.history.compact();
// returns { success, tokensRemoved, messagesRemoved, contextWindow }

await session.rpc.history.truncate({ eventId: "event_xyz" });
// returns { eventsRemoved }
```

Destructive operations. See [../02-core-concepts/infinite-sessions-and-compaction.md](../02-core-concepts/infinite-sessions-and-compaction.md).

### `session.usage.getMetrics` (experimental)

```typescript
await session.rpc.usage.getMetrics();
// returns {
//   totalPremiumRequestCost,
//   totalUserRequests,
//   totalApiDurationMs,
//   sessionStartTime,
//   codeChanges,
//   modelMetrics: { "gpt-5": { requests, tokensIn, tokensOut, durationMs }, ... },
//   currentModel,
//   lastCallInputTokens,
//   lastCallOutputTokens,
// }
```

Per-session cost and usage. Essential for dark factory cost tracking.

## Reverse-RPC (server to client)

These are called by the CLI server into your SDK client:

- `sessionFs.readFile` / `writeFile` / `appendFile`
- `sessionFs.exists` / `stat` / `mkdir`
- `sessionFs.readdir` / `readdirWithTypes`
- `sessionFs.rm` / `rename`

You register handlers via `createSessionFsHandler`. See [session-filesystem-provider.md](session-filesystem-provider.md).

## Protocol versioning note

Some methods exist only in protocol v3+. Calling them on a v2 server throws. The SDK negotiates version at `start()` and you can inspect `client.negotiatedProtocolVersion`.

## See also

- [session-modes.md](session-modes.md)
- [session-fork-and-fleet.md](session-fork-and-fleet.md)
- [session-filesystem-provider.md](session-filesystem-provider.md)
- [../08-reference/rpc-methods.md](../08-reference/rpc-methods.md) — full method index
