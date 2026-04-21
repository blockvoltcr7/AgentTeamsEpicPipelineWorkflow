# Authentication

Two paths: GitHub auth (the default) or BYOK (Bring Your Own Key).

## GitHub auth

### Signed-in user (default)

User signs in via `copilot` CLI:

```bash
copilot
# User prompted to sign in via browser
```

Credentials stored in system keychain. SDK auto-uses them:

```typescript
const client = new CopilotClient();
// No auth config needed
```

### Token-based

Pass a token programmatically:

```typescript
const client = new CopilotClient({
  githubToken: "ghp_...",     // or gho_, ghu_, github_pat_
  useLoggedInUser: false,     // don't fall back to keychain
});
```

Accepted token prefixes:
- `gho_` — OAuth token
- `ghu_` — GitHub App user token
- `github_pat_` — fine-grained PAT
- `ghp_` — classic PAT

### Environment variables (priority order)

The CLI checks, in order:

1. `COPILOT_GITHUB_TOKEN`
2. `GH_TOKEN`
3. `GITHUB_TOKEN`

Useful for CI/CD:

```yaml
env:
  COPILOT_GITHUB_TOKEN: ${{ secrets.COPILOT_TOKEN }}
```

## BYOK (Bring Your Own Key)

No GitHub subscription required. You provide the API key for any supported provider.

### OpenAI

```typescript
const session = await client.createSession({
  model: "gpt-5",
  provider: {
    type: "openai",
    apiKey: process.env.OPENAI_API_KEY,
    // baseUrl: "https://api.openai.com/v1",   // default
  },
});
```

### Anthropic (Claude)

```typescript
const session = await client.createSession({
  model: "claude-sonnet-4.5",
  provider: {
    type: "anthropic",
    apiKey: process.env.ANTHROPIC_API_KEY,
  },
});
```

### Azure OpenAI / AI Foundry

```typescript
const session = await client.createSession({
  model: "gpt-5.2-codex",
  provider: {
    type: "openai",
    baseUrl: "https://your-resource.openai.azure.com/openai/v1/",
    wireApi: "responses",    // use Responses API wire protocol
    apiKey: process.env.FOUNDRY_API_KEY,
  },
});
```

### Azure with managed identity

```typescript
const session = await client.createSession({
  model: "gpt-5.2-codex",
  provider: {
    type: "azure",
    baseUrl: "...",
    // managed identity auth configured via Azure SDK
  },
});
```

### Ollama (local)

```typescript
const session = await client.createSession({
  model: "llama3.1:70b",
  provider: {
    type: "openai",
    baseUrl: "http://localhost:11434/v1",
    apiKey: "ollama",   // any value; Ollama doesn't check
  },
});
```

### Any OpenAI-compatible server

```typescript
provider: {
  type: "openai",
  baseUrl: "http://vllm-server:8000/v1",
  apiKey: "...",
}
```

Works with vLLM, LiteLLM, Microsoft Foundry Local, etc.

## Per-session vs per-client providers

### Per-client (applies to all sessions)

```typescript
const client = new CopilotClient({
  provider: { type: "openai", apiKey: "..." },
});
```

### Per-session (overrides client)

```typescript
const session = await client.createSession({
  provider: { type: "anthropic", apiKey: "..." },
});
```

This lets you mix providers per session — a researcher agent on Claude, an editor agent on GPT.

## Mixing GitHub + BYOK

You can use GitHub for the CLI entitlement but BYOK for actual inference:

```typescript
const client = new CopilotClient({
  githubToken: "...",                // for Copilot entitlement
});

const session = await client.createSession({
  model: "claude-sonnet-4.5",
  provider: { type: "anthropic", apiKey: "..." },  // inference via Anthropic
});
```

## Security patterns

### Never hardcode keys

```typescript
// Bad
provider: { type: "openai", apiKey: "sk-abcd1234..." }

// Good
provider: { type: "openai", apiKey: process.env.OPENAI_API_KEY }
```

### Container-proxy pattern

When running the CLI in a container, inject credentials at the proxy layer so they never enter the container image or runtime. See [deployment-patterns.md](deployment-patterns.md).

### Per-user keys in multi-tenant

For SaaS where each user has their own API key:

```typescript
app.post("/chat", async (req, res) => {
  const userApiKey = await vault.getUserKey(req.user.id);

  const session = await client.createSession({
    provider: { type: userApiKey.provider, apiKey: userApiKey.key },
    sessionId: `user-${req.user.id}-...`,
  });
});
```

### Key rotation

No built-in key rotation hook. Rotate by:

1. Fetch new key
2. Reconfigure new sessions with the new key
3. Let old sessions drain naturally

## Quota and usage

Check quota:

```typescript
const quota = await client.rpc.account.getQuota();
// {
//   quotaSnapshots: {
//     premium_interactive: {
//       entitlementRequests,
//       usedRequests,
//       remainingPercentage,
//       overage,
//       overageAllowedWithExhaustedQuota,
//       resetDate,
//     },
//   },
// }
```

Per-session cost via `session.rpc.usage.getMetrics()`. See [../04-advanced/hidden-rpc-methods.md](../04-advanced/hidden-rpc-methods.md).

## Reasoning effort

For models that support it (o-series, Claude, etc.):

```typescript
await session.rpc.model.switchTo({
  modelId: "gpt-5",
  reasoningEffort: "high",   // "low" | "medium" | "high" | "xhigh" (model-specific)
});
```

Higher effort = more tokens consumed = more expensive. Good for complex tasks, overkill for simple ones.

## Gotchas

1. **Token scope matters**. Fine-grained PATs need the right permissions (Copilot access for GitHub-path; nothing for pure BYOK).
2. **BYOK bypasses Copilot quota** but is charged by the provider directly. Monitor those separately.
3. **Azure wireApi matters.** `"responses"` vs `"chat_completions"` — wrong value = 400 errors.
4. **Ollama models vary.** Not all respect tool-use protocols. Test before deploying.
5. **Mixed-provider sessions can surprise you.** A model switch mid-session may invalidate cached tool definitions.

## Reference scenarios

Auth test scenarios exist at `/test/scenarios/auth/`:

- `gh-app/` — GitHub App authentication
- `byok-openai/` — OpenAI BYOK
- `byok-anthropic/` — Anthropic BYOK
- `byok-azure/` — Azure OpenAI BYOK
- `byok-ollama/` — Ollama local

## See also

- [deployment-patterns.md](deployment-patterns.md) — where auth fits in each pattern
- [../04-advanced/hidden-rpc-methods.md](../04-advanced/hidden-rpc-methods.md) — `account.getQuota`, `session.rpc.usage.getMetrics`
- Official docs: `/docs/auth/index.md`, `/docs/auth/byok.md`
