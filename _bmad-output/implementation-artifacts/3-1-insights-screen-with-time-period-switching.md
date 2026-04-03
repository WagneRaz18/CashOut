# Story 3.1: Insights Screen with Time Period Switching

Status: done

## Story

As a user,
I want to switch between daily, weekly, and monthly spending views,
So that I can analyze my cash spending patterns at different time scales.

## Acceptance Criteria

1. **Given** the Insights tab **When** selected **Then** the default view is Weekly (UX-DR22)

2. **Given** the Insights screen **When** a segmented control (Day/Week/Month) is pinned at top **Then** tapping a segment switches the time period instantly with no loading states (NFR3, UX-DR14)

3. **Given** InsightsViewModel **When** created **Then** it is `@Observable` with `@MainActor`, fetches expenses from `ExpenseRepository` for the current period, and performs in-memory aggregation by `categoryID` in Swift (group, sum, sort) **And** does NOT use `NSExpression`-based aggregate queries

4. **Given** the Insights screen **When** `.NSPersistentStoreRemoteChange` notification is received **Then** aggregations are recalculated automatically via async sequence subscription in `.task`

5. **Given** the headline metric **When** a period is selected **Then** it shows the total spending for that period (e.g., "฿247.50 This Week") with `.monospacedDigit()` and `.title3` style (FR18, UX-DR23)

6. **Given** comparison text **When** data exists for the previous period **Then** a neutral comparison is shown (e.g., "฿12 more than last week") — no judgment framing, no red/green coloring (UX-DR26)

7. **Given** no entries for the selected period **When** the Insights screen is shown **Then** "฿0.00" headline with empty donut outline placeholder and "No entries this [period]" is displayed (UX-DR15)

8. **Given** the `.task` handler **When** the Insights tab appears **Then** it guards against redundant re-loads (re-fires on every tab appear in TabView)

## Tasks / Subtasks

- [x] Task 1: Create `InsightsViewModel` (AC: #1, #3, #5, #6, #7, #8)
  - [x] 1.1 Create file `CashOut/ViewModels/InsightsViewModel.swift`
  - [x] 1.2 Define `@MainActor @Observable final class InsightsViewModel` with dependencies: `repository: ExpenseRepositoryProtocol`, `categoryRepository: CategoryRepositoryProtocol` — follow established DI pattern with `@ObservationIgnored` on all dependency references
  - [x] 1.3 Define nested `enum TimePeriod: String, CaseIterable` with cases `.daily("Day")`, `.weekly("Week")`, `.monthly("Month")` and computed labels: `currentPeriodLabel` ("Today"/"This Week"/"This Month"), `previousPeriodLabel` ("yesterday"/"last week"/"last month"), `emptyStateLabel` ("day"/"week"/"month")
  - [x] 1.4 Define nested `struct CategoryTotal: Identifiable, Sendable` with `categoryID: UUID`, `total: Int64`, `id` computed from `categoryID`
  - [x] 1.5 State properties: `var selectedPeriod: TimePeriod = .weekly`, `var totalAmount: Int64 = 0`, `var previousPeriodTotal: Int64? = nil`, `var categoryTotals: [CategoryTotal] = []`, `var errorMessage: String?`
  - [x] 1.6 Guard state: `@ObservationIgnored private var loadedPeriod: TimePeriod?` — tracks which period was last loaded to prevent redundant re-fetches on tab re-appear
  - [x] 1.7 Computed properties: `var isEmpty: Bool` (totalAmount == 0 && categoryTotals.isEmpty), `var headlineText: String` (totalAmount.displayAmount), `var periodLabel: String` (selectedPeriod.currentPeriodLabel), `var comparisonText: String?` (nil when previousPeriodTotal is nil; otherwise "฿X more/less than [previous label]" or "Same as [previous label]"), `var emptyStateText: String` ("No entries this [period]")
  - [x] 1.8 `func loadData() async` — guard: `guard loadedPeriod != selectedPeriod else { return }`. Compute current + previous `DateInterval` using `Calendar.current.dateInterval(of:for:)`. Fetch both via `repository.fetchExpenses(for:)`. `guard !Task.isCancelled` after each await. Aggregate: `reduce` for totalAmount, group+sum by categoryID for categoryTotals (sorted descending by total). Set `previousPeriodTotal` = nil if previous fetch returns empty, else reduce sum. Set `loadedPeriod = selectedPeriod` on success.
  - [x] 1.9 `func invalidateAndReload() async` — sets `loadedPeriod = nil`, then calls internal load logic (bypassing guard). This is for remote change notification re-aggregation.
  - [x] 1.10 `func subscribeToRemoteChanges() async` — **First** call `await invalidateAndReload()` as a catch-up fetch (notifications that fired while tab was hidden are missed by the async sequence — this compensates on tab re-appear). **Then** enter `for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) { guard !Task.isCancelled else { break }; await invalidateAndReload() }`

- [x] Task 2: Date interval computation (AC: #3)
  - [x] 2.1 Private helper: `dateInterval(for period: TimePeriod, referenceDate: Date = Date()) -> DateInterval` using `Calendar.current.dateInterval(of: .day/.weekOfYear/.month, for: referenceDate)!`
  - [x] 2.2 Private helper: `previousDateInterval(for period: TimePeriod) -> DateInterval` — compute previous reference date via `Calendar.current.date(byAdding: .day/-1, .weekOfYear/-1, .month/-1)`, then call `dateInterval(for:referenceDate:)`
  - [x] 2.3 **IMPORTANT**: `ExpenseRepository.fetchExpenses(for:)` uses exclusive upper bound (`createdAt < end`) — `Calendar.dateInterval` returns `[start, start+duration)`, which aligns correctly. No off-by-one adjustment needed.

- [x] Task 3: Rewrite `InsightsView` (AC: #1, #2, #4, #5, #6, #7, #8)
  - [x] 3.1 In `CashOut/Views/Insights/InsightsView.swift`, replace placeholder with full implementation
  - [x] 3.2 `@State private var viewModel = InsightsViewModel()`
  - [x] 3.3 Body structure: `VStack(spacing: 0)` with segmented control at top, then `ScrollView` with content
  - [x] 3.4 Segmented control: `Picker("Period", selection: $viewModel.selectedPeriod) { ForEach(InsightsViewModel.TimePeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).padding(.horizontal, Spacing.md)` — pinned outside ScrollView so it stays at top
  - [x] 3.5 **CRITICAL: Both empty and populated states MUST be inside the ScrollView** — do NOT conditionally replace the ScrollView with a standalone VStack. If the ScrollView is removed from the view hierarchy, `.tabBarMinimizeBehavior(.onScrollDown)` on the TabView loses its scroll target and the tab bar remains permanently expanded. Use `if/else` inside the ScrollView, with empty state centered via `.frame(minHeight:)` using a GeometryReader or `.containerRelativeFrame(.vertical)`.
  - [x] 3.6 Empty state (inside ScrollView): `VStack` centered — `Text(viewModel.headlineText)` (.title3, .monospacedDigit()) + `Text(viewModel.emptyStateText)` (.body, .secondary). Center with `.frame(maxWidth: .infinity, minHeight: geometry.size.height)` or `.containerRelativeFrame(.vertical)`.
  - [x] 3.7 Populated state (inside ScrollView): headline section — `VStack` with `Text(viewModel.headlineText)` (.title3, .monospacedDigit()) + `Text(viewModel.periodLabel)` (.subheadline, .secondary) + optional `Text(viewModel.comparisonText)` (.caption, .secondary) if non-nil. Wrap headline group in `.accessibilityElement(children: .combine)` so VoiceOver announces "฿247.50, This Week" as one unit (UX spec line 946).
  - [x] 3.8 Placeholder area for donut chart (Story 3-2) and bar chart (Story 3-3) — leave as `EmptyView()` or simple comment marker inside the populated VStack. Do NOT implement charts.
  - [x] 3.9 `.task(id: viewModel.selectedPeriod) { await viewModel.loadData() }` — handles initial load + period change. Guard inside ViewModel prevents redundant re-fetches on tab re-appear.
  - [x] 3.10 `.task { await viewModel.subscribeToRemoteChanges() }` — separate task for notification subscription. Auto-cancels on view disappear, restarts on re-appear. The catch-up fetch at the start of `subscribeToRemoteChanges()` ensures remote changes that arrived while the tab was hidden are incorporated.
  - [x] 3.11 `.navigationTitle("Insights")` — already in placeholder, preserve it
  - [x] 3.12 **No `onChange(of: selectedPeriod)` needed** — `.task(id:)` handles period changes natively (cancels old task, starts new one)

- [x] Task 4: Update `MockExpenseRepository` for configurable fetch results (AC: #3)
  - [x] 4.1 In `CashOutTests/Repositories/MockExpenseRepository.swift`, add `var stubbedFetchResult: [ExpenseData] = []`
  - [x] 4.2 Add `var fetchPeriods: [DateInterval] = []` for test assertions — array because `loadData()` calls `fetchExpenses` twice per invocation (current period + previous period). Tests can assert on `.count` and individual intervals.
  - [x] 4.3 Change `fetchExpenses(for:)` to: `fetchExpensesCalled = true; fetchPeriods.append(period); if shouldThrow { throw throwError }; return stubbedFetchResult`
  - [x] 4.4 **Check existing tests** — `FeedViewModelTests` and any other tests calling `fetchExpenses` must still pass. Currently no existing test depends on the empty return value (FeedViewModel uses FRC, not `fetchExpenses`), so the change is safe.

- [x] Task 5: Create `InsightsViewModelTests` (AC: #1, #3, #5, #6, #7, #8)
  - [x] 5.1 Create file `CashOutTests/ViewModels/InsightsViewModelTests.swift`
  - [x] 5.2 `@MainActor final class InsightsViewModelTests: XCTestCase`
  - [x] 5.3 `makeSUT()` helper returning `(viewModel: InsightsViewModel, expenseRepo: MockExpenseRepository, categoryRepo: MockCategoryRepository)`
  - [x] 5.4 `makeExpense()` helper — same pattern as FeedViewModelTests
  - [x] 5.5 Test: default selectedPeriod is `.weekly`
  - [x] 5.6 Test: `loadData` calls `fetchExpenses` with correct DateInterval for each period
  - [x] 5.7 Test: `loadData` computes `totalAmount` as sum of all expense amounts
  - [x] 5.8 Test: `loadData` aggregates `categoryTotals` grouped by categoryID, sorted descending by total
  - [x] 5.9 Test: `loadData` sets `previousPeriodTotal` to nil when previous period returns empty
  - [x] 5.10 Test: `loadData` sets `previousPeriodTotal` to sum when previous period has data
  - [x] 5.11 Test: `comparisonText` returns "฿X more than last week" when current > previous
  - [x] 5.12 Test: `comparisonText` returns "฿X less than last week" when current < previous
  - [x] 5.13 Test: `comparisonText` returns "Same as last week" when equal
  - [x] 5.14 Test: `comparisonText` returns nil when `previousPeriodTotal` is nil
  - [x] 5.15 Test: `loadData` guards against redundant reload (call twice, `fetchExpensesCalled` count is 1 set of calls)
  - [x] 5.16 Test: `loadData` re-fetches after period change (change period, call loadData, verify second fetch)
  - [x] 5.17 Test: `invalidateAndReload` forces re-fetch even for same period
  - [x] 5.18 Test: `isEmpty` returns true when no expenses, false when populated
  - [x] 5.19 Test: `loadData` sets `errorMessage` on fetch failure (with `guard !Task.isCancelled` in catch)
  - [x] 5.20 Test: empty state text matches period ("No entries this day/week/month")

- [x] Task 6: Register new files in Xcode project (AC: all)
  - [x] 6.1 Add `InsightsViewModel.swift` to CashOut target in `project.pbxproj`
  - [x] 6.2 Add `InsightsViewModelTests.swift` to CashOutTests target in `project.pbxproj`

- [x] Task 7: Verify build and test suite (AC: all)
  - [x] 7.1 Build the project — verify zero errors, zero warnings
  - [x] 7.2 Run full test suite — verify all 106 existing tests pass plus 19 new tests (125 total)
  - [ ] 7.3 Manual verification: Insights tab shows "฿0.00" + "No entries this week" by default (empty state)
  - [ ] 7.4 Manual verification: segmented control switches between Day/Week/Month instantly
  - [ ] 7.5 Manual verification: headline metric updates when expenses exist for the selected period
  - [ ] 7.6 Manual verification: comparison text appears when previous period has data

### Review Findings

- [x] [Review][Decision] Error state semantics — Resolved: clear on error. `performLoad()` catch block now resets `totalAmount`, `categoryTotals`, `previousPeriodTotal` before setting `errorMessage`. [InsightsViewModel.swift:155-161]
- [x] [Review][Patch] InsightsView now displays errorMessage — Added error text (`.caption`, `.red`) at top of ScrollView content. [InsightsView.swift:18-25]
- [x] [Review][Patch] `repository` changed to `let` — Removed `@ObservationIgnored`, now `private let repository`. [InsightsViewModel.swift:85]
- [x] [Review][Patch] `Date()` captured once in `performLoad()` — Single `let now = Date()` passed to both `dateInterval` and `previousDateInterval`. [InsightsViewModel.swift:130-132]
- [x] [Review][Patch] Force unwraps on Calendar methods justified — Added inline safety comments. [InsightsViewModel.swift:166,171]
- [x] [Review][Patch] Previous period date interval now tested — Added assertions on `fetchPeriods[1]` in `testLoadDataCallsFetchExpensesWithCorrectDateIntervals`. [InsightsViewModelTests.swift:79-91]

## Dev Notes

### New Files (2)

| File | Location | Purpose |
|------|----------|---------|
| `InsightsViewModel.swift` | `CashOut/ViewModels/` | **Create** — Insights screen logic: period switching, expense fetching, in-memory aggregation, comparison computation |
| `InsightsViewModelTests.swift` | `CashOutTests/ViewModels/` | **Create** — ~16 unit tests for ViewModel logic |

### Modified Files (3)

| File | Location | Action |
|------|----------|--------|
| `InsightsView.swift` | `CashOut/Views/Insights/` | **Rewrite** — replace placeholder with segmented control + headline metric + empty state |
| `MockExpenseRepository.swift` | `CashOutTests/Repositories/` | **Modify** — add `stubbedFetchResult`, `lastFetchPeriod`, update `fetchExpenses` return |
| `project.pbxproj` | `CashOut.xcodeproj/` | **Modify** — register 2 new files |

### Architecture Pattern: Remote Change Notification + Re-fetch

Insights uses a **different observation pattern** than Feed:
- **Feed** uses `NSFetchedResultsController` (FRC) for animated row insertions/deletions
- **Insights** uses `.NSPersistentStoreRemoteChange` notification + re-fetch — simpler, appropriate for aggregation

This means InsightsViewModel does NOT use `startObservingExpenses()` or `onExpensesChanged`. It fetches explicitly via `fetchExpenses(for:)` and subscribes to the remote change notification for re-aggregation.

[Source: architecture.md line 292 — "Insights | Remote change notification + re-fetch | Re-aggregates on change — data volume is tiny"]

### Aggregation Strategy

- Single `NSFetchRequest` with date-range predicate via `fetchExpenses(for:)`
- In-memory aggregation by `categoryID` in Swift: `Dictionary(grouping:by:)` or manual loop with `[UUID: Int64]` accumulator
- Sort `categoryTotals` descending by total amount
- Do **NOT** use `NSExpression`-based aggregate queries — unnecessary complexity for ~6,000 records

[Source: architecture.md line 536-540]

### Date Interval Computation

Use `Calendar.current.dateInterval(of:for:)` for computing period boundaries:
- `.day` → today's start/end
- `.weekOfYear` → this week's start (respects locale first-day-of-week) to end
- `.month` → this month's 1st to last day

The returned `DateInterval` has `start` (inclusive) and `end = start + duration` (exclusive upper bound). This aligns with `ExpenseRepository.fetchExpenses(for:)` which uses `createdAt >= start AND createdAt < end` (exclusive upper bound per architecture learnings 2026-03-28).

### .task Pattern — Two Separate Tasks

```
.task(id: viewModel.selectedPeriod) — initial load + period-change reload
.task                               — remote change notification subscription
```

**Why two tasks:**
- `.task(id:)` cancels and restarts when `selectedPeriod` changes — perfect for period-switching
- A separate `.task` hosts the notification `for await` loop — if it were inside `.task(id:)`, changing the period would kill the subscription
- Both auto-cancel on view disappear and restart on re-appear — expected behavior

**Guard pattern:** `loadedPeriod: TimePeriod?` tracks the last successfully loaded period. On tab re-appear with the same period, the guard skips re-fetch. On period change, `loadedPeriod != selectedPeriod` → re-fetches. On remote change, `invalidateAndReload()` sets `loadedPeriod = nil` → forces re-fetch.

[Source: .claude/learnings/ios-swiftui.md — ".task re-fires on every tab appear in TabView — guard with loaded-state check"]
[Source: .claude/learnings/architecture.md — "Remote change notification subscriptions must use NotificationCenter.notifications(named:) async sequence inside .task {}"]

### Comparison Text — Neutral Framing

UX-DR26 requires neutral comparison: no judgment, no red/green coloring.

- Current > previous: "฿12 more than last week"
- Current < previous: "฿12 less than last week"  
- Equal: "Same as last week"
- No previous data (empty array): no comparison text shown

Use `Int64.displayAmount` for the difference amount — never manually concatenate "฿".

[Source: ux-design-specification.md line 112 — "During insights: Calm observation. No judgment, no nudges"]
[Source: ux-design-specification.md line 121 — "Insights | Calm clarity — 'oh, that's where it went' | Judgment framing ('you overspent!'), color-coded warnings"]

### InsightsViewModel Does NOT Need

- `HapticServiceProtocol` — no haptic events on Insights screen
- `AuthenticationServiceProtocol` — no partner attribution needed for aggregations
- `onExpensesChanged` callback — uses fetch, not FRC observation
- `startObservingExpenses()` — uses notification subscription instead

### InsightsView Does NOT Include (Yet)

- Donut chart (`SectorMark`) — Story 3-2
- Bar chart (`BarMark`) — Story 3-3
- Category breakdown list — Story 3-3
- Tap-to-filter navigation to Feed — Stories 3-2, 3-3
- FloatingAddButton — already handled by ContentView's `.tabViewBottomAccessory`

Leave placeholder space/comments for where charts will be inserted in stories 3-2 and 3-3. Do NOT implement any chart views.

### Empty State Design

When no expenses exist for the selected period:
- "฿0.00" headline with `.title3` + `.monospacedDigit()`
- "No entries this [day/week/month]" in `.body` + `.secondary`
- Centered vertically
- No illustrations, no onboarding prompts, no CTA — minimal text only

[Source: ux-design-specification.md line 888 — "Insights (Tab 3) | No data for period | '$0.00' headline, empty donut outline, 'No entries this [period]'"]

### MockExpenseRepository — Safe Modification

Changing `fetchExpenses(for:)` to return `stubbedFetchResult` (default `[]`) is safe because:
- No existing test depends on the return value of `fetchExpenses(for:)` — FeedViewModel uses FRC-based observation, not `fetchExpenses`
- `stubbedFetchResult` defaults to `[]`, preserving current behavior
- `fetchExpensesCalled` flag is already tracked

### Segmented Control Styling

Use `Picker(.segmented)` — standard SwiftUI pattern:
```swift
Picker("Period", selection: $viewModel.selectedPeriod) {
    ForEach(InsightsViewModel.TimePeriod.allCases, id: \.self) { period in
        Text(period.rawValue).tag(period)
    }
}
.pickerStyle(.segmented)
```

The segmented control is **outside the ScrollView**, pinned at the top. The headline metric and future chart content are **inside the ScrollView**.

[Source: ux-design-specification.md line 874 — "View switching | Segmented control (Picker(.segmented)) | Insights day/week/month"]

### Existing Code Patterns to Follow

- **ViewModel DI**: `init(repository: ExpenseRepositoryProtocol = ExpenseRepository(), ...)` with `@ObservationIgnored` on all dependency references [Source: FeedViewModel.swift]
- **Error handling**: `guard !Task.isCancelled` after every await, in catch blocks too [Source: .claude/learnings/architecture.md]
- **Test class**: `@MainActor final class InsightsViewModelTests: XCTestCase` [Source: FeedViewModelTests.swift:4]
- **makeSUT pattern**: Return named tuple of (viewModel, mocks) [Source: FeedViewModelTests.swift:9-32]
- **makeExpense helper**: Shared across test classes [Source: FeedViewModelTests.swift:34-51]
- **Currency display**: Always `Int64.displayAmount` — never concatenate "฿" manually [Source: Int64+Currency.swift]
- **Constants for let**: Use `private static let` not `private let` for constants [Source: .claude/learnings/architecture.md]

### Previous Story Intelligence

**From Story 2-4 (Delete Expense Flow — last story in Epic 2):**
- 106 tests passing (105 counted + possible drift — verify before adding new)
- FeedViewModel has 4 dependencies (repository, categoryRepository, authService, hapticService)
- `MockExpenseRepository` has `fetchExpensesCalled` flag but returns `[]` — needs enhancement for Insights
- `@ObservationIgnored` on `let` is redundant but used in FeedViewModel for consistency — InsightsViewModel should follow the same pattern for dependencies declared as `let`
- Code review deferred items: save failure silent in release, haptic on rejected digit — pre-existing, not this story's concern

**Code Review Patterns to Follow:**
- `guard !Task.isCancelled` after every async operation
- All new test methods on `@MainActor` class
- Commit message pattern: `feat(insights): add insights screen with time period switching (story 3-1)`

### Git Intelligence

Recent commits follow `feat(feed):` prefix for Epic 2. Epic 3 should use `feat(insights):` prefix.
Suggested commit: `feat(insights): add insights screen with time period switching (story 3-1)`

### Project Structure Notes

- `InsightsViewModel.swift` goes in `CashOut/ViewModels/` — matches architecture directory tree [Source: architecture.md line 822]
- `InsightsView.swift` already exists in `CashOut/Views/Insights/` — rewrite in place
- `InsightsViewModelTests.swift` goes in `CashOutTests/ViewModels/` — matches architecture directory tree [Source: architecture.md line 891]
- No detected conflicts or variances with existing project structure
- ContentView.swift already has InsightsView in Tab 3 inside NavigationStack — no changes needed

### Boundaries — What NOT to Implement

- **No Swift Charts** — `SectorMark` (donut) is Story 3-2, `BarMark` (bars) is Story 3-3
- **No CategoryBreakdownView** — Story 3-3
- **No InsightsSummaryView** — Story 3-2 (donut + headline composite)
- **No filtered feed navigation** — Stories 3-2, 3-3 (tap donut/row → filtered feed)
- **No FRC observation** — Insights uses remote change notification + fetch pattern
- **No HapticService** — no haptic events on this screen
- **No changes to ContentView** — Insights tab already wired
- **No changes to ExpenseRepository** — `fetchExpenses(for:)` already exists and works
- **No changes to ExpenseData** — struct is sufficient
- **No NavigationStack changes** — already in ContentView wrapping InsightsView

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Story 3.1 acceptance criteria (line 588-628)]
- [Source: _bmad-output/planning-artifacts/architecture.md — Insights observation pattern (line 292)]
- [Source: _bmad-output/planning-artifacts/architecture.md — Insights aggregation strategy (line 536-540)]
- [Source: _bmad-output/planning-artifacts/architecture.md — InsightsViewModel file location (line 161, 822)]
- [Source: _bmad-output/planning-artifacts/architecture.md — Navigation pattern with per-tab NavigationStack (line 663-665)]
- [Source: _bmad-output/planning-artifacts/architecture.md — DI pattern (line 542-577)]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — Insights screen layout (line 496)]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — Direction C: Combined Donut + Daily Bars (line 539-541)]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — Journey 3 flow (line 627-657)]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — Segmented control (line 874)]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — Empty states (line 888)]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — InsightsSummaryView component (line 789-795)]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — Accessibility: Insights (line 946)]
- [Source: _bmad-output/planning-artifacts/prd.md — FR13-FR18 Spending Insights requirements]
- [Source: _bmad-output/planning-artifacts/prd.md — NFR: switching views must be instant with no loading states]
- [Source: .claude/learnings/architecture.md — @ObservationIgnored, Task.isCancelled, guard patterns]
- [Source: .claude/learnings/architecture.md — Remote change notification async sequence in .task]
- [Source: .claude/learnings/architecture.md — .task re-fire guard with loaded-state check]
- [Source: .claude/learnings/architecture.md — fetchExpenses exclusive upper bound (createdAt < end)]
- [Source: .claude/learnings/architecture.md — private static let for constants]
- [Source: .claude/learnings/ios-swiftui.md — .task re-fires on every tab appear]
- [Source: CashOut/Repositories/ExpenseRepository.swift:88-112 — fetchExpenses implementation]
- [Source: CashOut/Repositories/ExpenseRepositoryProtocol.swift:5 — fetchExpenses(for:) signature]
- [Source: CashOut/ViewModels/FeedViewModel.swift — established ViewModel pattern]
- [Source: CashOut/Views/Insights/InsightsView.swift — current placeholder to rewrite]
- [Source: CashOut/App/ContentView.swift:17-19 — Insights tab already in TabView]
- [Source: CashOut/Utilities/Extensions/Int64+Currency.swift — displayAmount formatting]
- [Source: CashOutTests/ViewModels/FeedViewModelTests.swift — makeSUT/makeExpense test patterns]
- [Source: CashOutTests/Repositories/MockExpenseRepository.swift — mock to extend]

### Orchestrator Validation (2026-04-03)

**Guardians run**: ios-swiftui-guardian, architecture-guardian, cloudkit-sync-guardian

**CRITICALs resolved in story spec:**
1. [ios-swiftui] Empty state MUST remain inside ScrollView — conditional branch that replaces ScrollView breaks `.tabBarMinimizeBehavior` (no scroll target). **Fixed:** Task 3.5 now requires both empty and populated states inside ScrollView with `.containerRelativeFrame` or GeometryReader for centering.

**WARNINGs addressed in story spec:**
1. [cloudkit-sync] Notification gap on tab re-appear — `subscribeToRemoteChanges()` async sequence misses notifications posted while tab was hidden. **Fixed:** Task 1.10 now calls `invalidateAndReload()` as catch-up fetch before entering the `for await` loop.
2. [ios-swiftui] Missing VoiceOver grouping on headline metric — UX spec line 946 says "Summary announces total + period" as one unit. **Fixed:** Task 3.7 now includes `.accessibilityElement(children: .combine)` on headline group.
3. [architecture] `MockExpenseRepository.lastFetchPeriod` can only track one period, but `loadData()` calls `fetchExpenses` twice (current + previous). **Fixed:** Task 4.2 now uses `fetchPeriods: [DateInterval]` array.
4. [architecture] `categoryRepository` declared but unused in Story 3-1. **Kept intentionally** — Story 3-2 (donut chart with category labels) will need it. Adding later would require modifying both ViewModel init and all test makeSUT() calls. Trivial cost now, saves churn later.
5. [architecture] `@ObservationIgnored` on `let` constants is redundant per learnings (2026-04-03) but FeedViewModel uses this pattern for consistency. **Accepted** — follow FeedViewModel pattern, don't refactor existing code.
6. [cloudkit-sync] `fetchExpenses(for:)` runs synchronous main-thread fetch on viewContext. **Accepted** — architecture doc specifies ~6,000 records max; synchronous fetch is negligible latency for this volume. Background context deferred to post-MVP.
7. [ios-swiftui] `comparisonText` computed property must use `guard let` on optional `previousPeriodTotal` — never force-unwrap. **Already specified** in Task 1.7 ("nil when previousPeriodTotal is nil").
8. [architecture] `invalidateAndReload()` "bypassing guard" phrasing — the mechanism is that `nil != .weekly` always evaluates true, not that the guard is literally bypassed. **Clarified** in Task 1.9 description.

**SUGGESTIONs noted:**
- `Calendar.current.dateInterval(of: .weekOfYear)` respects device locale's first-day-of-week (Sunday for th_TH). No manual `.firstWeekday` override needed.
- Architecture doc line 271 references non-existent `container.handleRemoteNotification(_:)` — stale doc, not a story issue. AppDelegate already correct.
- Consider `fetchExpensesCallCount: Int` alongside `fetchPeriods` array for simpler count assertions.

**Architecture guardian:** All clear. MVVM boundaries correct. DI pattern matches FeedViewModel. State modeling uses independent properties. Async lifecycle with .task(id:) + separate .task for notification subscription is sound.

**iOS/SwiftUI guardian:** All clear after CRITICAL fix. NavigationStack ownership correct. Picker(.segmented) pattern correct. .tabBarMinimizeBehavior placement correct. Dynamic Type supported via semantic text styles. Empty state matches UX spec.

**CloudKit sync guardian:** All clear after WARNING fix. NSPersistentStoreRemoteChangeNotificationPostOptionKey enabled on both stores. automaticallyMergesChangesFromParent true. No manual CKSubscription. fetchExpenses date predicate uses exclusive upper bound correctly.

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

- Build succeeded with zero errors on first attempt
- All 125 tests pass (106 existing + 19 new) with 0 failures

### Orchestrator Validation (Post-Implementation)

**Guardians run**: ios-swiftui-guardian, architecture-guardian, cloudkit-sync-guardian

**CRITICALs resolved:**
1. [cloudkit-sync] `.NSPersistentStoreRemoteChange` without `object:` filter — **Assessed as WARNING**: With single-container architecture, re-aggregating on local saves is desirable behavior (user adds expense on Entry tab → Insights re-aggregates when tab appears). Performance is negligible (~6K records). No code change needed.
2. [cloudkit-sync] `handleAccountChange` no-op in PersistenceController — **Out of scope**: Pre-existing code not modified by this story.

**WARNINGs resolved:**
1. [architecture] Removed redundant `@ObservationIgnored` from `let categoryRepository` per 2026-04-03 learning
2. [ios-swiftui] Added `.accessibilityElement(children: .combine)` to empty state VStack for VoiceOver consistency

**WARNINGs noted (by design):**
3. [architecture/ios-swiftui] Two `.task` modifiers cause duplicate initial fetch — intentional per story spec Task 1.10 (catch-up fetch for missed notifications)
4. [cloudkit-sync] Concurrent load ordering between `.task(id:)` and plain `.task` — mitigated by `@MainActor` serialization and `Task.isCancelled` guards

### Completion Notes List

- Created `InsightsViewModel` with `@MainActor @Observable` pattern matching FeedViewModel DI conventions
- Implemented `TimePeriod` enum with `.daily`/`.weekly`/`.monthly` cases and computed labels
- Implemented `loadData()` with guard-based redundancy prevention (`loadedPeriod` tracking)
- Implemented `invalidateAndReload()` for remote change notification re-aggregation
- Implemented `subscribeToRemoteChanges()` with catch-up fetch + `for await` notification loop
- Date interval helpers use `Calendar.current.dateInterval(of:for:)` — exclusive upper bound aligns with repository predicate
- Comparison text uses neutral framing per UX-DR26: "more than"/"less than"/"Same as"
- Rewrote InsightsView with segmented control pinned outside ScrollView, both empty and populated states inside ScrollView (CRITICAL for `.tabBarMinimizeBehavior`)
- Empty state uses `.containerRelativeFrame(.vertical)` for centering within ScrollView
- Headline group wrapped in `.accessibilityElement(children: .combine)` for VoiceOver
- Two separate `.task` modifiers: `.task(id:)` for load + period change, `.task` for notification subscription
- Updated `MockExpenseRepository` with `stubbedFetchResult` and `fetchPeriods: [DateInterval]` array
- 19 unit tests covering: defaults, date intervals, aggregation, comparison text, guard, invalidate, isEmpty, error handling, empty state text
- Applied learnings: `@ObservationIgnored` only on `var` (not redundant `let`), `guard !Task.isCancelled` in catch blocks
- Post-orchestrator fixes: removed redundant `@ObservationIgnored` on `let`, added empty state accessibility grouping
- Manual verification tasks (7.3–7.6) deferred to user

### Change Log

- 2026-04-03: Implemented all tasks 1-7 for Story 3-1 (Insights screen with time period switching)

### File List

- CashOut/ViewModels/InsightsViewModel.swift (new)
- CashOut/Views/Insights/InsightsView.swift (modified — rewritten from placeholder)
- CashOutTests/ViewModels/InsightsViewModelTests.swift (new)
- CashOutTests/Repositories/MockExpenseRepository.swift (modified — added stubbedFetchResult, fetchPeriods)
- CashOut.xcodeproj/project.pbxproj (modified — registered 2 new files)
- _bmad-output/implementation-artifacts/sprint-status.yaml (modified — status tracking)
