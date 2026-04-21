# Go SDK

Location: `/go/`

Go module path per `go.mod`.

## Public API

Types (`go/types.go`, `go/session.go`, `go/client.go`):

- `Client` — connection manager
- `Session` — conversation session
- `Tool` — tool definition (use `DefineTool[TArgs, TResult]` generic helper)
- `SessionConfig`, `CustomAgentConfig`, `MCPServerConfig`
- `PermissionHandler` (with `.ApproveAll`)
- `SessionEvent` — event union

## Client lifecycle

```go
import (
    "context"
    copilot "github.com/github/copilot-sdk/go"
)

ctx := context.Background()

client := copilot.NewClient(copilot.ClientOptions{
    Model: "gpt-5",
    // CliPath: "...",
    // CliURL:  "...",
})

if err := client.Start(ctx); err != nil {
    log.Fatal(err)
}
defer client.Stop(ctx)

session, err := client.CreateSession(ctx, copilot.SessionConfig{
    OnPermissionRequest: copilot.PermissionHandler.ApproveAll,
})
```

## Tool definition (generic helper)

```go
type WeatherArgs struct {
    Location string `json:"location" description:"City name"`
}

type WeatherResult struct {
    Temp     int    `json:"temp"`
    Location string `json:"location"`
}

getWeather := copilot.DefineTool(
    "get_weather",
    "Fetch weather for a location",
    func(args WeatherArgs, inv copilot.ToolInvocation) (WeatherResult, error) {
        return WeatherResult{Temp: 72, Location: args.Location}, nil
    },
)

session, err := client.CreateSession(ctx, copilot.SessionConfig{
    Tools: []copilot.Tool{getWeather},
    OnPermissionRequest: copilot.PermissionHandler.ApproveAll,
})
```

JSON Schema is generated automatically from struct reflection, honoring `json` and `description` tags.

## Sending messages

```go
// Fire-and-forget
err := session.Send(ctx, copilot.SendOptions{
    Prompt: "What's the weather in NYC?",
})

// Or await final message
msg, err := session.SendAndWait(ctx, copilot.SendOptions{
    Prompt: "...",
})
fmt.Println(msg.Data.Content)
```

## Event streaming

```go
// Channel-based
events := session.Events()
for event := range events {
    switch event.Type {
    case "assistant.message":
        fmt.Println(event.Data.Content)
    case "tool.execution_start":
        fmt.Printf("Tool: %s\n", event.Data.ToolName)
    case "session.idle":
        return
    }
}
```

## Hooks

```go
session, err := client.CreateSession(ctx, copilot.SessionConfig{
    Hooks: copilot.SessionHooks{
        OnPreToolUse: func(input copilot.PreToolUseHookInput, inv copilot.HookInvocation) (*copilot.PreToolUseHookOutput, error) {
            if input.ToolName == "bash" && strings.Contains(input.Arguments.Command, "rm -rf") {
                return &copilot.PreToolUseHookOutput{
                    PermissionDecision: "deny",
                }, nil
            }
            return nil, nil
        },
        OnPostToolUse: func(input copilot.PostToolUseHookInput, inv copilot.HookInvocation) (*copilot.PostToolUseHookOutput, error) {
            return nil, nil
        },
    },
    OnPermissionRequest: copilot.PermissionHandler.ApproveAll,
})
```

## Concurrency

Go SDK is fully concurrency-safe (`sync.RWMutex` throughout):

```go
// Safe to call from multiple goroutines on the same client
var wg sync.WaitGroup
for _, task := range tasks {
    wg.Add(1)
    go func(t Task) {
        defer wg.Done()
        session, _ := client.CreateSession(ctx, copilot.SessionConfig{...})
        defer session.Disconnect(ctx)
        session.SendAndWait(ctx, copilot.SendOptions{Prompt: t.Prompt})
    }(task)
}
wg.Wait()
```

## Embedded CLI (unique to Go)

The Go SDK can embed the CLI binary at build time:

```bash
# From project root, run the bundler
go run github.com/github/copilot-sdk/go/cmd/bundler@latest \
    -goos=linux -goarch=amd64 \
    -output=./embed
```

This generates `zcopilot_linux_amd64.go` with `//go:embed` directives. Your final binary then includes the CLI compressed with zstd:

```go
import _ "yourmodule/embed"   // triggers init() that registers the embedded CLI
```

First run extracts the CLI to `~/.cache/copilot-sdk/copilot_<version>` with SHA-256 verification. Subsequent runs reuse the cached binary.

See [../05-deployment/bundling.md](../05-deployment/bundling.md).

## Context cancellation

Every method takes `context.Context`. Cancel a long-running session cleanly:

```go
ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
defer cancel()

session.SendAndWait(ctx, ...)   // respects ctx cancellation
```

## Infinite sessions

```go
session, err := client.CreateSession(ctx, copilot.SessionConfig{
    InfiniteSessions: &copilot.InfiniteSessionsConfig{
        Enabled: true,
        BackgroundCompactionThreshold: 0.80,
        BufferExhaustionThreshold: 0.95,
    },
})
```

## MCP and custom agents

Same shape as other SDKs, Go-struct form:

```go
session, err := client.CreateSession(ctx, copilot.SessionConfig{
    MCPServers: map[string]copilot.MCPServerConfig{
        "postgres": {
            Type: "stdio",
            Command: "pg-mcp",
            Args: []string{"--port", "5432"},
            Tools: []string{"*"},
        },
    },
    CustomAgents: []copilot.CustomAgentConfig{
        {
            Name: "researcher",
            Tools: []string{"grep", "glob", "view"},
            Prompt: "You are a researcher.",
            Infer: true,
        },
    },
})
```

## Sub-agent streaming events

```go
session, err := client.CreateSession(ctx, copilot.SessionConfig{
    IncludeSubAgentStreamingEvents: true,
})
```

Added in commit `922959f` across all SDKs.

## Go-specific advantages

1. **Concurrency first-class** — no GIL, goroutines can hammer the client safely
2. **Statically compiled** — ship a single binary, no runtime dependency (with embedded CLI)
3. **Reflection-based schema** — zero boilerplate for tools
4. **Context propagation** — cancellation works top to bottom
5. **`just scenario-verify` runs Go alongside TS/Python/C#** — cross-language parity

## Testing

```bash
cd go/
./test.sh
```

Or:

```bash
just test-go
```

E2E tests in `/go/internal/e2e/` mirror the Node.js ones.

## See also

- [../05-deployment/bundling.md](../05-deployment/bundling.md) — Go bundler deep-dive
- [../07-internals/transport-and-protocol.md](../07-internals/transport-and-protocol.md) — JSON-RPC internals (Go has the canonical implementation)
- [feature-parity-matrix.md](feature-parity-matrix.md)
