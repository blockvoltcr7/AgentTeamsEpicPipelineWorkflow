# Epic Pipeline — Knowledge Transfer

> How OS HQ turns a PRD into fully executed code through a six-stage pipeline, powered by Claude Code Agent Teams.
>
> Last updated: April 2026

---

## Overview

The Epic Pipeline is a six-command workflow that transforms research and conversation context into deployed, working code — orchestrated by specialized AI agents working in parallel where safe to do so.

```
┌────────────┐    ┌─────────────┐    ┌───────────────────────┐    ┌──────────────┐    ┌───────────────┐    ┌─────────────┐
│ /seed-prd  │ →  │ /seed-epic  │ →  │ /push-epic-to-clickup │ →  │ /enrich-epic │ →  │ /analyze-epic │ →  │  /run-epic  │
│            │    │             │    │                       │    │              │    │               │    │             │
│ Research → │    │ PRD → local │    │ Local files →         │    │ Enrich with  │    │ Build graph   │    │ Spawn team  │
│ PRD docs   │    │ task files  │    │ ClickUp + deps wired  │    │ codebase     │    │ & plan phases │    │ & execute   │
└────────────┘    └─────────────┘    └───────────────────────┘    └──────────────┘    └───────────────┘    └─────────────┘
    AUTHOR             SEED                  PUSH                    PREPARE              PREPARE              EXECUTE
```

Each stage has a single responsibility. Each stage produces output that the next stage consumes. Every stage has a user confirmation gate before making changes.

### What each stage produces

```
Conversation context (research, decisions, Q&A)
    │
    ▼  /seed-prd
Structured PRD document (ai_docs/clickup/docs/{name}/)
    │
    ▼  /seed-epic
Local .md task files (ai_docs/clickup/docs/{name}/epics/)
    │
    ▼  /push-epic-to-clickup
ClickUp list with tasks + dependency relationships wired
    │
    ▼  /enrich-epic
Tasks enriched with codebase file paths, patterns, acceptance criteria
    │
    ▼  /analyze-epic
EXECUTION STRATEGY comments: phases, parallelization, worktree branches
    │
    ▼  /run-epic
Completed code — all tasks implemented by specialist agents
```

---

## The Six Stages

### Stage 0: `/seed-prd` — Research to Structured PRD

**What it does:** Transforms conversation context, codebase research, and clarifying Q&A into a structured multi-page PRD in a local folder.

**Usage:**
```
/seed-prd <output_folder_path>
```

**Example:**
```
/seed-prd ai_docs/clickup/docs/live-appointment-booking
```

**Input:** Conversation context — file references, architecture analysis, user answers to clarifying questions. The user describes what they want to build or migrate, points to reference files and target files.

**Output:** A folder with numbered markdown pages:
- `README.md` — index with page table and key reference files
- `01-executive-summary.md` — what, why, scope, business impact
- `02` through `10` — selected pages based on effort type (gap analysis, architecture, tool specs, UI changes, implementation phases, risks, etc.)
- Final page — definition of done with checklist and key decisions table

**How it works:**
1. **Research** — reads all referenced files (source, target, API docs, reference implementations)
2. **Clarify** — asks 3-5 focused questions about things that cannot be determined from code (auth strategy, rollout approach, scope boundaries)
3. **Generate** — writes pages selected from a catalog based on effort type (migration, greenfield, API integration, etc.)

**Key detail:** The PRD's `09-implementation-phases.md` page is structured so `/seed-epic` can parse it into tasks. This is the handoff point between authoring and execution.

| File | Purpose |
|---|---|
| `.claude/skills/seed-prd/SKILL.md` | Skill definition with 3-phase workflow |
| `.claude/skills/seed-prd/references/prd-structure.md` | Page catalog and selection guide |

---

### Stage 1: `/seed-epic` — PRD to Local Task Files

**What it does:** Parses a PRD's implementation roadmap and generates local `.md` task files inside an `epics/` subfolder of the PRD directory for review before pushing to ClickUp.

**Usage:**
```
/seed-epic <prd_path>
```

**Example:**
```
/seed-epic ai_docs/clickup/docs/live-appointment-booking
```

**Input:** PRD directory containing an implementation phases document (e.g., `09-implementation-phases.md`).

**Output:** `{prd_path}/epics/` folder containing:
- `epic-overview.md` — epic title, goal, scope, definition of done
- `01-task-name.md`, `02-task-name.md`, ... — one file per task with structured sections

**How it works:**
1. Reads the PRD roadmap and extracts phases and task breakdowns
2. Shows the user a plan of what will be created, asks for confirmation
3. Generates local `.md` files enriched with PRD context (schemas, API contracts, gap analysis — not just stubs)
4. Each task file is self-contained enough for an agent to implement without reading the full PRD

**Key detail:** This stage creates LOCAL files only inside the PRD folder — nothing is pushed to ClickUp yet. Review and edit before running `/push-epic-to-clickup`.

| File | Purpose |
|---|---|
| `.claude/skills/seed-epic/SKILL.md` | Skill definition |
| `.claude/skills/seed-epic/references/type-inference.md` | Rules for inferring task types |

---

### Stage 2: `/push-epic-to-clickup` — Local Files to ClickUp

**What it does:** Reads the local epic folder generated by `/seed-epic`, creates a ClickUp list with tasks, and **wires dependency relationships** using the ClickUp API.

**Usage:**
```
/push-epic-to-clickup <epic_folder_path> <folder_id>
```

**Example:**
```
/push-epic-to-clickup ai_docs/clickup/epics/3.1-tool-calling-agent 90177638784
```

**Input:** Local epic folder with `epic-overview.md` + numbered task `.md` files.

**Output:** ClickUp list inside the target folder, with:
- All tasks created with full markdown descriptions
- Priority mapped from effort estimates (S→normal, M/L→high, XL→urgent)
- **Dependency relationships wired** via `clickup_add_task_dependency` (`waiting_on` type)

**How it works:**
1. Reads `epic-overview.md` + all numbered `.md` files
2. Verifies the ClickUp folder exists
3. Creates a ClickUp list from the epic overview
4. Creates all tasks with full markdown descriptions
5. Parses `## Dependencies` → `Depends On:` lines and wires each as a ClickUp `waiting_on` relationship
6. Reports a summary with task IDs and wired relationships

**Key detail:** Only `Depends On` lines are used (not `Blocks`) to avoid creating duplicate relationships from both sides.

| File | Purpose |
|---|---|
| `~/.claude/skills/push-epic-to-clickup/SKILL.md` | Plugin skill definition |

---

### Stage 3: `/enrich-epic` — Codebase-Driven Task Enrichment

**What it does:** Takes ClickUp tasks and enriches them with implementation details, acceptance criteria, and file paths by cross-referencing local PRD docs and scanning the codebase.

**Usage:**
```
/enrich-epic <list_id>
```

**Example:**
```
/enrich-epic 901712200292
```

**Input:** ClickUp list ID containing the epic's tasks (created by `/push-epic-to-clickup`).

**Output:** Tasks updated in ClickUp with:
- `## Context` — business justification with PRD references
- `## Implementation` — exact file paths, code patterns, step-by-step guidance
- `## Acceptance Criteria` — 3+ verifiable outcomes
- `## Dependencies` — task IDs for Depends On and Blocks
- `## Technical Notes` — file paths, patterns, codebase references

**How it works:**

1. **Gather context** — Reads local PRD docs from `ai_docs/clickup/docs/` using a 3-tier strategy:
   - **Always read:** `05-core-features-mvp.md`, `07-data-model-and-security.md`, `11-definition-of-done-and-decision-log.md`
   - **Selective:** Architecture, tech stack, roadmap docs (when relevant)
   - **Rarely needed:** Executive summary, problem statement (only for business context tasks)

2. **Assess quality** — Scores each task 0–15 against the task format template:
   | Score | Status | Action |
   |---|---|---|
   | 0–5 | Critical | Must enrich |
   | 6–10 | Needs Enrichment | Should enrich |
   | 11–15 | Adequate | Optional refinement |

3. **Enrich interactively** — For each task the user selects:
   - Spawns an `Explore` subagent to scan the codebase
   - Assembles enriched description using the `clickup-task-format` template
   - Cross-references against PRD terminology and requirements
   - Shows enrichment for user review
   - On approval, updates the task in ClickUp

| File | Purpose |
|---|---|
| `.claude/commands/enrich-epic.md` | Command definition |
| `.claude/skills/enrich-epic/references/enrichment-criteria.md` | Scoring rubric, codebase analysis patterns |

---

### Stage 4: `/analyze-epic` — Dependency Graph & Parallelization

**What it does:** Builds a dependency graph, determines which tasks can run in parallel via git worktrees, assigns phase numbers, and adds execution strategy comments to each ClickUp task.

**Usage:**
```
/analyze-epic <list_id>
```

**Example:**
```
/analyze-epic 901712200292
```

**Input:** ClickUp list with enriched tasks (from `/enrich-epic`).

**Output:** Each task gets an `EXECUTION STRATEGY` comment:

```
EXECUTION STRATEGY

Phase: 1 — Parallel Window 1
Worktree Mode: PARALLEL
Depends On: None
Blocks: 86e0gppvg
Parallelizable: YES
Parallel Partner: 86e0gppv8, 86e0gpq0r
Merge conflict risk: LOW
Worktree Assignment: WORKTREE-A (branch: feat/tool-agent-3.1.1-add-zod)
```

**How it works:**

1. **Build DAG** — Parses `## Dependencies` from each task, constructs a directed acyclic graph. Validates: cycle detection, orphan detection, external reference warnings.

2. **Assign phases** — Topological sort: Phase 1 = zero in-degree nodes, Phase N = all deps in earlier phases.

3. **Detect parallelism** — For tasks within the same phase, three-layer file overlap detection:
   - **Layer 1:** Explicit file paths from `## Implementation` and `## Technical Notes`
   - **Layer 2:** Type-based inference (e.g., `Migration` → likely modifies `index.ts`)
   - **Layer 3:** Conflict zone check (barrel exports, sidebar, env.ts — NEVER parallelized)

4. **Present & confirm** — Shows phase plan, parallelization summary, estimated speedup.

5. **Apply comments** — Adds `EXECUTION STRATEGY` comment to each ClickUp task.

**Key design decisions:**
- Conservative parallelization — when in doubt, marks as SEQUENTIAL
- Comments, not description changes — keeps task descriptions clean for agents
- Conflict zones: `index.ts`, `drizzle.config.ts`, `AppSidebar.tsx`, `env.ts`, root layouts are NEVER parallelized

| File | Purpose |
|---|---|
| `.claude/commands/analyze-epic.md` | Command definition |
| `.claude/skills/analyze-epic/references/dependency-analysis.md` | DAG construction, file overlap algorithms |

---

### Stage 5: `/run-epic` — Agent Team Orchestration

**What it does:** Creates a Claude Code Agent Team, maps each task to a specialist agent, and executes work phase-by-phase — parallel tasks run in isolated git worktrees.

**Usage:**
```
/run-epic <list_id>
```

**Example:**
```
/run-epic 901712200292
```

**Input:** ClickUp list with enriched tasks + execution strategy comments.

**Output:** All tasks implemented. ClickUp statuses updated to Done.

**How it works:**

1. **Fetch & parse** — Reads task descriptions AND execution strategy comments. Extracts phase numbers, worktree modes, agent types, branch names.

2. **Map to agents** — Routes each task to a specialist:

   | Task Type | Agent | Specialization |
   |---|---|---|
   | Migration / Drizzle Schema | `drizzle` | SQL DDL, Drizzle ORM schemas |
   | Code (React/Next.js) | `typescript-react` / `oshq-frontend` | Pages, components, server actions |
   | RLS / Row Level Security | `supabase-rls-policy-generator` | RLS policy design |
   | Edge Function | `supabase-edge-function-writer` | Supabase Edge Functions |
   | Database Function | `supabase-function-generator` | PL/pgSQL procedures |
   | Infrastructure / Fallback | `general-purpose` | Build verification, misc |

3. **Present plan & confirm** — Shows phase plan table with agent assignments and worktree isolation.

4. **Execute phases** — For each phase:
   - Spawns specialist teammates (parallel phases → multiple agents in one message)
   - Updates ClickUp to `in progress`
   - Monitors teammates (messages arrive automatically)
   - Verifies completion in ClickUp
   - **Phase gate:** Merges worktree branches, runs build check before next phase

5. **Cleanup** — Shuts down teammates, team is cleaned up.

**Architecture:** The session running `/run-epic` IS the team lead. It creates the team, spawns all teammates directly, and manages phase gates. Teammates cannot spawn other teammates.

```
┌─────────────────────────────────────────────────────────┐
│                    YOUR TERMINAL                         │
│                                                          │
│  /run-epic 901712200292                                  │
│       │                                                  │
│       ▼                                                  │
│  ┌─────────┐    TeamCreate     ┌──────────────────────┐ │
│  │  Lead   │ ──────────────→   │    Shared Task List   │ │
│  │ Session │ ←──── messages ── │  (all agents can see) │ │
│  └────┬────┘                   └──────────────────────┘ │
│       │                                                  │
│       │  Phase 1 (parallel)                              │
│       ├──────────────────→ @agent-3.1.1-zod (worktree)  │
│       ├──────────────────→ @agent-3.1.2-client (worktree)│
│       ├──────────────────→ @agent-3.1.6-jwt (worktree)  │
│       │                                                  │
│       │  [Phase gate: merge worktrees + build check]     │
│       │                                                  │
│       │  Phase 2 (sequential)                            │
│       ├──────────────────→ @agent-3.1.3-tools (main)    │
│       │                                                  │
│       │  [Phase gate]                                    │
│       │                                                  │
│       │  Phase 3 (parallel)                              │
│       ├──────────────────→ @agent-3.1.4-wire (worktree) │
│       └──────────────────→ @agent-3.1.5-meta (worktree) │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

| File | Purpose |
|---|---|
| `.claude/commands/run-epic.md` | Command definition |
| `.claude/skills/run-epic/references/agent-mapping.md` | Task type → agent mapping |
| `.claude/skills/run-epic/references/orchestration-protocol.md` | Phase execution algorithm |

---

## How the Stages Connect

### Data Flow

```
     PRD Document                                   Local Files                                ClickUp
(ai_docs/clickup/docs/)                  (ai_docs/clickup/epics/{name}/)                   Task List
         │                                           │                                         │
         ▼                                           │                                         │
+─────────────────────+                              │                                         │
│    /seed-epic       │                              │                                         │
│                     │                              │                                         │
│ Reads: PRD roadmap  │                              │                                         │
│ Writes: Local .md   │──────────────────────────────▶                                         │
│   task files        │                              │                                         │
+─────────────────────+                              │                                         │
                                                     ▼                                         │
                                      +──────────────────────────+                             │
                                      │ /push-epic-to-clickup   │                             │
                                      │                          │                             │
                                      │ Reads: Local .md files  │                             │
                                      │ Writes: ClickUp list +  │─────────────────────────────▶
                                      │   tasks + dependencies  │                             │
                                      +──────────────────────────+                             │
                                                                                               │
                                                                                               ▼
                                                                              +─────────────────────────+
                                                                              │     /enrich-epic        │
                                                                              │                         │
                                                                              │ Reads: PRD docs + tasks │
                                                                              │ Analyzes: Codebase      │
                                                                              │ Writes: markdown_desc   │
                                                                              +───────────┬─────────────+
                                                                                          │
                                                                                          ▼
                                                                              +─────────────────────────+
                                                                              │    /analyze-epic        │
                                                                              │                         │
                                                                              │ Reads: ## Dependencies  │
                                                                              │ Computes: DAG, phases   │
                                                                              │ Writes: EXECUTION       │
                                                                              │   STRATEGY comments     │
                                                                              +───────────┬─────────────+
                                                                                          │
                                                                                          ▼
                                                                              +─────────────────────────+
                                                                              │      /run-epic          │
                                                                              │                         │
                                                                              │ Reads: Tasks + strategy │
                                                                              │ Spawns: Agent team      │
                                                                              │ Updates: Task status    │
                                                                              │   (Open → Done)         │
                                                                              +─────────────────────────+
```

### What Each Stage Reads and Writes

| Stage | Reads | Writes |
|---|---|---|
| `/seed-prd` | Conversation context, source files, API docs, reference code | Structured PRD (numbered `.md` pages in output folder) |
| `/seed-epic` | PRD roadmap doc | Local `.md` task files in `{prd_path}/epics/` |
| `/push-epic-to-clickup` | Local `.md` task files from `epics/` folder | ClickUp list + tasks + dependency relationships |
| `/enrich-epic` | Local PRD docs + ClickUp tasks | Updated `markdown_description` on each task |
| `/analyze-epic` | Task descriptions (`## Dependencies`, `## Type`) | `EXECUTION STRATEGY` comments on each task |
| `/run-epic` | Task descriptions + strategy comments | Task status transitions (Open → In Progress → Done) |

### Confirmation Gates

Every stage asks the user before making changes:

| Stage | What It Shows | What It Asks |
|---|---|---|
| `/seed-prd` | Research findings, identified gaps | 3-5 clarifying questions before generating |
| `/seed-epic` | Parsed phases/epics/tasks | "Create N local task files?" |
| `/push-epic-to-clickup` | Task list + dependency wiring plan | Creates automatically after parsing |
| `/enrich-epic` | Quality scores (0–15) for each task | "Which task to enrich?" |
| `/analyze-epic` | Phase plan + parallelization summary | "Ready to add execution strategy comments?" |
| `/run-epic` | Agent assignments + phase plan table | "Ready to execute this epic?" |

---

## Tutorial: Running the Pipeline End-to-End

This walkthrough uses Epic 3.1 (Tool-Calling Agent) as a real example.

### Prerequisites

1. **tmux** installed: `brew install tmux`
2. **Agent teams enabled** in `~/.claude/settings.json`:
   ```json
   {
     "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" },
     "teammateMode": "tmux"
   }
   ```
3. **ClickUp MCP** configured (for task reads/writes)
4. **Supabase MCP** configured (for database migrations during execution)
5. A PRD with implementation phases at `ai_docs/clickup/docs/{prd-name}/` (create one with `/seed-prd` if it doesn't exist)

### Step 0 (optional): Create the PRD

If you don't have a PRD yet, generate one from conversation context:

```
/seed-prd ai_docs/clickup/docs/my-feature
```

**What happens:**
- Claude reads referenced files, understands current + target state
- Asks 3-5 clarifying questions about scope, auth, rollout strategy, etc.
- After you answer, generates a structured multi-page PRD with gap analysis, architecture plan, implementation phases, and risk assessment

**Your action:** Review the PRD pages. The `09-implementation-phases.md` page is what `/seed-epic` will parse next.

### Step 1: Seed the epic

```
/seed-epic ai_docs/clickup/docs/livekitui
```

**What happens:**
- Claude reads the PRD's implementation phases document
- Extracts phases and task breakdowns
- Asks which phases to seed
- Generates local `.md` files inside the PRD folder:

```
ai_docs/clickup/docs/livekitui/
├── README.md                          ← PRD (already exists)
├── 09-implementation-phases.md        ← parsed by /seed-epic
└── epics/                             ← CREATED by /seed-epic
    ├── epic-overview.md
    ├── 01-add-zod-dependency.md
    ├── 02-create-ghl-client.md
    ├── 03-create-ghl-tools.md
    └── ...
```

**Your action:** Review the generated files in `epics/`. Edit any task descriptions that need adjustment. These files are your source of truth before pushing to ClickUp.

### Step 2: Push to ClickUp

```
/push-epic-to-clickup ai_docs/clickup/docs/livekitui/epics 90177638784
```

**What happens:**
- Creates a ClickUp list named "Epic 3.1: Tool-Calling Agent (GHL API Tools)"
- Creates 9 tasks inside it with full markdown descriptions
- Wires dependency relationships (e.g., Task 3.1.3 `waiting_on` Task 3.1.1 and Task 3.1.2)
- Reports: list ID, task IDs, relationship count

**Your action:** Note the `list_id` from the output — you'll use it for all remaining stages. Verify in ClickUp that tasks and dependency arrows look correct.

### Step 3: Enrich tasks

```
/enrich-epic <list_id>
```

**What happens:**
- Reads PRD docs + fetches all tasks from ClickUp
- Scores each task 0–15 on completeness
- Shows a quality assessment table
- You pick tasks to enrich one by one
- For each: scans the codebase, finds exact file paths and patterns, adds acceptance criteria
- Updates the task in ClickUp after your review

**Your action:** Focus on tasks scoring below 11. Review each enrichment before approving. Pay attention to file paths and acceptance criteria — these directly determine what agents will build.

### Step 4: Analyze execution strategy

```
/analyze-epic <list_id>
```

**What happens:**
- Builds a dependency graph (DAG) from `## Dependencies`
- Assigns phase numbers via topological sort
- Detects which tasks can run in parallel (file overlap analysis)
- Assigns worktree branches for parallel tasks
- Shows the phase plan:

```
Phase 1 — Parallel (3 tasks): 3.1.1, 3.1.2, 3.1.6
Phase 2 — Sequential (1 task): 3.1.3
Phase 3 — Parallel (2 tasks): 3.1.4, 3.1.5
Phase 4 — Sequential (1 task): 3.1.7
Phase 5 — Sequential (1 task): 3.1.8
Phase 6 — Sequential (1 task): 3.1.9
```

- After your approval, adds `EXECUTION STRATEGY` comments to each ClickUp task

**Your action:** Review the phase plan. Check that parallel tasks truly don't share files. Adjust if needed.

### Step 5: Execute with agent team

```
/run-epic <list_id>
```

**What happens:**
- Reads tasks + strategy comments
- Maps each task to a specialist agent
- Shows the full plan with agent assignments
- After your approval, creates a team and executes phase-by-phase:
  - **Parallel phases:** Multiple agents spawn simultaneously in git worktrees
  - **Sequential phases:** One agent works on the main branch
  - **Phase gates:** Lead merges worktree branches and runs build checks between phases
  - **ClickUp updates:** Tasks transition Open → In Progress → Done automatically

**Your action:** Monitor the tmux panes. Respond to any teammate questions. The lead session handles orchestration automatically. Manual phases (like smoke testing) will pause and tell you what to test.

### After completion

The epic is done when:
- All ClickUp tasks are marked Done
- All code is on the feature branch
- Build passes (`pnpm run build`)

Next steps:
- Create a PR to merge the feature branch into `main`
- Deploy any backend changes (e.g., redeploy LiveKit agent)
- Update CLAUDE.md if the epic added new patterns

---

## Real-World Example: Epic 3.1 Tool-Calling Agent

This epic added 5 GHL API tools to the voice agent. Here's how the pipeline executed it:

### Phase plan (from `/analyze-epic`)

| Phase | Mode | Tasks | Isolation |
|---|---|---|---|
| 1 | Parallel (3 agents) | 3.1.1 Add zod, 3.1.2 GHL client, 3.1.6 JWT metadata | 3 worktrees |
| 2 | Sequential (1 agent) | 3.1.3 Create 5 tool definitions | Main branch |
| 3 | Parallel (2 agents) | 3.1.4 Wire tools, 3.1.5 Parse metadata | 2 worktrees |
| 4 | Sequential (1 agent) | 3.1.7 Build verification | Main branch |
| 5 | Sequential (manual) | 3.1.8 Smoke test | Manual QA |
| 6 | Sequential (1 agent) | 3.1.9 Update CLAUDE.md | Main branch |

### Execution timeline

```
Phase 1: 3 agents spawn in worktrees (agent pkg, agent src, web pkg)
         All complete in ~2 minutes
         Worktrees merge cleanly (different files, no conflicts)
         → Phase gate cleared

Phase 2: 1 agent creates ghl-tools.ts with 5 tool definitions
         Completes in ~4 minutes
         → Phase gate cleared

Phase 3: 2 agents spawn in worktrees (agent.ts, main.ts)
         Both complete in ~2 minutes
         Worktrees merge cleanly
         → Phase gate cleared

Phase 4: 1 agent runs tsc --noEmit + pnpm run build
         Both pass, zero errors
         → Phase gate cleared

Phase 5: Manual smoke test (user tests voice → tool → answer flow)
         → Confirmed working

Phase 6: 1 agent updates CLAUDE.md with agent tools documentation
         → Epic complete
```

**Result:** 9 tasks, 6 phases, 8 specialist agent deployments. Phases 1 and 3 each ran agents in parallel, cutting wall-clock time. All ClickUp tasks updated to Done automatically. Two commits pushed to the feature branch.

---

## The Agent Roster

Each teammate is a specialist agent with domain-specific knowledge:

| Agent | Specialization | When Used |
|---|---|---|
| `drizzle` | SQL migrations, Drizzle ORM schemas, type exports | Database schema tasks |
| `oshq-frontend` | OS HQ admin pages, tables, dialogs, server actions | UI tasks specific to OS HQ patterns |
| `typescript-react` | General React/Next.js components | UI tasks without OS HQ-specific patterns |
| `supabase-rls-policy-generator` | Row Level Security policy design | RLS policy tasks |
| `supabase-edge-function-writer` | Supabase Edge Functions | Serverless function tasks |
| `supabase-function-generator` | PL/pgSQL stored procedures, triggers | Database function tasks |
| `supabase-realtime-expert` | Channels, presence, broadcast | Realtime feature tasks |
| `supabase-dba-schema-advisor` | Schema review, index optimization | DBA/schema design tasks |
| `general-purpose` | Fallback for unmatched task types | Infrastructure, build verification, misc |

The `oshq-frontend` agent is a custom agent built specifically for this codebase. It knows OS HQ's exact patterns: admin page structure (async RSC → server action → client component), `ServerActionResponse<T>` convention, status badge pattern, search-filtered table pattern, and the "Industrial Forge" monochrome theme.

---

## Supporting Infrastructure

### Task Description Template

All stages depend on a shared task format (defined in `.claude/skills/clickup-task-format/SKILL.md`):

```markdown
## Type
[Migration | Code | RLS | UI | Infrastructure | ...]

## Context
[WHY this task exists — business justification with PRD references]

## Implementation
[HOW to do it — file paths, code patterns, step-by-step]

## Acceptance Criteria
- [ ] [Verifiable outcome]

## Dependencies
- **Depends On:** [task references with IDs]
- **Blocks:** [task references with IDs]

## Technical Notes
- [File paths, patterns, effort estimate]
```

### Naming Conventions

- **Task names:** `{epic}.{sequence} {Verb} {object}` — e.g., `3.1.3 Create 5 GHL tool definitions`
- **Branch names:** `feat/{prefix}-{number}-{description}` — e.g., `feat/tool-agent-3.1.1-add-zod`
- **Epic folders:** `ai_docs/clickup/epics/{epic-number}-{epic-name}/`

### Conflict Zones

Files that are NEVER safe for parallel modification:

| File | Why |
|---|---|
| `lib/drizzle/schema/index.ts` | Barrel exports — every new schema table adds a line |
| `drizzle.config.ts` | Schema registration |
| `components/layout/AppSidebar.tsx` | Navigation sidebar |
| `lib/env.ts` | Environment variables |
| `app/layout.tsx`, `app/(protected)/layout.tsx` | Root layouts |

---

## tmux Setup for Agent Teams

To see teammates in split panes (recommended for monitoring):

```json
// ~/.claude/settings.json
{
  "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" },
  "teammateMode": "tmux"
}
```

Requires `tmux` installed (`brew install tmux` on macOS).

| Action | In-Process Mode | tmux Split-Pane Mode |
|---|---|---|
| Cycle through teammates | `Shift+Down` | Click the pane |
| Interrupt a teammate | `Escape` | Click pane + `Escape` |
| Toggle shared task list | `Ctrl+T` | `Ctrl+T` |
| Message a teammate | `Shift+Down` to select, type | Click into pane, type |

---

## Complete File Reference

```
.claude/
├── commands/
│   ├── enrich-epic.md                         # Stage 3: Task enrichment
│   ├── analyze-epic.md                        # Stage 4: Dependency analysis
│   └── run-epic.md                            # Stage 5: Agent team orchestration
│
├── skills/
│   ├── seed-prd/                              # Stage 0: Research → structured PRD
│   │   ├── SKILL.md
│   │   └── references/
│   │       └── prd-structure.md
│   │
│   ├── seed-epic/                             # Stage 1: PRD → local task files
│   │   ├── SKILL.md
│   │   └── references/
│   │       └── type-inference.md
│   │
│   ├── clickup-task-format/                   # Shared task description template
│   │   ├── SKILL.md
│   │   └── references/
│   │       └── execution-strategy.md
│   │
│   ├── enrich-epic/
│   │   └── references/
│   │       └── enrichment-criteria.md
│   │
│   ├── analyze-epic/
│   │   └── references/
│   │       └── dependency-analysis.md
│   │
│   └── run-epic/
│       └── references/
│           ├── agent-mapping.md
│           └── orchestration-protocol.md
│
├── agents/
│   ├── oshq-frontend-agent.md
│   ├── drizzle-agent.md
│   ├── supabase-rls-policy-generator.md
│   ├── supabase-edge-function-writer.md
│   ├── supabase-function-generator.md
│   ├── supabase-realtime-expert.md
│   └── supabase-dba-schema-advisor.md

~/.claude/skills/
└── push-epic-to-clickup/                      # Stage 2: Local files → ClickUp (plugin skill)
    └── SKILL.md

ai_docs/
├── clickup/
│   ├── docs/                                  # Local PRD mirror (read by /enrich-epic)
│   │   ├── livekitui/
│   │   │   ├── 05-core-features-mvp.md        # ← Always read
│   │   │   ├── 07-data-model-and-security.md  # ← Always read
│   │   │   ├── 09-implementation-phases-and-roadmap.md
│   │   │   └── 11-definition-of-done-and-decision-log.md  # ← Always read
│   │   └── ...
│   │
│   └── epics/                                 # Local epic folders (created by /seed-epic)
│       ├── 3.1-tool-calling-agent/
│       │   ├── epic-overview.md
│       │   ├── 01-add-zod-dependency.md
│       │   └── ...
│       └── ...
│
└── workflow/
    └── epic-pipeline.md                       # This document
```

---

## Quick Reference

```bash
# Full pipeline — 6 commands in sequence
/seed-prd <output_folder>                                # 0. Research → structured PRD
/seed-epic <prd_path>                                    # 1. PRD → local .md task files (in prd_path/epics/)
/push-epic-to-clickup <epic_folder> <folder_id>      # 2. Local files → ClickUp + deps
/enrich-epic <list_id>                                # 3. Enrich with codebase analysis
/analyze-epic <list_id>                               # 4. Plan phases & parallelization
/run-epic <list_id>                                   # 5. Execute with agent team
```
