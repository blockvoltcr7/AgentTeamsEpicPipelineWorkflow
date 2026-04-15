# Agent Mapping

Maps task `## Type` values (read from local spec files) to execution specializations.

If matching custom agents exist in `.github/agents/`, the main Copilot CLI agent may delegate to them. Otherwise, the main agent should keep the same specialization in mind and execute the work directly.

## Mapping Table

| Task Type Keyword | Suggested Specialization | When to Use |
|---|---|---|
| `Migration` | `drizzle` | SQL DDL migrations, schema changes |
| `Migration (data-preserving)` | `drizzle` | Migrations that must preserve existing data |
| `Migration + Drizzle Schema` | `drizzle` | Combined SQL migration + TypeScript ORM schema |
| `Code` (Drizzle context) | `drizzle` | Drizzle schema files, type exports, barrel updates |
| `Code` (React/Next.js context) | `typescript-react` | Pages, components, server actions, hooks |
| `RLS` / `Row Level Security` | `supabase-rls-policy-generator` | RLS policy design and SQL |
| `Edge Function` | `supabase-edge-function-writer` | Supabase edge function development |
| `Database Function` | `supabase-function-generator` | PL/pgSQL stored procedures, triggers |
| `Realtime` | `supabase-realtime-expert` | Channels, presence, broadcast |
| `Schema Design` / `DBA` | `supabase-dba-schema-advisor` | Schema review, index optimization |
| *(no match)* | `general-purpose` | Fallback (built-in, no .md file needed) |

## Matching Rules

1. **Primary match:** Keyword match against the `## Type` section of each task's spec file body.
2. **Context override for `Migration`:** After a primary `Migration` match, scan `## Context` and `## Implementation` for RLS keywords (`RLS`, `Row Level Security`, `policy`, `policies`). If found, override to `supabase-rls-policy-generator`. This handles tasks typed as `Migration` whose actual work is RLS policy creation (e.g., a task named "RLS policies for ghl.* tables" with `## Type: Migration`).
3. **`Code` disambiguation:** When `## Type` is just `Code`, scan `## Context` and `## Implementation` for:
   - Drizzle keywords: `drizzle`, `schema`, `migration`, `table`, `pgSchema`, `barrel export` → `drizzle`
   - React/Next.js keywords: `React`, `Next.js`, `component`, `page`, `server action`, `client`, `tsx` → `typescript-react`
   - Neither → `general-purpose`
4. **Custom agent resolution:** If a repository-scoped custom agent exists for the specialization, the main Copilot CLI agent may delegate to it. If no matching custom agent exists, the main agent should keep ownership and execute the task directly.
