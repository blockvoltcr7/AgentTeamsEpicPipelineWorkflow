# Built-in Tools Reference

Tools exposed natively by the Copilot CLI. Available in every session without registration.

## Tool list

| Tool | Purpose | Permission kind |
|---|---|---|
| `bash` | Execute shell commands | `shell` |
| `view` | Read file contents | `read` |
| `edit` | Modify file in place | `write` |
| `create_file` | Create new file | `write` |
| `grep` | Regex search across files | `read` |
| `glob` | Glob pattern file discovery | `read` |
| `task_complete` | Signal task done | — (special) |
| `ask_user` | Query the user | — (special) |

## `bash`

### Purpose
Run shell commands. The workhorse tool for tests, builds, and arbitrary automation.

### Parameters (approximate)

```typescript
{
  command: string,
  cwd?: string,
  timeout?: number,   // ms
}
```

### Output

```
stdout + stderr combined, with exit code reported
```

Tests verify:
- Exit code is captured in output
- stderr is captured separately from stdout (e.g., `echo error >&2`)

### Permission handling

Every `bash` call triggers `onPermissionRequest` with `kind: "shell"`. Your handler decides.

For autonomous operation, use `approveAll` or whitelist safe commands:

```typescript
onPermissionRequest: async (req) => {
  if (req.kind === "shell") {
    if (/^(npm test|pytest|go test)/.test(req.command)) {
      return { kind: "approved" };
    }
    return { kind: "denied-by-policy" };
  }
  return { kind: "approved" };
}
```

### Overriding

```typescript
defineTool("bash", {
  overridesBuiltInTool: true,
  parameters: {...},
  handler: async (args) => {
    await auditLog.record(args.command);
    return await sandbox.run(args.command);
  },
});
```

## `view`

### Purpose
Read a file, optionally a specific line range.

### Parameters

```typescript
{
  path: string,
  start?: number,   // line (1-indexed)
  end?: number,     // line
}
```

Or similar — exact shape varies with CLI version.

### Output

File contents, with line numbers in some formats.

### Error handling

For nonexistent files, returns an error matching patterns like:
`NOT_FOUND | NOT_EXIST | NO_SUCH | FILE_NOT_FOUND | DOES_NOT_EXIST | ERROR`

Tests verify these error shapes so your custom overrides must match.

### Permission

`kind: "read"`.

## `edit`

### Purpose
Modify an existing file. The agent provides a search+replace or full-content edit.

### Parameters (approximate)

```typescript
{
  path: string,
  oldContent?: string,
  newContent: string,
}
```

### Permission

`kind: "write"`.

### Overriding

Useful for audit trails:

```typescript
defineTool("edit", {
  overridesBuiltInTool: true,
  parameters: {...},
  handler: async (args) => {
    await auditLog.edit(args.path, args.oldContent, args.newContent);
    return await fs.edit(args.path, args);
  },
});
```

## `create_file`

### Purpose
Create a new file.

### Parameters (approximate)

```typescript
{
  path: string,
  content: string,
}
```

### Permission

`kind: "write"`.

### Behavior

Tests verify:
- File is created with specified contents
- Reading the file afterward returns the same content (persistence across turns)

## `grep`

### Purpose
Regex or literal pattern search across files.

### Parameters (approximate)

```typescript
{
  pattern: string,
  path?: string,
  regex?: boolean,
}
```

### Output

Matching lines with file paths and line numbers.

### Permission

`kind: "read"`.

## `glob`

### Purpose
Find files by glob pattern. Supports `**` recursion.

### Parameters (approximate)

```typescript
{
  pattern: string,   // e.g., "**/*.ts"
  cwd?: string,
}
```

### Output

List of matching file paths.

### Permission

`kind: "read"`.

## `task_complete` (special)

### Purpose
Signal that the task is finished. This is how autopilot mode knows to stop.

### Parameters

```typescript
{
  summary?: string,
}
```

### Behavior

Calling this emits `session.task_complete` event. In autopilot mode, the CLI's "keep working" nudge stops once this is called.

### Cannot be overridden

It's built into the runtime's loop logic, not just a surfaced tool.

### Monitoring

```typescript
session.on("session.task_complete", (e) => {
  console.log("Task done:", e.data.summary);
});
```

## `ask_user` (special)

### Purpose
Agent asks the user a question. Triggers your `onUserInputRequest` handler.

### Parameters (from the agent's perspective)

```typescript
{
  question: string,
  choices?: string[],   // optional predefined options
}
```

### Handler

```typescript
onUserInputRequest: async (request, invocation) => {
  // request.question, request.choices
  return {
    answer: "user's choice",
    wasFreeform: false,
  };
}
```

### Availability

Only available if you register `onUserInputRequest`. Without it, the tool is not exposed to the model.

## Tool permission kinds summary

Every tool invocation routes through `onPermissionRequest` with one of these kinds:

| Kind | Meaning | Typical tools |
|---|---|---|
| `shell` | Executes arbitrary commands | `bash` |
| `write` | Modifies files | `edit`, `create_file` |
| `read` | Reads files | `view`, `grep`, `glob` |
| `mcp` | MCP server tool call | any MCP tool |
| `custom-tool` | User-registered custom tool | your `defineTool` tools |
| `url` | Fetches a URL | network tools |
| `memory` | Writes to agent memory | memory tools |
| `hook` | Hook-triggered operation | hook-invoked tools |

## Skipping permissions

```typescript
defineTool("safe_lookup", {
  skipPermission: true,   // no permission prompt
  ...
});
```

Only for genuinely side-effect-free tools. The permission handler is your safety net; bypass with care.

## Complex parameter types

Custom tools support:

- Strings, numbers, booleans
- Nested objects
- Arrays
- Unions (`string | number`)
- Enums
- Optional fields
- Descriptions (via Zod `.describe()` or JSON Schema `description`)

All survive round-trip through the LLM.

## Tool result types

Three return shapes:

### Plain string

```typescript
return "42";
```

Shown to the model as-is.

### JSON object

```typescript
return { temp: 72, unit: "F" };
```

Serialized to JSON; model parses it.

### Structured `ToolCallResult`

```typescript
return {
  textResultForLlm: "Operation succeeded",
  resultType: "ok" | "error",
  structuredData: { ... },        // for UI consumption
  binaryResults: [...],            // images, files
  toolTelemetry: {                 // observability
    duration_ms: 150,
  },
};
```

Full control. Use when you want to separate what the LLM sees from what your UI gets.

## Error handling in tools

```typescript
handler: async (args) => {
  try {
    return await doWork(args);
  } catch (err) {
    // Option 1: throw
    throw new Error(`Failed: ${err.message}`);

    // Option 2: structured error
    return {
      textResultForLlm: `Failed: ${err.message}`,
      resultType: "error",
    };
  }
}
```

Either approach: the model sees the error and can decide to retry, ask for help, or abandon.

## Tool execution events

For every tool call:

```
tool.execution_start
   ↓
(permission.requested → permission.completed)
   ↓
[optional: tool.execution_partial_result (streaming)]
[optional: tool.execution_progress (progress updates)]
   ↓
tool.execution_complete
```

All events carry the same `toolCallId` for correlation.

## Version-specific behaviors

Tool names and parameter shapes may evolve across CLI versions. The SDK codegen picks up changes via the `@github/copilot` package version pin.

To inspect current tool definitions:

```typescript
const { tools } = await client.rpc.tools.list({ model: "gpt-5" });
for (const t of tools) {
  console.log(t.name, t.parameters, t.instructions);
}
```

## See also

- [../02-core-concepts/tools-and-mcp.md](../02-core-concepts/tools-and-mcp.md) — tool registration patterns
- [event-types.md](event-types.md) — tool-related events
- [rpc-methods.md](rpc-methods.md) — `tools.list`, `tools.handlePendingToolCall`
- [../02-core-concepts/hooks-and-events.md](../02-core-concepts/hooks-and-events.md) — `onPreToolUse`, `onPostToolUse`
