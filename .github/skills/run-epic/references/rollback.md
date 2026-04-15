# Rolling Back an Epic

Git is the rollback mechanism for the local epic store. Every meaningful checkpoint is an auto-commit:

- `Finalize epic: <name>` — produced by `finalize-epic`
- `Enrich epic: <name> (<N> tasks updated)` — produced by `enrich-epic`
- `Run epic <name>: phase <N> complete (<M> tasks done)` — produced by `run-epic` after each successful phase

## Rolling Back to a Previous State

To return an epic to an earlier state:

```bash
# 1. Find the checkpoint commit you want to return to
git log --oneline -- <epic_folder>

# 2. Restore just the epic folder to that commit (does NOT touch other files)
git checkout <commit> -- <epic_folder>

# 3. Resume by re-running run-epic — it reads status.log and resumes
#    from wherever the rolled-back state left off
```

## When to Roll Back

| Scenario | Rollback Target |
|---|---|
| Phase 4 produced bad code that broke phase 1–3 work | Last `phase 3 complete` commit |
| Enrichment overwrote good manual edits | Last `Finalize epic` commit, then re-run enrich-epic with different choices |
| Crash mid-execution (offered automatically by run-epic) | Last clean checkpoint before the `in_progress` transition |
| Want to redo analysis with different conflict zones | Last `Enrich epic` commit, then re-run analyze-epic |

## What Roll Back Does NOT Do

- It does NOT undo source code changes outside the epic folder. If a phase modified files in `src/`, those changes remain. Use `git checkout <commit> -- <other-paths>` separately if needed.
- It does NOT delete worktrees that were created during the rolled-back work. List them with `git worktree list` and clean up manually.
- It does NOT rewrite history. The original commits remain in `git log`; rollback creates a new state on top of them.
