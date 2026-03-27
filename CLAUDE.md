# CLAUDE.md

CashOut — iOS app for couples to track cash spending. Real-time shared visibility via CloudKit. Two users (personal use), no backend, TestFlight only.

## Critical Requirements

- **iOS 26+, Swift/SwiftUI** only
- **MVVM Architecture**: View → ViewModel → Model (strict separation)
- **CloudKit**: Shared database for real-time couples sync
- **Local-first**: Persist locally, sync in background, offline-capable
- **Sign in with Apple**: Authentication for household pairing
- **No custom backend**: All infrastructure on Apple platform services

---

## Project Status

**Phase: Pre-implementation planning** — no application code yet.

| Artifact | Status | Location |
|----------|--------|----------|
| Product Brief | DONE | `_bmad-output/planning-artifacts/product-brief-CashOut.md` |
| PRD | DONE | `_bmad-output/planning-artifacts/prd.md` |
| UX Design | DONE | `_bmad-output/planning-artifacts/ux-design-specification.md` |
| Architecture | TODO | |
| Epics & Stories | TODO | |

---

## Workflow

- **Complex tasks**: Plan mode first (Shift+Tab x2), get approval, then implement
- **BMAD sequence**: product brief → PRD → UX design → architecture → readiness check → epics/stories → sprint planning → story dev
- **Story implementation**: `/bmad-create-story` → `/bmad-dev-story`
- **Pre-commit**: `/code-review` → `git add` → `/auto-document` → `/commit`

---

## Agents

| Condition | Agent | Model | Reads |
|-----------|-------|-------|-------|
| SwiftUI views, SwiftData models, Sign in with Apple, iOS platform | `ios-swiftui-guardian` | sonnet | `.claude/learnings/ios-swiftui.md` |
| CloudKit sync, CKRecord, CKShare, offline queue, conflict resolution | `cloudkit-sync-guardian` | sonnet | `.claude/learnings/cloudkit-sync.md` |
| ViewModels, data layer, DI, state management, navigation, architecture | `architecture-guardian` | sonnet | `.claude/learnings/architecture.md` |
| Library docs, API lookup, web research | `web-search-researcher` | sonnet | — |

**Guardians**: Read-only domain enforcers. Each reads its learnings file on every invocation, validates code against all rules, and reports violations with file:line references. They review — they don't modify code.

**Recording**: Mistake found → add entry to the guardian's learnings file | Decision made → update learnings

**Orchestrator**: `/orchestrate <task>` — classifies task, delegates to relevant guardians in parallel, synthesizes report. Use for debug, review, validate, investigate tasks.

**Skills**: `/orchestrate`, `/auto-document`, `/code-review`, `/commit`, `/bmad-help`, `/bmad-create-architecture`, `/bmad-create-epics-and-stories`, `/bmad-create-story`, `/bmad-dev-story`, `/bmad-sprint-planning`, `/bmad-code-review`

---

## Key Directories

```
_bmad/                          # BMAD framework (do not modify)
_bmad/_config/                  # Project BMAD config (agent customizations)
_bmad-output/planning-artifacts/   # Product brief, PRD, architecture, epics
_bmad-output/implementation-artifacts/  # Story specs, tech specs
_bmad-output/test-artifacts/    # Test plans, traceability
docs/                           # Project knowledge docs
tools/memory/                   # Pixeltable memory MCP server (Python)
.claude/agents/                 # Custom Claude Code agents
.claude/skills/                 # Skill definitions
.claude/learnings/              # Domain-specific learnings files
```

---

## BMAD Config

- **User name**: Boss
- **Skill level**: intermediate
- **Output language**: English
- **Output folder**: `_bmad-output/`

---

## Documentation Lookup

1. **First: Use Ref MCP** — `ref_search_documentation` then `ref_read_url`
2. **Fallback: Use Context7** — `resolve-library-id` then `get-library-docs`
3. **Web: Use Brave Search** — for recent iOS changes, CloudKit patterns

---

## Claude Code Rules

1. **Only change what's requested** — ask before modifying unrelated code
2. **No placeholders** — never use "YOUR_API_KEY", "TODO", dummy data
3. **Show evidence** — when claiming code exists, show file:line reference
4. **Ask when uncertain** — never guess versions, APIs, or requirements

---

## Orchestrate Integration for BMAD Workflows

All BMAD workflow skills (e.g., `/bmad-dev-story`, `/bmad-create-story`, `/bmad-code-review`, `/bmad-create-architecture`, `/bmad-create-epics-and-stories`, `/bmad-quick-dev-new-preview`) must use the orchestrate skill at `@.claude/skills/orchestrate/` for domain validation.

**When to run `/orchestrate`:**
- **Before finalizing code** — `/bmad-dev-story` and `/bmad-quick-dev-new-preview` must run `/orchestrate` in review mode before marking tasks complete
- **Before finalizing architecture** — `/bmad-create-architecture` must run `/orchestrate` in validate mode before presenting architecture decisions
- **During code review** — `/bmad-code-review` must include `/orchestrate` findings alongside its own adversarial review layers
- **Before creating stories** — `/bmad-create-story` and `/bmad-create-epics-and-stories` should run `/orchestrate` in validate mode to verify technical feasibility of acceptance criteria

**What `/orchestrate` does:** Delegates to domain guardians (`ios-swiftui-guardian`, `cloudkit-sync-guardian`, `architecture-guardian`) in parallel, produces a structured report with CRITICAL/WARNING/SUGGESTION categories. CRITICAL items must be resolved before work is considered complete.

---

## Learnings (Mistakes & Lessons)

<!-- When Claude makes a mistake or a non-obvious lesson is learned, add it to the appropriate file below -->
<!-- Agents and skills load the relevant file on-demand when working in that domain -->

| Domain | File | Entries |
|--------|------|---------|
| SwiftUI, SwiftData, iOS Platform | `.claude/learnings/ios-swiftui.md` | ~0 |
| CloudKit Sync, Sharing, Offline | `.claude/learnings/cloudkit-sync.md` | ~0 |
| MVVM, Data Layer, Patterns | `.claude/learnings/architecture.md` | ~0 |

**To add a new learning:** Add it to the appropriate `.claude/learnings/*.md` file under the matching section header.
