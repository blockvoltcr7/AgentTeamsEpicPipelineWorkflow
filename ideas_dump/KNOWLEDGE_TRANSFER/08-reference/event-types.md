# Event Type Reference

Complete list of session event types, grouped by category. Generated from `nodejs/src/generated/session-events.ts`.

Columns:
- **Persisted**: survives session resume (vs ephemeral, which is lost)
- **Payload**: summary of `event.data` contents

All events have: `id: string`, `type: string`, `timestamp: ISO-8601 string`.

## Session lifecycle

| Event | Persisted | Payload |
|---|---|---|
| `session.start` | ✅ | start metadata, initial config |
| `session.resume` | ✅ | resume context |
| `session.remote_steerable_changed` | ✅ | remote steering capability change |
| `session.shutdown` | ✅ | final usage metrics |
| `session.context_changed` | ✅ | cwd/git branch/repo change |
| `session.idle` | ❌ | — (always last event in send cycle) |

## Session state

| Event | Persisted | Payload |
|---|---|---|
| `session.error` | ✅ | `{ error, errorContext, recoverable }` |
| `session.info` | ✅ | `{ message }` |
| `session.warning` | ✅ | `{ message }` |
| `session.model_change` | ✅ | `{ previousModel, newModel, previousReasoningEffort?, reasoningEffort? }` |
| `session.mode_changed` | ✅ | `{ mode }` |
| `session.plan_changed` | ✅ | `{ action: "create"\|"update"\|"delete" }` |
| `session.workspace_file_changed` | ✅ | `{ path, change }` |
| `session.title_changed` | ❌ | `{ title }` |
| `session.handoff` | ✅ | handoff details |

## Compaction and history

| Event | Persisted | Payload |
|---|---|---|
| `session.truncation` | ✅ | truncation metrics |
| `session.snapshot_rewind` | ✅ | rewound events |
| `session.usage_info` | ❌ | current context window utilization |
| `session.compaction_start` | ✅ | — |
| `session.compaction_complete` | ✅ | `{ tokensRemoved, messagesRemoved, contextWindow }` |
| `session.task_complete` | ✅ | `{ summary? }` |

## User input

| Event | Persisted | Payload |
|---|---|---|
| `user.message` | ✅ | `{ content, attachments? }` |
| `pending_messages.modified` | ❌ | pending message queue state |

## Assistant turns

| Event | Persisted | Payload |
|---|---|---|
| `assistant.turn_start` | ✅ | — |
| `assistant.turn_end` | ✅ | — |
| `assistant.intent` | ❌ | `{ intent }` (current agent intent) |
| `assistant.reasoning` | ✅ | `{ content }` (extended thinking) |
| `assistant.reasoning_delta` | ❌ | `{ deltaContent }` |
| `assistant.streaming_delta` | ❌ | streaming progress |
| `assistant.message` | ✅ | `{ messageId, content, toolRequests? }` |
| `assistant.message_delta` | ❌ | `{ deltaContent }` |
| `assistant.usage` | ❌ | LLM API call metrics |

## Tool execution

| Event | Persisted | Payload |
|---|---|---|
| `tool.user_requested` | ✅ | `{ toolName }` (user manually invoked) |
| `tool.execution_start` | ✅ | `{ toolCallId, toolName, arguments }` |
| `tool.execution_partial_result` | ❌ | streaming tool output |
| `tool.execution_progress` | ❌ | progress notification |
| `tool.execution_complete` | ✅ | `{ toolCallId, success, result?, error?, durationMs }` |

## Skills and hooks

| Event | Persisted | Payload |
|---|---|---|
| `skill.invoked` | ✅ | `{ skillName, args }` |
| `hook.start` | ✅ | `{ hookName }` |
| `hook.end` | ✅ | `{ hookName, result }` |

## Sub-agents

| Event | Persisted | Payload |
|---|---|---|
| `subagent.started` | ✅ | `{ toolCallId, agentName, agentDisplayName, agentDescription }` |
| `subagent.completed` | ✅ | `{ toolCallId, agentName, agentDisplayName, model?, totalToolCalls?, totalTokens?, durationMs? }` |
| `subagent.failed` | ✅ | `{ toolCallId, agentName, agentDisplayName, error, ... }` |
| `subagent.selected` | ✅ | `{ agentName, agentDisplayName, tools: string[]\|null }` |
| `subagent.deselected` | ✅ | same as selected |

## System messages

| Event | Persisted | Payload |
|---|---|---|
| `system.message` | ✅ | `{ content }` (developer/system message) |
| `system.notification` | ✅ | `{ kind, ... }` |

Notification kinds:
- `agent_completed`
- `agent_idle`
- `shell_completed`
- `shell_detached_completed`

## User interaction (all ephemeral)

| Event | Payload |
|---|---|
| `permission.requested` | `{ requestId, kind, toolName?, operation? }` |
| `permission.completed` | `{ requestId, result }` |
| `user_input.requested` | `{ requestId, question, choices? }` |
| `user_input.completed` | `{ requestId, answer, wasFreeform }` |
| `elicitation.requested` | `{ requestId, message, requestedSchema }` |
| `elicitation.completed` | `{ requestId, action, content }` |
| `command.queued` | `{ commandId }` |
| `command.execute` | `{ commandId, name, args }` |
| `command.completed` | `{ commandId, success, error? }` |
| `external_tool.requested` | `{ toolName, arguments }` |
| `external_tool.completed` | `{ toolCallId, result }` |

Permission kinds: `shell`, `write`, `read`, `mcp`, `custom-tool`, `url`, `memory`, `hook`.

## MCP integration (ephemeral)

| Event | Payload |
|---|---|
| `mcp.oauth_required` | `{ serverName, authUrl }` |
| `mcp.oauth_completed` | `{ serverName, success }` |
| `sampling.requested` | MCP sampling request from server |
| `sampling.completed` | sampling completion |

## Configuration changes

| Event | Persisted | Payload |
|---|---|---|
| `session.tools_updated` | ✅ | `{ tools }` |
| `session.background_tasks_changed` | ❌ | `{ tasks }` |
| `session.skills_loaded` | ✅ | `{ skills }` |
| `session.custom_agents_updated` | ✅ | `{ agents }` |
| `session.mcp_servers_loaded` | ✅ | `{ servers }` |
| `session.mcp_server_status_changed` | ✅ | `{ serverName, status }` |
| `session.extensions_loaded` | ✅ | `{ extensions }` |
| `commands.changed` | ❌ | `{ commands }` |
| `capabilities.changed` | ❌ | `{ ui: { elicitation: bool }, ... }` |
| `exit_plan_mode.requested` | ❌ | `{ requestId, plan }` |
| `exit_plan_mode.completed` | ❌ | `{ autoApproveEdits, selectedAction, feedback? }` |

## Control

| Event | Persisted | Payload |
|---|---|---|
| `abort` | ✅ | `{ reason }` |

## Event ordering contract

These invariants are tested and enforced:

1. `session.idle` is always the last event in a send cycle.
2. `assistant.message_delta` always precedes `assistant.message`.
3. `tool.execution_complete.toolCallId` matches `tool.execution_start.toolCallId`.
4. `user.message` precedes `assistant.message` in the same turn.
5. Every event has non-empty `id` and ISO-8601 `timestamp`.
6. `session.compaction_complete` follows `session.compaction_start` one-to-one.
7. `permission.completed` follows `permission.requested` by `requestId`.
8. `subagent.completed` or `subagent.failed` always follows `subagent.started`.

## Ephemeral vs persisted summary

Ephemeral events (NOT replayed on resume):
- `session.idle`
- `session.title_changed`
- `session.usage_info`
- All `*.message_delta`, `*.reasoning_delta`, `*.streaming_delta`
- `pending_messages.modified`
- `assistant.intent`, `assistant.usage`
- `tool.execution_partial_result`, `tool.execution_progress`
- All `permission.*`, `user_input.*`, `elicitation.*`, `command.*`, `external_tool.*`
- All `mcp.oauth_*`, `sampling.*`
- `session.background_tasks_changed`, `commands.changed`, `capabilities.changed`
- `exit_plan_mode.*`

## Subscribing to events

```typescript
// Typed
session.on("assistant.message", (e) => {
  // e.data is typed
});

// Wildcard
session.on((e) => {
  console.log(e.type, e.id);
});

// Early (captures events before explicit subscription)
await client.createSession({
  onEvent: (e) => allEvents.push(e),
});
```

## See also

- [rpc-methods.md](rpc-methods.md) — methods that emit these events
- [built-in-tools.md](built-in-tools.md) — tools and their events
- [../02-core-concepts/hooks-and-events.md](../02-core-concepts/hooks-and-events.md) — subscribing patterns
- [../02-core-concepts/agents-and-subagents.md](../02-core-concepts/agents-and-subagents.md) — subagent events
