# Story 3.3: Daily Bar Chart & Category Breakdown List

Status: review

## Story

As a user,
I want a bar chart showing daily spending patterns and a detailed category breakdown,
So that I can identify spending trends and see per-category totals.

## Acceptance Criteria

1. **Given** the Insights screen below the donut **When** data exists for the selected period **Then** a bar chart (`BarMark` via Swift Charts) shows daily totals for the Day view, daily totals (Mon–Sun) for the Week view, and weekly totals for the Month view (UX-DR22)

2. **Given** the bar chart **When** rendered **Then** the Y-axis adjusts dynamically so the largest value fills the chart — no fixed thresholds, no red budget ceiling lines

3. **Given** the category breakdown **When** displayed below the bar chart **Then** each row shows: category colored icon, category name, amount with `.monospacedDigit()`, and a proportion bar indicating percentage of total (FR17)

4. **Given** a category breakdown row **When** tapped **Then** the view navigates to a filtered feed showing only entries for that category (same as tapping a donut slice) (UX-DR22)

5. **Given** the Insights screen **When** the user scrolls down through charts and breakdown **Then** the tab bar auto-minimizes via `.tabBarMinimizeBehavior(.onScrollDown)` (UX-DR13)

6. **Given** the Insights screen **When** a filtered feed is showing **Then** a system back button (from `NavigationStack`) returns to the full Insights view

7. **Given** VoiceOver is enabled **When** the bar chart is focused **Then** it announces daily/weekly totals as text summaries (UX-DR16)

8. **Given** VoiceOver is enabled **When** a category breakdown row is focused **Then** it announces "[category name], [amount], [percentage] of total"

## Tasks / Subtasks

- [x] Task 1: Extend `InsightsViewModel` with bar chart data (AC: #1, #2, #7)
  - [x] 1.1 Add nested `struct BarEntry: Identifiable, Sendable` with fields: `label: String`, `total: Int64`, `var id: String { label }`. Labels are unique within any single period (e.g., "Mon"–"Sun" for weekly; "W1"–"W5" for monthly; "Today" for daily).
  - [x] 1.2 Add state property: `var barEntries: [BarEntry] = []`
  - [x] 1.3 Add computed property: `var barChartAccessibilityLabel: String` — joins `barEntries` as "[label]: [amount]" per entry, separated by ". ". Return "No spending data" when empty.
  - [x] 1.4 In `performLoad()`, after computing `chartSlices`, add: `barEntries = computeBarEntries(from: currentExpenses, period: period, interval: currentInterval)`. Place **before** the `loadedPeriod = period` assignment.
  - [x] 1.5 Create private helper `func computeBarEntries(from expenses: [ExpenseData], period: TimePeriod, interval: DateInterval) -> [BarEntry]`:
    - **`.daily`**: Return a single `BarEntry(label: "Today", total: expenses.reduce(Int64(0)) { $0 + $1.amount })`. (The daily view shows one bar for today's total. The donut chart and category breakdown provide the detail.)
    - **`.weekly`**: Create a `DateFormatter` with `dateFormat = "EEE"` and **`locale = Locale(identifier: "en_US_POSIX")`** (ensures English "Mon"–"Sun" labels regardless of device locale — Thai devices would otherwise produce Thai-script abbreviations). Iterate through each day in the `interval` (from `interval.start`, adding `.day` until `>= interval.end`). For each day, sum expenses where `Calendar.current.isDate(expense.createdAt, inSameDayAs: date)`. Return `[BarEntry]` in chronological order (7 entries, zero-fill for days without expenses).
    - **`.monthly`**: Use day-stepping iteration (same structure as weekly branch): iterate from `interval.start` through each day of the month. For each expense, compute `Calendar.current.component(.weekOfMonth, from: expense.createdAt)` and group into a `var weeklyTotals: [Int: Int64] = [:]` dictionary with `weeklyTotals[weekNum, default: 0] += expense.amount`. Use `guard let range = Calendar.current.range(of: .weekOfMonth, in: .month, for: interval.start) else { return [] }` — **do NOT force-unwrap** (`Calendar.range()` returns nil on non-Gregorian calendars; Buddhist calendar is common on Thai devices). Generate entries for each week in the range: labels "W1", "W2", …, "W5". Return in order, zero-fill for weeks without expenses.
  - [x] 1.6 In the `catch` block of `performLoad()`, add `barEntries = []` alongside the other state resets. **Place it after the existing `guard !Task.isCancelled else { return }` check** — that guard must remain the first line of the catch block per architecture learnings.

- [x] Task 2: Create `DailyBarChartView` (AC: #1, #2, #7)
  - [x] 2.1 Create file `CashOut/Views/Insights/DailyBarChartView.swift` — `import SwiftUI; import Charts`
  - [x] 2.2 Pure presentation sub-view: `struct DailyBarChartView: View`. Init parameters: `entries: [InsightsViewModel.BarEntry]`, `accessibilityLabel: String`.
  - [x] 2.3 Body: `Chart { ForEach(entries) { entry in BarMark(x: .value("Period", entry.label), y: .value("Amount", entry.total)).foregroundStyle(Color.accentColor.opacity(0.7)).cornerRadius(4) } }`
  - [x] 2.4 Lock X-axis order to array order: `.chartXScale(domain: entries.map(\.label))` — prevents alphabetical resorting. **Fallback if ordering breaks during testing:** Switch to index-based x-values with `ForEach(Array(entries.enumerated()), id: \.element.id)` using `BarMark(x: .value("Period", index), ...)` and `.chartXAxis { AxisMarks(values: Array(0..<entries.count)) { value in AxisValueLabel { Text(entries[value.index].label) } } }` for guaranteed chronological order.
  - [x] 2.5 Y-axis: do NOT set `.chartYScale(domain:)` — let Swift Charts auto-scale so the largest value fills the chart (AC #2). Hide Y-axis labels for cleaner look: `.chartYAxis(.hidden)`.
  - [x] 2.6 Chart frame: `.frame(height: 140)` — compact but readable. Full available width (no fixed width constraint).
  - [x] 2.7 Padding: `.padding(.horizontal, Spacing.md)` — match InsightsSummaryView alignment.
  - [x] 2.8 Accessibility: `.accessibilityLabel(accessibilityLabel)` on the `Chart` view. Individual bars get `.accessibilityLabel(entry.label)` + `.accessibilityValue(entry.total.displayAmount)`.
  - [x] 2.9 Empty state: when `entries.isEmpty`, render nothing (`EmptyView()`). The parent view already handles the full empty state via `InsightsSummaryView`.
  - [x] 2.10 No legend needed: `.chartLegend(.hidden)` — bars are single-color, not per-category.

- [x] Task 3: Create `CategoryBreakdownView` (AC: #3, #4, #8)
  - [x] 3.1 Create file `CashOut/Views/Insights/CategoryBreakdownView.swift` — `import SwiftUI`
  - [x] 3.2 Pure presentation sub-view: `struct CategoryBreakdownView: View`. Init parameters: `slices: [InsightsViewModel.ChartSlice]`, `totalAmount: Int64`, `onCategoryTapped: (UUID) -> Void`.
  - [x] 3.3 Body: `VStack(spacing: Spacing.sm)` containing `ForEach(slices)` rows. Do NOT use `List` — the view is inside a `ScrollView` (nested `List` in `ScrollView` causes layout issues). Use plain `VStack` + `ForEach`.
  - [x] 3.4 Each row layout: `Button { onCategoryTapped(slice.categoryID) } label: { HStack(spacing: Spacing.sm) { categoryIcon, categoryName, Spacer(), amountText, proportionBar } }`. Use `.buttonStyle(.plain)` to prevent the default button highlight overriding the category colors.
  - [x] 3.5 Category icon: `Image(systemName: iconName)` in a colored circle (28×28pt) using `Color(slice.colorName)` — match `FeedRowView` icon badge pattern. Resolve `iconName` from the `slices` data. **Note:** `ChartSlice` currently has `colorName` but NOT `iconName`. Either:
    - (A) Add `iconName: String` to `ChartSlice` struct and populate during `performLoad()` from the `categoryMap`, OR
    - (B) Pass `fetchedCategories: [CategoryData]` to the view and look up icons there.
    - **Choose option (A)** — keeps the view pure and avoids extra lookups. Add `iconName` to `ChartSlice`.
  - [x] 3.6 Category name: `Text(slice.categoryName)` with `.font(.subheadline)`.
  - [x] 3.7 Amount text: `Text(slice.total.displayAmount)` with `.font(.subheadline)`, `.monospacedDigit()`.
  - [x] 3.8 Proportion bar: Below the HStack text row, show a horizontal bar that fills a proportion of available width. **CRITICAL: Guard division by zero explicitly** — `totalAmount == 0` produces NaN which cascades to layout errors. Implementation:
    ```swift
    let proportion = totalAmount > 0 ? Double(slice.total) / Double(totalAmount) : 0.0

    GeometryReader { geometry in
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(slice.colorName))
            .frame(width: max(geometry.size.width * proportion, 2))
    }
    .frame(height: 4)
    ```
    Use `max(..., 2)` to ensure even tiny percentages are visible. The `totalAmount > 0` guard prevents NaN (populated state guarantees non-zero, but guard makes it safe regardless).
  - [x] 3.9 Proportion bar can be either inline (right side of HStack) or below the row. Choose **below the text row** for cleaner layout with Dynamic Type. Wrap each row in a `VStack(alignment: .leading, spacing: Spacing.xs)`.
  - [x] 3.10 Per-row accessibility: `.accessibilityElement(children: .combine)` on the row container. Override with `.accessibilityLabel("\(slice.categoryName), \(slice.total.displayAmount), \(percentageString) of total")` where `percentageString` = `"\(Int(proportion * 100))%"`.
  - [x] 3.11 Outer padding: `.padding(.horizontal, Spacing.md)` to match chart alignment.
  - [x] 3.12 Empty state: when `slices.isEmpty`, render `EmptyView()`.

- [x] Task 4: Add `iconName` to `ChartSlice` (AC: #3)
  - [x] 4.1 In `InsightsViewModel.swift`, add `iconName: String` to `struct ChartSlice`. Update the struct definition.
  - [x] 4.2 In `performLoad()` where `chartSlices` are built, populate `iconName: category?.iconName ?? "ellipsis.circle.fill"` from the `categoryMap` lookup.
  - [x] 4.3 Verify no compile errors in `InsightsSummaryView.swift` — it creates `ChartSlice` references but only reads `.categoryName`, `.colorName`, `.total`. The new field doesn't break existing code; `InsightsSummaryView` doesn't use it.

- [x] Task 5: Wire views into `InsightsView` (AC: #1, #3, #4, #5, #6)
  - [x] 5.1 In `InsightsView.swift`, replace the `// Placeholder for bar chart and category breakdown (Story 3-3)` comment (line 54) with:
    ```swift
    DailyBarChartView(
        entries: viewModel.barEntries,
        accessibilityLabel: viewModel.barChartAccessibilityLabel
    )

    CategoryBreakdownView(
        slices: viewModel.chartSlices,
        totalAmount: viewModel.totalAmount,
        onCategoryTapped: { categoryID in
            viewModel.selectCategory(categoryID)
        }
    )
    ```
  - [x] 5.2 Both views are inside the existing `VStack(spacing: Spacing.md)` within the populated state, after `InsightsSummaryView`. The navigation destination (line 58-66) already handles `selectedCategoryID` → `FilteredFeedView` — no changes needed for category breakdown taps (same flow as donut slice taps).
  - [x] 5.3 No changes to empty state — bar chart and breakdown are only rendered in the populated branch.
  - [x] 5.4 `import Charts` is NOT needed in `InsightsView.swift` — Charts import stays in `DailyBarChartView.swift` only.
  - [x] 5.5 Tab bar auto-minimize (AC #5): already handled by `.tabBarMinimizeBehavior(.onScrollDown)` on the `TabView` in `ContentView.swift`. The `ScrollView` in `InsightsView` provides the scrollable content. No additional work needed.
  - [x] 5.6 System back button (AC #6): already handled by `NavigationStack` in `ContentView.swift:18` wrapping `InsightsView`. `FilteredFeedView` is pushed via `.navigationDestination`. No additional work needed.

- [x] Task 6: Write unit tests for bar entry computation (AC: #1)
  - [x] 6.1 In `InsightsViewModelTests.swift`, add tests for `barEntries` after `loadData()`:
  - [x] 6.2 Test: `testBarEntriesPopulatedAfterLoadData` — load with expenses, verify `barEntries` is non-empty.
  - [x] 6.3 Test: `testBarEntriesAllZeroTotalWhenNoExpenses` — load with empty stub, verify `barEntries` entries all have `total == 0`. For `.weekly`, `barEntries.count == 7` (all zero). For `.daily`, `barEntries.count == 1` with `total == 0`. For `.monthly`, entries for each week in the month (all zero).
  - [x] 6.4 Test: `testBarEntriesForWeeklyPeriodHasSevenEntries` — set period to `.weekly`, load with expenses, verify `barEntries.count == 7`.
  - [x] 6.5 Test: `testBarEntriesForDailyPeriodHasOneEntry` — set period to `.daily`, load, verify `barEntries.count == 1` and label is "Today".
  - [x] 6.6 Test: `testBarEntriesForMonthlyPeriodHasCorrectWeekCount` — set period to `.monthly`, load, verify `barEntries.count` matches weeks in current month.
  - [x] 6.7 Test: `testBarEntriesClearedOnError` — load successfully, then error, verify `barEntries.isEmpty`.
  - [x] 6.8 Test: `testBarChartAccessibilityLabelContainsEntryLabels` — load with data, verify accessibility label contains entry labels and amounts.
  - [x] 6.9 Test: `testChartSliceIncludesIconName` — verify `chartSlices` have correct `iconName` from category data.

- [x] Task 7: Register new files in Xcode project (AC: all)
  - [x] 7.1 Add `DailyBarChartView.swift` to CashOut target in `project.pbxproj`
  - [x] 7.2 Add `CategoryBreakdownView.swift` to CashOut target in `project.pbxproj`

- [x] Task 8: Verify build and test suite (AC: all)
  - [x] 8.1 Build the project — verify zero errors, zero warnings
  - [x] 8.2 Run full test suite — verify all 134 existing tests pass plus ~8 new tests
  - [ ] 8.3 Manual verification: bar chart displays with correct bars for each period
  - [ ] 8.4 Manual verification: category breakdown rows show colored icons, amounts, proportion bars
  - [ ] 8.5 Manual verification: tapping a breakdown row navigates to filtered feed
  - [ ] 8.6 Manual verification: scrolling down minimizes the tab bar
  - [ ] 8.7 Manual verification: VoiceOver announces bar chart totals and breakdown row details

## Dev Notes

### New Files (2)

| File | Location | Purpose |
|------|----------|---------|
| `DailyBarChartView.swift` | `CashOut/Views/Insights/` | **Create** — Bar chart (`BarMark`) showing period-appropriate temporal aggregation |
| `CategoryBreakdownView.swift` | `CashOut/Views/Insights/` | **Create** — Category list with colored icons, amounts, and proportion bars |

### Modified Files (3)

| File | Location | Action |
|------|----------|--------|
| `InsightsViewModel.swift` | `CashOut/ViewModels/` | **Modify** — add `BarEntry` struct, `barEntries`, `barChartAccessibilityLabel`, `computeBarEntries()`, add `iconName` to `ChartSlice` |
| `InsightsView.swift` | `CashOut/Views/Insights/` | **Modify** — replace placeholder with `DailyBarChartView` + `CategoryBreakdownView` |
| `project.pbxproj` | `CashOut.xcodeproj/` | **Modify** — register 2 new files |

### Test Files (1 modified)

| File | Location | Action |
|------|----------|--------|
| `InsightsViewModelTests.swift` | `CashOutTests/ViewModels/` | **Modify** — add ~8 tests for bar entry computation, iconName on ChartSlice |

### Architecture: DailyBarChartView & CategoryBreakdownView as Presentation Components

Both new views are **sub-views** (not screens), so they do NOT have their own ViewModels. Per architecture rule: "One ViewModel per screen (not per component)." They receive all data via init parameters and communicate taps via closure callbacks.

The ownership chain is:
```
InsightsView (@State viewModel: InsightsViewModel)
  ├── InsightsSummaryView (donut + headline — Story 3-2, done)
  ├── DailyBarChartView (entries + accessibilityLabel — this story)
  ├── CategoryBreakdownView (slices + totalAmount + onCategoryTapped — this story)
  └── .navigationDestination → FilteredFeedView (already wired, Story 3-2)
```

[Source: architecture.md line 389 — "One ViewModel per screen (not per component)"]
[Source: architecture.md line 842 — `DailyBarChartView.swift` # Bar chart (BarMark)]
[Source: architecture.md line 843 — `CategoryBreakdownView.swift` # Category list with proportion bars]

### Swift Charts BarMark API

`BarMark` (iOS 17+, `import Charts`) creates bar charts:

```swift
BarMark(
    x: .value("Period", entry.label),
    y: .value("Amount", entry.total)
)
.foregroundStyle(Color.accentColor.opacity(0.7))
.cornerRadius(4)
```

- Use `.chartXScale(domain: entries.map(\.label))` to enforce chronological order (prevents alphabetical sorting of String x-values)
- Do NOT set `.chartYScale(domain:)` — let Swift Charts auto-scale for dynamic Y-axis (AC #2)
- `.chartYAxis(.hidden)` — cleaner look; exact amounts shown in the category breakdown below
- `.chartLegend(.hidden)` — bars are single-color, not per-category

[Source: architecture.md line 31 — "Swift Charts (SectorMark, BarMark)"]

### Bar Chart Data Model

The `BarEntry` struct is minimal:
```swift
struct BarEntry: Identifiable, Sendable {
    let label: String   // "Mon"–"Sun" | "W1"–"W5" | "Today"
    let total: Int64
    var id: String { label }
}
```

Aggregation per period:
- **Daily**: 1 bar — today's total (single `BarEntry(label: "Today", total: sum)`)
- **Weekly**: 7 bars — one per day (Mon–Sun), zero-filled for days without expenses
- **Monthly**: 4–5 bars — one per week (W1–W5), zero-filled for weeks without expenses

The aggregation uses in-memory grouping from the already-fetched `currentExpenses` array (same fetch used for donut/category totals). No additional repository calls needed.

[Source: architecture.md line 536-540 — "single NSFetchRequest + in-memory aggregation in Swift"]

### Category Breakdown — Row Layout

Each row uses a two-line layout for Dynamic Type support:

```
┌─────────────────────────────────────────┐
│ [🍽] Food & Drink              ฿120.00  │
│ ████████████████░░░░░░░░░░░  60%        │
├─────────────────────────────────────────┤
│ [🚗] Transport                  ฿40.00  │
│ ██████░░░░░░░░░░░░░░░░░░░░░  20%        │
└─────────────────────────────────────────┘
```

- Top line: `HStack` with icon badge (28×28pt colored circle), category name (.subheadline), Spacer, amount (.subheadline .monospacedDigit)
- Bottom line: proportion bar (`GeometryReader` + `RoundedRectangle`, height 4pt) colored with category color
- Wrapped in `Button(.plain)` for tap handling
- Each row is a `VStack(alignment: .leading, spacing: Spacing.xs)`

[Source: ux-design-specification.md line 539 — "Category breakdown list with colored icons and proportion bars"]
[Source: FeedRowView.swift — icon badge pattern (28×28pt colored circle)]

### Category Breakdown — Proportion Bar

The proportion bar fills proportionally with an explicit division-by-zero guard:

```swift
let proportion = totalAmount > 0 ? Double(slice.total) / Double(totalAmount) : 0.0

GeometryReader { geometry in
    RoundedRectangle(cornerRadius: 2)
        .fill(Color(slice.colorName))
        .frame(width: max(geometry.size.width * proportion, 2))
}
.frame(height: 4)
```

Use `max(..., 2)` to ensure tiny percentages remain visible. The `totalAmount > 0` guard prevents NaN from cascading to layout errors.

### Navigation — Category Breakdown Tap → Filtered Feed

The tap flow is identical to donut slice taps (Story 3-2):

1. User taps breakdown row → `onCategoryTapped(slice.categoryID)` fires
2. `InsightsView` calls `viewModel.selectCategory(categoryID)` → sets `selectedCategoryID`
3. `.navigationDestination(item: Bindable(viewModel).selectedCategoryID)` pushes `FilteredFeedView`
4. System back button returns to full Insights view

No new navigation infrastructure needed — all wiring exists from Story 3-2.

[Source: InsightsView.swift:58-66 — existing navigationDestination]
[Source: ContentView.swift:18 — NavigationStack wraps InsightsView]

### Tab Bar Auto-Minimize (AC #5)

`.tabBarMinimizeBehavior(.onScrollDown)` is already applied on the `TabView` in `ContentView.swift`. The `ScrollView` in `InsightsView` provides the scrollable content target. With the new bar chart and breakdown list adding vertical content, the ScrollView will have enough content to trigger the minimize behavior. No additional work needed.

[Source: architecture.md line 680 — ".tabBarMinimizeBehavior(.onScrollDown) applied on TabView"]
[Source: ContentView.swift — TabView modifier]

### VoiceOver Accessibility (AC #7, #8)

**Bar chart (AC #7):**
- Chart-level: `.accessibilityLabel(barChartAccessibilityLabel)` — e.g., "Mon: ฿50.00. Tue: ฿120.00. Wed: ฿0.00. ..."
- Per-bar: `.accessibilityLabel(entry.label)` + `.accessibilityValue(entry.total.displayAmount)`

**Category breakdown (AC #8):**
- Per-row: `.accessibilityElement(children: .combine)` + `.accessibilityLabel("\(name), \(amount), \(percentage)% of total")`

Use `Int64.displayAmount` for all amounts — never concatenate "฿" manually.

[Source: ux-design-specification.md line 511-515 — "Bar chart announces daily totals"]

### Adding `iconName` to `ChartSlice`

`ChartSlice` currently has `categoryID`, `categoryName`, `colorName`, `total`. The category breakdown needs `iconName` for the icon badge. Add `iconName: String` to the struct and populate from `categoryMap` during `performLoad()`:

```swift
struct ChartSlice: Identifiable, Sendable {
    let categoryID: UUID
    let categoryName: String
    let colorName: String
    let iconName: String      // NEW
    let total: Int64
    var id: UUID { categoryID }
}
```

In `performLoad()`:
```swift
return ChartSlice(
    categoryID: ct.categoryID,
    categoryName: category?.name ?? "Unknown",
    colorName: category?.colorName ?? "CoolGray",
    iconName: category?.iconName ?? "ellipsis.circle.fill",  // NEW
    total: ct.total
)
```

`InsightsSummaryView` reads `categoryName`, `colorName`, `total` — it doesn't use `iconName`, so no changes needed there.

### ScrollView Content Order

After Story 3-3, the populated state ScrollView content is:
```
VStack(spacing: Spacing.md) {
    InsightsSummaryView(...)        // Donut chart + headline (Story 3-2)
    DailyBarChartView(...)          // Bar chart (this story)
    CategoryBreakdownView(...)     // Category breakdown list (this story)
}
```

All three are inside the `ScrollView` in the `else` (populated) branch. The empty state branch remains unchanged (just `InsightsSummaryView` with empty slices).

### Existing Code Patterns to Follow

- **ViewModel DI**: `init(repository:categoryRepository:authService:)` — established [Source: InsightsViewModel.swift:119-127]
- **Error handling**: `guard !Task.isCancelled` after every await [Source: .claude/learnings/architecture.md]
- **Currency display**: Always `Int64.displayAmount` — never concatenate "฿" manually [Source: Int64+Currency.swift]
- **Sub-views in feature folder**: Both new files go in `CashOut/Views/Insights/` [Source: architecture.md line 839-843]
- **ViewModel never imports SwiftUI**: Bar entry computation in ViewModel; `Chart`/`BarMark` rendering in View [Source: .claude/learnings/architecture.md]
- **Test class pattern**: `@MainActor final class` with `makeSUT()` [Source: InsightsViewModelTests.swift:5-28]
- **Button in VStack**: Use `Button { } label: { }` + `.buttonStyle(.plain)` for tappable rows — `.onTapGesture` conflicts with other gestures [Source: .claude/learnings/ios-swiftui.md line 17]
- **Dictionary safety**: `Dictionary(uniquingKeysWith: { _, last in last })` — never `uniqueKeysWithValues:` [Source: .claude/learnings/architecture.md line 60]
- **State clearing on error**: Insights screens clear ALL state on error — stale totals are misleading [Source: .claude/learnings/architecture.md line 55]

### Boundaries — What NOT to Implement

- **No changes to `InsightsSummaryView`** — donut chart done (Story 3-2), untouched
- **No changes to `FilteredFeedView`** — reuse as-is for category tap navigation
- **No changes to `ContentView`** — TabView and NavigationStack already wired
- **No changes to `ExpenseRepository`** — `fetchExpenses(for:)` already provides the data
- **No changes to `CategoryRepository`** — `fetchCategories()` already provides category metadata
- **No new ViewModel** — DailyBarChartView and CategoryBreakdownView are pure sub-views
- **No `FetchedResultsController`** — Insights uses remote change notification + re-fetch pattern
- **No custom animations** — "No custom animations in v1" per UX spec
- **No loading states** — data is always instant (local-first)
- **No Combine publishers** — use `@Observable` + `async/await` only
- **No changes to `.task` modifiers** — existing `.task(id:)` + `.task` pattern handles data loading and remote change subscription
- **No edit/delete on CategoryBreakdownView** — read-only navigation to filtered feed

### Previous Story Intelligence

**From Story 3-2 (Category Donut Chart — last completed story in Epic 3):**
- 134 tests passing (125 pre-existing + 9 new)
- `InsightsViewModel` extended with: `ChartSlice`, `chartSlices`, `selectedCategoryID`, `currentPeriodInterval`, `fetchedCategories`, `chartAccessibilityLabel`, `selectCategory()`, `currentUserID`
- `InsightsSummaryView` created as pure presentation component with donut chart (SectorMark)
- `FilteredFeedView` created with category-filtered expense list — reusable for breakdown taps
- Navigation: `Bindable(viewModel).selectedCategoryID` with `.navigationDestination(item:)` — pattern established
- `chartAngleSelection` binding type must match `PlottableValue` type (e.g., `Int64?`) — same principle applies to `BarMark` selection if added
- `Dictionary(uniquingKeysWith:)` used instead of `uniqueKeysWithValues:` — prevents crash on duplicate keys
- Empty state: `InsightsSummaryView` with empty slices + `.containerRelativeFrame(.vertical)` — MUST stay inside ScrollView
- Commit prefix: `feat(insights):` for Epic 3

**Code Review Deferred Items (from Stories 3-1, 3-2):**
- D1: Default `AuthenticationService()` in ViewModel init — established DI pattern, pre-existing
- D2: Duplicate `categoryName` values break `chartForegroundStyleScale` domain — deferred to Epic 5
- D3: "This day total:" awkward VoiceOver phrasing — pre-existing, deferred

### Git Intelligence

Recent commits:
- `0ca108a fix(insights): resolve 4 code review findings for story 3-2`
- `b1b76e9 feat(insights): add category donut chart with tap-to-filter navigation (story 3-2)`
- `2b58439 fix(insights): resolve 6 code review findings for story 3-1`
- `1b34cc0 feat(insights): add insights screen with time period switching (story 3-1)`

Suggested commit: `feat(insights): add daily bar chart and category breakdown list (story 3-3)`

### Project Structure Notes

- `DailyBarChartView.swift` → `CashOut/Views/Insights/` — matches architecture directory tree [Source: architecture.md line 842]
- `CategoryBreakdownView.swift` → `CashOut/Views/Insights/` — matches architecture directory tree [Source: architecture.md line 843]
- No new ViewModels needed (InsightsViewModel extended, new views are pure sub-views)
- No detected conflicts with existing project structure

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Story 3.3 acceptance criteria (line 663-704)]
- [Source: _bmad-output/planning-artifacts/architecture.md line 31 — Swift Charts (SectorMark, BarMark)]
- [Source: _bmad-output/planning-artifacts/architecture.md line 389 — One ViewModel per screen]
- [Source: _bmad-output/planning-artifacts/architecture.md line 536-540 — Insights Aggregation Strategy]
- [Source: _bmad-output/planning-artifacts/architecture.md line 542-577 — DI Pattern]
- [Source: _bmad-output/planning-artifacts/architecture.md line 645-680 — Navigation Pattern]
- [Source: _bmad-output/planning-artifacts/architecture.md line 680 — tabBarMinimizeBehavior on TabView]
- [Source: _bmad-output/planning-artifacts/architecture.md line 839-843 — Insights directory structure]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md line 177 — Tab bar auto-minimize]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md line 251 — Chart Swift Charts]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md line 496 — Insights vertical scroll layout]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md line 511-515 — Bar chart accessibility]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md line 539-541 — Direction C: Combined Donut + Daily Bars]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md line 639 — Category breakdown with proportion bars]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md line 648-652 — Information by time period table]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md line 884-889 — Empty states]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md line 946 — Insights accessibility]
- [Source: _bmad-output/planning-artifacts/prd.md line 253-260 — FR13-FR18 Spending Insights]
- [Source: .claude/learnings/architecture.md — @ObservationIgnored, Task.isCancelled, guard patterns, Dictionary safety]
- [Source: .claude/learnings/ios-swiftui.md — .task re-fires, Button in VStack, Charts binding types]
- [Source: CashOut/ViewModels/InsightsViewModel.swift — existing ViewModel to extend]
- [Source: CashOut/Views/Insights/InsightsView.swift:54 — placeholder comment to replace]
- [Source: CashOut/Views/Insights/InsightsSummaryView.swift — reference for sub-view pattern]
- [Source: CashOut/Views/Insights/FilteredFeedView.swift — navigation target for category taps]
- [Source: CashOut/Views/Feed/FeedRowView.swift — icon badge pattern (28×28pt colored circle)]
- [Source: CashOut/Utilities/Extensions/Color+CategoryTokens.swift — CategoryColor enum]
- [Source: CashOut/Utilities/Constants.swift — Spacing enum (xs/sm/md/lg/xl)]
- [Source: CashOut/Utilities/Extensions/Int64+Currency.swift — displayAmount formatting]
- [Source: CashOut/Models/CategoryData.swift — CategoryData DTO (id, name, iconName, colorName)]
- [Source: CashOut/App/ContentView.swift:18 — NavigationStack wraps InsightsView]
- [Source: CashOutTests/ViewModels/InsightsViewModelTests.swift — existing test patterns]
- [Source: CashOutTests/Repositories/MockCategoryRepository.swift — mock with categoriesToReturn]
- [Source: _bmad-output/implementation-artifacts/3-1-insights-screen-with-time-period-switching.md — Story 3-1 intelligence]
- [Source: _bmad-output/implementation-artifacts/3-2-category-donut-chart.md — Story 3-2 intelligence]

### Orchestrator Validation (2026-04-04)

**Guardians run**: ios-swiftui-guardian, architecture-guardian, cloudkit-sync-guardian

**CRITICALs resolved in story spec:**
1. [ios-swiftui + architecture] Division-by-zero in proportion bar (Task 3.8) — `Double(slice.total) / Double(totalAmount)` produces NaN when `totalAmount == 0`, cascading to layout errors. **Fixed:** Task 3.8 now includes explicit `let proportion = totalAmount > 0 ? ... : 0.0` guard in code block.
2. [architecture] Force-unwrap crash on `Calendar.range(of: .weekOfMonth, in: .month, for:)!` — returns nil on non-Gregorian calendars (Buddhist calendar common on Thai devices). **Fixed:** Task 1.5 monthly logic now uses `guard let range = ... else { return [] }`.
3. [architecture] `DateFormatter` without pinned locale produces Thai-script day abbreviations on `th_TH` devices instead of "Mon"–"Sun". **Fixed:** Task 1.5 weekly logic now pins `locale = Locale(identifier: "en_US_POSIX")`.

**WARNINGs addressed in story spec:**
1. [ios-swiftui] `.chartXScale(domain:)` String ordering is undocumented behavior — may not guarantee chronological order. **Fixed:** Task 2.4 now includes index-based fallback approach if ordering breaks.
2. [architecture] Task 1.6 `barEntries = []` catch block placement — must come after existing `guard !Task.isCancelled` check. **Fixed:** Task 1.6 now explicitly documents guard must remain first line.
3. [architecture] Task 1.5 monthly iteration ambiguous — didn't specify day-stepping vs. week-stepping. **Fixed:** Task 1.5 now specifies day-stepping with `weekOfMonth` grouping and `[Int: Int64]` dictionary.
4. [architecture] Task 6.3 test description contradictory — said "1 for weekly" but weekly should be 7. **Fixed:** Renamed to `testBarEntriesAllZeroTotalWhenNoExpenses` with corrected description.
5. [cloudkit-sync] Verify `computeBarEntries()` takes only `expenses` parameter. **Verified:** Task 1.5 signature is `(expenses:period:interval:)` with no repository calls.

**WARNINGs noted (by design):**
6. [ios-swiftui] `GeometryReader` inside `VStack` in `ScrollView` may report zero-width on first layout pass — `max(..., 2)` minimum guard mitigates this known iOS quirk.
7. [cloudkit-sync] FilteredFeedView has no remote-change subscription — stale data while viewing. Accepted v1 trade-off from Story 3-2 (Task 4.7), unchanged.

**SUGGESTIONs noted:**
- Consider adding deferred-work.md entry for FilteredFeedView remote-change staleness (currently only in Story 3-2 spec).
- Note timezone sensitivity for cross-timezone households — `Calendar.current.isDate(_:inSameDayAs:)` uses device timezone. Acceptable for v1 (both users likely same timezone).
- Document `BarEntry.id` uniqueness contract (guaranteed by one-per-day/week iteration) with inline comment.

**Architecture guardian:** All clear. MVVM boundaries correct. Sub-view ownership follows "One ViewModel per screen" rule. DI pattern matches. State clearing on error includes new `barEntries`. No new repository calls. Dictionary patterns safe (`[key, default: 0] += amount`).

**iOS/SwiftUI guardian:** All clear after CRITICAL fixes. BarMark API correct for iOS 17+. Chart frame sizing valid inside ScrollView. VStack + ForEach avoids nested scrollable content issue. Button + `.buttonStyle(.plain)` is correct pattern. TabBar minimize behavior unchanged. Empty state preservation confirmed. Accessibility patterns valid.

**CloudKit sync guardian:** All clear. Remote change propagation chain correctly recomputes `barEntries` alongside existing outputs. No new subscriptions needed. Single `categoryRepository.fetchCategories()` call serves all uses including new `iconName`. No Core Data changes, no migration needed.

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

- Build succeeded with CODE_SIGNING_ALLOWED=NO (no provisioning profile on CLI)
- 143 tests passed (134 existing + 9 new), 0 failures
- Orchestrator review: 0 CRITICALs. Fixed DateFormatter allocation per guardian feedback (extracted to private static let). All WARNINGs are pre-existing patterns or acceptable trade-offs.

### Completion Notes List

- Task 1 + 4 combined: Extended `InsightsViewModel` with `BarEntry` struct, `barEntries` state, `barChartAccessibilityLabel` computed property, `computeBarEntries()` helper (daily/weekly/monthly aggregation), and added `iconName: String` to `ChartSlice`. Wired into `performLoad()` success and error paths. Weekly uses `en_US_POSIX` locale to prevent Thai-script labels. Monthly uses `guard let` on `Calendar.range()` for Buddhist calendar safety.
- Task 2: Created `DailyBarChartView` with `BarMark` chart, `.chartXScale(domain:)` for chronological ordering, auto-scaling Y-axis, `.chartYAxis(.hidden)`, per-bar and chart-level accessibility labels.
- Task 3: Created `CategoryBreakdownView` with category icon badges (28×28pt), proportion bars (`GeometryReader` + `RoundedRectangle`), division-by-zero guard, `Button` + `.buttonStyle(.plain)` for tap navigation, VoiceOver accessibility labels with percentage.
- Task 5: Replaced placeholder comment in `InsightsView` with `DailyBarChartView` + `CategoryBreakdownView`. Existing navigation destination and tab bar minimize behavior required no changes.
- Task 6: Added 9 unit tests covering bar entry population, zero-fill for all periods, error clearing, accessibility label, and `iconName` on `ChartSlice`.
- Task 7: Registered 2 new files in `project.pbxproj` (file refs, build files, group children, sources build phase).

### File List

- CashOut/ViewModels/InsightsViewModel.swift (modified)
- CashOut/Views/Insights/DailyBarChartView.swift (new)
- CashOut/Views/Insights/CategoryBreakdownView.swift (new)
- CashOut/Views/Insights/InsightsView.swift (modified)
- CashOut.xcodeproj/project.pbxproj (modified)
- CashOutTests/ViewModels/InsightsViewModelTests.swift (modified)

### Change Log

- 2026-04-04: Implemented Story 3-3 — daily bar chart and category breakdown list with 9 new tests (143 total passing)
