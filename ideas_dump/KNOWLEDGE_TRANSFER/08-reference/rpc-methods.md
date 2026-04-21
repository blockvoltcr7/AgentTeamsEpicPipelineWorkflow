# RPC Method Reference

Complete index of RPC methods in protocol v3. Generated from `go/rpc/generated_rpc.go` and `nodejs/src/generated/rpc.ts`.

Legend:
- **Server-scoped**: called on the client directly (`client.rpc.*`)
- **Session-scoped**: called on a session (`session.rpc.*`)
- **Reverse**: called by the server into your client-registered handler

## Server-scoped

### Health

| Method | Params | Returns |
|---|---|---|
| `ping` | `{ message? }` | `{ message, timestamp, protocolVersion }` |

### Models and tools

| Method | Params | Returns |
|---|---|---|
| `models.list` | — | `{ models: Model[] }` |
| `tools.list` | `{ model? }` | `{ tools: Tool[] }` |

### Account

| Method | Params | Returns |
|---|---|---|
| `account.getQuota` | — | `{ quotaSnapshots: {...} }` |

### MCP

| Method | Params | Returns |
|---|---|---|
| `mcp.config.list` | — | `McpConfigList` |
| `mcp.config.add` | `{ name, config }` | — |
| `mcp.config.update` | `{ name, config }` | — |
| `mcp.config.remove` | `{ name }` | — |
| `mcp.discover` | `{ workingDirectory? }` | `{ servers: DiscoveredMcpServer[] }` |

### Skills

| Method | Params | Returns |
|---|---|---|
| `skills.config.setDisabledSkills` | `{ disabledSkills: string[] }` | — |
| `skills.discover` | `{ projectPaths?, skillDirectories? }` | `{ skills: ServerSkill[] }` |

### Session FS (bootstrap)

| Method | Params | Returns |
|---|---|---|
| `sessionFs.setProvider` | `{ initialCwd, sessionStatePath, conventions }` | `{ success }` |

### Sessions (experimental)

| Method | Params | Returns |
|---|---|---|
| `sessions.fork` | `{ sessionId, toEventId? }` | `{ sessionId }` |

## Session-scoped

### Model

| Method | Params | Returns |
|---|---|---|
| `session.model.getCurrent` | — | `{ modelId: string\|null }` |
| `session.model.switchTo` | `{ modelId, reasoningEffort?, modelCapabilities? }` | `{ modelId }` |

### Mode

| Method | Params | Returns |
|---|---|---|
| `session.mode.get` | — | `{ mode: "interactive"\|"plan"\|"autopilot" }` |
| `session.mode.set` | `{ mode }` | — |

### Name

| Method | Params | Returns |
|---|---|---|
| `session.name.get` | — | `{ name: string\|null }` |
| `session.name.set` | `{ name }` | — |

### Plan

| Method | Params | Returns |
|---|---|---|
| `session.plan.read` | — | `{ exists, content, path }` |
| `session.plan.update` | `{ content }` | — |
| `session.plan.delete` | — | — |

### Workspaces

| Method | Params | Returns |
|---|---|---|
| `session.workspaces.getWorkspace` | — | `{ workspace: {...}\|null }` |
| `session.workspaces.listFiles` | — | `{ files: string[] }` |
| `session.workspaces.readFile` | `{ path }` | `{ content }` |
| `session.workspaces.createFile` | `{ path, content }` | — |

### Instructions

| Method | Params | Returns |
|---|---|---|
| `session.instructions.getSources` | — | `{ sources: InstructionSource[] }` |

### Fleet (experimental)

| Method | Params | Returns |
|---|---|---|
| `session.fleet.start` | `{ prompt? }` | `{ started: boolean }` |

### Agent (experimental)

| Method | Params | Returns |
|---|---|---|
| `session.agent.list` | — | `{ agents: AgentInfo[] }` |
| `session.agent.getCurrent` | — | `{ agent: AgentInfo\|null }` |
| `session.agent.select` | `{ name }` | `{ agent: AgentInfo }` |
| `session.agent.deselect` | — | — |
| `session.agent.reload` | — | `{ agents: AgentInfo[] }` |

### Skills (experimental)

| Method | Params | Returns |
|---|---|---|
| `session.skills.list` | — | `{ skills: Skill[] }` |
| `session.skills.enable` | `{ name }` | — |
| `session.skills.disable` | `{ name }` | — |
| `session.skills.reload` | — | — |

### MCP per-session (experimental)

| Method | Params | Returns |
|---|---|---|
| `session.mcp.list` | — | `{ servers: McpServerStatus[] }` |
| `session.mcp.enable` | `{ serverName }` | — |
| `session.mcp.disable` | `{ serverName }` | — |
| `session.mcp.reload` | — | — |

### Plugins (experimental, read-only)

| Method | Params | Returns |
|---|---|---|
| `session.plugins.list` | — | `{ plugins: Plugin[] }` |

### Extensions (experimental)

| Method | Params | Returns |
|---|---|---|
| `session.extensions.list` | — | `{ extensions: Extension[] }` |
| `session.extensions.enable` | `{ id }` | — |
| `session.extensions.disable` | `{ id }` | — |
| `session.extensions.reload` | — | — |

### Tools

| Method | Params | Returns |
|---|---|---|
| `session.tools.handlePendingToolCall` | `{ requestId, result?, error? }` | `{ success }` |

Internal — SDK wrappers use this automatically.

### Commands

| Method | Params | Returns |
|---|---|---|
| `session.commands.handlePendingCommand` | `{ requestId, error? }` | `{ success }` |

Internal.

### UI

| Method | Params | Returns |
|---|---|---|
| `session.ui.elicitation` | `{ message, requestedSchema }` | `{ action, content }` |
| `session.ui.handlePendingElicitation` | `{ requestId, result }` | `{ success }` |

### Permissions

| Method | Params | Returns |
|---|---|---|
| `session.permissions.handlePendingPermissionRequest` | `{ requestId, result }` | `{ success }` |

Internal.

### Log

| Method | Params | Returns |
|---|---|---|
| `session.log` | `{ message, level?, ephemeral?, url? }` | `{ eventId }` |

### Shell

| Method | Params | Returns |
|---|---|---|
| `session.shell.exec` | `{ command, cwd?, timeout? }` | `{ processId }` |
| `session.shell.kill` | `{ processId, signal? }` | `{ killed }` |

### History (experimental)

| Method | Params | Returns |
|---|---|---|
| `session.history.compact` | — | `{ success, tokensRemoved, messagesRemoved, contextWindow }` |
| `session.history.truncate` | `{ eventId }` | `{ eventsRemoved }` |

### Usage (experimental)

| Method | Params | Returns |
|---|---|---|
| `session.usage.getMetrics` | — | `UsageMetrics` |

## Reverse RPC (server → client)

Your application implements these as `sessionFs` handlers.

| Method | Params |
|---|---|
| `sessionFs.readFile` | `{ path }` |
| `sessionFs.writeFile` | `{ path, content }` |
| `sessionFs.appendFile` | `{ path, content }` |
| `sessionFs.exists` | `{ path }` |
| `sessionFs.stat` | `{ path }` |
| `sessionFs.mkdir` | `{ path }` |
| `sessionFs.readdir` | `{ path }` |
| `sessionFs.readdirWithTypes` | `{ path }` |
| `sessionFs.rm` | `{ path, recursive? }` |
| `sessionFs.rename` | `{ oldPath, newPath }` |

## Method count summary

| Category | Count |
|---|---|
| Server-scoped (stable) | ~11 |
| Server-scoped (experimental) | 1 |
| Session-scoped (stable) | ~15 |
| Session-scoped (experimental) | ~30 |
| Reverse (sessionFs) | 10 |
| **Total** | **~67** |

## Protocol version gate

Methods introduced in v3 throw on v2 servers. Notable v3-only:

- Most `session.*.reload` variants
- `session.fleet.*`
- `sessions.fork`
- Multi-client broadcast events (`capabilities.changed`)
- Permission result kind `no-result`

## See also

- [event-types.md](event-types.md) — all event types
- [built-in-tools.md](built-in-tools.md) — native tool reference
- [../04-advanced/hidden-rpc-methods.md](../04-advanced/hidden-rpc-methods.md) — usage examples
- [../07-internals/codegen-pipeline.md](../07-internals/codegen-pipeline.md) — how this list is generated
