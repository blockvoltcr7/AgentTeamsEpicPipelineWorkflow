# Dependency Analysis Algorithm

Detailed rules for building the dependency graph, detecting file overlap, and determining parallelization safety.

## 1. Dependency Parsing

### Extracting Dependencies from Spec Files

Parse the `## Dependencies` section of each task's spec file (`<NN>-<slug>.md`). Expected format:

```markdown
## Dependencies
- Depends On: setup-auth
- Depends On: shared-infra-epic/provision-redis
- Blocks: add-logout
```

**Parsing rules:**

1. Look for lines containing `Depends On:` or `depends on:` (case-insensitive)
2. Extract slugs: match the token after the colon. A slug is `[a-z0-9-]+`. A cross-epic slug has the form `<epic-folder>/<slug>`.
3. Look for `Blocks:` lines and extract the same way — these provide reverse-edge validation
4. The slug is the spec filename without the `^\d+-` numeric prefix (e.g., `02-add-login.md` → `add-login`). The numeric prefix is sort-only and is not part of the identity.

### Resolving References

Build a slug index by globbing `<epic_folder_path>/*.md` (excluding `epic-overview.md` and `*.plan.md`) and computing each file's slug.

| Reference Type | Resolution Strategy |
|---|---|
| Slug (`add-login`) | Direct lookup in this epic's slug index |
| Cross-epic slug (`other-epic/add-login`) | Resolve `other-epic` as a sibling folder of this epic, then look up `add-login` in its slug index |
| Unresolved slug | Hard fail — show the offending spec file and the unresolved reference. Do not proceed. |

### Implicit Ordering

If a task has NO `## Dependencies` section (or it's empty), do NOT assume the numeric filename prefix implies ordering. The numeric prefix is sort-only.

Flag the task for user review: "Task `<slug>` has no dependencies. Treating as independent (Phase 1 candidate). Is this correct?"

## 2. Graph Construction

### Building the DAG

```
Input:  List of tasks with parsed dependencies
Output: Adjacency list (forward edges) + reverse adjacency list (blocks)

For each task T:
  For each dependency D in T.depends_on:
    Add edge: D → T  (T depends on D)
    Add reverse: T to D.blocks
```

### Cycle Detection

Use depth-first search with coloring:
- WHITE: unvisited
- GRAY: in current DFS path (visiting descendants)
- BLACK: fully explored

If a GRAY node is revisited during DFS → **cycle detected**.

**On cycle detection:**
1. Report the full cycle path using slugs: "Circular dependency: setup-auth → add-login → setup-auth"
2. Include the spec file path for each slug
3. Stop analysis — user must fix the spec files before proceeding

### Orphan Detection

After building the graph, identify tasks where:
- `in_degree == 0` (no dependencies) AND
- `out_degree == 0` (nothing depends on them)

These are **orphans**. They could be:
- Truly independent tasks (valid Phase 1 candidates)
- Tasks with missing `## Dependencies` sections (data quality issue)

Flag for user review but proceed with analysis (treat as Phase 1).

## 3. Phase Assignment (Topological Sort)

### Algorithm

```
Initialize:
  phase = {}
  in_degree = count of incoming edges for each task

Phase 1:
  All tasks with in_degree == 0 → assign to Phase 1

Phase N (repeat until all assigned):
  Remove Phase N-1 tasks from the graph
  Recalculate in_degree for remaining tasks
  Tasks with in_degree == 0 → assign to Phase N

If tasks remain unassigned → cycle exists (should have been caught earlier)
```

### Phase Mode Assignment

After assigning phases:
- If a phase has exactly 1 task → `Sequential`
- If a phase has 2+ tasks → **candidate** for `Parallel Window` (pending file overlap analysis)
- If all tasks in a multi-task phase have file overlap → `Sequential` (even though multiple tasks)

## 4. File Overlap Detection

### Three-Layer Analysis

#### Layer 1: Explicit File Paths

Scan `## Implementation` and `## Technical Notes` sections for file paths:
- Match patterns: `lib/`, `app/`, `components/`, `drizzle/`, `supabase/`
- Match file extensions: `.ts`, `.tsx`, `.sql`, `.md`
- Extract full relative paths (e.g., `lib/drizzle/schema/organizations.ts`)

If two tasks in the same phase share any explicit file path → **SEQUENTIAL** (HIGH conflict risk)

#### Layer 2: Type-Based Inference

When explicit paths are insufficient, infer likely files from `## Type`:

| Task Type | Creates (New Files) | Modifies (Existing Files) |
|---|---|---|
| `Migration` | `drizzle/migrations/XXXX_*.sql` | — |
| `Migration + Drizzle Schema` | `drizzle/migrations/XXXX_*.sql`, `lib/drizzle/schema/{table}.ts` | `lib/drizzle/schema/index.ts` |
| `Code (Drizzle)` | `lib/drizzle/schema/{table}.ts` | `lib/drizzle/schema/index.ts` |
| `Code (React)` | `components/{feature}/*.tsx`, `app/{route}/*.tsx` | Depends on context |
| `RLS` | `drizzle/migrations/XXXX_*.sql` | — |
| `Edge Function` | `supabase/functions/{name}/*.ts` | — |
| `Database Function` | `drizzle/migrations/XXXX_*.sql` | — |

**Key insight:** New files (migrations, new components) rarely conflict because they have unique filenames. Conflicts come from **modifying existing shared files**.

Two tasks that both MODIFY `lib/drizzle/schema/index.ts` → **SEQUENTIAL** (MEDIUM conflict risk, barrel export conflict)

Two tasks that both CREATE new migration files → **PARALLEL OK** (LOW conflict risk, different filenames)

#### Layer 3: Conflict Zone Check

Conflict zones are files that are touched by many features and almost always cause merge conflicts when modified in parallel. The default conflict zone list (override per-project as needed):

| Conflict Zone File | Why It Conflicts |
|---|---|
| `lib/drizzle/schema/index.ts` | Every new schema table must be re-exported here |
| `drizzle.config.ts` | Every new schema file must be registered here |
| `components/layout/AppSidebar.tsx` | Navigation changes affect all pages |
| `lib/env.ts` | Environment variable additions affect all modules |
| `app/layout.tsx` | Root layout changes affect entire app |
| `app/(protected)/layout.tsx` | Protected route layout changes affect all protected pages |

If two tasks in the same phase both need to modify ANY of these files → **SEQUENTIAL, no exceptions**.

Projects with different conflict zones should override this table by editing this file directly. There is no external file to reference.

### Overlap Decision Matrix

For two tasks A and B in the same phase:

| A's Files | B's Files | Overlap? | Decision |
|---|---|---|---|
| New migration file | New migration file | No | PARALLEL (different filenames) |
| New migration + barrel export | New migration + barrel export | Yes (barrel) | SEQUENTIAL |
| New component in `/chat/` | New component in `/settings/` | No | PARALLEL |
| Modifies `AppSidebar.tsx` | Anything | Conflict zone | SEQUENTIAL |
| New schema file | New schema file | Yes (barrel) | SEQUENTIAL (both update index.ts) |
| RLS migration | Different RLS migration | No | PARALLEL (separate SQL files) |
| RLS migration | Schema migration | No | PARALLEL (separate SQL files) |

## 5. Branch Naming

### Algorithm

```
Input:  epic_name, task_name, worktree_slot (A or B)
Output: branch name

1. epic_prefix = first meaningful word of epic_name, lowercased
   "GHL Schema Foundation" → "ghl"
   "User Authentication System" → "auth"
   "Stripe Payment Integration" → "stripe"

2. task_number = extract leading number pattern from task_name
   "1.4 Create webhook events migration" → "1.4"
   "2.1 Add user profiles page" → "2.1"

3. short_desc = remaining words after number, kebab-cased, max 4 words
   "Create webhook events migration" → "webhook-migration"
   "Add RLS policies for ghl tables" → "rls-policies"

4. branch = "feat/{prefix}-{number}-{short_desc}"
   → "feat/ghl-1.4-webhook-migration"
```

### Worktree Slot Assignment

Within a parallel window, alternate slots:
- First parallel task → `WORKTREE-A`
- Second parallel task → `WORKTREE-B`
- If more than 2 parallel tasks → `WORKTREE-C`, etc.

Sequential tasks always get `MAIN BRANCH` (no worktree needed).

## 6. Merge Conflict Risk Assessment

### Risk Levels

| Level | Criteria | Worktree Mode |
|---|---|---|
| `NONE` | Different phases (sequential by design) | SEQUENTIAL |
| `LOW` | Same phase, no file overlap detected, different task types | PARALLEL |
| `MEDIUM` | Same phase, type-based inference suggests possible overlap | SEQUENTIAL (conservative) |
| `HIGH` | Same phase, explicit file overlap or conflict zone hit | SEQUENTIAL |

### Conservative Default

When in doubt, mark as **SEQUENTIAL**. False negatives (missed parallelism) are inconvenient. False positives (parallel tasks that conflict) cause merge conflicts that waste agent time.
