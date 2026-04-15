---
name: seed-prd
description: Generate a structured PRD (Product Requirements Document) from conversation context into a specified folder. Triggers on "seed PRD", "create PRD", "write PRD", "generate PRD", or "document this as a PRD". Takes a folder path as argument. Follows a 3-phase workflow — deep research, clarifying questions, then structured multi-page PRD output. Upstream of /seed-epic (PRD feeds into epic creation).
---

# Seed PRD — Conversation Context to Structured PRD

> Distills session research, decisions, and clarifications into a structured multi-page PRD.
>
> **Pipeline:** `/seed-prd` → `/seed-epic` → `/enrich-epic` → `/analyze-epic` → `/run-epic`

## Input

- `<args>` = `<output_folder_path>`
  - Path where PRD files will be written (relative to project root or absolute)

Examples:
- `/seed-prd ai_docs/clickup/docs/live-appointment-booking`
- `/seed-prd ai_docs/clickup/docs/new-feature`

If the argument is missing, ask the user for the output folder path.

---

## Phase 1 — Research & Discovery

Gather the raw material for the PRD. This phase is interactive.

### Step 1: Identify what needs to be documented

Determine the scope from conversation context or user description. Ask: **"What effort should this PRD cover? Point me to the relevant files, docs, or describe the feature."**

If the conversation already contains research context (prior file reads, architecture analysis, decision-making), use that directly.

### Step 2: Deep codebase research

Read all referenced source files, target files, API docs, and reference implementations. Build a mental model of:

- **Current state** — what exists today, how it works
- **Target state** — what needs to change, what the end result looks like
- **Reference implementations** — any existing code that solves the same problem elsewhere

### Step 3: Ask clarifying questions

Ask **3-5 focused questions** about things that CANNOT be determined from the code. Examples:
- Authentication strategy
- Rollout strategy (feature flag, hard cutover, shadow mode)
- Integration constraints
- Scope boundaries (what's in vs. out)

**Rule:** Do NOT ask questions answerable by reading the referenced files.

Wait for answers before proceeding to Phase 2.

---

## Phase 2 — Generate PRD

Write the PRD as numbered markdown files in the output folder.

### Step 4: Create output folder

Create the folder if it doesn't exist. Verify parent directory exists first.

### Step 5: Write PRD pages

Write each page as a separate numbered markdown file. Select pages from the template based on what's relevant to this effort. See `references/prd-structure.md` for the page catalog.

**Every PRD MUST include:**
- `README.md` — index with page table and key reference files
- `01-executive-summary.md` — what, why, scope, business impact
- A definition of done page (last numbered page) — checklist + key decisions log

**Select additional pages based on the effort.** Not every PRD needs all pages. A small feature might be 5 pages; a major migration might be 11.

### Step 6: Write README.md

The README is the index. Format:

```markdown
# {Feature Name} — {Short Descriptor} PRD

> Created {YYYY-MM-DD}.

## Pages

| # | File | Description |
|---|------|-------------|
| 01 | [Executive Summary](01-executive-summary.md) | What, why, and business impact |
| ... | ... | ... |

## Key Reference Files

- **Source of truth:** `path/to/reference`
- **Target files:** `path/to/target`
```

---

## Phase 3 — Summary & Handoff

### Step 7: Present summary

After writing all pages, present:

```
PRD complete and saved to `{output_folder}/` ({page_count} pages).

| # | Document | Key Content |
|---|----------|-------------|
| 01 | Executive Summary | ... |
| ... | ... | ... |

**Next step:** Run `/seed-epic <folder_id> {output_folder}` to create ClickUp epics from this PRD.
```

---

## Writing Guidelines

- **Be specific.** File paths, not "the config file". API response shapes, not "the response". Zod schemas, not "the validation".
- **Show the diff.** When describing changes, show current vs. target (tables work well).
- **Decisions are first-class.** Every non-obvious choice gets a row in the Definition of Done decisions table with rationale.
- **Code in PRDs.** Include TypeScript/Python snippets for interfaces, schemas, and key patterns. PRDs are for implementers.
- **No fluff.** Every paragraph earns its place. If it's obvious to a senior engineer reading the code, skip it.

## References

- PRD page templates and catalog: `references/prd-structure.md`
