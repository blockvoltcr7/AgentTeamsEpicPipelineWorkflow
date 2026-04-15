# Type Inference Rules

Infers the `## Type` value for a task stub based on keywords in the task name and description from the PRD roadmap.

## Inference Table

Scan the task name and description (from the PRD table row). Apply the **first matching rule** (rules are ordered by specificity):

| Priority | Keywords in Name/Description | Inferred Type | Rationale |
|----------|------------------------------|---------------|-----------|
| 1 | `RLS`, `row level security`, `policy`, `policies` | `RLS` | Security policy work |
| 2 | `migration` + (`table`, `schema`, `column`) | `Migration + Drizzle Schema` | DDL + ORM schema |
| 3 | `migration` | `Migration` | Pure SQL DDL |
| 4 | `edge function` | `Edge Function` | Supabase edge function |
| 5 | `database function`, `trigger`, `stored procedure` | `Database Function` | PL/pgSQL work |
| 6 | `env`, `environment`, `config`, `Vercel`, `deploy` | `Infrastructure` | Config and deployment |
| 7 | `install`, `registry`, `workspace`, `package.json` | `Infrastructure` | Package/tooling setup |
| 8 | `page`, `layout`, `sidebar`, `component`, `UI`, `dialog`, `form`, `responsive` | `UI` | Frontend components |
| 9 | `visualizer`, `animation`, `shader`, `WebGL`, `theme`, `dark mode`, `light mode` | `UI` | Visual/rendering work |
| 10 | `server action`, `action`, `token`, `auth` | `Code` | Server-side logic |
| 11 | `hook`, `provider`, `session`, `state` | `Code` | Client-side logic |
| 12 | `agent`, `STT`, `LLM`, `TTS`, `pipeline`, `dispatch` | `Code` | Agent backend logic |
| 13 | `test`, `e2e`, `verify`, `QA` | `Code` | Testing work |
| 14 | *(no match)* | `Code` | Safe default |

## Matching Rules

1. **Case-insensitive** — `RLS` matches `rls`, `Rls`, etc.
2. **Word boundary aware** — `env` matches `env validation` but not `environment` (use both keywords)
3. **Combine name + description** — Check both the task name column and description column from the PRD table
4. **First match wins** — Stop at the first matching rule (ordered by priority)

## Examples

| Task Name | Description | Inferred Type |
|-----------|-------------|---------------|
| Add `NEXT_PUBLIC_LIVEKIT_URL` to env validation | Update `lib/env.ts` with t3-env schema | `Infrastructure` |
| Create `lib/livekit/token-server.ts` | Utility function to generate LiveKit access tokens | `Code` |
| Create `app/actions/livekit-token-actions.ts` | Server action with Supabase auth check | `Code` |
| Add Vercel env vars | Push `LIVEKIT_*` vars to Vercel environments | `Infrastructure` |
| Install `@agents-ui` registry | Run shadcn registry add | `Infrastructure` |
| Create member agent page | RSC entry point with auth check | `UI` |
| Create `VoiceAgentView` client component | Session management with useSession | `UI` |
| Add agent page to member sidebar | Update AppSidebar.tsx | `UI` |
| Handle microphone permissions | Permission request flow | `UI` |
| Theme visualizer to teal | Override default colors | `UI` |
| Create `apps/agent/` workspace | package.json, tsconfig.json | `Infrastructure` |
| Create basic voice agent (`agent.ts`) | STT → LLM → TTS pipeline | `Code` |
| Configure agent dispatch | Register agent with LiveKit Cloud | `Code` |
| Create `livekit.agent_sessions` table | Migration with RLS policies | `Migration + Drizzle Schema` |

## Edge Cases

- **Task mentions both `migration` and `RLS`**: RLS wins (higher priority) — the migration is likely just the vehicle for the policy
- **Task says `Install` but is about a UI component**: Check if description mentions `component` or `shadcn` — if so, still `Infrastructure` (it's a setup step, not UI authoring)
- **Task says `Test end-to-end`**: Infer `Code` — testing tasks are implementation work
- **Agent backend tasks**: Even though they're in `apps/agent/`, they're still `Code` type — the agent mapping in `/run-epic` handles routing to the right specialist
