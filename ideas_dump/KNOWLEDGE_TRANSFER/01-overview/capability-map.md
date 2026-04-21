# Capability Map

Everything the Copilot Agent SDK can do, organized by theme. Each line links to the relevant deep-dive doc.

## Session management

| Capability | Doc |
|---|---|
| Create a session (ephemeral or named) | [sessions.md](../02-core-concepts/sessions.md) |
| Resume a session from disk | [sessions.md](../02-core-concepts/sessions.md) |
| Run multiple concurrent sessions on one client | [sessions.md](../02-core-concepts/sessions.md) |
| Share a session across multiple clients | [sessions.md](../02-core-concepts/sessions.md) |
| Fork a session at a specific event (experimental) | [session-fork-and-fleet.md](../04-advanced/session-fork-and-fleet.md) |
| Delete a session permanently | [sessions.md](../02-core-concepts/sessions.md) |
| Get session metadata (`session.getMetadata()`) | [sessions.md](../02-core-concepts/sessions.md) |
| List / enumerate sessions | [sessions.md](../02-core-concepts/sessions.md) |

## Agent orchestration

| Capability | Doc |
|---|---|
| Define custom agents with per-agent tools and prompts | [agents-and-subagents.md](../02-core-concepts/agents-and-subagents.md) |
| Have the runtime auto-route tasks to sub-agents | [agents-and-subagents.md](../02-core-concepts/agents-and-subagents.md) |
| Receive `subagent.started/completed/failed` events | [agents-and-subagents.md](../02-core-concepts/agents-and-subagents.md) |
| Switch between agents at runtime | [agents-and-subagents.md](../02-core-concepts/agents-and-subagents.md) |
| Switch session mode: interactive / plan / autopilot | [session-modes.md](../04-advanced/session-modes.md) |
| Start fleet mode (multi-agent fleet, experimental) | [session-fork-and-fleet.md](../04-advanced/session-fork-and-fleet.md) |

## Tools

| Capability | Doc |
|---|---|
| Register custom tools with typed parameters | [tools-and-mcp.md](../02-core-concepts/tools-and-mcp.md) |
| Override built-in tools (edit_file, read_file, etc.) | [tools-and-mcp.md](../02-core-concepts/tools-and-mcp.md) |
| Skip permission prompts for safe tools | [tools-and-mcp.md](../02-core-concepts/tools-and-mcp.md) |
| Attach local MCP servers (stdio subprocesses) | [tools-and-mcp.md](../02-core-concepts/tools-and-mcp.md) |
| Attach remote MCP servers (HTTP/SSE) | [tools-and-mcp.md](../02-core-concepts/tools-and-mcp.md) |
| Whitelist / blacklist MCP tools | [tools-and-mcp.md](../02-core-concepts/tools-and-mcp.md) |
| Use built-in tools (bash, view, edit, create_file, grep, glob) | [built-in-tools.md](../08-reference/built-in-tools.md) |
| Auto-discover `.mcp.json` / `.vscode/mcp.json` configs | [tools-and-mcp.md](../02-core-concepts/tools-and-mcp.md) |

## Hooks and callbacks

| Capability | Doc |
|---|---|
| `onPreToolUse` — intercept tool calls | [hooks-and-events.md](../02-core-concepts/hooks-and-events.md) |
| `onPostToolUse` — transform tool results | [hooks-and-events.md](../02-core-concepts/hooks-and-events.md) |
| `onUserPromptSubmitted` — modify user input | [hooks-and-events.md](../02-core-concepts/hooks-and-events.md) |
| `onSessionStart` / `onSessionEnd` — lifecycle | [hooks-and-events.md](../02-core-concepts/hooks-and-events.md) |
| `onErrorOccurred` — error recovery | [hooks-and-events.md](../02-core-concepts/hooks-and-events.md) |
| `onPermissionRequest` — approve/deny operations | [hooks-and-events.md](../02-core-concepts/hooks-and-events.md) |
| `onUserInputRequest` — respond to `ask_user` tool | [hooks-and-events.md](../02-core-concepts/hooks-and-events.md) |
| `onElicitationRequest` — form-based UI dialogs | [hooks-and-events.md](../02-core-concepts/hooks-and-events.md) |
| Register slash commands | [hooks-and-events.md](../02-core-concepts/hooks-and-events.md) |

## Events and streaming

| Capability | Doc |
|---|---|
| Subscribe to typed events (`session.on("assistant.message", ...)`) | [hooks-and-events.md](../02-core-concepts/hooks-and-events.md) |
| Stream message deltas in real-time | [hooks-and-events.md](../02-core-concepts/hooks-and-events.md) |
| Stream reasoning deltas (extended thinking) | [event-types.md](../08-reference/event-types.md) |
| Get complete event list with guaranteed ordering | [event-types.md](../08-reference/event-types.md) |
| Receive `capabilities.changed` when clients join/leave | [event-types.md](../08-reference/event-types.md) |

## Context management

| Capability | Doc |
|---|---|
| Enable infinite sessions with background compaction | [infinite-sessions-and-compaction.md](../02-core-concepts/infinite-sessions-and-compaction.md) |
| Manually trigger compaction (`session.history.compact`) | [hidden-rpc-methods.md](../04-advanced/hidden-rpc-methods.md) |
| Truncate history at a specific event (`session.history.truncate`) | [hidden-rpc-methods.md](../04-advanced/hidden-rpc-methods.md) |
| Switch model mid-session (`session.model.switchTo`) | [hidden-rpc-methods.md](../04-advanced/hidden-rpc-methods.md) |
| Override model capabilities (vision, reasoning, token limits) | [hidden-rpc-methods.md](../04-advanced/hidden-rpc-methods.md) |

## Filesystem and workspace

| Capability | Doc |
|---|---|
| Use a virtual filesystem (zero local disk, serverless-ready) | [session-filesystem-provider.md](../04-advanced/session-filesystem-provider.md) |
| List / read / create workspace files (`session.workspaces.*`) | [hidden-rpc-methods.md](../04-advanced/hidden-rpc-methods.md) |
| Direct shell execution (`session.shell.exec/kill`) | [hidden-rpc-methods.md](../04-advanced/hidden-rpc-methods.md) |
| Get active instruction sources (CLAUDE.md-style) | [hidden-rpc-methods.md](../04-advanced/hidden-rpc-methods.md) |

## System prompt

| Capability | Doc |
|---|---|
| Append custom instructions | [system-message-customization.md](../04-advanced/system-message-customization.md) |
| Replace full system prompt | [system-message-customization.md](../04-advanced/system-message-customization.md) |
| Customize individual sections (identity, tone, safety, etc.) | [system-message-customization.md](../04-advanced/system-message-customization.md) |
| Apply transforms to sections at runtime | [system-message-customization.md](../04-advanced/system-message-customization.md) |

## Plan and task management

| Capability | Doc |
|---|---|
| Read / update / delete plan file (`session.plan.*`) | [hidden-rpc-methods.md](../04-advanced/hidden-rpc-methods.md) |
| Receive `session.task_complete` on success | [session-modes.md](../04-advanced/session-modes.md) |
| Receive `exit_plan_mode.requested` for approval | [session-modes.md](../04-advanced/session-modes.md) |

## Observability

| Capability | Doc |
|---|---|
| OpenTelemetry tracing with W3C trace context | [hidden-rpc-methods.md](../04-advanced/hidden-rpc-methods.md) |
| Session usage metrics (tokens, cost, duration) | [hidden-rpc-methods.md](../04-advanced/hidden-rpc-methods.md) |
| Account quota (`account.getQuota`) | [hidden-rpc-methods.md](../04-advanced/hidden-rpc-methods.md) |
| Session log injection (`session.log()`) | [hidden-rpc-methods.md](../04-advanced/hidden-rpc-methods.md) |

## Authentication

| Capability | Doc |
|---|---|
| GitHub OAuth (signed-in user) | [authentication.md](../05-deployment/authentication.md) |
| GitHub App / fine-grained PAT | [authentication.md](../05-deployment/authentication.md) |
| BYOK: OpenAI | [authentication.md](../05-deployment/authentication.md) |
| BYOK: Anthropic (Claude) | [authentication.md](../05-deployment/authentication.md) |
| BYOK: Azure OpenAI / AI Foundry | [authentication.md](../05-deployment/authentication.md) |
| BYOK: Ollama / local OpenAI-compatible | [authentication.md](../05-deployment/authentication.md) |

## Deployment

| Capability | Doc |
|---|---|
| Fully-bundled (CLI binary embedded) | [deployment-patterns.md](../05-deployment/deployment-patterns.md) |
| Container-proxy (no secrets in container) | [deployment-patterns.md](../05-deployment/deployment-patterns.md) |
| App-backend-to-server (HTTP API + TCP CLI) | [deployment-patterns.md](../05-deployment/deployment-patterns.md) |
| App-direct-server (direct TCP) | [deployment-patterns.md](../05-deployment/deployment-patterns.md) |
| Embed CLI binary into Go binary (`go tool bundler`) | [bundling.md](../05-deployment/bundling.md) |
| Multi-user shared server with per-user isolation | [deployment-patterns.md](../05-deployment/deployment-patterns.md) |

## Advanced / experimental

| Capability | Doc |
|---|---|
| Session fork (branch at event ID) | [session-fork-and-fleet.md](../04-advanced/session-fork-and-fleet.md) |
| Fleet mode (multi-agent fleet) | [session-fork-and-fleet.md](../04-advanced/session-fork-and-fleet.md) |
| Skill management (enable/disable/reload) | [hidden-rpc-methods.md](../04-advanced/hidden-rpc-methods.md) |
| Extension management | [hidden-rpc-methods.md](../04-advanced/hidden-rpc-methods.md) |
| Plugin listing | [hidden-rpc-methods.md](../04-advanced/hidden-rpc-methods.md) |

## What the SDK does NOT do

- Host the model in-process (always needs CLI binary)
- Reconnect on CLI crash (higher layers must handle)
- Provide cross-instance state sync guarantees
- Offer a task queue / job scheduler (you must build this)
- Expose built-in authentication for your end-users (separate concern)
