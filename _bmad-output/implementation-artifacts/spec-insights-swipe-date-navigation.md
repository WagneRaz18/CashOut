---
title: 'Insights Tab Swipe Date Navigation'
type: 'feature'
created: '2026-05-02'
status: 'done'
baseline_commit: '0921319d1771b16d4f5627d357c79141771d1e8d'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The Insights tab only shows data for the current day/week/month with no way to view historical periods without leaving the screen.

**Approach:** Add left/right swipe gestures to `InsightsView` that offset the viewed period by one unit (day/week/month). Offset is tracked in `InsightsViewModel` as an `Int` (0 = current, negative = past). It resets to 0 whenever the user switches period tabs or returns to the Insights screen.

## Boundaries & Constraints

**Always:**
- Swipe left → go to earlier period (offset decreases by 1).
- Swipe right → go to later period (offset increases toward 0).
- Offset is capped at 0 — cannot navigate into the future.
- Switching period tabs (Day/Week/Month) resets offset to 0 before loading new period data.
- Returning to the Insights app tab resets offset to 0.
- Date arithmetic uses the existing Gregorian `calendar` and `dateInterval(for:referenceDate:)` helpers — shift the reference date by `dateOffset` units of `period.calendarComponent` before passing.
- `comparisonText` returns nil when `dateOffset != 0` (comparison label becomes misleading for non-current periods).
- THB amounts via `Int64.displayAmount` only — never manual string concatenation.
- All `DateFormatter` instances used for `periodLabel` must be `private static let` cached values (never allocated inline in computed properties).

**Ask First:**
- If calendar edge cases appear (e.g. Gregorian week boundaries straddling months) that would require new date logic not covered by existing helpers, halt and ask before choosing approach.

**Never:**
- No UI controls (arrows, buttons, pickers) for date navigation — swipe gesture only.
- Do not persist `dateOffset` across app sessions.
- Do not navigate forward past the current period (offset > 0 is forbidden).
- Do not modify the Day/Week/Month segmented picker.
- Do not use `.highPriorityGesture` for swipe — use `.simultaneousGesture` to avoid stealing scroll events from the inner ScrollView.
- Do not add `didSet`/`willSet` to any `@Observable`-tracked property — macro synthesizes its own setter and observers conflict.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Swipe left at current | offset == 0, any period | Data loads for 1 period back; offset becomes -1 | N/A |
| Swipe right at current | offset == 0 | Gesture ignored; no state change | N/A |
| Swipe left on historical | offset == -N | Data loads for N+1 periods back; offset becomes -(N+1) | N/A |
| Swipe right on historical | offset < 0 | Data loads for 1 period forward; offset increases by 1 | N/A |
| Period tab switch while navigated | selectedPeriod changes | offset resets to 0; new period's current data loads | N/A |
| Return to Insights app tab while navigated | tab switch back | offset resets to 0; current period data reloads only if needed | N/A |
| Daily at offset -1 | period == .daily, offset == -1 | periodLabel = "Yesterday"; bar labeled "Yesterday" | N/A |
| Daily at offset < -1 | period == .daily, offset == -N | periodLabel = formatted date ("Apr 29"); bar label = same | N/A |
| Weekly at offset -1 | period == .weekly, offset == -1 | periodLabel = "Last Week" | N/A |
| Weekly at offset < -1 | period == .weekly | periodLabel = date range ("Apr 21 – Apr 27") | N/A |
| Monthly at offset -1 | period == .monthly, offset == -1 | periodLabel = "Last Month" | N/A |
| Monthly at offset < -1 | period == .monthly | periodLabel = "Apr 2026" | N/A |
| comparisonText when navigated | dateOffset != 0 | nil — no comparison shown | N/A |

</frozen-after-approval>

## Code Map

- `CashOut/ViewModels/InsightsViewModel.swift` — All navigation state and date logic
- `CashOut/Views/Insights/InsightsView.swift` — Swipe gesture, task key, period-change reset
- `CashOutTests/ViewModels/InsightsViewModelTests.swift` — Unit tests for new navigation behaviour

## Tasks & Acceptance

**Execution:**

- [x] `CashOut/ViewModels/InsightsViewModel.swift` — Add `var dateOffset: Int = 0` (observable). Add `@ObservationIgnored private var loadedOffset: Int? = nil` (nil = never loaded; `Int?` so `invalidateAndReload()` can reset it to nil). Add `var loadKey: String { "\(selectedPeriod.rawValue)-\(dateOffset)" }`. Add `var canNavigateForward: Bool { dateOffset < 0 }`. Add sync methods: `navigatePrevious()` (decrements `dateOffset`), `navigateNext()` (guards `canNavigateForward`, increments `dateOffset`), `resetToCurrentPeriod()` (sets `dateOffset = 0` only if `!= 0`). Add private helper `referenceDate(for period: TimePeriod, offset: Int, relativeTo base: Date) -> Date` — applies `calendar.date(byAdding: period.calendarComponent, value: offset, to: base)`, returns `base` when offset is 0 or shift fails. Update `loadData()` guard from `loadedPeriod != selectedPeriod` to `loadedPeriod != selectedPeriod || loadedOffset != dateOffset`; wrap `performLoad()` call in `loadTask` cancel-before-replace pattern (same as `invalidateAndReload()`) to serialize concurrent callers. Update `invalidateAndReload()` to also reset `loadedOffset = nil` alongside `loadedPeriod = nil`. Update `performLoad()` to: capture `let offset = dateOffset`, compute `let refDate = referenceDate(for: period, offset: offset, relativeTo: now)` using already-captured `now`, pass `refDate` to both `dateInterval` and `previousDateInterval` calls, set `loadedOffset = offset` at the end alongside `loadedPeriod = period`. Update `computeBarEntries` daily case: replace hardcoded `"Today"` label with `calendar.isDateInToday(interval.start) ? "Today" : calendar.isDateInYesterday(interval.start) ? "Yesterday" : dayMonthFormatter.string(from: interval.start)`. Add `private static let` formatters needed for `periodLabel` range/month display (e.g., `mediumDateFormatter` for "Apr 29"/"Apr 21 – Apr 27", `monthYearFormatter` for "Apr 2026"). Update `periodLabel` computed property to return period-specific dynamic labels when `dateOffset != 0` per the I/O Matrix; use only the new static formatters. Update `comparisonText` to return `nil` when `dateOffset != 0` (guard at the top, before the existing `previousPeriodTotal` nil check). Update `BarEntry.id` to use a stable positional `Int` (0 for daily, 0–6 for weekly, 0-based week index for monthly) instead of the `label` string, to avoid ForEach delete+insert animation on swipe.

- [x] `CashOut/Views/Insights/InsightsView.swift` — Replace `.task(id: viewModel.selectedPeriod)` with `.task(id: viewModel.loadKey)` (do NOT call `resetToCurrentPeriod()` inside the task body — doing so immediately undoes swipe navigation). Add `.onAppear { viewModel.resetToCurrentPeriod() }` on the root `VStack` — fires when returning to the Insights app tab (SwiftUI TabView shows/hides views on tab switch), guaranteeing the reset even when `loadKey` is unchanged. Add `.onChange(of: viewModel.selectedPeriod) { viewModel.resetToCurrentPeriod() }` so period-tab switching resets offset synchronously. Add `.simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in ... })`: treat drag as horizontal only when `abs(value.translation.width) > abs(value.translation.height)`; if width < 0 call `viewModel.navigatePrevious()`; if width > 0 call `viewModel.navigateNext()`. Do NOT use `.highPriorityGesture` — ScrollView must retain scroll event priority.

- [x] `CashOutTests/ViewModels/InsightsViewModelTests.swift` — Add tests: `navigatePrevious` decrements offset; `navigateNext` from offset 0 is no-op (canNavigateForward = false); `navigateNext` from offset -1 reaches 0; `selectedPeriod` change triggers `resetToCurrentPeriod` and offset returns to 0; `loadData()` skips when period+offset match loaded state; `loadData()` reloads when offset changes; load at offset -2 → call `invalidateAndReload()` → call `loadData()` at offset -2 again → assert second fetch occurred (tests the guard + invalidation interaction); `periodLabel` returns correct labels for all periods at offsets 0, -1, -5 per I/O Matrix; `comparisonText` is nil when `dateOffset != 0` AND `previousPeriodTotal` is non-nil (set `previousPeriodTotal = 5000` as precondition to prove the new guard fires, not just the existing nil check); daily `computeBarEntries` returns "Yesterday" label at offset -1 (verified via `barEntries.first?.label` after full `loadData()` — note this test runs against the real clock).

**Acceptance Criteria:**
- Given Day view at today, when user swipes left, then yesterday's data loads and `periodLabel` shows "Yesterday".
- Given Day view showing a historical date, when user swipes right, then the next-later day loads.
- Given offset == 0, when user swipes right, then no navigation occurs and data is unchanged.
- Given user is on Week view at offset -2, when they tap the Month tab, then Month view loads this month's data with offset reset to 0.
- Given Insights tab is showing a historical date, when user navigates to Feed tab and returns, then offset resets to 0 and current period data is shown.
- Given offset != 0 and `previousPeriodTotal` is non-nil, when `comparisonText` is observed, then it is nil.
- Given offset -1 on the Day tab, when the bar chart renders, then the single bar is labeled "Yesterday".
- Given user scrolls vertically while on the Insights tab, then scroll works normally and swipe navigation does not trigger.

## Spec Change Log

**2026-05-02 — Step-04 adversarial review (loop 1):**
- bad_spec: `resetToCurrentPeriod()` was specified inside `.task(id:)` body — this immediately undoes every swipe (task fires because loadKey changed after swipe, first line resets offset to 0). Also: `.task(id:)` only re-fires when `loadKey` changes; on tab-return with unchanged loadKey, the task never fires so the reset never ran (AC5 fail).
- Fix: Removed `resetToCurrentPeriod()` from `.task(id:)` body. Added `.onAppear { viewModel.resetToCurrentPeriod() }` for tab-return handling — `.onAppear` fires whenever TabView makes the view visible, independent of loadKey state.
- KEEP: `.simultaneousGesture`, `.onChange(of: selectedPeriod)`, `.task(id: loadKey)` key design, all ViewModel changes, static formatters, positional BarEntry.id.

**2026-05-02 — Orchestrator review (pre-approval):**
- CRITICAL: Changed `.highPriorityGesture` to `.simultaneousGesture` — high-priority steals touch from ScrollView before direction check can run.
- CRITICAL: Removed `didSet` on `selectedPeriod`; replaced with `.onChange(of:)` in View — `@Observable` macro synthesizes its own setter, `didSet` on tracked property causes compiler error.
- CRITICAL: `invalidateAndReload()` now resets `loadedOffset = nil`; `loadedOffset` type changed to `Int?` — original spec left loadedOffset stale after remote-change invalidation.
- WARNING: Moved `resetToCurrentPeriod()` from `.onAppear` into top of `.task(id:)` body — `.onAppear`/`.task` ordering not guaranteed, risk of double-load race.
- WARNING: `loadData()` now uses `loadTask` cancel-before-replace — serializes concurrent callers with `invalidateAndReload()`.
- WARNING: `referenceDate` helper takes explicit `base: Date` parameter — avoids second `Date()` call inside helper, preserves existing midnight-safety discipline.
- WARNING: `BarEntry.id` changed to positional `Int` — label-string id causes ForEach delete+insert animation flash on every swipe.
- WARNING: Added `private static let` formatter requirement for `periodLabel` dynamic strings.
- WARNING: Added two test cases — `invalidateAndReload()` guard interaction; `comparisonText` nil guard with non-nil `previousPeriodTotal`.

## Design Notes

`loadKey` ties SwiftUI's `.task(id:)` lifecycle to both period + offset with zero extra complexity — a plain `String` satisfies `Equatable`. When either dimension changes, SwiftUI cancels the prior task and fires a new one. Calling `resetToCurrentPeriod()` at the top of the `.task(id:)` body (before `loadData()`) ensures the offset is always 0 when the Insights tab is entered, without a separate `.onAppear` hook whose ordering with `.task` is undefined.

`.simultaneousGesture` is the correct choice whenever a drag gesture sits over a scroll container: both recognizers run in parallel, and the direction check in `.onEnded` safely filters to horizontal-only without having stolen the touch stream from the scroll system.

`BarEntry.id` as a positional `Int` (0, 1, 2...) keeps SwiftUI's `ForEach` diffing stable across label changes — same bar position gets an update diff, not a delete+insert cycle.

## Verification

**Commands:**
- `xcodebuild test -scheme CashOut -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing CashOutTests/InsightsViewModelTests` -- expected: all tests pass, 0 failures

## Suggested Review Order

**Navigation state — the core concept**

- `dateOffset: Int` — root state; 0 = current, negative = past; never positive
  [`InsightsViewModel.swift:88`](../../CashOut/ViewModels/InsightsViewModel.swift#L88)

- `loadKey` combines period + offset into a single reactive SwiftUI task id
  [`InsightsViewModel.swift:104`](../../CashOut/ViewModels/InsightsViewModel.swift#L104)

- `canNavigateForward` — forward navigation cap; false at offset 0
  [`InsightsViewModel.swift:106`](../../CashOut/ViewModels/InsightsViewModel.swift#L106)

**Date arithmetic**

- `referenceDate(for:offset:relativeTo:)` — shifts base date by N period units
  [`InsightsViewModel.swift:453`](../../CashOut/ViewModels/InsightsViewModel.swift#L453)

- `performLoad()` captures offset snapshot before awaits; passes refDate to both intervals
  [`InsightsViewModel.swift:301`](../../CashOut/ViewModels/InsightsViewModel.swift#L301)

**Load guard — two-dimensional deduplication**

- `loadedOffset: Int?` — nil = never loaded; reset by `invalidateAndReload()`
  [`InsightsViewModel.swift:183`](../../CashOut/ViewModels/InsightsViewModel.swift#L183)

- `loadData()` guard checks both period and offset; uses `loadTask` cancel-before-replace
  [`InsightsViewModel.swift:212`](../../CashOut/ViewModels/InsightsViewModel.swift#L212)

- `invalidateAndReload()` resets both guards to nil for fresh fetch
  [`InsightsViewModel.swift:224`](../../CashOut/ViewModels/InsightsViewModel.swift#L224)

**Period label**

- `periodLabel` — dynamic label: Today/Yesterday/Last Week/date-range/month-year
  [`InsightsViewModel.swift:110`](../../CashOut/ViewModels/InsightsViewModel.swift#L110)

- Static `mediumDateFormatter` + `monthYearFormatter` — cached for hot-path access
  [`InsightsViewModel.swift:375`](../../CashOut/ViewModels/InsightsViewModel.swift#L375)

**Navigation methods**

- `navigatePrevious/Next/resetToCurrentPeriod` — sync mutations; task id change drives async reload
  [`InsightsViewModel.swift:234`](../../CashOut/ViewModels/InsightsViewModel.swift#L234)

**Bar chart label & stable identity**

- `BarEntry.position: Int` id — positional; prevents delete+insert animation on label change
  [`InsightsViewModel.swift:65`](../../CashOut/ViewModels/InsightsViewModel.swift#L65)

- Daily bar label: Today / Yesterday / formatted date — derived from interval.start
  [`InsightsViewModel.swift:408`](../../CashOut/ViewModels/InsightsViewModel.swift#L408)

**View wiring**

- `.task {}` (no id) — fires on every tab appear; resets offset to 0 reliably
  [`InsightsView.swift:111`](../../CashOut/Views/Insights/InsightsView.swift#L111)

- `.onChange(of: selectedPeriod)` — resets offset synchronously on period tab switch
  [`InsightsView.swift:114`](../../CashOut/Views/Insights/InsightsView.swift#L114)

- `.simultaneousGesture(DragGesture)` — horizontal-only swipe; scroll unaffected
  [`InsightsView.swift:117`](../../CashOut/Views/Insights/InsightsView.swift#L117)

- `.task(id: viewModel.loadKey)` — reactive reload on any period or offset change
  [`InsightsView.swift:128`](../../CashOut/Views/Insights/InsightsView.swift#L128)

**Tests**

- New navigation tests: offset mutations, guard behaviour, labels, bar entry label at offset -1
  [`InsightsViewModelTests.swift:764`](../../CashOutTests/ViewModels/InsightsViewModelTests.swift#L764)
