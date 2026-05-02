---
title: 'Insights Month Tab: Calendar View'
type: 'feature'
created: '2026-05-02'
status: 'in-review'
baseline_commit: '8e9794b77e228108a2df2c8059fc221267ed96c3'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The month tab displays a W1–W5 bar chart which obscures day-level detail and gives no intuitive way to jump to a specific day's insights.

**Approach:** Replace the monthly bar chart with a full calendar grid where each day cell shows its total spend. Today is visually marked. Tapping a past or current day navigates directly to that day's insight by switching the period to `.daily` and computing the correct `dateOffset`. Future days are non-interactive.

## Boundaries & Constraints

**Always:**
- Use `Calendar.gregorian` for all date arithmetic — Thai locale returns Buddhist calendar. `Calendar.gregorian` must explicitly pin `firstWeekday = 1` (Sunday-first grid) and `timeZone = TimeZone(identifier: "Asia/Bangkok")!`.
- Amounts formatted via `Int64.displayAmount` — never manual "฿" concatenation.
- Only days ≤ today are tappable. Equality check uses start-of-day comparison via `Calendar.gregorian`.
- `MonthlyCalendarView` shown only when `selectedPeriod == .monthly`; daily/weekly periods keep `DailyBarChartView`.
- `dailyTotals` is a **stored** property computed once in `applyLoadResults` — never a computed property on `@Observable` (would fire tracking notifications on every grid cell read).
- In `navigateToDay`, set `dateOffset` BEFORE `selectedPeriod` so `loadKey` transitions in one step, not two (avoids a spurious `.task(id:)` load with partial state).

**Ask First:**
- If a Monday-first week start is needed.

**Never:**
- Fetch additional data from the repository — derive day totals from already-fetched `currentExpenses`.
- Show future-month days in the grid — only current month days plus leading empty padding cells.
- Modify `DailyBarChartView` or its data model.
- Use `.disabled(true)` on future day cells — it suppresses VoiceOver focus entirely. Use `.allowsHitTesting(false)` instead.
- Force-unwrap `Calendar.range(of:in:for:)` — use `guard let` with graceful fallback.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Day with spend | `dailyTotals[startOfDay] = 4500` (45 THB) | Cell shows day number + "฿45" formatted amount | — |
| Day with no spend | Key absent from `dailyTotals` | Cell shows day number only, no amount label | — |
| Today cell | `startOfDay == todayStart` | Circular accent background on day number | — |
| Future day | `date > today` | Cell dimmed (opacity 0.3), `.allowsHitTesting(false)`, VoiceOver reads "Future date" hint | — |
| Tap past/today day | User taps April 28, today = May 2 | `dateOffset = -4` set first, then `selectedPeriod = .daily` | Guard future dates |
| Tap today | User taps today's cell | `dateOffset = 0` set first, then `selectedPeriod = .daily` | — |
| Month starts on Wednesday | `firstWeekday offset = 3` (0-based, Sunday-first) | 3 empty leading cells before "1" | — |
| Previous month via swipe | `dateOffset = -1` | Calendar shows previous month, all days tappable | — |

</frozen-after-approval>

## Code Map

- `CashOut/Views/Insights/InsightsView.swift` — Add `periodBinding` computed Binding; **atomically** remove `.onChange(of: selectedPeriod)` in the same edit; conditionally render `MonthlyCalendarView` vs `DailyBarChartView`
- `CashOut/ViewModels/InsightsViewModel.swift` — Add stored `var dailyTotals: [Date: Int64]`; populate in `applyLoadResults`; reset in `clearLoadResults`; add `var viewedMonthStart: Date`; add `func navigateToDay(_ date: Date)`; add `@ObservationIgnored private var currentExpenses`
- `CashOut/Views/Insights/MonthlyCalendarView.swift` — NEW: 7-column calendar grid with day cells, today marker, accessibility hints
- `CashOut/Utilities/Extensions/Calendar+App.swift` — Pin `firstWeekday = 1` and `timeZone = Asia/Bangkok` on the `gregorian` static

## Tasks & Acceptance

**Execution:**
- [x] `CashOut/Utilities/Extensions/Calendar+App.swift` -- Update `Calendar.gregorian` to explicitly set `firstWeekday = 1` and `timeZone = TimeZone(identifier: "Asia/Bangkok")!` -- ensures Sunday-first grid and correct startOfDay in CI (UTC) environments
- [x] `CashOut/ViewModels/InsightsViewModel.swift` -- Add `@ObservationIgnored private var currentExpenses: [ExpenseData] = []`; add `var dailyTotals: [Date: Int64] = [:]` (tracked stored prop); in `applyLoadResults`, set `currentExpenses = currentExpenses` and compute `dailyTotals = currentExpenses.reduce(into:) { map, e in map[Self.calendar.startOfDay(for: e.date), default: 0] += e.amount }`; reset both in `clearLoadResults`; add `var viewedMonthStart: Date { let ref = Self.calendar.date(byAdding: .month, value: dateOffset, to: Date()) ?? Date(); return Self.calendar.dateInterval(of: .month, for: ref)?.start ?? ref }` (monthly-only, safe since only read when `selectedPeriod == .monthly`); add `func navigateToDay(_ date: Date)` that guards `startOfDay(date) <= startOfDay(today)`, computes diff via `dateComponents([.day], from: startOfDay(date), to: startOfDay(today)).day ?? 0`, sets `dateOffset = -diff` THEN `selectedPeriod = .daily` -- pre-computed dailyTotals eliminates 31 repeated reduce calls; ordered writes ensure loadKey transitions once
- [x] `CashOut/Views/Insights/InsightsView.swift` -- In a single edit: (1) add `private var periodBinding: Binding<TimePeriod> { Binding(get: { viewModel.selectedPeriod }, set: { viewModel.selectedPeriod = $0; viewModel.resetToCurrentPeriod() }) }`; (2) replace `Bindable(viewModel).selectedPeriod` in Picker with `periodBinding`; (3) remove `.onChange(of: viewModel.selectedPeriod)` modifier entirely; (4) replace unconditional `DailyBarChartView(...)` with `if viewModel.selectedPeriod == .monthly { MonthlyCalendarView(...).transition(.opacity) } else { DailyBarChartView(...).transition(.opacity) }` -- atomic change prevents the double-reset window where both onChange and periodBinding.set call resetToCurrentPeriod; transitions prevent easeInOut animation conflict on structural view swap
- [x] `CashOut/Views/Insights/MonthlyCalendarView.swift` -- NEW: accepts `calendarMonth: Date`, `dailyTotals: [Date: Int64]`, `today: Date`, `onDayTap: (Date) -> Void`; builds header `["S","M","T","W","T","F","S"]`; constructs `[GridCell]` (Identifiable, stable ID from date timeInterval or sentinel for padding) with `weekdayOffset` leading nils; renders 7-column `LazyVGrid` (or `Grid`); each day cell: day number + optional amount via `Int64.displayAmount`; today gets circular accent; future cells: opacity 0.3 + `.allowsHitTesting(false)` + `.accessibilityHint("Future date, not available")`; tappable cells call `onDayTap(date)` -- pure display view, all business logic stays in ViewModel

**Acceptance Criteria:**
- Given month tab is active, when user views any month, then a calendar grid (not a bar chart) is displayed with correct day layout for that month.
- Given today is May 2, when calendar renders May, then day "2" shows a distinct circular accent and days 3–31 are dimmed and non-interactive.
- Given day cell shows ฿150 spend, when rendered, then the amount is formatted via `Int64.displayAmount`.
- Given user taps April 28 while viewing April (today = May 2), when tap fires, then `selectedPeriod == .daily` and `dateOffset == -4`.
- Given user taps today in calendar, when tap fires, then `selectedPeriod == .daily` and `dateOffset == 0`.
- Given user taps a future day, when tap fires, then no navigation occurs and period/offset remain unchanged.
- Given user changes period via picker (not via day tap), when picker fires, then `dateOffset` resets to 0 (existing behaviour preserved).
- Given day with no spend, when rendered, then cell shows only the day number with no amount label.
- Given VoiceOver is active, when focused on a future day cell, then VoiceOver reads the day number and "Future date, not available" hint (cell is not skipped).

## Spec Change Log

- **2026-05-02**: Orchestrate validation (ios-swiftui-guardian + architecture-guardian) found 4 CRITICALs:
  (1) `dailyTotals` changed from computed → stored in `applyLoadResults` (eliminates 31 repeated reduce calls per render);
  (2) `navigateToDay` write order reversed to `dateOffset` first to prevent spurious `.task(id:)` load on intermediate loadKey;
  (3) `periodBinding` + `.onChange` removal made atomic in single task to close double-reset window;
  (4) `Calendar.gregorian` updated to pin `firstWeekday = 1` and `timeZone = Asia/Bangkok`.
  Warnings addressed: `.transition(.opacity)` added, `.allowsHitTesting(false)` mandated, VoiceOver hint added, force-unwrap banned explicitly.

## Design Notes

**Avoiding the period-reset conflict:**
Replace the Picker binding with a computed `periodBinding` whose `set` calls `resetToCurrentPeriod()`, AND remove the `.onChange(of: selectedPeriod)` modifier in the same edit. These two changes must be atomic — if `.onChange` survives while `periodBinding` is active, picker-driven changes call `resetToCurrentPeriod()` twice. `navigateToDay` writes directly to `viewModel.selectedPeriod` bypassing `periodBinding`, so no reset fires.

**`navigateToDay` write order:**
`loadKey = "\(selectedPeriod.rawValue)-\(dateOffset)"`. Writing `selectedPeriod` first produces an intermediate `loadKey = "Day-<oldOffset>"`, triggering `.task(id:)` against partial state before `dateOffset` is updated. Writing `dateOffset` first keeps `selectedPeriod` unchanged during the first write, then `selectedPeriod` write produces the final `loadKey = "Day-<newOffset>"` in one transition.

**Calendar grid construction:**
```swift
// GridCell: Identifiable
struct GridCell: Identifiable {
    let id: Double  // date.timeIntervalSinceReferenceDate, or negative index for pads
    let date: Date?
}

let firstDay = calendarMonth  // viewedMonthStart (start of month)
guard let range = Calendar.gregorian.range(of: .day, in: .month, for: firstDay) else { return [] }
let weekdayOffset = Calendar.gregorian.component(.weekday, from: firstDay) - 1  // 0=Sun
// weekdayOffset nils, then range.count real dates
```

**`dailyTotals` in `applyLoadResults`:**
```swift
self.dailyTotals = currentExpenses.reduce(into: [:]) { map, e in
    map[Self.calendar.startOfDay(for: e.date), default: 0] += e.amount
}
```
Only days with expenses appear in the map. View shows amount label only when key present.

## Verification

**Commands:**
- `xcodebuild test -scheme CashOut -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing CashOutTests/InsightsViewModelTests` -- expected: 0 failures
- `xcodebuild test -scheme CashOut -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing CashOutTests/InsightsViewModelNavigationTests` -- expected: 0 failures (add `navigateToDay` + `dailyTotals` cases to this file)

**Manual checks:**
- Month tab shows calendar grid, not W1–W5 bars.
- Today cell has visible accent mark.
- Tap past day → transitions to daily view for that day (correct date).
- Tap future day → nothing happens.
- Swipe left/right still navigates months on calendar view.
- Picker switching to Day/Week resets to current period (today).
- VoiceOver: future day cells announce hint, not skipped.
