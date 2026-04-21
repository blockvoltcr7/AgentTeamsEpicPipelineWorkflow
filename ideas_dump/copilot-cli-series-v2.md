# Copilot CLI in Action — YouTube Mini-Series Playlist (v2)

## Series Title
**"Copilot CLI in Action"** — Real development workflows, no fluff

---

## Series Overview

**Total Episodes:** 18
**Format:** 3–6 minutes each, live terminal demos with voiceover
**Philosophy:** Every episode builds something real. No slides. No installation walkthroughs. You see it, you learn it.
**Stack Coverage:** API routes, database schemas/migrations, frontend components, cloud deployments, AI agents

---

## SECTION 1: The Core Loop (Episodes 1–4)
*The workflow that makes everything else click: Scope → Plan → Execute → Verify*

### Episode 1 — "Plan Before You Build"
- **Length:** 4–5 min
- **What you'll see:** Build a REST API endpoint from scratch using plan mode
- **Real-world scenario:** "We need a `/users` endpoint with pagination and filtering"
- **Demo flow:**
  - Open terminal in a TypeScript project repo
  - `copilot` → `Shift+Tab` → plan mode
  - `/plan Add a GET /api/users endpoint with pagination (limit/offset), filtering by status, and input validation`
  - Walk through Copilot's structured plan — files it will touch, approach, dependencies
  - Add acceptance criteria: "returns 400 on invalid params, supports cursor-based pagination, includes total count in response headers"
  - Accept the plan → watch Copilot execute
- **Takeaway:** A 30-second plan saves 30 minutes of rework. Add acceptance criteria every time.

### Episode 2 — "Trust But Verify: /diff and /review"
- **Length:** 4–5 min
- **What you'll see:** Review AI-generated database migration code before it touches your schema
- **Real-world scenario:** Copilot just generated a Supabase migration adding a `teams` table with RLS policies
- **Demo flow:**
  - After Copilot generates the migration SQL + TypeScript types
  - `/diff` → walk through every file changed, highlight the SQL migration
  - `/review` → Copilot reviews its own work, catches a missing index or RLS gap
  - Fix the issue Copilot flagged → `/diff` again to confirm
- **Takeaway:** `/diff` shows you what changed. `/review` tells you what's wrong. Use both before every commit.

### Episode 3 — "Undo Anything: Snapshots and Rewind"
- **Length:** 3–4 min
- **What you'll see:** Copilot breaks a frontend component — and we rewind in 2 keystrokes
- **Real-world scenario:** Asked Copilot to refactor a React dashboard component, it went too far
- **Demo flow:**
  - Show the working component in the browser
  - Ask Copilot to refactor it → it over-engineers the solution
  - `Esc Esc` → rewind to the snapshot before the refactor
  - Show the component working again
  - Re-prompt with tighter scope: "Refactor only the data fetching logic, don't touch the JSX"
- **Takeaway:** `Esc Esc` is your safety net. Commit early, rewind freely, re-prompt with precision.

### Episode 4 — "The Full Loop in 5 Minutes"
- **Length:** 5–6 min
- **What you'll see:** End-to-end feature build — API + DB + Frontend in one session
- **Real-world scenario:** "Add a comments feature to our app"
- **Demo flow:**
  1. **Scope:** Set permissions — `copilot --allow-tool 'shell(git:*)' --deny-tool 'shell(git push)'`
  2. **Plan:** `/plan Add a comments system: DB migration for comments table, API route for CRUD, React component to display and post comments`
  3. **Execute:** Accept plan → Copilot generates migration, API routes, and frontend component
  4. **Verify:** `/diff` → `/review` → run the app and show comments working
  5. **Share:** `/share file` → export session to Markdown for PR description
- **Takeaway:** Scope → Plan → Execute → Verify → Share. This is the loop for everything.

---

## SECTION 2: Control and Speed (Episodes 5–9)
*Go faster without losing control*

### Episode 5 — "Autopilot Mode: Bounded Autonomy"
- **Length:** 4–5 min
- **What you'll see:** Copilot builds and iterates on an API with error handling — autonomously
- **Real-world scenario:** "Build a webhook handler that validates signatures, processes events, and handles retries"
- **Demo flow:**
  - `copilot --allow-all --max-autopilot-continues 8`
  - Plan the webhook handler → "Accept plan and build on autopilot"
  - Watch Copilot: create the handler → add signature validation → add retry logic → write error responses → run tests — all without you typing
  - Point out premium request consumption at each step
  - `Ctrl+C` to stop if needed
- **Takeaway:** `--max-autopilot-continues` is your throttle. Start at 5–8, not unlimited.

### Episode 6 — "Permissions That Actually Make Sense"
- **Length:** 4–5 min
- **What you'll see:** Three permission postures for three real scenarios
- **Demo flow:**
  - **Exploration mode** (read-only): `copilot --available-tools 'read' 'grep' 'glob'` → "Explain the auth flow in this codebase"
  - **Development mode** (build + test, no deploy): `copilot --allow-tool 'shell(git:*)' --deny-tool 'shell(git push)' --allow-tool 'shell(npm:*)'`
  - **Locked-down review** (git status + diff only): `copilot --available-tools 'read' 'grep' 'shell(git status)' 'shell(git diff)'`
  - Show what happens when Copilot hits a denied tool — it asks, you decide
- **Takeaway:** Three postures you can memorize: explore, develop, review. Deny always wins over allow.

### Episode 7 — "Models, Tokens, and Staying in Budget"
- **Length:** 3–4 min
- **What you'll see:** Switch models mid-task and watch the cost difference in real time
- **Real-world scenario:** Start a complex refactor with a powerful model, then switch to a lighter model for boilerplate generation
- **Demo flow:**
  - `/model` → pick a high-capability model → start planning a complex API refactor
  - `/usage` → show token consumption and premium request count
  - Switch to a lighter model for generating repetitive CRUD routes
  - `/usage` again → compare the cost difference
  - `/context` → show what's consuming context window space
- **Takeaway:** Use big models for planning and complex logic. Switch to smaller models for boilerplate. `/usage` keeps you honest.

### Episode 8 — "Copilot as a Shell Command"
- **Length:** 3–4 min
- **What you'll see:** Three real scripting patterns you'll actually use
- **Demo flow:**
  - **Pattern 1 — PR prep:** `copilot -sp "Summarize all changes since the last tag as a changelog entry."` → pipe to clipboard
  - **Pattern 2 — Code explanation:** `copilot -sp "Explain what the auth middleware in src/middleware/auth.ts does, in 3 sentences."` → paste into PR description
  - **Pattern 3 — Quick generation:** `copilot -sp "Generate a TypeScript interface for a User object with id, email, name, role, and timestamps."` → pipe to file
  - Show how `-s` strips UI chrome for clean piping
- **Takeaway:** `-p` for prompts, `-s` for silence. Combine them for one-shot AI utilities in your shell.

### Episode 9 — "Parallelize with /fleet"
- **Length:** 4–5 min
- **What you'll see:** Three subagents work simultaneously on a feature
- **Real-world scenario:** "We need to add a notifications feature — API, database migration, and frontend all at once"
- **Demo flow:**
  - Plan the notifications feature first (API route + DB table + React component)
  - `/fleet Implement the plan. Parallelize: (a) Supabase migration + RLS policies, (b) API route with validation, (c) React notification bell component`
  - Watch three subagents work with separate context windows
  - Verify merged results → `/diff` across all changed files
- **Takeaway:** Plan first, fleet second. Each subagent uses premium requests — parallelize when work truly decomposes into independent pieces.

---

## SECTION 3: Real-World Builds (Episodes 10–14)
*Full feature builds across the stack — watch and learn*

### Episode 10 — "Build a REST API from a Spec"
- **Length:** 5–6 min
- **What you'll see:** Copilot turns an OpenAPI-style description into working API routes
- **Real-world scenario:** "Here's our API contract for the /products endpoint — build it"
- **Demo flow:**
  - Paste or reference an API spec in the prompt
  - Plan mode: Copilot proposes route structure, validation, error handling, response types
  - Execute: Copilot generates routes, middleware, types, and request validation
  - `/review` catches a missing auth middleware on a protected route → fix it
  - Run the server → hit the endpoint → show the response
- **Stack neutral:** Works for Express, Fastify, Go net/http, Python FastAPI — Copilot reads your project context

### Episode 11 — "Database Migrations Without the Mental Overhead"
- **Length:** 5–6 min
- **What you'll see:** Copilot generates a migration, RLS policies, and typed client code
- **Real-world scenario:** "Add a subscriptions table with Stripe integration fields"
- **Demo flow:**
  - Plan: "Add a subscriptions table with user_id FK, stripe_customer_id, plan tier, status, billing period, and timestamps. Add RLS so users can only read their own subscription."
  - Copilot generates: SQL migration, RLS policy, TypeScript types, and a typed query helper
  - `/diff` the migration SQL carefully — highlight foreign keys, indexes, defaults
  - `/review` — Copilot flags a missing index on `stripe_customer_id`
  - Apply migration → verify in DB
- **Applies to:** Supabase, NeonDB, Drizzle, Prisma, raw SQL — Copilot adapts to your ORM/migration tool

### Episode 12 — "Frontend Components from Description to DOM"
- **Length:** 5–6 min
- **What you'll see:** Copilot builds a data table component with sorting, filtering, and pagination
- **Real-world scenario:** "We need a reusable data table for the admin dashboard"
- **Demo flow:**
  - Plan: "Build a React data table component with column sorting, text search filtering, cursor-based pagination, loading states, and empty state. Use our existing design system tokens."
  - Copilot generates: component, types, hooks for data fetching, and a Storybook story
  - `/diff` → review the component structure and prop interface
  - Show it rendering in the browser with real data
  - Refine: "Add keyboard navigation for accessibility" → Copilot adds it incrementally
- **Takeaway:** Give Copilot your design system context and it will follow your patterns

### Episode 13 — "Full-Stack Feature: API + DB + UI in One Session"
- **Length:** 5–6 min
- **What you'll see:** Build a complete "team invitations" feature across the entire stack
- **Real-world scenario:** "Users should be able to invite teammates by email"
- **Demo flow:**
  - Plan covers all three layers: DB (invitations table + constraints), API (send/accept/revoke endpoints), UI (invite modal + pending invites list)
  - Use `/fleet` to parallelize the three layers
  - Watch subagents generate migration, API routes, and React components simultaneously
  - Merge → `/diff` the full feature → `/review`
  - Run the app → send an invite → show it in the pending list
- **Takeaway:** This is the ultimate demo of the full loop + fleet. One prompt, three layers, real feature.

### Episode 14 — "AI Agent Development with Copilot CLI"
- **Length:** 5–6 min
- **What you'll see:** Copilot helps build an AI agent tool and wire it into an agent framework
- **Real-world scenario:** "Add a document search tool to our support agent"
- **Demo flow:**
  - Start in a Python or TypeScript AI agent project (OpenAI Agent SDK, Agno, or ADK)
  - Plan: "Add a search_documents tool that queries our vector store, formats results with relevance scores, and handles empty results gracefully"
  - Copilot generates: tool definition, handler function, agent registration, and a test
  - `/review` → Copilot catches a missing error handler for vector store timeouts
  - Run the agent → invoke the tool → show results
- **Takeaway:** Copilot understands agent framework patterns — give it your agent config as context

---

## SECTION 4: Team Scale (Episodes 15–18)
*Ship guardrails, automate workflows, standardize across the org*

### Episode 15 — "Hooks: Ship Guardrails in Your Repo"
- **Length:** 4–5 min
- **What you'll see:** A `preToolUse` hook blocks a dangerous command and logs it
- **Real-world scenario:** "No one on the team should accidentally `git push` or `rm -rf` during a Copilot session"
- **Demo flow:**
  - Create `.github/hooks/copilot-cli-policy.json` with `preToolUse` rules
  - Create a deny script that blocks `git push` and `rm -rf`
  - Add a logging script that writes every tool invocation to `.github/hooks/logs/`
  - Run `copilot` → ask it to push → watch the hook block it → show the audit log entry
- **Takeaway:** Hooks ship with your repo. Every `git clone` gets the same guardrails. Policy as code, not policy as wiki.

### Episode 16 — "Custom Agents and Skills: Teach Copilot Your Patterns"
- **Length:** 4–5 min
- **What you'll see:** A custom "API builder" agent that knows your project's conventions
- **Demo flow:**
  - Create `.agent.md` defining an "API builder" persona: knows your route structure, validation patterns, error format, auth middleware
  - Create a `SKILL.md` for "scaffold a new API endpoint" — includes your file conventions and standards
  - `/agent` → select the API builder → ask it to add a new endpoint
  - Compare output quality vs. a generic prompt (faster, more consistent, fewer corrections needed)
- **Layering:** Instructions (general) → Skills (task-specific) → Hooks (enforcement) → build up gradually

### Episode 17 — "Copilot CLI in GitHub Actions"
- **Length:** 4–5 min
- **What you'll see:** An automated CI job that summarizes changes and flags issues
- **Real-world scenario:** "Every morning, get an AI summary of what changed in the repo overnight"
- **Demo flow:**
  - Show a GitHub Actions workflow: triggered on `schedule` or `workflow_dispatch`
  - Auth with `COPILOT_GITHUB_TOKEN` secret (fine-grained PAT with Copilot Requests scope)
  - Job step: `copilot -p "Summarize changes in the last 24 hours. Flag any breaking API changes, missing migrations, or security concerns."`
  - Show the output in Actions logs → optionally post to a PR comment or Slack
- **Takeaway:** Start read-only in CI. Earn trust before giving automated agents write access.

### Episode 18 — "MCP Servers: Connect Copilot to Everything"
- **Length:** 5–6 min
- **What you'll see:** Copilot queries your database and interacts with external services through MCP
- **Real-world scenario:** "I want Copilot to check the current DB schema before generating a migration"
- **Demo flow:**
  - Show built-in MCP servers: `github-mcp-server`, `fetch`, `playwright`
  - `/mcp add` → connect a Supabase or NeonDB MCP server
  - Ask Copilot: "Check the current schema for the users table, then add an organizations table with a foreign key relationship"
  - Copilot uses MCP to query the live schema → generates an accurate migration
  - Discuss: config lives in `~/.copilot/mcp-config.json`, session-only via `--additional-mcp-config`
- **Takeaway:** MCP turns Copilot from a code generator into a connected development agent. Start with read-only MCP servers.

---

## Cheat Sheet (Pin in Playlist Description + First Comment on Every Video)

```
THE CORE LOOP
  1. Scope    → Set permissions, trust folder
  2. Plan     → Shift+Tab → plan mode → /plan
  3. Execute  → Accept plan → interactive or autopilot
  4. Verify   → /diff → /review → Esc Esc if needed
  5. Share    → /share file → commit → PR

MODES (Shift+Tab to cycle)
  Plan mode       Think before editing
  Autopilot       Multi-step autonomous work

KEY COMMANDS
  /plan <task>                     Structured plan with steps
  /diff                            Review all session changes
  /review                          AI code review on changes
  /model                           Switch models mid-session
  /usage                           Token & cost breakdown
  /context                         What's in the context window
  /fleet <prompt>                  Parallel subagents
  /share file                      Export session to Markdown
  Esc Esc                          Rewind to previous snapshot

PERMISSION POSTURES
  Explore:  --available-tools 'read' 'grep' 'glob'
  Develop:  --allow-tool 'shell(git:*)' --deny-tool 'shell(git push)'
  Review:   --available-tools 'read' 'grep' 'shell(git status)'
  Full:     --allow-all --max-autopilot-continues 10

SCRIPTING
  copilot -p "prompt"              Prompt mode (exits after)
  copilot -sp "prompt"             Silent + prompt (pipe-friendly)
  copilot --autopilot -p "prompt"  Headless autopilot

CONFIG LOCATIONS
  ~/.copilot/config.json           User defaults
  .copilot/settings.json           Project settings
  .copilot/settings.local.json     Local overrides (gitignore)
  ~/.copilot/mcp-config.json       MCP server config
  .github/hooks/*.json             Policy hooks
```

---

## Series Improvements Checklist

### Strengths of This Structure
- [x] Every episode builds something real — no theory-only episodes
- [x] Progressive complexity — viewers can stop at Section 1 and still be productive
- [x] Full-stack coverage — API, DB, and frontend in dedicated episodes AND combined
- [x] The "Core Loop" taught in Section 1 is reinforced in every later episode
- [x] Permission postures (Ep 6) give teams a simple framework to memorize

### Areas to Review and Improve
- [ ] **Episode 13 (full-stack + /fleet) might be too ambitious for 5–6 min** — Consider splitting into a 2-part episode or extending to 7 min as a "capstone" episode
- [ ] **Stack specificity vs. stack neutrality** — Episodes 10–12 say "stack neutral" but real demos need a real stack. Decide: do you record with one stack (e.g., TypeScript + Supabase) and note alternatives verbally, or record variants?
- [ ] **Missing: error recovery beyond Esc-Esc** — What happens when Copilot generates code that compiles but has a logic bug? Consider adding a "debugging with Copilot" episode
- [ ] **Missing: working with existing large codebases** — All demos start from "add a feature." Consider an episode on "Understand and navigate an unfamiliar codebase with Copilot CLI" using read-only exploration mode
- [ ] **Missing: multi-file refactoring** — A dedicated episode on "Refactor a messy API layer into clean modules" would demonstrate Copilot's strength on cross-file changes
- [ ] **Episode ordering in Section 3** — Episode 14 (AI agents) may feel disconnected for non-AI teams. Consider making it a "bonus" episode or moving it after Episode 18
- [ ] **Thumbnail/branding consistency** — Define a template now: terminal screenshot + episode number + 4-word title. Color per section: Core = blue, Control = green, Builds = orange, Scale = purple
- [ ] **Call-to-action consistency** — Every episode should end with the same 5-second outro: "Cheat sheet in the description. Next episode: [title]."
- [ ] **Playlist gating** — Section 1 is mandatory context for Sections 2–4. Consider a playlist description that says "Start with Episodes 1–4 if you're new"
- [ ] **Team feedback loop** — After releasing Section 1, survey the team: "What workflow do you want to see next?" to prioritize Section 3 episode order
