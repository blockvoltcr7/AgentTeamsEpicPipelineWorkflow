# Executive Summary

## What this SDK is

The **GitHub Copilot Agent SDK** is a programmable harness around the GitHub Copilot CLI. It turns the CLI into a server process that your application drives over JSON-RPC, exposing every capability Copilot has — tools, agents, sessions, permissions, events — as a typed, language-native API.

It is **not** a new model. It is **not** a new agent framework. It is the machinery that lets you build agent-powered products on top of Copilot's existing autonomy loop, using your choice of Node.js, Python, Go, .NET, or Java.

## Key question: is this a harness to harness models and agents?

**Yes.** The architecture is unambiguously a harness:

```
Your app  ──(SDK)──▶ CopilotClient ──(JSON-RPC stdio/TCP)──▶ copilot CLI subprocess ──▶ LLM provider
```

- You never run the model in-process
- You control the CLI's behavior through typed method calls and event subscriptions
- The CLI handles the agent loop, tool dispatch, context management, and compaction
- You provide the tools, hooks, permissions, and orchestration

## Key question: can you build a dark factory?

**Yes.** Every primitive needed for an unattended agent pipeline exists:

| Requirement | SDK primitive |
|---|---|
| No human in the loop | `onPermissionRequest: approveAll` + `mode: "autopilot"` |
| Specialized roles | `customAgents` with per-agent tool whitelists and prompts |
| Long-running tasks | `infiniteSessions` with background compaction |
| Survive crashes | Persistent sessions via explicit `sessionId` + `resumeSession()` |
| Parallel execution | Multiple concurrent sessions on one client |
| Branching / A-B testing | `sessions.fork(sessionId, toEventId)` experimental API |
| Multi-agent orchestration | `session.fleet.start()` experimental API |
| Cloud-native deploy | `sessionFs` virtual filesystem — zero local disk |
| Cost monitoring | `session.usage.getMetrics()` |
| Task completion signal | `session.task_complete` event + autopilot nudge enforcement |

See [06-dark-factory/blueprint.md](../06-dark-factory/blueprint.md) for the full implementation pattern.

## Five things most readers miss

1. **Source of truth is JSON Schema.** The 4 SDKs are code-generated from `@github/copilot` npm package schemas via `json-schema-to-typescript` (TS) and `quicktype-core` (Python/Go/C#). No language is "primary."

2. **Custom agents delegate in-session, not cross-process.** They are runtime persona switches within one session with their own tool scopes — not spawned subprocesses. The Copilot runtime auto-routes work between them based on the user's request.

3. **Sub-agent events are first-class.** `subagent.started`, `subagent.completed`, `subagent.failed` events stream back with token counts, duration, tool call count — so you can monitor per-agent cost/latency.

4. **The CLI enforces completion.** In autopilot mode, if the agent stops without calling `task_complete`, the CLI injects a synthetic nudge forcing it to continue. You do not need retry logic.

5. **`sessionFs` is the key to serverless.** The server calls your SDK client for every file read/write, so you can route all I/O to S3, R2, Postgres BYTEA, or anywhere else. Zero local disk required.

## Five things most readers misunderstand

1. **Sub-agents are not subprocesses.** "Custom agents" live inside one session. To get independent processes, spawn concurrent `createSession()` calls.

2. **There is no reconnect logic.** If the CLI subprocess dies, all pending RPC calls fail. Higher-level orchestration must handle retry and resume.

3. **`session.idle` is not `session.task_complete`.** Idle means "agent stopped processing"; task_complete means "task fulfilled." In autopilot, the CLI forces the loop to continue until task_complete fires.

4. **Permission handler is required.** Every `createSession()` must pass an `onPermissionRequest` handler. There is no default. Use the built-in `approveAll` for autonomous operation.

5. **Protocol v3 is very recent.** Multi-client tool/permission broadcasts exist in v3 only; some APIs (like returning "no-result" from permission handlers) are v3-only and throw on v2 servers.

## Multi-language support at a glance

| Language | Status | Schema generation | Auto tool schemas |
|---|---|---|---|
| Node.js / TypeScript | Production | `json-schema-to-typescript` | Zod |
| Python | Production | `quicktype-core` | Pydantic |
| Go | Production | `quicktype-core` | Reflection |
| .NET (C#) | Production | `quicktype-core` | Manual JSON Schema |
| Java | Production (separate repo: `github/copilot-sdk-java`) | — | — |

All five reach feature parity via coordinated schema updates. See [03-sdk-comparison/feature-parity-matrix.md](../03-sdk-comparison/feature-parity-matrix.md).

## When to use this SDK

**Good fit:**
- Building developer tools that need Copilot-powered agents (IDE plugins, CLIs, web backends)
- Building autonomous pipelines that process tickets, PRs, code reviews, etc.
- Multi-tenant cloud services exposing agent capabilities
- Research into multi-agent orchestration on top of a production-grade CLI

**Bad fit:**
- You want a different model backend as first-class (use the Anthropic SDK, OpenAI SDK, or Vercel AI SDK instead). Copilot SDK does support BYOK, but it's routed through the Copilot CLI.
- You want to avoid a subprocess dependency (the SDK always needs the CLI binary somewhere)
- You need real-time sub-100ms latency (subprocess + JSON-RPC adds overhead)

## Where to go next

- Architecture details: [architecture.md](architecture.md)
- Full list of capabilities: [capability-map.md](capability-map.md)
- How to actually build things: [02-core-concepts/](../02-core-concepts/)
