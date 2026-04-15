---
name: seed-epic
description: Use when a local PRD exists with implementation phases and task breakdowns, and local epic/task markdown files need to be generated for review before pushing to ClickUp. Triggers on "create tasks from PRD", "seed the epic", "generate epics from PRD", "break down the PRD into tasks", or "seed epic". Takes one param — the PRD folder path. Writes to an `epics/` subfolder inside it.
---

# Seed Epic — PRD to Local Epic & Task Files

> Reads a full PRD, reasons about the right task decomposition, then generates local `.md` task files organized by epic for review.
>
> **Pipeline:** `/seed-prd` → **`/seed-epic`** → `/push-epic-to-clickup` → `/enrich-epic` → `/analyze-epic` → `/run-epic`

## Output Structure

```
{prd_path}/
├── README.md                              ← PRD index (already exists)
├── 01-executive-summary.md                ← PRD pages (already exist)
├── 09-implementation-phases.md            ← primary input for task extraction
└── epics/                                 ← CREATED by this skill
    ├── epic-overview.md                   ← root index: all epics, cross-epic deps
    ├── phase-1-system-prompt-rewrite/     ← Epic 1 = ClickUp List 1
    │   ├── epic-overview.md               ← list-level overview + task map
    │   └── 01-rewrite-setter-instructions.md
    ├── phase-2-static-tool-data/          ← Epic 2 = ClickUp List 2
    │   ├── epic-overview.md
    │   ├── 01-update-get-packages.md
    │   ├── 02-update-get-case-studies.md
    │   └── ...
    ├── phase-3-ai-powered-scoring/
    │   ├── epic-overview.md
    │   └── ...
    └── ...
```

**One folder per epic (phase). Local numbering per epic.** Each epic folder maps to one ClickUp list when pushed via `/push-epic-to-clickup`. Each `.md` task file inside becomes a ClickUp task in that list.

**All output stays local for review.** Nothing is pushed to ClickUp until `/push-epic-to-clickup`.

## Input

- `<args>` = `<prd_path>`
  - Path to local PRD directory (relative to project root or absolute)

Examples:
- `/seed-epic ai_docs/clickup/docs/live-appointment-booking`
- `/seed-epic ai_docs/clickup/docs/sage-ai-setter-optimization`

If the argument is missing, ask the user.

---

## Phase 1 — Absorb the Full PRD

The goal of this phase is to build a complete mental model of the effort before making any structural decisions.

### Step 1: Read the PRD index

Read `{prd_path}/README.md` to discover all pages and key reference files.

### Step 2: Read ALL PRD pages

Read every page listed in the README. Not just the implementation phases — all of them. You need the full context to reason well:

- **01 (Executive Summary)** — scope boundaries, what's in/out
- **02 (Problem Statement)** — current vs. target state
- **03 (Goals & Metrics)** — success criteria that become acceptance criteria
- **04 (Gap Analysis)** — tool-by-tool gaps that inform task boundaries
- **05 (Architecture Plan)** — data flow, new/modified files, design decisions
- **06 (Technical Specifications)** — schemas, API contracts, response shapes
- **07 (UI/Component Changes)** — interface diffs for UI tasks
- **08 (System Prompt Changes)** — prompt diffs for agent tasks
- **09 (Implementation Phases)** — the PRD author's proposed task breakdown
- **10 (Risk Assessment)** — risks that may require additional tasks
- **11 (Definition of Done)** — completion criteria and key decisions

Not all PRDs have all pages. Read what exists.

### Step 3: Read referenced source files

If the PRD references specific source files (e.g., "Modify: `apps/web/lib/chat/static-tools.ts`"), read them. You need to understand the current code to judge whether the PRD's task decomposition is correct.

**Budget:** Read the key files — don't read every file in the codebase. Focus on files that are being created or heavily modified.

---

## Phase 2 — Reason & Restructure

This is the critical phase. You are NOT transcribing the PRD — you are **thinking critically** about whether its task breakdown is correct, complete, and well-scoped for agent execution.

### Step 4: Evaluate the PRD's proposed breakdown

Review the implementation phases document (`09-implementation-phases.md`) against everything you absorbed. Ask yourself:

**Completeness:**
- Are there tasks the PRD missed? (e.g., a new tool is defined but never registered in the chat route, or a barrel export isn't updated)
- Do the acceptance criteria in the PRD's definition of done have matching tasks?
- Are there risks in `10-risk-assessment.md` that need their own mitigation tasks?

**Epic boundaries:**
- Does each phase in the PRD make sense as its own epic (ClickUp list)?
- Should any phases be split into two epics? (e.g., a phase with 10+ tasks spanning different concerns)
- Should any phases be merged? (e.g., two phases with 1 task each that are tightly coupled)

**Task boundaries:**
- Is any task doing too much? (A task that modifies 4+ files or spans multiple concerns should probably be split)
- Are any tasks trivially small and better merged? (e.g., "update barrel export" can be folded into the task that creates the new file)
- Does each task have a clear, testable deliverable?

**Dependencies:**
- Does the PRD's dependency graph make sense? Are there hidden dependencies it missed?
- Can more tasks be parallelized than the PRD suggests?
- Are there circular dependencies?
- What are the cross-epic dependencies? (e.g., Phase 4 UI tasks depend on Phase 2 data shape changes)

**Agent-readiness:**
- Can each task be implemented by an agent that only reads its task file + the referenced source files?
- Does each task have enough context to avoid ambiguity?

### Step 5: Build the restructured task list

Based on your analysis, produce the final task list. You have **full autonomy** to:

- **Split** tasks that are too large
- **Merge** tasks that are trivially small
- **Add** tasks the PRD missed
- **Reorder** tasks for better dependency flow
- **Split or merge phases/epics** if the boundaries are wrong
- **Reclassify** tasks between phases

**Constraint:** Every change must be justified. Don't restructure for the sake of it.

### Step 6: Present the plan with reasoning

Present your restructured plan with explicit reasoning about what changed and why:

```markdown
# Seed Plan: {prd_name}

**PRD:** `{prd_path}/`
**Output:** `{prd_path}/epics/`

## Analysis

{2-4 sentences: what you found when evaluating the PRD's breakdown. What's good, what needed to change.}

### Changes from PRD

| Change | What | Why |
|--------|------|-----|
| Added | `{new task name}` in Phase {N} | {reason} |
| Split | `{original}` → `{part A}` + `{part B}` | {reason} |
| Merged | `{task A}` + `{task B}` → `{combined}` | {reason} |
| Merged phases | Phase {A} + Phase {B} → single epic | {reason} |

_(If no changes: "The PRD's breakdown is well-structured. No changes needed.")_

## Epics

### Epic 1: `phase-1-{slug}/` — {Phase Name}

| # | Task Name | Type | Effort | Parallel? | Key Files |
|---|-----------|------|--------|-----------|-----------|
| 01 | {name} | {type} | {S/M/L/XL} | {Yes/No} | {files} |
| 02 | {name} | {type} | {S/M/L/XL} | {Yes/No} | {files} |

### Epic 2: `phase-2-{slug}/` — {Phase Name}

| # | Task Name | Type | Effort | Parallel? | Key Files |
|---|-----------|------|--------|-----------|-----------|
| 01 | {name} | {type} | {S/M/L/XL} | {Yes/No} | {files} |
| ... | ... | ... | ... | ... | ... |

## Cross-Epic Dependencies

{Which epics depend on which. E.g., "Epic 4 (Tool UIs) depends on Epic 2 (Static Tool Data) — UI components render the data shapes defined in Epic 2."}

## Dependency Graph

{ASCII dependency graph showing both intra-epic and cross-epic dependencies}

## Parallelization Summary

- **Epic {N}:** {which tasks are parallel, which are sequential}
- **Max parallel agents per epic:** {number}

**Total: {epic_count} epics, {task_count} task files + {epic_count + 1} epic-overview.md files**
```

Assign task types using the inference rules in `references/type-inference.md`.

### Step 7: Get confirmation

Ask: **"Create {epic_count} epic folders with {task_count} total tasks in `{prd_path}/epics/`? (Y to proceed, or tell me what to change)"**

Wait for approval before writing anything.

---

## Phase 3 — Write Local Files

### Step 8: Create the folder structure

Create `{prd_path}/epics/` and one subfolder per epic:

```
epics/
├── phase-1-{slug}/
├── phase-2-{slug}/
├── phase-3-{slug}/
└── ...
```

**Folder naming:** `phase-{N}-{slug}` where slug is a kebab-case summary (2-4 words). Examples: `phase-1-system-prompt-rewrite`, `phase-2-static-tool-data`, `phase-3-ai-powered-scoring`.

### Step 9: Write root epic-overview.md

Write `{prd_path}/epics/epic-overview.md` — this is the **root index** that maps all epics and their cross-dependencies. It captures your reasoning about the overall structure.

```markdown
# {Project Name} — Epic Overview

> Generated from PRD: `{prd_path}/`
> Seeded: {YYYY-MM-DD}

## Goal

{One paragraph: what this project achieves and why it matters. From the PRD's executive summary but in your own words.}

## Scope

**In scope:**
- {Bullet list of what's included}

**Out of scope:**
- {What's explicitly excluded — from the PRD's scope boundaries}

## Epics

| # | Epic | Folder | Task Count | Goal |
|---|------|--------|-----------|------|
| 1 | {epic_name} | `phase-1-{slug}/` | {count} | {goal_text} |
| 2 | {epic_name} | `phase-2-{slug}/` | {count} | {goal_text} |
| ... | ... | ... | ... | ... |

## Cross-Epic Dependencies

| Epic | Depends On | Reason |
|------|-----------|--------|
| Epic {N} | Epic {M} | {why — e.g., "UI components render data shapes defined in Epic 2"} |

## Execution Order

{Which epics can run in parallel, which must be sequential}

## Restructuring Notes

{If you made changes from the PRD's original breakdown, document them here with rationale. If no changes: "Breakdown follows the PRD's implementation phases without modification."}

## Definition of Done

{From the PRD's definition of done page — the completion criteria that apply to the project as a whole}
```

### Step 10: Write per-epic overview files

For each epic folder, write `{epic_folder}/epic-overview.md`:

```markdown
# {Epic Name}

> Epic {N} of {total_epics} | {task_count} tasks
> PRD: `{prd_path}/`

## Goal

{One paragraph: what this epic achieves — from the PRD's phase goal.}

## Tasks

| # | File | Task | Type | Effort | Depends On |
|---|------|------|------|--------|------------|
| 01 | `01-{slug}.md` | {name} | {type} | {effort} | — |
| 02 | `02-{slug}.md` | {name} | {type} | {effort} | 01 |

## Parallelization

{Which tasks in this epic can run in parallel, which are sequential.}

## Dependencies

- **Requires:** {other epic(s) this depends on, or "None (first epic)"}
- **Blocks:** {other epic(s) that depend on this, or "None"}

## Definition of Done

{Completion criteria specific to this epic}
```

### Step 11: Write task files

For each task, write `{epic_folder}/{NN}-{task-slug}.md`.

**File naming:** `01-rewrite-setter-instructions.md`, `02-update-get-packages.md`, etc. Two-digit zero-padded, **numbered locally within each epic** (each epic starts at 01). Slug is a kebab-case summary (3-5 words).

Each task file must be **self-contained for agent execution** — an agent should be able to implement the task by reading only this file and the referenced source files.

```markdown
# {NN} — {Task Name}

> Phase {N}: {phase_name} | Effort: {S/M/L/XL} | Type: {inferred_type}

## Context

{WHY this task exists. Not a restatement of "what to do" — the actual motivation. Pull from:
- The PRD's problem statement (02) or gap analysis (04) for the specific gap this task closes
- The architecture plan (05) for where this fits in the data flow
- Risk assessment (10) if this task mitigates a specific risk}

## Implementation

{WHAT to do — specific, concrete, no ambiguity.}

**Files:**
- Create: `{exact/path/to/new-file.ts}`
- Modify: `{exact/path/to/existing-file.ts}` — {what to change}

**Details:**

{Pull the maximum relevant detail from the PRD into this section:
- From 06 (Technical Specifications): exact Zod schemas, API contracts, response shapes
- From 07 (UI/Component Changes): interface before/after, behavioral changes
- From 08 (System Prompt Changes): prompt diffs, new sections
- Include TypeScript interfaces, code snippets, patterns to follow
- Reference existing code patterns: "Follow the pattern in `{existing-file.ts}`"}

## Acceptance Criteria

- [ ] {Verifiable outcome — not vague "works correctly" but specific observable result}
- [ ] {Another verifiable outcome}
- [ ] Build passes (`pnpm run build` in `apps/web/`)

## Dependencies

- **Depends On:** {task number(s) and name(s) within this epic, or cross-epic ref like "Epic 2, Task 01", or "None (first task)"}
- **Blocks:** {task number(s) and name(s), or "None (last in epic)"}

## Technical Notes

- **Epic:** {N} — {epic_name}
- **Priority:** {Low/Normal/High/Urgent}
- **Branch prefix:** `feat/{epic-slug}-{NN}-{task-slug}`
- **Risks:** {Any relevant risks from 10-risk-assessment.md, or "None identified"}
```

### Step 12: Verify enrichment quality

After writing all task files across all epics, do a quick self-check:

- Does every task that modifies a file include the current interface/schema from the PRD's technical specs?
- Does every UI task include the before/after component interface?
- Does every task that creates a new file include enough detail (schemas, patterns) for an agent to write it without guessing?
- Are cross-epic dependency references clear? (e.g., "Depends On: Epic 2, Task 01 — needs updated data shape")
- Did you cover ALL tasks from ALL phases in the PRD? Count them against the PRD's implementation phases.

If any task is thin on detail, go back and enrich it from the PRD pages.

---

## Phase 4 — Summary & Handoff

### Step 13: Present the creation summary

```markdown
# Seed Complete: {prd_name}

**Output:** `{prd_path}/epics/`

## Epics Created

| # | Epic Folder | Task Count | Goal |
|---|-------------|-----------|------|
| 1 | `phase-1-{slug}/` | {count} | {goal} |
| 2 | `phase-2-{slug}/` | {count} | {goal} |
| ... | ... | ... | ... |

**Total: {epic_count} epics, {task_count} tasks, {file_count} files created**

## Restructuring Summary

{Brief recap: what you changed from the PRD and why, or "No changes from PRD."}

## Next Steps

1. **Review** the task files in `{prd_path}/epics/` — edit anything that needs adjustment
2. **Push each epic to ClickUp:** `/push-epic-to-clickup {prd_path}/epics/phase-1-{slug}`
3. **Enrich:** `/enrich-epic <list_id>` to add codebase-specific details
4. **Analyze:** `/analyze-epic <list_id>` to plan phases and parallelization
5. **Execute:** `/run-epic <list_id>` to spawn the agent team
```

---

## Dependency Strategy

### Intra-epic dependencies (within one epic folder)

1. **Explicit PRD dependencies** — Use the PRD's `09-implementation-phases.md` dependency annotations.
2. **Structural inference** — If Task B modifies a file that Task A creates, B depends on A. If Task B renders data that Task A's schema defines, B depends on A.
3. **Positional fallback** (last resort):

| Position | Depends On | Blocks |
|----------|-----------|--------|
| First in epic | None | Next task |
| Middle | Previous task | Next task |
| Last in epic | Previous task | None |

Mark positional-only dependencies with `(positional)` so `/enrich-epic` knows to refine them.

### Cross-epic dependencies (between epic folders)

Documented in the root `epic-overview.md` and in individual task files when a task depends on work from another epic. Use the format: `"Epic {N}, Task {NN} — {task name}"`.

Common patterns:
- UI epics depend on data/backend epics (UI renders the data shapes)
- Testing epics depend on all preceding epics
- Infrastructure epics (env vars, packages) are often prerequisites for everything

---

## Error Handling

| Situation | Action |
|-----------|--------|
| Missing `prd_path` | Ask for it |
| PRD directory doesn't exist | Report error with path checked |
| No implementation phases file found | List available files, ask which contains the task breakdown |
| Roadmap has no parseable structure | Show what you found, ask user to point to the right section |
| `epics/` folder already exists | Ask: "Overwrite existing epics or append?" |
| User wants to change the plan | Apply changes, re-present the plan table, re-confirm |
| PRD is missing key pages (no specs, no architecture) | Warn that task files will be thinner than ideal, proceed with what's available |

---

## References

- Type inference rules: `references/type-inference.md`
- Task format template: `.claude/skills/clickup-task-format/SKILL.md`
- Upstream: `/seed-prd` — creates the PRD that this skill parses
- Downstream: `/push-epic-to-clickup` — pushes one epic folder as a ClickUp list
- Downstream: `/enrich-epic` — enriches tasks with codebase analysis
- Downstream: `/analyze-epic` — builds dependency graph and execution plan
- Downstream: `/run-epic` — spawns agent team to execute tasks
