# Node.js / TypeScript SDK

Location: `/nodejs/`

Package: `@github/copilot-sdk`

## Public API

Main exports (`nodejs/src/index.ts`):

- `CopilotClient` — main client class
- `CopilotSession` — conversation session
- `defineTool` — helper for typed tools with Zod parameters
- `approveAll` — built-in permissive permission handler
- `convertMcpCallToolResult` — MCP result adapter
- `SYSTEM_PROMPT_SECTIONS` — 10 named sections for customization

Extension helper (`@github/copilot-sdk/extension`):

- `joinSession` — for running the SDK as a CLI extension subprocess

## Client lifecycle

```typescript
import { CopilotClient } from "@github/copilot-sdk";

const client = new CopilotClient({
  model: "gpt-5",
  // autoStart: true,     // default; start() called on first createSession
  // cliPath: "/usr/local/bin/copilot",   // override CLI path
  // cliUrl: "http://localhost:3000",     // connect to headless server
  // githubToken: "ghp_...",
  // useLoggedInUser: false,
  // configDir: "/path/to/user/config",
  // isChildProcess: false,              // true when running as extension
});

await client.start();              // explicit; usually implicit
const session = await client.createSession({ ... });

// Do work...

const errors = await client.stop();   // graceful
// or
await client.forceStop();             // SIGKILL
```

## Session example

```typescript
import { CopilotClient, approveAll, defineTool } from "@github/copilot-sdk";
import { z } from "zod";

const weatherTool = defineTool("get_weather", {
  description: "Fetch weather for a location",
  parameters: z.object({ location: z.string() }),
  handler: async ({ location }) => ({ temp: 72, location }),
});

const client = new CopilotClient();
const session = await client.createSession({
  model: "gpt-5",
  tools: [weatherTool],
  onPermissionRequest: approveAll,
  streaming: true,
  hooks: {
    onPreToolUse: async (input) => {
      console.log(`Tool: ${input.toolName}`);
    },
  },
});

session.on("assistant.message_delta", (event) => {
  process.stdout.write(event.data.deltaContent);
});

session.on("assistant.message", (event) => {
  console.log("\nFinal:", event.data.content);
});

await session.sendAndWait({ prompt: "What's the weather in NYC?" });
await session.disconnect();
await client.stop();
```

## Sending messages

```typescript
// Fire-and-forget with event subscription
await session.send({
  prompt: "Hello",
  attachments: [
    { type: "file", path: "/abs/path/readme.md", displayName: "readme.md" },
    { type: "directory", path: "/abs/path/src", displayName: "src" },
    { type: "selection", filePath: "...", selection: {...}, text: "..." },
    { type: "blob", data: "base64...", mimeType: "image/png", displayName: "screenshot.png" },
  ],
  mode: "enqueue" | "immediate",
  requestHeaders: { "X-Trace": "..." },
});

// Or await the final assistant message
const finalMessage = await session.sendAndWait({ prompt: "..." });
```

## Tool definition (full signature)

```typescript
defineTool(name, {
  description: string,
  parameters: ZodSchema | JsonSchema,
  handler: (args, invocation) => unknown | Promise<unknown>,
  overridesBuiltInTool?: boolean,   // required when replacing edit/read_file/etc.
  skipPermission?: boolean,          // skip permission handler
})
```

Handler invocation contains:
```typescript
{
  sessionId: string,
  toolCallId: string,
  toolName: string,
  arguments: unknown,
  traceparent?: string,
  tracestate?: string,
}
```

## Zod vs raw JSON Schema

```typescript
// Zod (preferred)
parameters: z.object({
  id: z.string().describe("Issue ID"),
  labels: z.array(z.string()).optional(),
})

// Raw JSON Schema (fallback)
parameters: {
  type: "object",
  properties: {
    id: { type: "string", description: "Issue ID" },
    labels: { type: "array", items: { type: "string" } },
  },
  required: ["id"],
}
```

## Using `joinSession` for extensions

When running as a subprocess spawned by the CLI (an "extension"):

```typescript
// /path/to/my-extension.mjs
import { joinSession } from "@github/copilot-sdk/extension";

await joinSession({
  tools: [...],
  hooks: {...},
  commands: [...],
  onElicitationRequest: async (ctx) => ({...}),
  onUserInputRequest: async (req) => ({...}),
});
```

The CLI discovers extensions from:
- `.github/extensions/*/extension.mjs` (repo-local)
- User config directory

**Constraints:**
- Must be `.mjs` (ES modules only — no TypeScript)
- Cannot use `console.log()` (stdin/stdout is reserved for JSON-RPC); use `session.log()` instead
- Reloaded on CLI restart or `/clear`

## AsyncDispose support

TypeScript 5.2+:

```typescript
{
  await using session = await client.createSession({...});
  await session.sendAndWait({ prompt: "..." });
  // session.disconnect() automatically called at scope exit
}
```

## Extension points

| Point | Purpose |
|---|---|
| `tools: Tool[]` | Custom tools |
| `mcpServers: Record<string, MCPServerConfig>` | MCP servers |
| `customAgents: CustomAgentConfig[]` | Custom agents |
| `hooks: SessionHooks` | Lifecycle hooks |
| `commands: CommandDefinition[]` | Slash commands |
| `systemMessage: SystemMessageConfig` | Prompt customization |
| `onPermissionRequest` | Required permission callback |
| `onUserInputRequest` | Enables `ask_user` tool |
| `onElicitationRequest` | Enables UI dialogs |

## Node.js-specific quirks

1. **Streaming and handlers**: if you subscribe after `send()`, you miss early events. Use `onEvent` in session config for early capture.
2. **CJS compatibility**: Works in both CJS and ESM (tested in `test/cjs-compat.test.ts`).
3. **Symbol.asyncDispose**: TS 5.2+ only; polyfill not shipped.
4. **Attachments are sync-sized**: Large blobs go over JSON-RPC inline; for huge files, use a `sessionFs` provider and pass paths.

## Testing

Vitest-based (`nodejs/vitest.config.ts`). E2E tests in `/nodejs/test/e2e/` use the record/replay harness (see [../07-internals/test-harness.md](../07-internals/test-harness.md)).

## Build

```bash
just install-nodejs
just format-nodejs
just lint-nodejs
just test-nodejs
just scenario-verify       # full e2e
```

Or inside `/nodejs/`:

```bash
npm install
npm run build
npm run test
```

## See also

- [feature-parity-matrix.md](feature-parity-matrix.md)
- [../02-core-concepts/](../02-core-concepts/)
- [../05-deployment/deployment-patterns.md](../05-deployment/deployment-patterns.md)
