# Hooks and Events

Two distinct mechanisms for intercepting the agent's execution:

- **Hooks** — synchronous callbacks that can modify behavior (pre/post tool use, pre/post session, etc.)
- **Events** — read-only notifications streamed to subscribers (`assistant.message`, `tool.execution_*`, etc.)

## Hook registry

All hooks pass through the session config's `hooks` property:

```typescript
await client.createSession({
  hooks: {
    onPreToolUse:         async (input, inv) => { ... },
    onPostToolUse:        async (input, inv) => { ... },
    onUserPromptSubmitted: async (input, inv) => { ... },
    onSessionStart:       async (input, inv) => { ... },
    onSessionEnd:         async (input, inv) => { ... },
    onErrorOccurred:      async (input, inv) => { ... },
  },
  // Not part of `hooks`, but conceptually similar:
  onPermissionRequest:   async (request, inv) => ({ kind: "approved" }),
  onUserInputRequest:    async (request, inv) => ({ answer: "..." }),
  onElicitationRequest:  async (ctx, inv) => ({ action: "accept", content: {} }),
});
```

## Hook details

### `onPreToolUse`

Fires before every tool execution. Can approve, deny, or modify args.

```typescript
onPreToolUse: async (input, { sessionId }) => {
  // input: { toolName, toolCallId, arguments, ... }
  if (input.toolName === "bash" && input.arguments.command.includes("rm -rf")) {
    return { permissionDecision: "deny", reason: "Blocked destructive command" };
  }

  // Modify args
  return { modifiedArguments: { ...input.arguments, safe: true } };
}
```

### `onPostToolUse`

Fires after every tool execution. Can transform the result before the model sees it.

```typescript
onPostToolUse: async (input, inv) => {
  // input: { toolName, toolCallId, result, success, ... }
  return {
    modifiedResult: redactSecrets(input.result),
  };
}
```

Use this to redact secrets, inject context, or enforce formatting.

### `onUserPromptSubmitted`

Fires when the user sends a message.

```typescript
onUserPromptSubmitted: async (input, inv) => {
  // input: { prompt, timestamp, cwd }
  return {
    modifiedPrompt: `[audit: ${new Date().toISOString()}] ${input.prompt}`,
  };
}
```

### `onSessionStart`

Fires at session creation or resume.

```typescript
onSessionStart: async (input, inv) => {
  // input: { source: "new" | "resumed", timestamp, cwd }
  if (input.source === "resumed") {
    telemetry.recordResume(inv.sessionId);
  }
}
```

Only way to distinguish new vs. resumed sessions (not exposed as session property).

### `onSessionEnd`

Fires when session disconnects. Use for cleanup, final logging.

```typescript
onSessionEnd: async (input, inv) => {
  await uploadTranscript(inv.sessionId);
}
```

Note: runs asynchronously after disconnect. Don't expect it to block.

### `onErrorOccurred`

Fires on any recoverable or non-recoverable error.

```typescript
onErrorOccurred: async (input, inv) => {
  // input: { error, errorContext, recoverable, timestamp, cwd }
  // errorContext: "model_call" | "tool_execution" | "system" | "user_input"

  if (input.errorContext === "model_call" && input.recoverable) {
    await sleep(1000); // let caller retry
  } else {
    alertOps({ session: inv.sessionId, error: input.error });
  }
}
```

Four error contexts. Route recovery based on which.

## Permission handler

`onPermissionRequest` is separate from `hooks` because it's required:

```typescript
onPermissionRequest: async (request, invocation) => {
  // request: { kind, toolName, operation, ... }
  // kind: "shell" | "write" | "read" | "mcp" | "custom-tool" | "url" | "memory" | "hook"

  switch (request.kind) {
    case "shell":
      if (isDangerous(request.command)) {
        return { kind: "denied-by-policy", message: "Not allowed" };
      }
      return { kind: "approved" };

    case "write":
    case "read":
      return { kind: "approved" };

    default:
      return { kind: "denied-interactively-by-user" };
  }
}
```

### Permission result kinds

| Kind | Meaning |
|---|---|
| `approved` | Allow once |
| `approved-for-session` | Allow all future matching requests in this session |
| `denied-by-policy` | Deny; operator policy (hard deny) |
| `denied-interactively-by-user` | Deny; user said no |
| `no-result` | Defer to next handler (v3 only — throws on v2) |

### Built-in shortcut

```typescript
import { approveAll } from "@github/copilot-sdk";

await client.createSession({
  onPermissionRequest: approveAll,   // approves every request
});
```

Use for autonomous operation.

## Event subscriptions

### Typed subscription

```typescript
session.on("assistant.message", (event) => {
  // TypeScript knows event.data.content exists
  console.log(event.data.content);
});
```

### Wildcard subscription

```typescript
session.on((event) => {
  console.log(event.type, event.id, event.timestamp);
});
```

### Early subscription (before first send)

Events emitted before handlers register are lost. To capture early events, pass `onEvent` in session config:

```typescript
await client.createSession({
  onEvent: (event) => {
    allEvents.push(event);
  },
});
```

## Event ordering contract (strict)

These are tested invariants:

1. **`session.idle` is always the last event** in a send cycle:
   ```
   types.lastIndexOf("session.idle") === types.length - 1
   ```

2. **`assistant.message_delta` precedes `assistant.message`** (when streaming):
   ```
   types.indexOf("assistant.message_delta") < types.lastIndexOf("assistant.message")
   ```

3. **`tool.execution_complete.toolCallId` matches `tool.execution_start.toolCallId`** exactly.

4. **Every event has non-empty `id` and ISO-8601 `timestamp`**.

## Ephemeral vs persisted events

Some events are **ephemeral** (not saved to session state, not replayed on resume):

| Ephemeral | Persisted |
|---|---|
| `session.idle` | `session.start` |
| `assistant.message_delta` | `assistant.message` |
| `assistant.streaming_delta` | `assistant.turn_start/end` |
| `tool.execution_partial_result` | `tool.execution_start/complete` |
| `permission.requested/completed` | `session.task_complete` |
| `user_input.requested/completed` | `session.compaction_complete` |
| `capabilities.changed` | `subagent.started/completed/failed` |
| `command.queued/execute/completed` | — |

If you resume a session, you'll replay only the persisted events. Ephemeral events are lost.

## Capability negotiation

The session tracks what the connected clients can do:

```typescript
console.log(session.capabilities);
// { ui: { elicitation: true } }   <- set when at least one client has onElicitationRequest
```

When a second client joins with new capabilities, everyone gets a `capabilities.changed` event:

```typescript
session.on("capabilities.changed", (e) => {
  console.log("UI capabilities now:", e.data.ui);
});
```

This is the v3-only multi-client coordination mechanism.

## User input vs elicitation (two different things)

### `onUserInputRequest`

Handles the `ask_user` tool — model asks a question, gets an answer.

```typescript
onUserInputRequest: async (req) => ({
  answer: "yes",
  wasFreeform: false,
})
```

### `onElicitationRequest`

Handles form-based UI dialogs the CLI may trigger (not just tool-initiated).

```typescript
onElicitationRequest: async (ctx) => ({
  action: "accept",    // "accept" | "decline" | "cancel"
  content: { fieldA: "value", fieldB: 42 },
})
```

Enables `session.ui.confirm()`, `session.ui.select()`, `session.ui.input()`, `session.ui.elicitation()`.

## Commands

Register slash commands (invoked via TUI or programmatically):

```typescript
await client.createSession({
  commands: [
    {
      name: "deploy",
      description: "Deploy the current branch",
      handler: async (ctx) => {
        await runDeploy();
      },
    },
  ],
});
```

## System message transforms

Modify system prompt sections at runtime:

```typescript
systemMessage: {
  mode: "customize",
  sections: {
    custom_instructions: {
      action: async (currentContent) => currentContent + "\n[injected at runtime]",
    },
  },
}
```

See [../04-advanced/system-message-customization.md](../04-advanced/system-message-customization.md).

## See also

- [../08-reference/event-types.md](../08-reference/event-types.md) — all ~50+ event types
- [tools-and-mcp.md](tools-and-mcp.md) — tool registration and MCP
- [sessions.md](sessions.md) — session lifecycle hooks
