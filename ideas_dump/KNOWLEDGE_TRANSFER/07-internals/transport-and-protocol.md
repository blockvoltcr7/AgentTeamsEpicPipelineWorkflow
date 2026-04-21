# Transport and Protocol Internals

How bytes actually flow between your SDK and the Copilot CLI.

## Wire format: LSP-style framing

The SDK uses **Content-Length header framing**, the same scheme as the Language Server Protocol. This is not the Chrome DevTools / newline-delimited JSON convention.

```
Content-Length: 342\r\n
\r\n
{"jsonrpc":"2.0","id":1,"method":"session.send","params":{...}}
```

Two-part frame:

1. Headers (newline-separated `Name: Value` pairs) terminated by a blank line
2. Body of exactly `Content-Length` bytes

Canonical implementation: `go/internal/jsonrpc2/frame.go`.

### Why LSP framing?

- Binary-safe (body can contain any bytes; no need to escape newlines)
- Streams naturally (parser knows exactly how many bytes to read)
- Well-known pattern (LSP, Debug Adapter Protocol, etc.)

### Header validation

From `frame.go`:

- `Content-Length` is required; missing = error
- Must be positive
- Must not exceed `math.MaxInt`
- Clean EOF returns `io.EOF`; mid-frame EOF returns `io.ErrUnexpectedEOF`

### Writer side

```go
fmt.Fprintf(w.out, "Content-Length: %d\r\n\r\n", len(data))
w.out.Write(data)
```

## Protocol: JSON-RPC 2.0

Standard JSON-RPC 2.0, version string `"2.0"` hardcoded at `jsonrpc2.go:15`.

### Call vs notification

| Type | Has `id` | Expects response |
|---|---|---|
| Call | Yes | Yes |
| Notification | No | No |

Notifications run synchronously in the reader goroutine. Calls spawn a goroutine per request so slow handlers don't block the reader.

### Write serialization

Writes are serialized through a **1-buffered channel**:

```go
writer: make(chan *headerWriter, 1)
```

This avoids a mutex. Only one goroutine holds the writer slot at a time. Simpler than `sync.Mutex` and gives you deterministic ordering.

### Handler panic recovery

```go
defer func() {
    if r := recover(); r != nil {
        // convert to JSON-RPC error response
    }
}()
```

Panics in handlers become JSON-RPC errors, not process crashes.

## Transport modes

### Stdio (default)

```go
func NewClient(stdin io.WriteCloser, stdout io.ReadCloser)
```

The SDK spawns the CLI as a subprocess and takes its stdin/stdout. Stderr is captured separately for error messages.

### TCP

```typescript
new CopilotClient({ cliUrl: "tcp://localhost:3000" })
```

For connecting to `copilot --headless --port 3000`. Port detection via regex on stdout: `/listening on port ([0-9]+)/i`.

### External URL

Same as TCP but with HTTP-style URL:

```typescript
new CopilotClient({ cliUrl: "http://copilot.internal:3000" })
```

## Protocol versioning

### Current state

- Current: **v3** (as of SDK 0.2.x)
- Minimum supported: **v2**
- Version literal stored in `/sdk-protocol-version.json`

### Negotiation

On `client.start()`, the SDK calls `verifyProtocolVersion()`. If the server's minimum is higher than the client's maximum, the call throws.

```typescript
// Roughly:
const { protocolVersion } = await client.rpc.ping({});
if (protocolVersion < MINIMUM_SUPPORTED) {
  throw new ProtocolMismatchError();
}
```

### v2 vs v3 differences

| Feature | v2 | v3 |
|---|---|---|
| Single-client sessions | ✅ | ✅ |
| Multi-client broadcasts | ❌ | ✅ |
| `capabilities.changed` events | ❌ | ✅ |
| Permission result `no-result` | ❌ (throws) | ✅ |
| Experimental APIs (fork, fleet, history) | ❌ | ✅ |

## Process lifecycle

### Spawn

```go
cmd := exec.CommandContext(ctx, cliPath, args...)
cmd.Env = env     // with COPILOT_API_URL, etc.
configureProcAttr(cmd)   // Windows: HideWindow
cmd.Start()
```

### Exit handling

The SDK provides a `processDone` channel that closes when the subprocess exits:

```go
func (c *Client) SetProcessDone(done chan struct{}, errPtr *error) {
    c.processDone = done
    c.processErr = errPtr
}
```

When `processDone` closes, pending RPC calls receive:

```
"process exited unexpectedly"
```

### No reconnect logic

**This is intentional and important**: if the CLI crashes, every pending call fails immediately. There's no automatic retry, exponential backoff, or reconnect. Higher layers must handle this.

Why? Because:
- Recovering an in-flight agent turn is not safe — the LLM may have partially applied tools
- The SDK cannot know whether a retry would double-apply state
- Forcing the application to decide keeps behavior predictable

For HA, build retry/resume at the orchestrator level using persistent `sessionId` + `resumeSession()`.

## File locking

Protects the CLI extraction cache from concurrent writers. Lives in `go/internal/flock/`.

### Platform implementations

**Unix / Linux** (`flock_unix.go`):

```go
syscall.Flock(int(f.Fd()), syscall.LOCK_EX)   // exclusive, blocking
syscall.Flock(int(f.Fd()), syscall.LOCK_UN)   // release
```

Advisory POSIX locks — kernel tracks them but doesn't enforce; cooperating processes must all honor them. EINTR is retried.

**Windows** (`flock_windows.go`):

```go
LockFileEx(handle, LOCKFILE_EXCLUSIVE_LOCK, 0, 1, 0, &overlapped)
UnlockFileEx(...)
```

Mandatory kernel locks — other processes cannot write to the locked region. Single-byte lock at offset 0.

**Other platforms**:

Returns `errors.ErrUnsupported`. Installation proceeds without locking — two processes extracting simultaneously may race, but the SDK tolerates this (last writer wins; SHA-256 check catches corruption).

### Lock scope

**Protects**: CLI binary extraction in `~/.cache/copilot-sdk/`.

**Does NOT protect**: session state, running CLI processes, or any runtime data.

## Process management differences

### Unix / Linux / macOS (`process_other.go`)

```go
func configureProcAttr(cmd *exec.Cmd) {
    // nothing
}
```

Subprocess inherits the parent's console as-is.

### Windows (`process_windows.go`)

```go
func configureProcAttr(cmd *exec.Cmd) {
    cmd.SysProcAttr = &syscall.SysProcAttr{ HideWindow: true }
}
```

On Windows, every `exec.Cmd` spawns a visible console window by default. For GUI apps (IDE extensions, Electron apps), this is jarring. `HideWindow: true` suppresses it.

## Reverse RPC (server → client)

Most RPCs go client → server. But `sessionFs.*` methods flow the other direction: the CLI calls your SDK when it needs a file operation.

### Registration

Your handlers are registered by passing `createSessionFsHandler`. The SDK internally sets up JSON-RPC handlers for incoming `sessionFs.readFile`, `writeFile`, etc. requests.

### Frame routing

A single bidirectional connection carries both directions. The `id` field disambiguates responses; `method` routes incoming requests.

## Multiplexing sessions

One `CopilotClient` = one JSON-RPC connection = potentially many sessions.

Each session has a unique ID. RPC methods include `sessionId` in their params:

```json
{
  "jsonrpc": "2.0",
  "id": 42,
  "method": "session.send",
  "params": { "sessionId": "abc-123", "prompt": "..." }
}
```

Events likewise carry `sessionId` so the SDK knows which `CopilotSession` to dispatch to.

## Tracing

OpenTelemetry W3C trace context is propagated via tool invocations:

```typescript
handler: async (args, invocation) => {
  // invocation.traceparent — W3C trace context
  // invocation.tracestate — vendor-specific state
}
```

You can continue the trace in your tool handler by calling into your own observability stack.

## Debug logging

Set `DEBUG=*` (Node.js) or enable the equivalent in each SDK to log JSON-RPC frames. Useful for protocol-level debugging.

Every RPC call and response gets logged with method, id, and truncated params/result.

## Gotchas

1. **LSP framing, not newline-delimited**. If you're writing a custom proxy, use Content-Length.
2. **No reconnect**. Build your own recovery layer.
3. **Handler goroutines**. Slow tool handlers don't block other RPCs, but memory can grow if many concurrent slow handlers.
4. **Write channel is 1-buffered**. A slow reader on the other side backpressures the writer; this is intentional.
5. **Flock doesn't protect session state**. Build your own distributed lock if multiple processes may resume the same session.

## See also

- [codegen-pipeline.md](codegen-pipeline.md) — how the RPC spec becomes code
- [test-harness.md](test-harness.md) — how the harness intercepts the wire
- [../05-deployment/bundling.md](../05-deployment/bundling.md) — CLI installation / flock
- [../04-advanced/hidden-rpc-methods.md](../04-advanced/hidden-rpc-methods.md) — complete method list
