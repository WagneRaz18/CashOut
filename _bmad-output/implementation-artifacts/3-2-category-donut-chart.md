# Story 3.2: Category Donut Chart

Status: done

## Story

As a user,
I want a visual donut chart showing my spending proportions by category,
So that I can instantly see where most of my cash is going.

## Acceptance Criteria

1. **Given** the Insights screen **When** data exists for the selected period **Then** a compact donut chart (120pt frame, `SectorMark` via Swift Charts) displays category proportions using the muted category colors from the asset catalog (UX-DR6, UX-DR7)

2. **Given** the donut chart **When** a slice is tapped **Then** the view navigates (via `NavigationStack` push) to a filtered feed showing only entries for that category in the current period (UX-DR22)

3. **Given** chart colors **When** rendered **Then** they use the same category colors as feed rows and category picker — consistent everywhere via `CategoryColor` asset catalog colorsets

4. **Given** the donut chart **When** rendered in dark mode and light mode **Then** category colors use their respective mode variants from the asset catalog (light/dark pairs already defined per category)

5. **Given** VoiceOver is enabled **When** the donut chart is focused **Then** it provides a text summary: "This week total: [amount]. Largest category: [name] at [amount]" (UX-DR16)

6. **Given** no data for the period **When** the donut area is rendered **Then** an empty donut outline is shown (single `SectorMark` with `Color.secondary.opacity(0.2)`) — the chart is not hidden entirely (UX-DR15)

## Tasks / Subtasks

- [x] Task 1: Extend `InsightsViewModel` for chart data (AC: #1, #2, #3, #5)
  - [x] 1.1 Add `struct ChartSlice: Identifiable, Sendable` with fields: `categoryID: UUID`, `categoryName: String`, `colorName: String`, `total: Int64`, `id` computed from `categoryID`
  - [x] 1.2 Add published state: `var chartSlices: [ChartSlice] = []`
  - [x] 1.3 Add published state: `var selectedCategoryID: UUID?` — set when user taps a donut slice, nil when no selection
  - [x] 1.4 In `performLoad()`, after computing `categoryTotals`, also compute `chartSlices`: call `try await categoryRepository.fetchCategories()`, then **`guard !Task.isCancelled else { return }`** (required after every await). Build a local `let categoryMap: [UUID: CategoryData] = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })` for O(1) lookups. For each `CategoryTotal`, resolve `categoryName` and `colorName` from the map. Sort descending by total (same order as `categoryTotals`). The category map is local to `performLoad()` — rebuilt on every call to stay consistent with viewContext state after remote changes.
  - [x] 1.5 Add computed property `var chartAccessibilityLabel: String` — "This [period] total: [amount]. Largest category: [name] at [amount]." using `Int64.displayAmount` for amounts. Return "No entries this [period]" when `chartSlices` is empty.
  - [x] 1.6 On error in `performLoad()`, clear `chartSlices = []` alongside other state resets.
  - [x] 1.7 Add `func selectCategory(_ categoryID: UUID?)` — sets `selectedCategoryID`. The View will react to this via `NavigationStack` path or `navigationDestination`.

- [x] Task 2: Create `InsightsSummaryView` (AC: #1, #3, #4, #5, #6)
  - [x] 2.1 Create file `CashOut/Views/Insights/InsightsSummaryView.swift`
  - [x] 2.2 Layout: `HStack` with compact donut (left, 120pt) and headline text group (right: total amount, period label, comparison text)
  - [x] 2.3 Donut chart implementation using `Chart { ForEach(slices) { SectorMark(...) } }`:
    - `angle: .value("Amount", slice.total)`
    - `innerRadius: .ratio(0.618)` (Apple's documented golden ratio — creates donut hole)
    - `angularInset: 1` (subtle gap between slices)
    - `.cornerRadius(3)` on each mark (rounded slice ends)
  - [x] 2.4 Category colors: use `.foregroundStyle(by: .value("Category", slice.categoryName))` combined with `.chartForegroundStyleScale(domain:range:)` on the `Chart` — domain is `slices.map(\.categoryName)`, range is `slices.map { Color($0.colorName) }`. This maps each category to its asset catalog color, consistent with feed rows and category picker.
  - [x] 2.5 Chart size: `.frame(width: 120, height: 120)` on the Chart view
  - [x] 2.6 Hide the auto-generated legend: `.chartLegend(.hidden)` — the category breakdown list (Story 3-3) serves as the legend
  - [x] 2.7 Empty state: when `slices` is empty, render a single `SectorMark(angle: .value("Empty", 1), innerRadius: .ratio(0.618))` with `.foregroundStyle(Color.secondary.opacity(0.2))` and `.chartLegend(.hidden)`. No tap interaction on empty state.
  - [x] 2.8 Accessibility: apply `.accessibilityLabel(accessibilityLabel)` on the Chart view (string passed in from ViewModel's `chartAccessibilityLabel`). Individual sector marks get `.accessibilityLabel(slice.categoryName)` + `.accessibilityValue(slice.total.displayAmount)`.
  - [x] 2.9 Headline text group (right side of HStack): `Text(headlineText)` (.title3, .monospacedDigit()), `Text(periodLabel)` (.subheadline, .secondary), optional `Text(comparisonText)` (.caption, .secondary). Wrap in `.accessibilityElement(children: .combine)`.
  - [x] 2.10 The view receives all data via init parameters (not a ViewModel reference) — it is a pure presentation component: `init(slices: [ChartSlice], headlineText: String, periodLabel: String, comparisonText: String?, emptyStateText: String, accessibilityLabel: String, onSliceTapped: (UUID) -> Void)`. When `slices` is empty, the headline group shows `headlineText` + `emptyStateText` instead of `periodLabel`/`comparisonText`.

- [x] Task 3: Implement donut slice tap interaction (AC: #2)
  - [x] 3.1 Add `@State private var selectedAngle: Int64?` to `InsightsSummaryView` — **must be `Int64?`** to match the `PlottableValue` type of `angle: .value("Amount", slice.total)` where `slice.total` is `Int64`. Using `Int?` causes a type mismatch in the `.chartAngleSelection` binding.
  - [x] 3.2 Apply `.chartAngleSelection(value: $selectedAngle)` on the Chart
  - [x] 3.3 **CRITICAL**: Also apply `.chartGesture { chart in SpatialTapGesture().onEnded { event in let angle = chart.angle(at: event.location); chart.selectAngleValue(at: angle) } }` — `.chartAngleSelection` alone uses hold-not-tap gesture (confirmed Apple bug). The `SpatialTapGesture` override enables proper single-tap.
  - [x] 3.4 Add `.onChange(of: selectedAngle)` handler that walks `slices` to resolve the tapped category: accumulate totals until `rawValue <= accumulated`, then call `onSliceTapped(slice.categoryID)`.
  - [x] 3.5 After tap resolves, reset `selectedAngle = nil` so subsequent taps register.

- [x] Task 4: Create `FilteredFeedView` for category-filtered navigation (AC: #2)
  - [x] 4.1 Create file `CashOut/Views/Insights/FilteredFeedView.swift`
  - [x] 4.2 Init parameters: `categoryID: UUID`, `categoryName: String`, `period: DateInterval`, `categories: [CategoryData]`, `repository: ExpenseRepositoryProtocol = ExpenseRepository()`. The `categories` array is passed from InsightsViewModel (already fetched) to avoid a redundant CategoryRepository call. The repository is injected via protocol for DI consistency.
  - [x] 4.3 Fetch filtered expenses in `.task`: `do { let all = try await repository.fetchExpenses(for: period); expenses = all.filter { $0.categoryID == categoryID } } catch { errorMessage = error.localizedDescription }`. **Must have `catch` block** — never use `try?` on repository operations. Add `@State private var errorMessage: String?` and display it.
  - [x] 4.4 Display as a `List` of `FeedRowView` — reuse the existing component. For each expense, look up category from the passed `categories` array via `categories.first { $0.id == expense.categoryID }`. For `isCurrentUser`, use `AuthenticationService().currentUserID == expense.createdByUserID` (or pass current user ID as init param). For `partnerInitials`, use a simple first-character-of-name fallback. Read-only — no edit/delete swipe actions.
  - [x] 4.5 Empty state: "No [categoryName] entries this [period]" centered, `.secondary` style (per UX empty state spec). Error state: display `errorMessage` in `.caption` + `.red`.
  - [x] 4.6 `.navigationTitle(categoryName)` — system back button from `NavigationStack` returns to Insights
  - [x] 4.7 **Does NOT** need its own ViewModel — it's a simple read-only list. Use `@State` for the fetched data + a `.task` to load. **Note**: no remote-change subscription — stale data acceptable for this read-only view in v1.

- [x] Task 5: Wire `InsightsSummaryView` into `InsightsView` (AC: #1, #2)
  - [x] 5.1 In `InsightsView.swift`, replace the `// Placeholder for donut chart (Story 3-2)` comment with `InsightsSummaryView(...)` passing ViewModel properties
  - [x] 5.2 Move the existing headline text (headlineText, periodLabel, comparisonText VStack) OUT of InsightsView — it is now part of `InsightsSummaryView`'s right side. The populated state in InsightsView becomes: `InsightsSummaryView(...)` followed by future chart/breakdown placeholders.
  - [x] 5.3 Add `.navigationDestination(item: Bindable(viewModel).selectedCategoryID)` on the `ScrollView` (inside the NavigationStack). **CRITICAL**: `@State` on an `@Observable` class does NOT expose `$viewModel` as a `Bindable` wrapper. You must use `Bindable(viewModel).selectedCategoryID` to obtain the `Binding<UUID?>` needed by `navigationDestination(item:)`. Alternatively, declare `@Bindable private var viewModel` instead of `@State`. The destination closure receives the `UUID` and creates `FilteredFeedView(categoryID:categoryName:period:categories:)`.
  - [x] 5.4 The `onSliceTapped` closure calls `viewModel.selectCategory(categoryID)` which sets `selectedCategoryID`, triggering the navigation
  - [x] 5.5 Empty state (viewModel.isEmpty): show `InsightsSummaryView` in empty mode (empty slices array) — the empty donut outline + "฿0.00" headline is shown. Do NOT hide the summary view when empty. **CRITICAL**: Wrap the empty-state `InsightsSummaryView` in a container with `.containerRelativeFrame(.vertical) { height, _ in height }` to maintain vertical centering within the ScrollView — identical to the current empty state pattern. Without this, the empty donut top-aligns and `.tabBarMinimizeBehavior(.onScrollDown)` centering is lost.
  - [x] 5.6 `import Charts` is only needed in `InsightsSummaryView.swift`, not in `InsightsView.swift`

- [x] Task 6: Update `InsightsViewModel` to provide `DateInterval` for navigation (AC: #2)
  - [x] 6.1 Expose `private(set) var currentPeriodInterval: DateInterval?` — set during `performLoad()` to the current period's `DateInterval`. Use `private(set)` so the property is readable by views but only settable from within the ViewModel. Needed so `FilteredFeedView` can use the same period.
  - [x] 6.2 On error, set `currentPeriodInterval = nil`.

- [x] Task 7: Write unit tests for new ViewModel logic (AC: #1, #5)
  - [x] 7.1 Test: `chartSlices` populated after `loadData()` with correct category names, colors, totals
  - [x] 7.2 Test: `chartSlices` sorted descending by total
  - [x] 7.3 Test: `chartSlices` is empty when no expenses
  - [x] 7.4 Test: `chartAccessibilityLabel` contains total and largest category name
  - [x] 7.5 Test: `chartAccessibilityLabel` returns empty state text when no data
  - [x] 7.6 Test: `selectCategory` sets `selectedCategoryID`
  - [x] 7.7 Test: `currentPeriodInterval` set after successful load
  - [x] 7.8 Test: `chartSlices` cleared on error
  - [x] 7.9 Populate the existing `MockCategoryRepository.categoriesToReturn` (already defined at MockCategoryRepository.swift:9) with default `CategoryData` stubs matching the `categoryID` UUIDs used in expense stubs — do NOT create a new field, the mock already has it

- [x] Task 8: Register new files in Xcode project (AC: all)
  - [x] 8.1 Add `InsightsSummaryView.swift` to CashOut target in `project.pbxproj`
  - [x] 8.2 Add `FilteredFeedView.swift` to CashOut target in `project.pbxproj`

- [x] Task 9: Verify build and test suite (AC: all)
  - [x] 9.1 Build the project — verify zero errors, zero warnings
  - [x] 9.2 Run full test suite — verify all existing tests pass plus new tests
  - [x] 9.3 Manual verification: donut chart displays with correct category colors
  - [x] 9.4 Manual verification: tapping a donut slice navigates to filtered feed
  - [x] 9.5 Manual verification: empty donut outline shows when no data
  - [x] 9.6 Manual verification: dark mode category colors render correctly

### Review Findings

- [x] [Review][Patch] P1: `Dictionary(uniqueKeysWithValues:)` crashes on duplicate category IDs — use `uniquingKeysWith:` [`InsightsViewModel.swift:182`] ✓ fixed
- [x] [Review][Patch] P2: `resolveCategory` returns nil when rawValue exceeds accumulated total due to chart rounding — fall back to last slice [`InsightsSummaryView.swift:123-132`] ✓ fixed
- [x] [Review][Patch] P3: Missing test assertions for `currentPeriodInterval` and `fetchedCategories` cleared on error path [`InsightsViewModelTests.swift`] ✓ fixed
- [x] [Review][Patch] P4: `FilteredFeedView.partnerInitials` uses `String(id.prefix(2))` — inconsistent with FeedViewModel which returns `"P"` [`FilteredFeedView.swift:74-76`] ✓ fixed
- [x] [Review][Defer] D1: Default `AuthenticationService()` in ViewModel init — established pattern across all ViewModels — deferred, pre-existing
- [x] [Review][Defer] D2: Duplicate `categoryName` values break `chartForegroundStyleScale` domain — requires unique name enforcement at category creation (Epic 5) — deferred, pre-existing
- [x] [Review][Defer] D3: "This day total:" awkward VoiceOver phrasing for daily period — pre-existing `emptyStateLabel` from Story 3-1 — deferred, pre-existing

## Dev Notes

### New Files (2)

| File | Location | Purpose |
|------|----------|---------|
| `InsightsSummaryView.swift` | `CashOut/Views/Insights/` | **Create** — Donut chart (SectorMark) + headline metric composite component |
| `FilteredFeedView.swift` | `CashOut/Views/Insights/` | **Create** — Category-filtered expense list for tap-to-navigate from donut |

### Modified Files (3)

| File | Location | Action |
|------|----------|--------|
| `InsightsViewModel.swift` | `CashOut/ViewModels/` | **Modify** — add `ChartSlice`, `chartSlices`, `selectedCategoryID`, `currentPeriodInterval`, `chartAccessibilityLabel` |
| `InsightsView.swift` | `CashOut/Views/Insights/` | **Modify** — wire in InsightsSummaryView, add navigationDestination, restructure populated/empty state |
| `project.pbxproj` | `CashOut.xcodeproj/` | **Modify** — register 2 new files |

### Test Files (1 modified)

| File | Location | Action |
|------|----------|--------|
| `InsightsViewModelTests.swift` | `CashOutTests/ViewModels/` | **Modify** — add ~8 tests for chart slice computation, accessibility label, selectedCategory, error clearing |

### Architecture: InsightsSummaryView as Presentation Component

`InsightsSummaryView` is a **sub-view** (not a screen), so it does NOT have its own ViewModel. Per architecture rules: "One ViewModel per screen (not per component)." It receives all data via init parameters and communicates taps via a closure callback.

The ownership chain is:
```
InsightsView (@State viewModel: InsightsViewModel)
  └── InsightsSummaryView (data params + onSliceTapped closure)
        └── Chart { SectorMark... }
```

[Source: architecture.md line 389 — "One ViewModel per screen (not per component)"]

### Swift Charts SectorMark API

`SectorMark` (iOS 17+, `import Charts`) creates pie/donut charts. Key parameters:

```swift
SectorMark(
    angle: .value("Amount", slice.total),
    innerRadius: .ratio(0.618),  // Golden ratio → donut (not pie)
    angularInset: 1               // Subtle gap between slices
)
.cornerRadius(3)
```

- `innerRadius: .ratio(0.618)` — Apple's recommended golden ratio for donut hole
- `angularInset: 1` — keep small; large values distort small slices disproportionately
- `.cornerRadius(3)` — rounds the cut ends of each slice

[Source: Apple Developer Documentation — SectorMark]

### Chart Color Mapping — chartForegroundStyleScale

Use `.chartForegroundStyleScale(domain:range:)` on the `Chart` to map categories to their asset catalog colors:

```swift
Chart { ... }
    .foregroundStyle(by: .value("Category", slice.categoryName))  // per mark
    .chartForegroundStyleScale(
        domain: slices.map(\.categoryName),
        range: slices.map { Color($0.colorName) }
    )
```

This ensures donut slice colors match feed row icon badges and category picker chips — same `Color("Sage")`, `Color("Slate")`, etc. from the asset catalog.

[Source: architecture.md line 445-460 — Category Color Tokens]
[Source: Color+CategoryTokens.swift — CategoryColor enum resolves colorName → Color]

### Tap Interaction — chartAngleSelection + SpatialTapGesture Fix

**CRITICAL**: `.chartAngleSelection` alone registers hold-not-tap (confirmed Apple bug). Must pair with `.chartGesture`:

```swift
.chartAngleSelection(value: $selectedAngle)
.chartGesture { chart in
    SpatialTapGesture()
        .onEnded { event in
            let angle = chart.angle(at: event.location)
            chart.selectAngleValue(at: angle)
        }
}
```

Resolve the raw angle value to a category by walking the slices array and accumulating totals:

```swift
func resolveCategory(for rawValue: Int64, slices: [ChartSlice]) -> UUID? {
    var accumulated: Int64 = 0
    for slice in slices {
        accumulated += slice.total
        if rawValue <= accumulated { return slice.categoryID }
    }
    return nil
}
```

[Source: Apple Developer Forums — chartAngleSelection tap vs hold bug]

### Navigation: Donut Slice → Filtered Feed

Insights tab already has a `NavigationStack` (in ContentView.swift:17-19). The flow is:

1. User taps donut slice → `onSliceTapped(categoryID)` fires
2. `InsightsView` calls `viewModel.selectCategory(categoryID)` → sets `selectedCategoryID`
3. `navigationDestination(item: $viewModel.selectedCategoryID)` pushes `FilteredFeedView`
4. System back button returns to full Insights view

**Important**: `selectedCategoryID` must be a `Hashable` type for `navigationDestination(item:)`. Use a wrapper struct or pass `UUID` directly since `UUID` conforms to `Hashable`.

[Source: architecture.md line 645-680 — Navigation Pattern]
[Source: ContentView.swift:17-19 — NavigationStack wraps InsightsView]

### FilteredFeedView — Lightweight, No ViewModel

`FilteredFeedView` is a simple read-only list. It does NOT need its own ViewModel because:
- It's a one-shot fetch (not observable)
- No edit/delete operations
- No FRC subscription needed

Pattern: `@State private var expenses: [ExpenseData] = []` + `.task { expenses = try await repo.fetchExpenses(for: period).filter { $0.categoryID == categoryID } }`

Reuse `FeedRowView` for each row — consistent appearance with the main feed.

[Source: ux-design-specification.md line 637 — "Browse filtered entries"]

### Empty State — Donut Outline

When no data exists, show an empty donut outline (NOT hidden):

```swift
Chart {
    SectorMark(
        angle: .value("Empty", 1),
        innerRadius: .ratio(0.618)
    )
    .foregroundStyle(Color.secondary.opacity(0.2))
}
.chartLegend(.hidden)
```

This renders a gray ring matching the donut dimensions. The "฿0.00" headline + "No entries this [period]" text appear alongside.

[Source: ux-design-specification.md line 888 — "$0.00 headline, empty donut outline"]

### Category Resolution via categoryRepository

`InsightsViewModel` already has `categoryRepository` injected (was intentionally included in Story 3-1 for this purpose). Use `categoryRepository.fetchCategories()` to resolve `categoryID → (name, colorName)`.

**Performance note**: Fetch categories once per `performLoad()` call, not per category total. Cache in a local `[UUID: CategoryData]` dictionary for O(1) lookups.

[Source: 3-1 story Orchestrator Validation — "categoryRepository declared but unused in Story 3-1. Kept intentionally — Story 3-2 (donut chart with category labels) will need it."]

### Accessibility — Chart Summary

UX spec requires: "Summary announces total + period. Donut announces category breakdown."

The chart-level `.accessibilityLabel` should be: "This week total: ฿247.50. Largest category: Food & Drink at ฿120.00."

Individual sector marks get per-slice labels: `.accessibilityLabel("Food & Drink")` + `.accessibilityValue("฿120.00")`.

Use `Int64.displayAmount` for all amounts — never concatenate "฿" manually.

[Source: ux-design-specification.md line 946 — "Donut announces category breakdown"]
[Source: ux-design-specification.md line 789-795 — InsightsSummaryView accessibility spec]

### Existing Code Patterns to Follow

- **ViewModel DI**: `init(repository: ExpenseRepositoryProtocol = ExpenseRepository(), ...)` — already established in InsightsViewModel [Source: InsightsViewModel.swift:96-102]
- **Error handling**: `guard !Task.isCancelled` after every await [Source: .claude/learnings/architecture.md]
- **Currency display**: Always `Int64.displayAmount` — never concatenate "฿" manually [Source: Int64+Currency.swift]
- **Constants for let**: Use `private static let` not `private let` [Source: .claude/learnings/architecture.md]
- **One View per file**: InsightsSummaryView in its own file, FilteredFeedView in its own file [Source: architecture.md line 389]
- **Sub-views in same feature folder**: Both new files go in `CashOut/Views/Insights/` [Source: architecture.md line 372-389]
- **ViewModel never imports SwiftUI**: Chart data preparation happens in ViewModel; `Chart`/`SectorMark` rendering happens in View [Source: .claude/learnings/architecture.md]
- **Test class pattern**: `@MainActor final class` with `makeSUT()` [Source: InsightsViewModelTests.swift:5-23]

### Boundaries — What NOT to Implement

- **No `BarMark` / bar chart** — Story 3-3
- **No `CategoryBreakdownView`** (list with proportion bars) — Story 3-3
- **No `DailyBarChartView`** — Story 3-3
- **No edit/delete on FilteredFeedView** — read-only filtered list
- **No custom animations** — "No custom animations in v1" per UX spec. Swift Charts default transitions are sufficient.
- **No loading states** — CashOut is local-first; data is always instant
- **No Combine publishers** — use `@Observable` + `async/await` only
- **No changes to `FeedRowView`** — reuse as-is in FilteredFeedView
- **No changes to `CategoryRepository`** — `fetchCategories()` already exists
- **No changes to `ExpenseRepository`** — `fetchExpenses(for:)` already exists
- **No changes to `ContentView`** — NavigationStack already wraps InsightsView

### Previous Story Intelligence

**From Story 3-1 (Insights Screen with Time Period Switching):**
- 125 tests passing (106 pre-existing + 19 new)
- `categoryRepository` was intentionally injected in Story 3-1 for this story's use
- `@ObservationIgnored` only on `var` (not `let`) per 2026-04-03 learning — `repository` and `categoryRepository` are `let`, no annotation needed
- `performLoad()` already has the aggregation loop — extend it to also compute `chartSlices`
- Both empty and populated states MUST stay inside ScrollView (CRITICAL for `.tabBarMinimizeBehavior`)
- `.task(id: viewModel.selectedPeriod)` for period switching, `.task` for remote change subscription — pattern unchanged
- `MockExpenseRepository` has `stubbedFetchResult` and `fetchPeriods: [DateInterval]` — no changes needed
- `MockCategoryRepository` has `categoriesToReturn: [CategoryData]` — set up with default categories for chart tests
- Commit prefix: `feat(insights):` for Epic 3

### Git Intelligence

Recent commits:
- `fix(insights): resolve 6 code review findings for story 3-1`
- `feat(insights): add insights screen with time period switching (story 3-1)`

Suggested commit: `feat(insights): add category donut chart with tap-to-filter navigation (story 3-2)`

### Project Structure Notes

- `InsightsSummaryView.swift` → `CashOut/Views/Insights/` — matches architecture directory tree [Source: architecture.md line 841]
- `FilteredFeedView.swift` → `CashOut/Views/Insights/` — sub-view of Insights feature
- No new ViewModels needed (InsightsViewModel extended, FilteredFeedView uses @State)
- No detected conflicts with existing project structure

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Story 3.2 acceptance criteria]
- [Source: _bmad-output/planning-artifacts/architecture.md line 31 — Swift Charts (SectorMark, BarMark)]
- [Source: _bmad-output/planning-artifacts/architecture.md line 389 — One ViewModel per screen]
- [Source: _bmad-output/planning-artifacts/architecture.md line 445-460 — Category Color Tokens]
- [Source: _bmad-output/planning-artifacts/architecture.md line 537-540 — Insights Aggregation Strategy]
- [Source: _bmad-output/planning-artifacts/architecture.md line 542-577 — DI Pattern]
- [Source: _bmad-output/planning-artifacts/architecture.md line 645-680 — Navigation Pattern]
- [Source: _bmad-output/planning-artifacts/architecture.md line 839-843 — Insights directory structure]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md line 415-431 — Category colors muted palette]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md line 496 — Insights tab layout]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md line 539-541 — Direction C: Combined Donut + Daily Bars]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md line 625-657 — Journey 3 flow]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md line 789-795 — InsightsSummaryView component spec]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md line 884-889 — Empty states]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md line 946 — Insights accessibility]
- [Source: _bmad-output/planning-artifacts/prd.md line 253-260 — FR13-FR18 Spending Insights]
- [Source: .claude/learnings/architecture.md — @ObservationIgnored, Task.isCancelled, guard patterns]
- [Source: .claude/learnings/ios-swiftui.md — .task re-fires, ScrollView empty state, .tabBarMinimizeBehavior]
- [Source: CashOut/ViewModels/InsightsViewModel.swift — existing ViewModel to extend]
- [Source: CashOut/Views/Insights/InsightsView.swift — existing view with placeholder comments]
- [Source: CashOut/Views/Feed/FeedRowView.swift — reusable row component for FilteredFeedView]
- [Source: CashOut/Utilities/Extensions/Color+CategoryTokens.swift — CategoryColor enum]
- [Source: CashOut/Utilities/Constants.swift — DefaultCategory with colorName mapping]
- [Source: CashOut/Models/CategoryData.swift — CategoryData DTO struct]
- [Source: CashOut/Models/ExpenseData.swift — ExpenseData DTO struct]
- [Source: CashOut/Repositories/CategoryRepositoryProtocol.swift — fetchCategories() signature]
- [Source: CashOut/App/ContentView.swift:17-19 — NavigationStack wraps InsightsView]
- [Source: CashOutTests/ViewModels/InsightsViewModelTests.swift — existing test patterns]
- [Source: CashOutTests/Repositories/MockCategoryRepository.swift — mock with categoriesToReturn]
- [Source: Apple Developer Documentation — SectorMark API]
- [Source: Apple Developer Forums — chartAngleSelection tap vs hold bug fix]
- [Source: _bmad-output/implementation-artifacts/3-1-insights-screen-with-time-period-switching.md — previous story intelligence]

### Orchestrator Validation (2026-04-04)

**Guardians run**: ios-swiftui-guardian, architecture-guardian, cloudkit-sync-guardian

**CRITICALs resolved in story spec:**
1. [ios-swiftui] `selectedAngle` binding type must be `Int64?`, not `Int?` — `chartAngleSelection` binding type must match the `PlottableValue` type (`slice.total` is `Int64`). **Fixed:** Task 3.1 updated to `Int64?`, Dev Notes resolveCategory function updated to `Int64` parameter.
2. [ios-swiftui + architecture] `$viewModel.selectedCategoryID` requires `@Bindable` — `@State` on `@Observable` class does not expose `$viewModel` as a `Bindable`. **Fixed:** Task 5.3 updated with `Bindable(viewModel).selectedCategoryID` syntax.
3. [ios-swiftui] Empty state InsightsSummaryView missing `.containerRelativeFrame(.vertical)` — without it the empty donut top-aligns and centering is lost. **Fixed:** Task 5.5 updated with explicit wrapper requirement.
4. [ios-swiftui] InsightsSummaryView init missing `emptyStateText` parameter — needed for "No entries this [period]" text. **Fixed:** Task 2.10 updated with full init signature including `emptyStateText: String`.
5. [architecture] `fetchCategories()` needs `guard !Task.isCancelled` after await — third await in performLoad() was missing cancellation guard. **Fixed:** Task 1.4 updated with explicit guard requirement.
6. [architecture] FilteredFeedView `.task` has no error handling — `try await` without catch silences errors. **Fixed:** Task 4.3 updated with `catch` block + `@State errorMessage`.
7. [architecture] FilteredFeedView needs FeedRowView dependencies (category, isCurrentUser, partnerInitials) — Task 4.4 reuses FeedRowView but spec omitted required init parameters. **Fixed:** Task 4.2 updated with `categories: [CategoryData]` parameter, Task 4.4 updated with category lookup and user attribution.

**WARNINGs addressed in story spec:**
1. [architecture] `currentPeriodInterval` should be `private(set)` — **Fixed:** Task 6.1 updated.
2. [architecture] `categoriesToReturn` already exists on MockCategoryRepository — **Fixed:** Task 7.9 clarified to populate existing field, not create new one.
3. [architecture] FilteredFeedView needs repository DI via init parameter — **Fixed:** Task 4.2 updated with `repository: ExpenseRepositoryProtocol = ExpenseRepository()`.
4. [cloudkit-sync] FilteredFeedView has no remote-change subscription — stale data while viewing filtered feed. **Accepted for v1:** Read-only view, data refreshes on return to Insights. Task 4.7 documents this trade-off.
5. [architecture] `selectedCategoryID` on ViewModel is navigation state — acceptable per simple-app exception (architecture.md line 62). It's item-driven push navigation, not a full NavigationPath.

**WARNINGs noted (by design):**
6. [architecture] Categories fetched per performLoad() call — acceptable overhead for small dataset, guarantees freshness after remote changes. Local `[UUID: CategoryData]` dictionary is per-invocation, not stored.
7. [cloudkit-sync] `fetchCategories()` cancellation guard — **Fixed** (promoted from WARNING to part of CRITICAL #5 fix).

**SUGGESTIONs noted:**
- Add learnings entry for `chartAngleSelection` binding type must match `PlottableValue` type — record during implementation.
- Verify `chart.angle(at:)` and `chart.selectAngleValue(at:)` API signatures in Xcode before implementing Task 3.3.
- `InsightsSummaryView.onSliceTapped` closure spelled out as `(UUID) -> Void` in Task 2.10.

**Architecture guardian:** All clear. MVVM boundaries correct. DI pattern follows established convention. ChartSlice nested in ViewModel (consistent with CategoryTotal). State modeling correct. @Bindable syntax documented.

**iOS/SwiftUI guardian:** All clear after CRITICAL fixes. SectorMark API correct for iOS 17+. chartForegroundStyleScale maps categories to asset catalog colors. Empty donut outline pattern correct. ScrollView containment preserved. Accessibility labels use Int64.displayAmount.

**CloudKit sync guardian:** All clear. Existing `invalidateAndReload()` path covers chart data refresh. No additional subscriptions needed. Categories sync via NSPersistentCloudKitContainer + automaticallyMergesChangesFromParent. No race conditions in sequential @MainActor awaits.

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

- Build: zero errors, zero warnings
- Test: 134 tests, 0 failures (125 pre-existing + 9 new)
- CoreData entity uniqueness warnings in test context are pre-existing, not related to this story

### Completion Notes List

- Task 1+6: Extended InsightsViewModel with ChartSlice struct, chartSlices, selectedCategoryID, currentPeriodInterval, fetchedCategories, chartAccessibilityLabel computed property, selectCategory() method. Added fetchCategories() call in performLoad() with cancellation guard. Error path clears all new state.
- Task 2+3: Created InsightsSummaryView as pure presentation component. HStack layout with 120pt donut chart (SectorMark, golden ratio inner radius, angularInset, cornerRadius) and headline text group. chartForegroundStyleScale maps to asset catalog colors. chartAngleSelection + SpatialTapGesture workaround for tap interaction. Empty state shows gray donut outline. Per-slice accessibility labels + chart-level summary.
- Task 4: Created FilteredFeedView — lightweight read-only list with @State + .task. Reuses FeedRowView. Receives categories array from ViewModel (avoids redundant fetch). Error handling with catch block. currentUserID passed as init param.
- Task 5: Rewired InsightsView — replaced placeholder with InsightsSummaryView in both empty and populated states. Used Bindable(viewModel).selectedCategoryID for navigationDestination. Empty state uses containerRelativeFrame for centering. Added static authService for currentUserID access.
- Task 7: Added 9 unit tests covering chartSlices population, sort order, empty state, error clearing, accessibility label content, selectCategory, currentPeriodInterval. All use MockCategoryRepository.categoriesToReturn for category resolution.
- Task 8: Registered InsightsSummaryView.swift and FilteredFeedView.swift in project.pbxproj (build files, file references, group children, source build phase).
- Task 9: Build succeeded (0 errors, 0 warnings). Full test suite: 134 tests, 0 failures.

### Orchestrator Findings (Pre-Review Validation)

**CRITICAL (resolved):**
1. [architecture+cloudkit] Orphaned `AuthenticationService` instance in `InsightsView` — fixed by injecting `AuthenticationServiceProtocol` into `InsightsViewModel` and exposing `currentUserID` computed property. Removed static instance from view.
2. [architecture] Missing `guard !Task.isCancelled` in `FilteredFeedView.task` — added after `await` and in `catch` block.

**WARNING (noted):**
- Test `Date()` race: fixed by capturing `let now = Date()` once in test assertions.
- `subscribeToRemoteChanges()` + `loadData()` race on first appear — pre-existing from Story 3-1, `Task.isCancelled` guards prevent stale writes.
- FilteredFeedView stale data during remote changes — documented v1 trade-off (read-only view).

### Change Log

- 2026-04-04: Implemented Story 3-2 — category donut chart with tap-to-filter navigation
- 2026-04-04: Resolved orchestrator CRITICAL findings: AuthenticationService DI, Task.isCancelled guards

### File List

| Action | File |
|--------|------|
| Created | `CashOut/Views/Insights/InsightsSummaryView.swift` |
| Created | `CashOut/Views/Insights/FilteredFeedView.swift` |
| Modified | `CashOut/ViewModels/InsightsViewModel.swift` |
| Modified | `CashOut/Views/Insights/InsightsView.swift` |
| Modified | `CashOut.xcodeproj/project.pbxproj` |
| Modified | `CashOutTests/ViewModels/InsightsViewModelTests.swift` |
