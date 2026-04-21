# 07 — Worktree Isolation

## Why Worktrees

Parallel tasks run concurrently. Two agents writing to the same branch simultaneously will produce a race condition — one agent's commit will overwrite the other's, or `git` will error on concurrent writes to the working tree.

Git worktrees solve this cleanly: each parallel task gets a **separate checkout of the repository at its own branch**, in its own directory. The agents write to their own working trees, commit to their own branches, and never interfere with each other. After the phase completes, the branches are merged back.

```
main branch (working tree)
    │
    ├── .git/worktrees/run-epics/phase-1-02-add-rls/
    │   └── branch: feat/phase-1-02-add-rls
    │   └── [agent-B runs here]
    │
    └── .git/worktrees/run-epics/phase-1-03-add-api-route/
        └── branch: feat/phase-1-03-add-api-route
        └── [agent-C runs here]
```

The agent's `workingDirectory` in `client.createSession()` is set to the worktree path. The agent thinks it's in a normal project directory — it doesn't know it's in a worktree.

---

## Worktree Branch Naming

```
feat/{epic-slug}-{task-id}
```

Examples:
- `feat/phase-1-foundation-02-add-rls`
- `feat/phase-2-ui-04-build-dashboard`

The name is derived deterministically from the epic folder name and task ID. This means:
- The same task always gets the same branch name
- Existing branches from prior runs can be detected and cleaned up
- Branch names are human-readable in `git log` and PR lists

---

## Worktree Lifecycle

```
Phase N (parallel) begins
    │
    ├─ For each parallel task:
    │     worktreeManager.createWorktree(branch, baseBranch)
    │       ├─ git worktree add .git/worktrees/run-epics/{branch-slug} -b {branch} {baseBranch}
    │       └─ returns: /abs/path/to/worktree
    │
    ├─ Agents run in their worktrees (Promise.all)
    │
    ├─ Each agent commits its work within its worktree
    │
    [PHASE GATE]
    │
    ├─ worktreeManager.mergeAll(completedTasks, baseBranch)
    │     For each completed task:
    │       ├─ git merge --ff-only {branch}  (from base branch)
    │       │   ├─ success → merged, continue
    │       │   └─ fail    → conflict flagged, human intervention required
    │       └─ git worktree remove .git/worktrees/run-epics/{branch-slug}
    │
    └─ Phase N+1 begins (on clean merged main)
```

---

## `worktree-manager.ts` Interface

```typescript
export interface WorktreeManager {
  // Create a worktree for a parallel task. Returns absolute path to worktree.
  createWorktree(branch: string, baseBranch: string): Promise<string>;

  // Remove a worktree and optionally delete its branch.
  removeWorktree(branch: string, deleteBranch?: boolean): Promise<void>;

  // Check if a branch already exists (from a prior run).
  branchExists(branch: string): Promise<boolean>;

  // Merge a list of branches into baseBranch. Fast-forward only.
  // Returns: { merged: string[], conflicts: string[] }
  mergeAll(branches: string[], baseBranch: string): Promise<MergeResult>;
}
```

```typescript
// Implementation sketch — uses execFileNoThrow (safe, no shell injection)
import { execFileNoThrow } from "../../utils/execFileNoThrow.js";

export class GitWorktreeManager implements WorktreeManager {

  private readonly worktreeRoot = ".git/worktrees/run-epics";

  async createWorktree(branch: string, baseBranch: string): Promise<string> {
    const slug = branch.replace(/\//g, "-");
    const worktreePath = path.resolve(this.worktreeRoot, slug);

    // Clean up stale worktree from prior run if it exists
    if (await this.branchExists(branch)) {
      await this.removeWorktree(branch, false);
    }

    // Each arg is passed as a separate array element — no shell injection risk
    await execFileNoThrow("git", [
      "worktree", "add", worktreePath, "-b", branch, baseBranch
    ]);

    return worktreePath;
  }

  async mergeAll(branches: string[], baseBranch: string): Promise<MergeResult> {
    const merged: string[] = [];
    const conflicts: string[] = [];

    for (const branch of branches) {
      const result = await execFileNoThrow("git", ["merge", "--ff-only", branch]);

      if (result.status === 0) {
        merged.push(branch);
        await this.removeWorktree(branch, true);
      } else {
        conflicts.push(branch);
        console.error(`[worktree] Merge conflict: ${branch} → ${baseBranch}`);
        console.error(`[worktree] Resolve manually then re-run`);
      }
    }

    return { merged, conflicts };
  }
}
```

**Note on shell safety:** All `git` calls use `execFileNoThrow` with arguments as separate array elements. This prevents shell injection — branch names from `.plan.md` files cannot be used to inject shell commands. Never use `exec()` or `execSync()` with string interpolation for git commands.

---

## Fast-Forward Only Merging

The orchestrator uses `--ff-only` for all merges. This means:
- If the worktree branch is a clean linear extension of the base branch, merge succeeds instantly
- If the base branch has advanced since the worktree was created (e.g., a sequential task in the same phase wrote to base), the merge cannot fast-forward

**This is by design.** Sequential and parallel tasks in the same phase don't share a phase — if they're in the same phase, they're all parallel. Sequential tasks only appear in phases where there are no parallel tasks. So in practice, fast-forward merges should always succeed within a phase.

If a fast-forward merge fails, it means either:
1. A sequential task ran on base and a parallel task tried to merge (shouldn't happen by construction)
2. The parallel tasks touched the same file (a problem with the task annotations, not the orchestrator)

In either case, the orchestrator flags the conflict and stops. A human must resolve it before continuing.

---

## Conflict Zones

Certain files are high-risk for parallel task conflicts. The `/analyze-epic` step should have detected these and marked the affected tasks sequential. But as a defense layer, the orchestrator can warn (not block) when parallel tasks in the same phase involve these known conflict zones:

| File | Why it's a conflict zone |
|---|---|
| `lib/drizzle/schema/index.ts` | Barrel export — every new schema file adds a line |
| `drizzle.config.ts` | Schema list — adding a new Drizzle namespace |
| `components/layout/AppSidebar.tsx` | Navigation — every new page adds a nav entry |
| `lib/env.ts` | Environment variables — any new env var modifies this file |
| `app/layout.tsx` | Root layout — rare but catastrophic if two tasks touch it |

The conflict zone check is a warning, not a blocker. It runs during DAG validation (dry-run output includes warnings). The `--strict-conflicts` flag upgrades warnings to errors.

---

## Worktree Cleanup Policy

Worktrees are removed:
1. **After successful merge** — immediately, as part of `mergeAll`
2. **On orchestrator startup** — `recovery.ts` scans `.git/worktrees/run-epics/` and removes any stale worktrees from prior runs (branches that no longer correspond to open tasks)

If a worktree exists but its task is `done`, the worktree is a stale artifact. Remove it.

```typescript
// In recovery.ts — worktree cleanup
const staleWorktrees = await worktreeManager.listWorktrees(worktreeRoot);
for (const wt of staleWorktrees) {
  const task = findTaskByBranch(allTasks, wt.branch);
  if (!task || task.plan.status === "done") {
    await worktreeManager.removeWorktree(wt.branch, false); // keep branch for audit
    console.log(`[recovery] Removed stale worktree: ${wt.branch}`);
  }
}
```
