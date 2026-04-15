# PRD Page Catalog

Select pages based on effort complexity. Every PRD needs 01 (executive summary), README, and a definition-of-done page. Pick additional pages as needed.

## Page Templates

### 01 — Executive Summary (required)

Sections: What, Why, Scope (in/out), Business Impact.

Keep to one page. Lead with the one-sentence "what", then "why it matters now", then scope bullets.

### 02 — Problem Statement

Sections: Current State (table of what exists), The Gap (table of what's missing), Key Differences Beyond the Obvious.

Use tables to compare current vs. target. Call out non-obvious gaps (e.g., missing state management, parameter shape differences).

### 03 — Product Goals & Success Metrics

Sections: Goals (numbered), Success Metrics (table with "How to Verify" column).

Metrics must be verifiable — "verify it appears in X" not "it works correctly."

### 04 — Gap Analysis

Deep tool-by-tool or feature-by-feature comparison. For each item:
- Current implementation (with code snippet)
- Target implementation (with API contract)
- Gaps table: Gap | Detail | Action

Best for migration/porting efforts. Skip for greenfield features.

### 05 — Architecture Plan

Sections: Data Flow (ASCII diagram), New Files, Modified Files, Key Design Decisions.

Show the request flow end-to-end. For each new/modified file, explain what it does and why.

### 06 — Technical Specifications

Exact schemas, API contracts, response shapes. Include:
- Input schemas (Zod, Pydantic, JSON Schema)
- API request format
- API response format (raw + normalized)
- Error shape

Best for API integration efforts. Include actual TypeScript/Python interfaces.

### 07 — UI/Component Changes

Per-component breakdown: Current interface → New interface, what changes, what stays.

Include the TypeScript interface for both old and new result shapes. Describe behavioral changes.

### 08 — System Prompt / Configuration Changes

For AI agent efforts: show the diff of prompt sections. Use `+`/`-` diff markers or before/after tables.

### 09 — Implementation Phases

Ordered tasks grouped into phases. Each phase has:
- Goal (one sentence)
- Tasks with: files to create/modify, what to do, dependencies
- Deliverable (e.g., "build passes")
- Dependency graph (ASCII)
- Parallelization notes

### 10 — Risk Assessment

Risks rated High/Medium/Low with: What, Impact, Mitigation. 

Group by severity. 2-3 high risks, 2-4 medium, rest low. Every risk needs a concrete mitigation, not "be careful."

### 11 — Definition of Done (required as last page)

Two sections:
1. **Completion Criteria** — checkbox list of concrete deliverables
2. **Key Decisions** — table with Decision | Choice | Rationale columns

The decisions table captures every non-obvious choice made during the PRD process so implementers understand the "why."

---

## Selecting Pages

| Effort Type | Recommended Pages |
|-------------|-------------------|
| Small feature (1-3 files) | 01, 03, 09, DoD |
| API integration / porting | 01, 02, 04, 05, 06, 07, 09, 10, DoD |
| Major migration | 01, 02, 03, 04, 05, 06, 07, 08, 09, 10, DoD |
| Greenfield feature | 01, 03, 05, 06, 09, 10, DoD |
| AI agent / prompt work | 01, 02, 05, 06, 08, 09, 10, DoD |

Adjust as needed — these are starting points, not rules.
