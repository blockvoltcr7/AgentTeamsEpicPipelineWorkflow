# .NET SDK

Location: `/dotnet/`

NuGet package name per `dotnet/src/*.csproj`.

## Public API

Main types (`dotnet/src/`):

- `CopilotClient` — `IDisposable` / `IAsyncDisposable`
- `CopilotSession` — session
- `Tool` — tool definition (no `DefineTool<T>` helper; manual JSON Schema)
- `ISessionFsHandler` — for virtual FS
- `CopilotClientOptions`, `SessionConfig`, `CustomAgentConfig`, `MCPServerConfig`
- `PermissionHandler` — handlers
- `SessionLifecycleEvent` — event union

## Client lifecycle

```csharp
using Copilot;

await using var client = new CopilotClient(new CopilotClientOptions
{
    Model = "gpt-5",
    // CliPath = "/usr/local/bin/copilot",
    // CliUrl = "http://localhost:3000",
});

await client.StartAsync();

var session = await client.CreateSessionAsync(new SessionConfig
{
    OnPermissionRequest = PermissionHandler.ApproveAll,
});

// Do work...
// await using disposes client automatically
```

## Sending messages

```csharp
var message = await session.SendAndWaitAsync(new SendOptions
{
    Prompt = "What's the weather?"
});
Console.WriteLine(message.Data.Content);
```

## Tools (manual schema)

.NET is the **only SDK without automatic schema generation**. You must provide JSON Schema:

```csharp
var getWeather = new Tool
{
    Name = "get_weather",
    Description = "Fetch weather for a location",
    Parameters = JsonDocument.Parse("""
        {
          "type": "object",
          "properties": {
            "location": { "type": "string", "description": "City name" }
          },
          "required": ["location"]
        }
    """).RootElement,
    Handler = async (args, invocation) =>
    {
        var location = args.GetProperty("location").GetString();
        return new { temp = 72, location };
    },
};

var session = await client.CreateSessionAsync(new SessionConfig
{
    Tools = new[] { getWeather },
    OnPermissionRequest = PermissionHandler.ApproveAll,
});
```

## Microsoft.Extensions.AI integration

.NET's unique angle: tools are compatible with the broader MEAI ecosystem. A `Tool` can be adapted from/to an `AIFunction`, making Copilot tools interoperable with other .NET AI libraries (Semantic Kernel, etc.).

## Events

```csharp
session.On<AssistantMessageEvent>("assistant.message", (e) =>
{
    Console.WriteLine(e.Data.Content);
});

session.On<ToolExecutionCompleteEvent>("tool.execution_complete", (e) =>
{
    Console.WriteLine($"Tool done: {e.Data.ToolCallId}");
});
```

## Permission handler (with protocol v2/v3 guard)

```csharp
OnPermissionRequest = async (request, invocation) =>
{
    if (request.Kind == "shell" && IsDangerous(request.Command))
        return new PermissionResult { Kind = "denied-by-policy" };

    return new PermissionResult { Kind = "approved" };
};
```

**Note:** returning `"no-result"` throws on protocol v2 servers (enforced at runtime). Only safe on v3+.

## Session filesystem provider

```csharp
public class MyFsHandler : ISessionFsHandler
{
    public Task<SessionFsReadFileResult> ReadFileAsync(SessionFsReadFileRequest req)
        => Task.FromResult(new SessionFsReadFileResult { Content = "..." });

    public Task WriteFileAsync(SessionFsWriteFileRequest req) => Task.CompletedTask;
    public Task AppendFileAsync(SessionFsAppendFileRequest req) => Task.CompletedTask;
    public Task<SessionFsExistsResult> ExistsAsync(SessionFsExistsRequest req) => ...;
    public Task<SessionFsStatResult> StatAsync(SessionFsStatRequest req) => ...;
    public Task MkdirAsync(SessionFsMkdirRequest req) => Task.CompletedTask;
    public Task<SessionFsReaddirResult> ReaddirAsync(SessionFsReaddirRequest req) => ...;
    public Task<SessionFsReaddirWithTypesResult> ReaddirWithTypesAsync(SessionFsReaddirWithTypesRequest req) => ...;
    public Task RmAsync(SessionFsRmRequest req) => Task.CompletedTask;
    public Task RenameAsync(SessionFsRenameRequest req) => Task.CompletedTask;
}

var client = new CopilotClient(new CopilotClientOptions
{
    SessionFs = new SessionFsConfig
    {
        InitialCwd = "/virtual",
        SessionStatePath = "/virtual/state",
        Conventions = "posix",
    },
});

var session = await client.CreateSessionAsync(new SessionConfig
{
    CreateSessionFsHandler = (sessionId) => new MyFsHandler(),
    OnPermissionRequest = PermissionHandler.ApproveAll,
});
```

## Native RID bundling

The .NET SDK automatically finds the CLI binary from:

1. Explicit `CliPath` option
2. `COPILOT_CLI_PATH` environment variable
3. External URL (`CliUrl`)
4. Bundled: `runtimes/{rid}/native/copilot` or `runtimes/{rid}/native/copilot.exe`

No PATH search (by design — prevents accidental wrong-binary usage).

## Source-generated JSON (AOT / trimming)

The SDK ships source-generated `JsonSerializerContext` instances:

- `ClientJsonContext`
- `TypesJsonContext`
- Custom `RequestIdTypeInfoResolver` for StreamJsonRpc compatibility

This means `dotnet publish -p:PublishAot=true` works without runtime reflection.

## Thread safety

Uses `ConcurrentDictionary<string, CopilotSession>` internally for session tracking. Safe to call from multiple threads.

## .NET-specific quirks

1. **Permission handler required** — every session needs `OnPermissionRequest`; no default.
2. **No PATH search for CLI** — deterministic-only binary lookup.
3. **stderr captured** — CLI stderr goes into a `StringBuilder` and is included in error messages.
4. **TCP port detection** — regex on stdout: `/listening on port ([0-9]+)/i`.
5. **Session FS config timing** — `SetProvider` RPC fails if sessions already exist. Configure before creating any.
6. **xUnit test helpers use reflection** — `ITestOutputHelper` → `ITest` via private field access.

## Testing

```bash
just test-dotnet
```

Or inside `/dotnet/`:

```bash
dotnet test
```

Tests use xUnit and share the record/replay harness via `CapiProxy.cs`.

## See also

- [feature-parity-matrix.md](feature-parity-matrix.md)
- [../04-advanced/session-filesystem-provider.md](../04-advanced/session-filesystem-provider.md)
- [../07-internals/test-harness.md](../07-internals/test-harness.md)
