---
name: seed-prd
description: Generate a structured PRD from conversation context, codebase research, and clarifying answers into a local docs folder. Use when the user asks to create a PRD, seed a PRD, document an effort before implementation, or prepare roadmap docs that will feed the epic pipeline.
---

# Seed PRD

Create a structured PRD in a local folder so downstream workflow stages can turn it into executable tasks.

## Input

Parse one argument from the user request:
- `output_folder_path`: local destination for the PRD folder

If the path is missing, ask for it.

## Workflow

### 1. Research the effort

Read the user-provided reference files, architecture notes, and target files. Build a concrete picture of:
- current state
- target state
- affected files and integrations
- risks and open design choices

Only read `ai_docs/` when the request or referenced materials require it.

### 2. Ask focused clarifying questions

Ask only for decisions that cannot be discovered from code or the provided docs. Keep this to the minimum needed to write an implementable PRD.

Typical examples:
- rollout strategy
- scope boundaries
- auth or permissions assumptions
- migration or backwards-compatibility requirements

### 3. Create the PRD folder

Write the PRD into `output_folder_path` as numbered markdown pages.

Always create:
- `README.md`
- `01-executive-summary.md`
- a final definition-of-done page

Select the rest of the pages from `references/prd-structure.md` based on the effort type.

### 4. Keep the PRD implementation-ready

The PRD must be specific enough for `seed-epic` to parse into tasks. In particular:
- implementation phases must be explicit
- files, APIs, schemas, and constraints should be concrete
- decisions and scope cuts should be recorded

### 5. Summarize the handoff

After writing the PRD, report:
- output folder
- pages written
- the next step: `seed-epic <prd_path>`

## Writing rules

- Prefer exact file paths over vague references.
- Show current vs target behavior when relevant.
- Include concrete contracts, schemas, or signatures when they are important to implementation.
- Do not pad the PRD with generic product language.

## References

- `references/prd-structure.md`
