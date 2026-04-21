# Feature Parity Matrix

All five SDKs (Node.js, Python, Go, .NET, Java) target the same protocol and are generated from the same JSON Schema. Parity is maintained by policy (CHANGELOG notes when a feature "ships across all four SDKs"). Actual differences are largely language idioms and tooling ergonomics.

## Core features

| Feature | Node.js | Python | Go | .NET | Java |
|---|---|---|---|---|---|
| Session create / resume / delete | ✅ | ✅ | ✅ | ✅ | ✅ |
| Concurrent sessions | ✅ | ✅ | ✅ | ✅ | ✅ |
| Session metadata lookup | ✅ | ✅ | ✅ | ✅ | — |
| Persistent sessions | ✅ | ✅ | ✅ | ✅ | ✅ |
| Streaming deltas | ✅ | ✅ | ✅ | ✅ | ✅ |
| Reasoning deltas (extended thinking) | ✅ | ✅ | ✅ | ✅ | ✅ |

## Tool support

| Feature | Node.js | Python | Go | .NET | Java |
|---|---|---|---|---|---|
| Custom tools | ✅ | ✅ | ✅ | ✅ | ✅ |
| Auto schema generation | ✅ Zod | ✅ Pydantic | ✅ reflection | ❌ manual JSON | ? |
| Built-in tool overrides | ✅ | ✅ | ✅ | ✅ | ✅ |
| Skip-permission flag | ✅ | ✅ | ✅ | ✅ | ✅ |
| Complex nested parameter types | ✅ | ✅ | ✅ | ✅ | ✅ |
| Structured tool results | ✅ | ✅ | ✅ | ✅ | ✅ |

## Agents and orchestration

| Feature | Node.js | Python | Go | .NET | Java |
|---|---|---|---|---|---|
| Custom agents | ✅ | ✅ | ✅ | ✅ | ✅ |
| Pre-select agent at create | ✅ | ✅ | ✅ | ✅ | ✅ |
| Runtime agent switching | ✅ | ✅ | ✅ | ✅ | ? |
| Sub-agent streaming events | ✅ | ✅ | ✅ | ✅ | ? |
| `IncludeSubAgentStreamingEvents` | ✅ | ✅ | ✅ | ✅ | — |
| Session modes (interactive/plan/autopilot) | ✅ | ✅ | ✅ | ✅ | ? |

## MCP

| Feature | Node.js | Python | Go | .NET | Java |
|---|---|---|---|---|---|
| Stdio MCP servers | ✅ | ✅ | ✅ | ✅ | ✅ |
| HTTP/SSE MCP servers | ✅ | ✅ | ✅ | ✅ | ✅ |
| Tool whitelist/blacklist | ✅ | ✅ | ✅ | ✅ | ✅ |
| Runtime enable/disable | ✅ | ✅ | ✅ | ✅ | ? |
| Env var passthrough | ✅ | ✅ | ✅ | ✅ | ✅ |
| OAuth MCP flow events | ✅ | ✅ | ✅ | ✅ | ? |

## Hooks and callbacks

| Feature | Node.js | Python | Go | .NET | Java |
|---|---|---|---|---|---|
| `onPreToolUse` / `onPostToolUse` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `onUserPromptSubmitted` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `onSessionStart` / `onSessionEnd` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `onErrorOccurred` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `onPermissionRequest` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `onUserInputRequest` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `onElicitationRequest` | ✅ | ✅ | ✅ | ✅ | ? |
| Slash commands | ✅ | ✅ | ✅ | ✅ | ? |

## Infinite sessions

| Feature | Node.js | Python | Go | .NET | Java |
|---|---|---|---|---|---|
| Background compaction | ✅ | ✅ | ✅ | ✅ | ✅ |
| Configurable thresholds | ✅ | ✅ | ✅ | ✅ | ✅ |
| Manual compaction (experimental) | ✅ | ✅ | ✅ | ✅ | ? |
| Manual truncation (experimental) | ✅ | ✅ | ✅ | ✅ | ? |
| `workspacePath` exposure | ✅ | ✅ | ✅ | ✅ | ? |

## System message customization

| Feature | Node.js | Python | Go | .NET | Java |
|---|---|---|---|---|---|
| Append mode | ✅ | ✅ | ✅ | ✅ | ✅ |
| Replace mode | ✅ | ✅ | ✅ | ✅ | ✅ |
| Customize (section-level) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Runtime transform functions | ✅ | ✅ | ✅ | ✅ | ? |
| 10 standard sections | ✅ | ✅ | ✅ | ✅ | ✅ |

## Observability

| Feature | Node.js | Python | Go | .NET | Java |
|---|---|---|---|---|---|
| OpenTelemetry with W3C trace context | ✅ | ✅ | ✅ | ✅ | ✅ |
| Usage metrics (experimental) | ✅ | ✅ | ✅ | ✅ | ? |
| Account quota | ✅ | ✅ | ✅ | ✅ | ✅ |
| Session logging (`session.log`) | ✅ | ✅ | ✅ | ✅ | ✅ |

## Experimental / advanced

| Feature | Node.js | Python | Go | .NET | Java |
|---|---|---|---|---|---|
| Session fork | ✅ | ✅ | ✅ | ✅ | ? |
| Fleet mode | ✅ | ✅ | ✅ | ✅ | ? |
| Session FS provider | ✅ | ✅ | ✅ | ✅ | ? |
| Skills management | ✅ | ✅ | ✅ | ✅ | ? |
| Extensions management | ✅ | ✅ | ✅ | ✅ | ? |
| Plugin listing | ✅ | ✅ | ✅ | ✅ | ? |

## Transport

| Feature | Node.js | Python | Go | .NET | Java |
|---|---|---|---|---|---|
| stdio | ✅ | ✅ | ✅ | ✅ | ✅ |
| TCP | ✅ | ✅ | ✅ | ✅ | ✅ |
| External URL | ✅ | ✅ | ✅ | ✅ | ✅ |
| Bundled CLI binary | npm | pip | `go tool bundler` | NuGet RID | Maven |
| Extension subprocess mode | ✅ `joinSession` | ? | ? | ? | ? |

## Language-specific differences

### Node.js
- TypeScript-native, Zod for schemas
- Supports `Symbol.asyncDispose` (TS 5.2+) for `await using session = ...`
- `joinSession` helper for running as a CLI extension subprocess
- Rich type inference for tool handlers

### Python
- Async/await native
- Context manager support (`async with CopilotClient() as client:`)
- Pydantic integration for tool schemas
- Fully typed with TypedDict / dataclass definitions

### Go
- Statically compiled, zero runtime deps
- Generic `DefineTool[TArgs, TResult]` with reflection-based schema
- `sync.RWMutex` for thread safety
- Embedded CLI via `go tool bundler` (unique to Go)
- Context-based cancellation throughout

### .NET
- Microsoft.Extensions.AI integration — tools compatible with broader .NET AI ecosystem
- Source-generated JSON for AOT/trimming
- `ConcurrentDictionary` for session tracking
- **No auto schema generation** — tools require manual JSON Schema
- Native RID bundling (`runtimes/{rid}/native/copilot`)

### Java
- Separate repo: `github/copilot-sdk-java`
- Maven Central artifact
- Less detailed coverage in main SDK repo (externally maintained)

## Recommendation by use case

| Your need | Pick |
|---|---|
| Production dark factory | Go (concurrency, zero deps, embeddable) |
| Rapid prototyping | Python (Pydantic, async/await ergonomics) |
| IDE extension / web UI | Node.js (ecosystem, streaming) |
| .NET shop | .NET (accept the manual schema overhead) |
| JVM shop | Java (separate repo, mature but less feature density) |

## How parity is maintained

All SDKs generated from `@github/copilot/schemas/*.json`. See [../07-internals/codegen-pipeline.md](../07-internals/codegen-pipeline.md).

CHANGELOG explicitly calls out cross-SDK feature drops:
> v0.2.1 — "Commands and UI elicitation across all four SDKs"
> v0.2.0 — "OpenTelemetry support across all SDKs"

When a feature lands in one, it lands in all. The SDK team treats parity gaps as bugs.

## See also

- [nodejs-sdk.md](nodejs-sdk.md)
- [python-sdk.md](python-sdk.md)
- [go-sdk.md](go-sdk.md)
- [dotnet-sdk.md](dotnet-sdk.md)
- [../07-internals/codegen-pipeline.md](../07-internals/codegen-pipeline.md)
