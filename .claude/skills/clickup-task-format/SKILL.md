---
name: clickup-task-format
description: Format and create ClickUp tasks with proper markdown, execution strategy comments, and worktree coordination metadata. Use when creating, updating, or reformatting ClickUp tasks via the ClickUp MCP. Also use when planning parallel work across git worktrees — ensures tasks have the dependency and parallelization metadata agents need to avoid merge conflicts.
---

# ClickUp Task Formatting

## Critical Rule

**Always use `markdown_description`** (never `description`) when calling `clickup_create_task` or `clickup_update_task`. The `description` field renders `\n` as literal text. `markdown_description` renders proper markdown with headers, code blocks, and checklists.

## Task Description Template

Every task in the OS HQ Dashboard folder must use this structure:

```markdown
## Type

[Migration | Code | Migration + Drizzle Schema | UI | Infrastructure]

## Context

[1-2 paragraphs explaining WHY this task exists and what problem it solves]

## Implementation

[Code blocks, SQL, or step-by-step instructions. Use fenced code blocks for all code.]

## Acceptance Criteria

- [ ] [Specific, verifiable outcome 1]
- [ ] [Specific, verifiable outcome 2]
- [ ] [Specific, verifiable outcome 3]

## Dependencies

- **Depends On:** Task X.X (`task_id`) — [what it needs from that task]
- **Blocks:** Task X.X (`task_id`) — [what it provides to that task]

## Technical Notes

- [Implementation details, file paths, patterns to follow]
```

## Execution Strategy Comments

After creating or updating a task in the OS HQ Dashboard folder, add an execution strategy comment using `clickup_create_task_comment`. This is required for agent coordination with git worktrees.

See [references/execution-strategy.md](references/execution-strategy.md) for the comment template and decision rules.

## Naming Convention

Task names: `{epic}.{sequence} {Verb} {object}` — e.g., `1.2 Create ghl.organizations table`

Branch names for worktrees: `feat/ghl-{task_number}-{short-description}` — e.g., `feat/ghl-1.4-webhook-migration`

## Quick Reference

| Action | Tool | Key Parameter |
|--------|------|---------------|
| Create task | `clickup_create_task` | `markdown_description` (NOT `description`) |
| Update description | `clickup_update_task` | `markdown_description` (NOT `description`) |
| Add strategy comment | `clickup_create_task_comment` | `comment_text` with strategy template |
| Check dependencies | `clickup_get_task` | Read status of dependent task IDs |
| Check comments | `clickup_get_task_comments` | Read execution strategy before starting |
