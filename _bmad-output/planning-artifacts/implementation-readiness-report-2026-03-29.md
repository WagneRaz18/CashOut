# Implementation Readiness Assessment Report

**Date:** 2026-03-29
**Project:** CashOut

**Document Inventory:**
- PRD: `_bmad-output/planning-artifacts/prd.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Epics & Stories: `_bmad-output/planning-artifacts/epics.md`
- UX Design: `_bmad-output/planning-artifacts/ux-design-specification.md`
- Story Spec: `_bmad-output/implementation-artifacts/1-5-numpad-and-amount-display.md`

---

## PRD Analysis

### Functional Requirements

- FR1: User can create a new expense entry by selecting a category and entering an amount
- FR2: User can optionally add a text note to an expense entry
- FR3: User can save an expense entry and have it immediately persisted locally
- FR4: User can access the entry flow directly on app launch with zero navigation
- FR5: User can view a chronological feed of all household expense entries
- FR6: User can tap an existing entry to edit its category, amount, or note
- FR7: User can delete an existing entry with a confirmation prompt
- FR8: User can see which partner logged each entry
- FR9: User can select from a set of predefined default categories (Food & Drink, Transport, Entertainment, Household, Shopping, Other)
- FR10: User can create custom spending categories
- FR11: User can edit existing custom categories
- FR12: User can select any category (predefined or custom) with a single tap during entry
- FR13: User can view a daily spending breakdown by category
- FR14: User can view a weekly spending breakdown by category
- FR15: User can view a monthly spending breakdown by category
- FR16: User can switch between daily, weekly, and monthly views effortlessly
- FR17: User can see total spending per category within any selected time period
- FR18: User can see overall total spending within any selected time period
- FR19: User can sign in with Apple to authenticate
- FR20: Both household members can view all expense entries in a shared feed in real-time
- FR21: Both household members can see edits and deletes reflected in real-time
- FR22: Second partner can join the shared household by installing the app and signing in — no invite codes or manual configuration
- FR23: User can create, edit, and delete entries while offline
- FR24: User can view all locally stored entries while offline
- FR25: System syncs queued offline changes automatically when connectivity returns
- FR26: System resolves sync conflicts using last-write-wins strategy

**Total FRs: 26**

### Non-Functional Requirements

**Performance:**
- NFR1: App launch to entry-ready state must be near-instant — no splash screens, no loading spinners
- NFR2: Expense entry save must feel immediate — local persistence completes with no perceptible delay
- NFR3: Switching between daily/weekly/monthly views must be instant with no loading states
- NFR4: Scrolling through the expense feed must be smooth with no frame drops
- NFR5: CloudKit sync must operate in the background without blocking any user interaction

**Security & Privacy:**
- NFR6: All data is encrypted at rest (Apple Data Protection) and in transit (CloudKit TLS)
- NFR7: No spending data is accessible outside the household's shared CloudKit zone
- NFR8: Authentication via Sign in with Apple — no custom credential storage
- NFR9: No analytics, telemetry, or third-party SDKs that transmit user data
- NFR10: No data leaves the device/iCloud boundary

**Data Management:**
- NFR11: System retains expense data for a rolling 6-month window
- NFR12: Data older than 6 months may be archived or purged
- NFR13: No data loss during normal sync operations — local-first persistence guarantees durability
- NFR14: Deletes and edits must propagate fully to both devices — no orphaned or ghost entries

**Total NFRs: 14**

### Additional Requirements

- iOS 26+ minimum deployment target
- SwiftUI for all UI
- No Android, no web, no cross-platform
- No App Store submission for v1 — distributed via TestFlight
- iCloud/CloudKit access required for sync
- Sign in with Apple required for auth
- No camera, location, microphone, contacts, or other device permissions needed in v1
- No push notifications in v1
- Entry flow must be the default screen on app launch
- Local-first architecture: write locally, sync in background

### PRD Completeness Assessment

The PRD is thorough and well-structured. All 26 functional requirements are clearly numbered and actionable. Non-functional requirements cover performance, security, and data management comprehensively. User journeys are concrete with specific examples. Scope boundaries are explicitly defined with permanent non-goals. The PRD provides a strong foundation for epic/story traceability.

---

## Epic Coverage Validation

### Coverage Matrix

| FR | PRD Requirement | Epic Coverage | Story | Status |
|----|----------------|---------------|-------|--------|
| FR1 | Create expense entry (category + amount) | Epic 1 | 1.6 | ✓ Covered |
| FR2 | Optional text note on entry | Epic 1 | 1.6 | ✓ Covered |
| FR3 | Immediate local persistence on save | Epic 1 | 1.6 | ✓ Covered |
| FR4 | Entry flow on launch with zero navigation | Epic 1 | 1.3 | ✓ Covered |
| FR5 | Chronological feed of household entries | Epic 2 | 2.1 | ✓ Covered |
| FR6 | Tap entry to edit (category, amount, note) | Epic 2 | 2.3 | ✓ Covered |
| FR7 | Delete entry with confirmation | Epic 2 | 2.4 | ✓ Covered |
| FR8 | Partner attribution on each entry | Epic 2 | 2.1 | ✓ Covered |
| FR9 | Predefined default categories (6) | Epic 1 | 1.4 | ✓ Covered |
| FR10 | Create custom spending categories | Epic 5 | 5.2 | ✓ Covered |
| FR11 | Edit existing custom categories | Epic 5 | 5.2 | ✓ Covered |
| FR12 | Single-tap category selection during entry | Epic 1 | 1.6 | ✓ Covered |
| FR13 | Daily spending breakdown by category | Epic 3 | 3.1 | ✓ Covered |
| FR14 | Weekly spending breakdown by category | Epic 3 | 3.1 | ✓ Covered |
| FR15 | Monthly spending breakdown by category | Epic 3 | 3.1 | ✓ Covered |
| FR16 | Effortless switching between day/week/month | Epic 3 | 3.1 | ✓ Covered |
| FR17 | Total spending per category per period | Epic 3 | 3.3 | ✓ Covered |
| FR18 | Overall total spending per period | Epic 3 | 3.1 | ✓ Covered |
| FR19 | Sign in with Apple authentication | Epic 1 | 1.2 | ✓ Covered |
| FR20 | Shared feed visible to both partners real-time | Epic 4 | 4.2 | ✓ Covered |
| FR21 | Edits and deletes reflected in real-time | Epic 4 | 4.2 | ✓ Covered |
| FR22 | Second partner joins via install + sign in | Epic 4 | 4.1, 4.2 | ✓ Covered |
| FR23 | Offline create, edit, delete | Epic 1 | 1.6 | ✓ Covered |
| FR24 | View all locally stored entries while offline | Epic 1 | 1.6 | ✓ Covered |
| FR25 | Automatic sync of queued offline changes | Epic 4 | 4.3 | ✓ Covered |
| FR26 | Last-write-wins conflict resolution | Epic 4 | 4.2 | ✓ Covered |

### Missing Requirements

**No missing FRs.** All 26 functional requirements from the PRD have traceable coverage in the epics and stories.

### Coverage Statistics

- Total PRD FRs: 26
- FRs covered in epics: 26
- Coverage percentage: **100%**

---

## UX Alignment Assessment

### UX Document Status

**Found:** `_bmad-output/planning-artifacts/ux-design-specification.md` — comprehensive UX spec covering design system, user journeys, component specs, accessibility, and emotional design.

### UX ↔ PRD Alignment

Strong alignment. The UX spec directly references all 4 PRD user journeys (Quick Log, Fix-Up, Insights, Partner Onboarding) and implements them with specific interaction mechanics. All 26 FRs are addressed in UX design decisions. The 5-second entry constraint from the PRD is validated with a step-by-step timing analysis (3.1s actual).

### UX ↔ Architecture Alignment

Mostly aligned with two resolved discrepancies (documented below as corrections already applied in story specs).

### Alignment Issues (Resolved in Story Specs)

**1. NumpadView Liquid Glass API — UX vs Architecture conflict (RESOLVED)**

| Document | NumpadView Styling |
|----------|-------------------|
| UX Spec (line 255, 819) | `.glassEffect(.regular.interactive())` |
| Architecture (line 789-792) | `.buttonStyle(.glass)` — "Never combine both" |
| Story 1.5 Spec | `.buttonStyle(.glass)` — follows architecture |
| Epics UX-DR1 | `.buttonStyle(.glass)` — corrected from UX wording |

**Resolution:** Architecture rule is authoritative. Numpad keys are `Button` elements, so they use `.buttonStyle(.glass)`, not `.glassEffect()`. The story spec and epics already apply this correction. **The UX spec should be updated** to reflect `.buttonStyle(.glass)` for numpad keys to prevent future confusion.

**2. AmountDisplayView `.monospacedDigit()` — UX vs Story conflict (RESOLVED)**

| Document | Amount Display Typography |
|----------|--------------------------|
| UX Spec (line 464) | "`.monospacedDigit()` on all monetary amounts" |
| Epics UX-DR2 (line 96) | "SF Pro Rounded 48pt medium weight with `.monospacedDigit()`" |
| Story 1.5 Spec (Task 2.4) | "do NOT add `.monospacedDigit()` — rounded + monospaced may conflict" |

**Resolution:** Story spec's correction is sound — `.monospacedDigit()` is appropriate for vertically-aligned amounts in feed rows (where `.rounded` is not used), but combining `.rounded` + `.monospacedDigit()` on the entry display may produce conflicting font traits. **The epics UX-DR2 should be updated** to remove `.monospacedDigit()` for the entry amount display only.

### Warnings

- **UX-DR2 epics wording is stale** — still says `.monospacedDigit()` for entry display despite the story spec explicitly correcting this. Risk: future stories implementing the entry display might follow epics rather than the story spec.
- **UX spec line 255/819 not updated** — still references `.glassEffect(.regular.interactive())` for numpad keys. Risk: future UX-referencing work might use wrong API.
- **Both discrepancies are non-blocking** — story specs carry the corrections, and the architecture is authoritative.

---

## Epic Quality Review

### Epic User Value Validation

| Epic | Title | User Value? | Standalone? | Verdict |
|------|-------|------------|-------------|---------|
| 1 | Solo Cash Entry | ✓ "User can sign in and log cash expenses" | ✓ Fully functional solo app | ✅ Pass |
| 2 | Expense Feed & Management | ✓ "User can review history, fix mistakes" | ✓ Needs Epic 1 data only | ✅ Pass |
| 3 | Spending Insights | ✓ "User can understand spending patterns" | ✓ Needs Epic 1+2 data | ✅ Pass |
| 4 | Household Sharing & Real-Time Sync | ✓ "Both partners share in real-time" | ✓ Needs Epic 1 auth + model | ✅ Pass |
| 5 | Category Customization & Settings | ✓ "User can personalize categories" | ✓ Needs Epic 1+4 | ✅ Pass |

**No technical epics detected.** All 5 epics describe user outcomes.

### Epic Independence Analysis

- **Epic 1 → standalone:** ✅ No upstream dependencies
- **Epic 2 → depends on Epic 1:** ✅ Valid (needs expense data to display in feed)
- **Epic 3 → depends on Epic 1+2:** ✅ Stories 3.2 and 3.3 explicitly require Epic 2 FeedView for tap-to-filter navigation — legitimate forward dependency, properly declared
- **Epic 4 → depends on Epic 1:** ✅ Needs auth (1.2) and data model (1.1)
- **Epic 5 → depends on Epic 1+4:** ⚠️ Story 5.1 Settings depends on Epic 4 CloudSharingService for "Invite Partner" button

**No circular dependencies.** No epic requires a later epic to function. Dependency chain is linear: 1 → 2 → 3, 1 → 4, 1+4 → 5.

### Story Quality Assessment

#### Within-Epic Story Dependencies

**Epic 1 (7 stories):**
- 1.1 Project Setup → standalone ✅
- 1.2 Sign in with Apple → needs 1.1 ✅
- 1.3 App Shell & Tab Navigation → needs 1.1 ✅
- 1.4 Design Tokens, Categories, Repository → needs 1.1 ✅
- 1.5 Numpad & Amount Display → needs 1.3 (EntryView), 1.4 (Int64.displayAmount, Spacing) ✅
- 1.6 Category Picker, Save & Persistence → needs 1.4 (categories), 1.5 (numpad/amount) ✅
- 1.7 Haptics, Accessibility, Dynamic Type → needs 1.5 (numpad), 1.6 (category picker, save) ✅

**Dependency chain is strictly forward within epic** — no story depends on a later story. ✅

**Epic 2 (4 stories):**
- 2.1 Feed with Attribution → needs Epic 1 ✅
- 2.2 Floating Add Button → needs 2.1 (Feed screen exists) ✅
- 2.3 Edit Expense Flow → needs 2.1 (feed rows to tap) ✅
- 2.4 Delete Expense Flow → needs 2.1 (feed rows to swipe) ✅

**Epics 3, 4, 5:** Dependencies properly declared, all forward-only. ✅

#### Acceptance Criteria Quality (Story 1.5 — Focus Story)

| AC | Given/When/Then | Testable | Specific | Verdict |
|----|----------------|----------|----------|---------|
| AC1 | ✅ Proper BDD | ✅ 3x4 grid, .buttonStyle(.glass), 60pt+, 8pt gaps | ✅ Measurable | ✅ Pass |
| AC2 | ✅ Proper BDD | ✅ "$0.00", 48pt, rounded, .secondary color | ✅ Measurable | ✅ Pass |
| AC3 | ✅ Proper BDD | ✅ Immediate update, primary color | ✅ Observable | ✅ Pass |
| AC4 | ✅ Proper BDD | ✅ Int64 cents, "1250" → "$12.50" | ✅ Testable math | ✅ Pass |
| AC5 | ✅ Proper BDD | ✅ Last digit removed | ✅ Observable | ✅ Pass |

All 5 ACs are in proper Given/When/Then format, testable, and specific. ✅

#### Story 1.1 — Database Creation Timing Check

Story 1.1 creates both Expense and Category entities upfront in the Core Data model. This is the **correct approach** for Core Data + CloudKit — the `.xcdatamodeld` schema must be defined in advance for `NSPersistentCloudKitContainer` to deploy the CloudKit schema. Unlike a table-per-story approach (which works for SQL), Core Data's schema-first model requires upfront entity definition. **No violation.**

### Best Practices Compliance Checklist

| Check | E1 | E2 | E3 | E4 | E5 |
|-------|----|----|----|----|-----|
| Epic delivers user value | ✅ | ✅ | ✅ | ✅ | ✅ |
| Epic functions independently (with predecessors) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Stories appropriately sized | ✅ | ✅ | ✅ | ✅ | ✅ |
| No forward dependencies | ✅ | ✅ | ✅ | ✅ | ✅ |
| Database tables created when needed | ✅ | n/a | n/a | n/a | n/a |
| Clear acceptance criteria | ✅ | ✅ | ✅ | ✅ | ✅ |
| Traceability to FRs maintained | ✅ | ✅ | ✅ | ✅ | ✅ |

### Quality Findings

#### 🟡 Minor Concerns

1. **Story 1.1 is large** — Project Setup includes Xcode config, Core Data model, PersistenceController, CloudKit setup, Info.plist, AppDelegate, and folder structure. This is acceptable for a greenfield project setup story but is at the upper bound of story sizing.

2. **Epic 3 cross-epic dependency** — Stories 3.2 and 3.3 require Epic 2 FeedView for filtered navigation. Properly declared, but means Epic 3 cannot be fully independent. **Acceptable** — the filtered feed navigation is a natural integration point.

3. **Epic 5 cross-epic dependency** — Story 5.1 requires Epic 4 CloudSharingService. **Acceptable** — the Settings Household section needs the sharing service to present the invite flow.

#### No 🔴 Critical Violations or 🟠 Major Issues found.

---

## Summary and Recommendations

### Overall Readiness Status

**READY**

Story 1.5 (Numpad & Amount Display) is ready for implementation. All supporting artifacts are complete, aligned, and traceable.

### Findings Summary

| Category | Critical | Major | Minor |
|----------|----------|-------|-------|
| PRD Analysis | 0 | 0 | 0 |
| FR Coverage | 0 | 0 | 0 |
| UX Alignment | 0 | 0 | 2 (resolved in story specs) |
| Epic Quality | 0 | 0 | 3 (acceptable) |
| **Total** | **0** | **0** | **5** |

### Critical Issues Requiring Immediate Action

**None.** No blocking issues found. Story 1.5 can proceed to implementation.

### Recommended Next Steps (Non-Blocking Housekeeping)

1. **Update UX spec NumpadView entry** (line 255, 819) — change `.glassEffect(.regular.interactive())` to `.buttonStyle(.glass)` to match architecture rules. Prevents future confusion.
2. **Update epics UX-DR2** (line 96) — remove `.monospacedDigit()` from AmountDisplayView description, or add a note clarifying it applies only to feed row amounts, not entry display. Prevents conflict with story spec correction.
3. **Proceed with `/bmad-dev-story` for Story 1.5** — all prerequisites are in place:
   - Story 1.3 (App Shell, EntryView placeholder) is implemented
   - Story 1.4 (Int64.displayAmount, Spacing tokens) is implemented
   - Story spec is detailed with 5 tasks, 8 unit tests, and clear dev notes
   - All 36 existing tests pass

### Story 1.5 Implementation Prerequisites Verified

| Prerequisite | Status | Evidence |
|-------------|--------|----------|
| EntryView.swift exists (from Story 1.3) | ✅ | `CashOut/Views/Entry/EntryView.swift` |
| Int64.displayAmount extension (from Story 1.4) | ✅ | `CashOut/Utilities/Extensions/Int64+Currency.swift` |
| Spacing enum (from Story 1.4) | ✅ | `CashOut/Utilities/Constants.swift` |
| ViewModels directory exists | ✅ | Per Story 1.1 folder structure |
| CashOutTests/ViewModels directory exists | ✅ | Contains `AuthenticationViewModelTests.swift` |
| All existing tests pass | ✅ | 36 tests, zero regressions |

### Final Note

This assessment identified 5 minor issues across 2 categories (UX alignment and epic quality). None are blocking. The two UX alignment discrepancies are already resolved in the story spec — the recommended updates to source documents are housekeeping to prevent future drift. Story 1.5 is well-specified and ready for development.
