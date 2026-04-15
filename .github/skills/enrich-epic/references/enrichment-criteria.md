# Task Enrichment Criteria

Scoring rubric and analysis patterns for evaluating and enriching local task file descriptions.

## Scoring Rubric

### Section: ## Type (Required — Pass/Fail)

**Pass**: One of the recognized types:
- `Migration`
- `Migration + Drizzle Schema`
- `Code`
- `Code (Drizzle)`
- `Code (React)`
- `UI`
- `Infrastructure`
- `RLS`
- `Edge Function`
- `Database Function`

**Fail**: Missing, empty, or unrecognized type.

### Section: ## Context (0–3 points)

| Score | Criteria |
|---|---|
| 0 | Missing or empty |
| 1 | Generic description (e.g., "This task creates a table") |
| 2 | Explains why with business context but no PRD reference |
| 3 | Explains why, references specific PRD goals, explains business impact |

**When enriching**: Cross-reference the task with relevant PRD sections. Cite the specific PRD feature or goal that justifies the task. Include the business impact (e.g., "This table enables the Overview Dashboard feature described in PRD Feature 2, which gives business owners their 'morning coffee view' of key metrics").

### Section: ## Implementation (0–5 points)

| Score | Criteria |
|---|---|
| 0 | Missing or empty |
| 1 | Vague instructions (e.g., "Create the migration") |
| 2 | Some specific detail but missing file paths or code |
| 3 | File paths mentioned, general approach described |
| 4 | Specific file paths, pattern references (file:line), step-by-step in plain English |
| 5 | Complete guide: exact file paths, pattern references, key function signatures, step-by-step — but NOT full code implementations |

**When enriching**: Reference existing patterns by file path (e.g., "Follow `clickup-provisioning-actions.ts`"). List steps in plain English with file paths. Include key function signatures as one-liners (e.g., "`getAllOrganizations(): Promise<ServerActionResponse<Organization[]>>`"). Do NOT include full function bodies, complete code blocks, or entire SQL statements — the coding agent writes the code, the enrichment tells it WHERE to look and WHAT to build.

**Size target**: Implementation section should be 500-800 characters. If it's longer, you're writing code instead of guidance.

### Section: ## Acceptance Criteria (0–3 points)

| Score | Criteria |
|---|---|
| 0 | Missing or empty |
| 1 | 1-2 vague criteria |
| 2 | 3+ criteria but some are not verifiable |
| 3 | 3+ specific, verifiable criteria in checkbox format |

**When enriching**: Each criterion must be testable. Good: "RLS policy prevents users from reading rows where location_id does not match their access". Bad: "Security works correctly".

### Section: ## Dependencies (0–2 points)

| Score | Criteria |
|---|---|
| 0 | Missing or empty |
| 1 | Dependencies mentioned but without task IDs or clear references |
| 2 | Both "Depends On" and "Blocks" listed with task names and IDs |

**When enriching**: Review all tasks in the epic. If task A creates a table and task B adds RLS to that table, B depends on A. Use slug-based format: `- Depends On: <slug>`. Cross-epic refs use `- Depends On: <epic-folder>/<slug>`. Slugs are filenames without the `^\d+-` numeric prefix.

### Section: ## Technical Notes (0–2 points)

| Score | Criteria |
|---|---|
| 0 | Missing or empty |
| 1 | Some notes but no file paths or codebase references |
| 2 | Includes file paths, patterns to follow, and existing code references |

**When enriching**: Include specific file paths from the codebase, naming conventions observed, and any configuration files that need to be aware of (e.g., barrel exports in `index.ts`).

---

## Enrichment Decision Thresholds

| Total Score | Category | Action |
|---|---|---|
| 0–5 | **Critical** | Must enrich — task is unworkable for agents |
| 6–10 | **Needs Enrichment** | Should enrich — agent will struggle or produce incorrect output |
| 11–15 | **Adequate** | Optional — agent can proceed but refinement may improve quality |

---

## PRD Cross-Reference Strategy

When enriching a task, map it to PRD content:

1. **Match by keyword**: Search PRD for terms in the task name and description
2. **Match by feature**: If the task is about "pipeline view", find the PRD's Pipeline Summary feature section
3. **Match by phase**: Use the PRD's Implementation Phases to locate the task's phase context
4. **Match by data model**: If the task involves tables, cross-reference with the PRD's Data Model section
5. **Match by architecture**: If the task involves services, cross-reference with the System Architecture section

Always cite the specific PRD section in the enriched `## Context`.

---

## Codebase Analysis Patterns

When analyzing the codebase for a task, search these locations based on task type:

| Task Type | Search Locations |
|---|---|
| Migration | `apps/web/drizzle/migrations/`, `apps/web/lib/drizzle/schema/` |
| Drizzle Schema | `apps/web/lib/drizzle/schema/`, `apps/web/lib/drizzle/db.ts` |
| Server Actions | `apps/web/app/actions/`, existing action files for patterns |
| React/UI Components | `apps/web/components/`, `apps/web/app/(protected)/` |
| RLS Policies | `apps/web/drizzle/migrations/` (grep for `CREATE POLICY`) |
| Edge Functions | `supabase/functions/` |
| Infrastructure/Config | `apps/web/lib/`, `drizzle.config.ts`, `apps/web/lib/env.ts` |

### Pattern Discovery

For each task, find the **closest existing pattern** in the codebase:

| If the task is... | Find an existing... | Use it as... |
|---|---|---|
| Creating a new schema table | Schema file in `lib/drizzle/schema/` (e.g., `slack-channels.ts`) | Template for column types, relations, barrel export pattern |
| Creating a server action | Action file in `app/actions/` (e.g., `slack-provisioning-actions.ts`) | Template for error handling, auth guards, response types |
| Creating a new admin page | Page in `app/(protected)/admin/` (e.g., `slack-provisioning/`) | Template for RSC + client component pattern, data fetching |
| Creating a migration | Recent migration in `drizzle/migrations/` | Template for naming, SQL conventions, RLS patterns |
| Adding RLS policies | Existing RLS migration (grep for `CREATE POLICY`) | Template for policy structure, role checks |
| Adding a new route | Existing route group in `app/(protected)/` | Template for layout, loading, error boundary patterns |

Reference discovered patterns by file path in `## Implementation` and `## Technical Notes`. Do NOT copy full code — just point to the file and describe what to follow.

### Shared Infrastructure Awareness

When enriching, note if the task will need to modify shared files. Flag these for the downstream `/analyze-epic` dependency analysis:

- `lib/drizzle/schema/index.ts` — barrel exports (every new schema table)
- `drizzle.config.ts` — schema list (if adding a new Drizzle schema namespace)
- `components/layout/AppSidebar.tsx` — navigation (if adding new admin pages)
- `lib/env.ts` — environment variables (if adding new env vars)
- `app/layout.tsx` or `app/(protected)/layout.tsx` — root layouts
