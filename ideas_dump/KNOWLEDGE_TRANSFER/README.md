# GitHub Copilot Agent SDK — Knowledge Transfer

Comprehensive documentation synthesized from a deep exploration of the `copilot-sdk` codebase. Captures architecture, APIs, hidden capabilities, and patterns for building autonomous agent systems.

## How to read this

- **New to the SDK?** Start at [01-overview/executive-summary.md](01-overview/executive-summary.md)
- **Building something?** Go to [02-core-concepts/](02-core-concepts/) then [06-dark-factory/](06-dark-factory/)
- **Choosing a language?** Read [03-sdk-comparison/feature-parity-matrix.md](03-sdk-comparison/feature-parity-matrix.md)
- **Deploying to production?** See [05-deployment/](05-deployment/)
- **Looking up a specific RPC method or event?** See [08-reference/](08-reference/)

## Table of Contents

### 01 — Overview
- [Executive Summary](01-overview/executive-summary.md) — What this SDK is, in 2 pages
- [Architecture](01-overview/architecture.md) — Harness model, subprocess pattern, diagrams
- [Capability Map](01-overview/capability-map.md) — Everything you can build with it

### 02 — Core Concepts
- [Sessions](02-core-concepts/sessions.md) — Lifecycle, persistence, concurrency
- [Agents and Sub-agents](02-core-concepts/agents-and-subagents.md) — Custom agents, delegation, sub-agent events
- [Tools and MCP](02-core-concepts/tools-and-mcp.md) — Custom tools, MCP servers, built-in overrides
- [Hooks and Events](02-core-concepts/hooks-and-events.md) — Lifecycle hooks, event streaming, ordering contract
- [Infinite Sessions and Compaction](02-core-concepts/infinite-sessions-and-compaction.md) — Context window management

### 03 — SDK Comparison
- [Feature Parity Matrix](03-sdk-comparison/feature-parity-matrix.md) — Language-by-language capabilities
- [Node.js / TypeScript SDK](03-sdk-comparison/nodejs-sdk.md)
- [Python SDK](03-sdk-comparison/python-sdk.md)
- [Go SDK](03-sdk-comparison/go-sdk.md)
- [.NET SDK](03-sdk-comparison/dotnet-sdk.md)

### 04 — Advanced Features
- [Session Modes](04-advanced/session-modes.md) — interactive / plan / autopilot
- [Session Fork and Fleet](04-advanced/session-fork-and-fleet.md) — Experimental branching and multi-agent
- [Session Filesystem Provider](04-advanced/session-filesystem-provider.md) — Virtual FS for serverless
- [Hidden RPC Methods](04-advanced/hidden-rpc-methods.md) — Undocumented protocol capabilities
- [System Message Customization](04-advanced/system-message-customization.md) — Prompt sections and transforms

### 05 — Deployment
- [Deployment Patterns](05-deployment/deployment-patterns.md) — Four architectures
- [Authentication](05-deployment/authentication.md) — GitHub OAuth, BYOK providers
- [Bundling and Embedding](05-deployment/bundling.md) — Go bundler, embedded CLI

### 06 — Dark Factory (Autonomous Agent Pipelines)
- [Blueprint](06-dark-factory/blueprint.md) — Full architecture for unattended agent systems
- [Implementation Guide](06-dark-factory/implementation-guide.md) — Code-level patterns

### 07 — Internals
- [Transport and Protocol](07-internals/transport-and-protocol.md) — JSON-RPC wire format
- [Codegen Pipeline](07-internals/codegen-pipeline.md) — How 4 SDKs stay in sync
- [Test Harness](07-internals/test-harness.md) — Record/replay system

### 08 — Reference
- [RPC Methods](08-reference/rpc-methods.md) — Complete method inventory
- [Event Types](08-reference/event-types.md) — All 50+ session events
- [Built-in Tools](08-reference/built-in-tools.md) — Native Copilot CLI tools

---

## Source

This documentation was synthesized from eight parallel explorations of:
- `/nodejs/` Node.js/TypeScript SDK source and tests
- `/python/` Python SDK source and tests
- `/go/` Go SDK source including transport and bundler internals
- `/dotnet/` .NET SDK source and tests
- `/docs/` Official documentation
- `/test/scenarios/` Cross-language scenario tests
- `/scripts/codegen/` Code generation pipeline
- `/scripts/corrections/` Feedback aggregation
- Generated RPC specs (`go/rpc/generated_rpc.go`, `nodejs/src/generated/`)

Repository state at time of exploration: `main` branch, commit `922959f` (Expose IncludeSubAgentStreamingEvents in all four SDKs), protocol version 3, SDK version 0.2.2.
