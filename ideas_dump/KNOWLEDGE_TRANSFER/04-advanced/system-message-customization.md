# System Message Customization

Three modes for controlling the system prompt, from conservative to invasive.

## Three modes

| Mode | Default? | What it does | Risk |
|---|---|---|---|
| `append` | ✅ yes | Add your instructions to the end of Copilot's prompt | Low |
| `replace` | ❌ | Fully replace the system prompt | High (loses guardrails) |
| `customize` | ❌ | Modify specific sections | Medium (section-targeted) |

## Append mode (default)

Simplest and safest. Your content gets appended to Copilot's full system prompt.

```typescript
await client.createSession({
  systemMessage: {
    content: "When asked about our codebase, prefer showing examples.",
  },
});
```

Equivalent shorthand:

```typescript
await client.createSession({
  systemMessage: { content: "..." },
});
```

Use when: you want to add context or preferences without touching Copilot's built-in instructions.

## Replace mode

Total override. You become responsible for ALL prompting, including safety guidance.

```typescript
await client.createSession({
  systemMessage: {
    mode: "replace",
    content: `You are a helpful assistant. Follow these rules: ...`,
  },
});
```

Use sparingly:
- You lose Copilot's safety guardrails
- You lose tool-use instructions
- Agent behavior may degrade
- You are responsible for teaching the model how to use tools

Use when: you're building a non-coding agent where Copilot's defaults don't apply.

## Customize mode (recommended for production)

Section-level overrides. Modify what you need, leave the rest intact.

### The ten standard sections

```typescript
const SYSTEM_PROMPT_SECTIONS = [
  "identity",            // "You are Copilot..."
  "tone",                // conversation tone
  "tool_efficiency",     // tool-use guidelines
  "environment_context", // runtime context
  "code_change_rules",   // how to modify code
  "guidelines",          // general conduct
  "safety",              // safety policies
  "tool_instructions",   // per-tool instructions
  "custom_instructions", // from CLAUDE.md etc.
  "last_instructions",   // final reinforcement
];
```

### Section actions

```typescript
await client.createSession({
  systemMessage: {
    mode: "customize",
    sections: {
      tone: {
        action: "replace",
        content: "Be terse. No preamble. Code examples only.",
      },
      safety: {
        action: "remove",   // dangerous — think twice
      },
      guidelines: {
        action: "append",
        content: "Always prefer TypeScript over JavaScript.",
      },
      custom_instructions: {
        action: (currentContent) => currentContent + "\n[runtime inject]",
      },
    },
    content: "Additional global content (like append mode).",
  },
});
```

Three possible `action` values:

| Action | Effect |
|---|---|
| `"replace"` | Overwrite section with `content` |
| `"remove"` | Delete section entirely |
| `"append"` | Add `content` to end of section |
| `(current: string) => string` | Transform function — full control |

## Transform functions

The most powerful option. Runtime access to current content, returns new content:

```typescript
systemMessage: {
  mode: "customize",
  sections: {
    environment_context: {
      action: (current) => {
        // Inject dynamic context
        return `${current}\n\nCurrent branch: ${gitBranch}\nCurrent user: ${username}`;
      },
    },
    tool_instructions: {
      action: async (current) => {
        // Async allowed — e.g., fetch org policy
        const policy = await fetchOrgPolicy();
        return `${current}\n\n## Org Policy\n${policy}`;
      },
    },
  },
}
```

Use cases:
- Inject per-session context (user ID, branch, env)
- Add runtime policies fetched from a config service
- Redact or substitute content based on request
- A/B test prompt variations

## Practical patterns

### Pattern 1: Tighter tone for CI runs

```typescript
if (process.env.CI) {
  systemMessage.sections.tone = {
    action: "replace",
    content: "Be extremely terse. Output only what's necessary. No emoji.",
  };
}
```

### Pattern 2: Organization-wide policies

```typescript
const orgPolicy = await fetchOrgPolicy();

systemMessage.sections.guidelines = {
  action: "append",
  content: `\n## Organization Policy\n${orgPolicy}`,
};
```

### Pattern 3: Per-agent persona (alternative to custom agents)

```typescript
systemMessage.sections.identity = {
  action: "replace",
  content: "You are a senior SRE specializing in observability. Be data-driven.",
};
```

### Pattern 4: Injecting recent decisions

```typescript
systemMessage.sections.custom_instructions = {
  action: async (current) => {
    const recent = await getRecentDecisions(userId);
    return `${current}\n\n## Recent decisions\n${recent.join("\n")}`;
  },
};
```

## Interaction with custom agents

Custom agents have their own `prompt` field. At runtime, when a custom agent is active, the active prompt combines:

```
<your customize'd system prompt>
<custom agent's prompt>
```

Custom agent prompts are additive — they don't replace your session's system prompt. If you want per-agent full control, use `customize` mode + `replace` on `identity`:

```typescript
const session = await client.createSession({
  customAgents: [{
    name: "researcher",
    prompt: "Focus on finding evidence, don't make changes.",
    // ...
  }],
  systemMessage: {
    mode: "customize",
    sections: {
      identity: {
        action: (current) => (isResearcher ? "You are a researcher." : current),
      },
    },
  },
});
```

## Gotchas

1. **`remove` on `safety` is dangerous.** Loss of safety guidance can lead to unsafe tool use in autopilot mode.
2. **Transform functions run on every session creation/resume.** Keep them fast (or cache results).
3. **Async transforms must be properly awaited.** Synchronous return of `Promise<string>` is valid, but unhandled rejections crash session init.
4. **Sections aren't documented individually.** If a section rename happens, customize mode silently no-ops. Test after SDK upgrades.
5. **Testing prompts is hard.** No built-in "show me the final prompt" API. Use logging in transform functions to inspect inputs.

## Inspecting the active prompt

While there's no direct API to dump the current system prompt, you can get instruction sources via:

```typescript
await session.rpc.instructions.getSources();
```

This shows CLAUDE.md-style sources but not the full assembled prompt. For debugging, log from inside a transform function:

```typescript
systemMessage.sections.custom_instructions = {
  action: (current) => {
    console.log("Current section content:", current);
    return current + "[added]";
  },
};
```

## See also

- [../02-core-concepts/agents-and-subagents.md](../02-core-concepts/agents-and-subagents.md) — custom agent prompts
- [hidden-rpc-methods.md](hidden-rpc-methods.md) — `session.instructions.getSources`
- [../02-core-concepts/hooks-and-events.md](../02-core-concepts/hooks-and-events.md) — `onUserPromptSubmitted` as an alternative injection point
