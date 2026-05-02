---
title: 'Insights Category Filter Toggle'
type: 'feature'
created: '2026-05-02'
status: 'done'
baseline_commit: '7e3fdfbb9ccf7fd8ada7673c9cc6a60360438566'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Insights always shows all categories in the chart and total, with no way to temporarily exclude categories the user wants to ignore for a given analysis session.

**Approach:** Add ephemeral per-session exclusion state to `InsightsViewModel`. Tapping a row in `CategoryBreakdownView` toggles its excluded state; excluded categories vanish from the donut chart and headline total. Chart slice tap retains existing drill-down navigation. All exclusions reset on every successful data load and on tab reappear.

## Boundaries & Constraints

**Always:**
- Exclusion state is ephemeral — never persisted, never synced via CloudKit
- `clearCategoryFilter()` resets on: every call to `applyLoadResults` AND every `InsightsView.onAppear`
- Breakdown list shows ALL categories (excluded + included) so user can re-include
- Chart shows only included (`visibleChartSlices`); chart slice tap navigates to FilteredFeedView (unchanged)
- Proportion bars on excluded rows render 0-width (proportion forced to `0.0`)
- `headlineText` and `comparisonText` derived consistently: `filteredTotalAmount`; `comparisonText` returns `nil` when filter active
- Fix pre-existing crash risk: remove `.animation(.easeInOut, value: viewModel.loadKey)` from ScrollView; replace with `.transition(.opacity)` on `InsightsSummaryView`
- Fix pre-existing crash risk: `.id()` on `InsightsSummaryView` must encode both `loadKey` and `excludedCategories.count`

**Ask First:**
- Any change to how `FilteredFeedView` drill-down is triggered from the chart

**Never:**
- `.disabled(true)` or `.allowsHitTesting(false)` on excluded rows — they must remain tappable
- Modifying `totalAmount` (unfiltered sum) — keep as-is for period comparison logic
- Adding filter state to `loadKey` (would trigger unnecessary data reloads)

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Tap included row | Row for category A, `excludedCategories = []` | A added to `excludedCategories`; chart redraws without A; headline drops A's total | N/A |
| Tap excluded row | Row for category A, `excludedCategories = [A]` | A removed from `excludedCategories`; chart re-includes A; headline rises | N/A |
| All categories excluded | User excludes every category | Chart shows empty donut; headline shows ฿0; breakdown shows all rows dimmed | N/A |
| Tab switch + return | Filter active, user switches tab and returns | `.onAppear` fires `clearCategoryFilter()`; all rows included, chart restored | N/A |
| Period change | Filter active, user taps Day/Week/Month | `applyLoadResults` fires `clearCategoryFilter()` before setting new data | N/A |
| Remote sync refresh | New expenses arrive, `invalidateAndReload()` triggers | `applyLoadResults` fires `clearCategoryFilter()` | N/A |
| Chart slice tap | Tap included slice in donut | Navigates to FilteredFeedView (unchanged behavior) | N/A |

</frozen-after-approval>

## Code Map

- `CashOut/ViewModels/InsightsViewModel.swift` — add filter state, computed slices, filtered total, reset logic
- `CashOut/Views/Insights/InsightsView.swift` — wire filter props, fix `.animation` crash, fix `.id` encoding, add `.onAppear` reset
- `CashOut/Views/Insights/CategoryBreakdownView.swift` — add excluded param, visual dimming, toggle callback, accessibility
- `CashOut/Views/Insights/InsightsSummaryView.swift` — receives pre-filtered slices; no structural change needed

## Tasks & Acceptance

**Execution:**
- [x] `CashOut/ViewModels/InsightsViewModel.swift` -- Add `var excludedCategories: Set<UUID> = []`; add `func toggleCategoryFilter(_ id: UUID)` (insert or remove); add `func clearCategoryFilter()` (guard `!excludedCategories.isEmpty`); add `var visibleChartSlices: [ChartSlice]` (computed, filters excluded); add `var filteredTotalAmount: Int64` (computed, sum of visibleChartSlices); update `headlineText` to `filteredTotalAmount.displayAmount`; update `comparisonText` to return `nil` when `!excludedCategories.isEmpty`; call `clearCategoryFilter()` at top of `applyLoadResults` -- ephemeral filter state with reactive computed properties; reset on every data load
- [x] `CashOut/Views/Insights/InsightsView.swift` -- Remove `.animation(.easeInOut(duration: 0.15), value: viewModel.loadKey)` from ScrollView; add `.transition(.opacity)` to `InsightsSummaryView`; change `InsightsSummaryView` `.id` to `"\(viewModel.loadKey)-\(viewModel.excludedCategories.count)"`; pass `viewModel.visibleChartSlices` as `slices` to `InsightsSummaryView` (chart renders only included); pass `viewModel.chartSlices` as `slices` and `viewModel.filteredTotalAmount` as `totalAmount` and `viewModel.excludedCategories` to `CategoryBreakdownView`; change `CategoryBreakdownView.onCategoryTapped` to `viewModel.toggleCategoryFilter`; add `.onAppear { viewModel.clearCategoryFilter() }` to view body -- fixes crash risk from Charts domain mutation; resets filter on tab return
- [x] `CashOut/Views/Insights/CategoryBreakdownView.swift` -- Replace `let onCategoryTapped: (UUID) -> Void` with `let onCategoryFilterToggled: (UUID) -> Void`; add `let excludedCategories: Set<UUID>`; inside `ForEach`, compute `let isExcluded = excludedCategories.contains(slice.categoryID)`; override proportion: `let proportion = isExcluded ? 0.0 : (totalAmount > 0 ? Double(slice.total) / Double(totalAmount) : 0.0)`; apply `.opacity(isExcluded ? 0.35 : 1.0)` to Button label content; update `.accessibilityLabel` to include excluded state; add `.accessibilityValue(isExcluded ? "excluded" : "included")`; add `.accessibilityHint(isExcluded ? "Double tap to include in chart" : "Double tap to exclude from chart")`; wire button action to `onCategoryFilterToggled` -- visual + accessible exclusion state, 0-width bar communicates exclusion

**Acceptance Criteria:**
- Given Insights is open with expenses, when user taps a category row in the breakdown list, then that category's slice disappears from the donut chart and the headline total decreases by that category's amount
- Given a category row is excluded (dimmed), when user taps it again, then the slice reappears in the donut chart and the headline total increases
- Given filter is active, when user taps a donut slice, then FilteredFeedView opens for that category (unchanged)
- Given filter is active on any period, when user switches to a different period tab, then all categories are re-included before new data renders
- Given filter is active, when user switches to another app tab and returns to Insights, then all categories are re-included
- Given all categories are excluded, when viewing Insights, then the donut chart shows an empty ring and headline shows ฿0
- Given comparisonText is visible, when any filter is active, then comparisonText is hidden (nil)

## Design Notes

`visibleChartSlices` and `filteredTotalAmount` are `@Observable` computed properties — they automatically track `chartSlices` and `excludedCategories` as dependencies. No `didSet` or manual invalidation needed.

The `.id("\(viewModel.loadKey)-\(viewModel.excludedCategories.count)")` key forces `InsightsSummaryView` to fully teardown and rebuild on every filter toggle. This is mandatory for Swift Charts: domain arrays (`chartForegroundStyleScale`) cannot be mutated in-place without risking `EXC_BREAKPOINT` in `ConcreteScale+Discrete.swift`.

## Verification

**Commands:**
- `xcodebuild -scheme CashOut -destination 'platform=iOS Simulator,name=iPhone 16' build` -- expected: BUILD SUCCEEDED, zero errors

**Manual checks (if no CLI):**
- Tap each category row in breakdown → row dims, chart slice disappears, total updates
- Tap dimmed row → row restores, chart slice reappears
- Switch period tab while filter active → all rows un-dimmed on new period render
- Switch to Feed tab and return to Insights → filter cleared
- Tap donut slice → FilteredFeedView opens (not a filter toggle)
- Enable VoiceOver → excluded row announces "excluded" value and hint

## Suggested Review Order

**Filter state model**

- Ephemeral `excludedCategories` stored property — root of all filter state
  [`InsightsViewModel.swift:103`](../../CashOut/ViewModels/InsightsViewModel.swift#L103)

- `visibleChartSlices` computed var — `@Observable` auto-tracks `chartSlices` + `excludedCategories`
  [`InsightsViewModel.swift:120`](../../CashOut/ViewModels/InsightsViewModel.swift#L120)

- `filteredTotalAmount` + `headlineText` — headline now reflects filtered spend
  [`InsightsViewModel.swift:124`](../../CashOut/ViewModels/InsightsViewModel.swift#L124)

- `toggleCategoryFilter` — insert-or-remove via `Set.insert(_:).inserted`
  [`InsightsViewModel.swift:282`](../../CashOut/ViewModels/InsightsViewModel.swift#L282)

- `clearCategoryFilter` — guarded no-op when set already empty
  [`InsightsViewModel.swift:288`](../../CashOut/ViewModels/InsightsViewModel.swift#L288)

**Reset paths**

- Reset in `applyLoadResults` — fires on every data load regardless of trigger path
  [`InsightsViewModel.swift:368`](../../CashOut/ViewModels/InsightsViewModel.swift#L368)

- `.onAppear` reset — fires on every tab return to Insights
  [`InsightsView.swift:117`](../../CashOut/Views/Insights/InsightsView.swift#L117)

**View wiring + Charts identity**

- Chart receives `visibleChartSlices` only; slice tap still navigates (unchanged)
  [`InsightsView.swift:62`](../../CashOut/Views/Insights/InsightsView.swift#L62)

- `.id` encodes actual visible slice UUIDs — forces Charts teardown on domain change
  [`InsightsView.swift:73`](../../CashOut/Views/Insights/InsightsView.swift#L73)

- Breakdown receives all `chartSlices` + `filteredTotalAmount` + `excludedCategories`
  [`InsightsView.swift:94`](../../CashOut/Views/Insights/InsightsView.swift#L94)

- `.animation` moved from ScrollView to inner VStack — scopes crash-risk away from Charts
  [`InsightsView.swift:103`](../../CashOut/Views/Insights/InsightsView.swift#L103)

**Breakdown visual + accessibility**

- `isExcluded` flag + proportion forced to 0.0 for excluded rows
  [`CategoryBreakdownView.swift:15`](../../CashOut/Views/Insights/CategoryBreakdownView.swift#L15)

- `.opacity(0.35)` dims excluded rows without blocking hit testing
  [`CategoryBreakdownView.swift:44`](../../CashOut/Views/Insights/CategoryBreakdownView.swift#L44)

- VoiceOver state (`"excluded"`) + action hint on each row
  [`CategoryBreakdownView.swift:49`](../../CashOut/Views/Insights/CategoryBreakdownView.swift#L49)
