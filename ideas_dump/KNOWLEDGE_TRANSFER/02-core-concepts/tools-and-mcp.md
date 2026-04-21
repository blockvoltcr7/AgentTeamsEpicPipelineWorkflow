# Tools and MCP

## Three ways to give an agent tools

1. **Built-in tools** — bash, view, edit, create_file, grep, glob (always available)
2. **Custom tools** — functions you write in your SDK language, registered per session
3. **MCP servers** — external tool providers (local subprocess or remote HTTP/SSE)

## Built-in tools

The Copilot CLI exposes these natively:

| Tool | Purpose | Permission kind |
|---|---|---|
| `bash` | Execute shell commands | `shell` |
| `view` | Read file (optional line range) | `read` |
| `edit` | Modify file in place | `write` |
| `create_file` | Create new file | `write` |
| `grep` | Regex search across files | `read` |
| `glob` | Glob pattern file discovery | `read` |

See [../08-reference/built-in-tools.md](../08-reference/built-in-tools.md) for full signatures.

## Custom tools

### Node.js (Zod)

```typescript
import { defineTool } from "@github/copilot-sdk";
import { z } from "zod";

const getWeather = defineTool("get_weather", {
  description: "Fetch weather for a location",
  parameters: z.object({
    location: z.string().describe("City name"),
    units: z.enum(["celsius", "fahrenheit"]).optional(),
  }),
  handler: async ({ location, units }, invocation) => {
    // invocation: { sessionId, toolCallId, toolName, arguments, traceparent?, tracestate? }
    return { temp: 72, location, units };
  },
  skipPermission: false,       // default; set true to bypass permission handler
  overridesBuiltInTool: false, // set true when replacing a built-in like "edit"
});

await client.createSession({
  ...,
  tools: [getWeather],
});
```

### Python (Pydantic)

```python
from copilot import define_tool
from pydantic import BaseModel, Field

class WeatherArgs(BaseModel):
    location: str = Field(description="City name")
    units: str | None = None

@define_tool(name="get_weather", description="Fetch weather")
async def get_weather(args: WeatherArgs, invocation) -> dict:
    return {"temp": 72, "location": args.location}

session = await client.create_session(
    tools=[get_weather],
    on_permission_request=PermissionHandler.approve_all,
)
```

### Go (reflection)

```go
getWeather := copilot.DefineTool(
    "get_weather",
    "Fetch weather for a location",
    func(args WeatherArgs, inv copilot.ToolInvocation) (WeatherResult, error) {
        return WeatherResult{Temp: 72, Location: args.Location}, nil
    },
)

session, err := client.CreateSession(ctx, copilot.SessionConfig{
    Tools: []copilot.Tool{getWeather},
})
```

### .NET (manual schema)

```csharp
var getWeather = new Tool {
    Name = "get_weather",
    Description = "Fetch weather",
    Parameters = JsonDocument.Parse("""
        {"type":"object","properties":{"location":{"type":"string"}},"required":["location"]}
    """).RootElement,
    Handler = async (args, invocation) => new { temp = 72, location = args["location"] },
};
```

.NET is the only SDK without automatic schema generation.

## Tool return types

Three options:

```typescript
// 1. Plain string — passed as-is to the model
handler: async () => "42"

// 2. JSON object — serialized and shown to model
handler: async () => ({ result: 42, confidence: 0.95 })

// 3. Structured ToolCallResult — full control
handler: async () => ({
  textResultForLlm: "42",              // what the model sees
  resultType: "ok" | "error",
  structuredData: { ... },             // richer data for UI
  binaryResults: [...],                // images, files
  toolTelemetry: {                     // for observability
    duration_ms: 150,
    custom_metric: "value",
  },
})
```

## Overriding built-in tools

```typescript
const customEdit = defineTool("edit", {
  description: "Custom edit that logs to audit trail",
  overridesBuiltInTool: true,  // REQUIRED
  parameters: z.object({...}),
  handler: async (args) => {
    await auditLog.record(args);
    return { success: true };
  },
});
```

Without `overridesBuiltInTool: true`, the CLI throws at session creation.

## Skipping permissions

```typescript
const safeLookup = defineTool("lookup", {
  skipPermission: true,   // no permission prompt
  handler: ...,
});
```

Only do this for genuinely side-effect-free operations. The permission handler is your safety net.

## MCP servers

### Stdio (local subprocess)

```typescript
mcpServers: {
  "my-tools": {
    type: "stdio",           // (newer SDK versions: "local")
    command: "node",
    args: ["./mcp-server.js"],
    env: { DEBUG: "true" },
    cwd: "./servers",
    tools: ["*"],            // "*" = all tools, [] = none, or specific names
    timeout: 30000,
  },
}
```

### HTTP / SSE (remote)

```typescript
mcpServers: {
  "github": {
    type: "http",
    url: "https://api.githubcopilot.com/mcp/",
    headers: { "Authorization": "Bearer ${TOKEN}" },
    tools: ["*"],
  },
}
```

### Tool scoping

| Value | Effect |
|---|---|
| `tools: ["*"]` | All tools exposed to the agent |
| `tools: []` | Server connected but no tools exposed (useful for OAuth-only MCP) |
| `tools: ["tool_a", "tool_b"]` | Whitelist |

### OAuth-required MCP servers

Emits events:
- `mcp.oauth_required` — your UI must handle this
- `mcp.oauth_completed` — after user completes flow

## Auto-discovery (v0.2.2+)

```typescript
await client.createSession({
  enableConfigDiscovery: true,
  // auto-discovers:
  // - .mcp.json
  // - .vscode/mcp.json
  // - .github/copilot/skills/
});
```

Saves having to manually declare MCP servers in code when they're already configured in the repo.

## Per-agent MCP

Custom agents can have their own MCP servers:

```typescript
customAgents: [
  {
    name: "db-admin",
    mcpServers: {
      "postgres-mcp": { type: "stdio", command: "pg-mcp", ... },
    },
    tools: ["postgres-mcp.query", "postgres-mcp.explain"],
    prompt: "You are a Postgres admin...",
  },
]
```

When this agent is active, only its MCP tools are available. When a different agent activates, its MCP set swaps in.

## Runtime MCP management (experimental)

```typescript
await session.rpc.mcp.list();             // get all MCP servers + status
await session.rpc.mcp.enable({ serverName: "my-mcp" });
await session.rpc.mcp.disable({ serverName: "my-mcp" });
await session.rpc.mcp.reload();           // re-read configs from disk
```

Global MCP config (across all sessions) is managed via the server-scoped `mcp.config.*` methods.

## The `ask_user` built-in

The agent can ask the user questions via the `ask_user` tool, which triggers your `onUserInputRequest` handler:

```typescript
onUserInputRequest: async (request, invocation) => {
  // request: { question: string, choices?: string[] }
  if (request.choices?.length) {
    return { answer: request.choices[0], wasFreeform: false };
  }
  return { answer: "default response", wasFreeform: true };
}
```

Without a handler, the agent cannot use this tool.

## Tool execution events

```typescript
session.on("tool.execution_start", (e) => {
  console.log(`Tool starting: ${e.data.toolName}, ID: ${e.data.toolCallId}`);
});

session.on("tool.execution_complete", (e) => {
  console.log(`Tool done: ${e.data.toolCallId}`);
  // e.data.success, e.data.result, e.data.durationMs
});

session.on("tool.execution_partial_result", (e) => {
  // streaming output from long-running tools (ephemeral, not replayed)
});

session.on("tool.execution_progress", (e) => {
  // progress updates (ephemeral)
});
```

## Complex type support

Tools support nested objects, arrays, unions, enums — whatever your schema library expresses:

```typescript
parameters: z.object({
  filters: z.array(z.object({
    field: z.string(),
    operator: z.enum(["eq", "ne", "gt", "lt"]),
    value: z.union([z.string(), z.number()]),
  })),
  sort: z.object({
    field: z.string(),
    direction: z.enum(["asc", "desc"]),
  }).optional(),
})
```

## Error handling in tools

```typescript
handler: async (args) => {
  try {
    return await doWork(args);
  } catch (err) {
    // Option A: throw - SDK catches and returns error to model
    throw new Error(`Failed: ${err.message}`);

    // Option B: return structured error
    return {
      textResultForLlm: "The operation failed: permission denied",
      resultType: "error",
      error: err.message,
    };
  }
}
```

The model sees the error and can recover (retry with different args, ask user, abandon).

## See also

- [hooks-and-events.md](hooks-and-events.md) — permission handlers, hooks
- [../08-reference/built-in-tools.md](../08-reference/built-in-tools.md) — built-in tool reference
- [../04-advanced/hidden-rpc-methods.md](../04-advanced/hidden-rpc-methods.md) — `session.tools.handlePendingToolCall`
