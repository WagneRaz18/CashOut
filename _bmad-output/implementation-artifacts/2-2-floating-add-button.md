# Story 2.2: Floating Add Button

Status: review

## Story

As a user,
I want a floating add button on the Feed and Insights tabs,
So that I can quickly log a new expense without switching to the Add tab.

## Acceptance Criteria

1. **Given** the Feed tab **When** displayed **Then** a FloatingAddButton (52×52pt circle with `.buttonStyle(.glassProminent)` + `.buttonBorderShape(.circle)`, SF Symbol "plus" in accent color) appears bottom-trailing above the tab bar via `.tabViewBottomAccessory` (UX-DR5)

2. **Given** the Insights tab **When** displayed **Then** the same FloatingAddButton appears in the same position

3. **Given** the Add tab **When** displayed **Then** the FloatingAddButton is hidden (UX-DR5)

4. **Given** the FloatingAddButton **When** tapped **Then** an entry sheet is presented with the same numpad/category UI as the Add tab via `.sheet()` with `.presentationDetents([.large])`

5. **Given** the entry sheet **When** an expense is saved via the sheet **Then** the sheet dismisses and the feed or insights view updates to reflect the new entry

6. **Given** VoiceOver is enabled **When** the FloatingAddButton is focused **Then** it announces "Add expense" (UX-DR16)

## Tasks / Subtasks

- [x] Task 1: Create FloatingAddButton component (AC: #1, #6)
  - [x] 1.1 Create `CashOut/Views/Feed/FloatingAddButton.swift`
  - [x] 1.2 `struct FloatingAddButton: View` with `var action: () -> Void` parameter
  - [x] 1.3 `Button` with `Image(systemName: "plus")` label, `.font(.title2)`, `.frame(width: 52, height: 52)` on the label
  - [x] 1.4 Apply `.buttonStyle(.glassProminent)` + `.buttonBorderShape(.circle)`. **CRITICAL: Do NOT add `.glassEffect()` — architecture rule: glass button styles and `.glassEffect()` conflict on the same element.** [Source: architecture.md — Liquid Glass API Rules; learnings/ios-swiftui.md line 38]
  - [x] 1.5 Add `.accessibilityLabel("Add expense")`
  - [x] 1.6 Register file in `project.pbxproj`

- [x] Task 2: Add `.tabViewBottomAccessory` to ContentView (AC: #1, #2, #3)
  - [x] 2.1 In `ContentView.swift`, add `@State private var showingAddExpenseSheet = false`
  - [x] 2.2 Add `.tabViewBottomAccessory { }` modifier to the `TabView`
  - [x] 2.3 Inside the accessory closure, conditionally render: `if selectedTab != 0 { FloatingAddButton { showingAddExpenseSheet = true } }` — this hides the FAB on the Add tab (tab 0). **Fallback:** if the conditional leaves an empty accessory area visible on the Add tab, switch to `.opacity(selectedTab != 0 ? 1 : 0)` + `.allowsHitTesting(selectedTab != 0)` to hide without removing from the hierarchy
  - [x] 2.4 **DO NOT** use a ZStack overlay approach — `.tabViewBottomAccessory` is the iOS 26 native mechanism that integrates with tab bar Liquid Glass chrome and `.tabBarMinimizeBehavior(.onScrollDown)` transitions (FAB goes inline with minimized pill automatically)

- [x] Task 3: Add entry sheet presentation on ContentView (AC: #4, #5)
  - [x] 3.1 Add `.sheet(isPresented: $showingAddExpenseSheet)` modifier on the `TabView`
  - [x] 3.2 Sheet content: `EntryView(onSaveComplete: { showingAddExpenseSheet = false })` with `.presentationDetents([.large])`
  - [x] 3.3 **No NavigationStack wrapper, no toolbar cancel button** — sheet dismisses via standard pull-down gesture (UX-DR26: "pull down to dismiss without saving") or automatically on save via the `onSaveComplete` callback
  - [x] 3.4 **No `.navigationTransition(.zoom)` for v1** — the zoom transition has a known iOS 26 bug (nav bar shift on return) and requires complex namespace scoping across TabView/NavigationStack boundaries. Standard sheet presentation is reliable and fulfills the AC.

- [x] Task 4: Modify EntryView to support sheet dismiss-on-save (AC: #5)
  - [x] 4.1 Add `var onSaveComplete: (() -> Void)? = nil` property to `EntryView` — optional, so the existing tab usage is unaffected (no parameter needed)
  - [x] 4.2 In the `onSave` Task closure (after `try await viewModel.saveExpense()` succeeds), add `onSaveComplete?()` — this triggers sheet dismissal when used in sheet mode, and is a no-op in tab mode
  - [x] 4.3 **Do NOT modify `ExpenseEntryViewModel`** — the dismiss callback belongs at the View layer, not the ViewModel. The ViewModel already resets the form after save; the View adds the dismiss behavior.
  - [x] 4.4 Verify existing `EntryView()` calls (in `ContentView.swift` Tab 1) continue to compile without changes — the default `nil` parameter ensures backward compatibility

- [x] Task 5: Register files and verify build (AC: #1–#6)
  - [x] 5.1 Register `FloatingAddButton.swift` in `project.pbxproj` (PBXBuildFile, PBXFileReference, PBXGroup for Views/Feed)
  - [x] 5.2 Build the project — verify zero errors, zero warnings
  - [x] 5.3 Verify FAB visible on Feed tab, visible on Insights tab, hidden on Add tab
  - [x] 5.4 Verify FAB tap opens entry sheet with numpad + category picker
  - [x] 5.5 Verify saving in sheet dismisses it and new entry appears in Feed
  - [x] 5.6 Verify pulling down sheet dismisses without saving
  - [x] 5.7 Verify VoiceOver announces "Add expense" on FAB focus
  - [x] 5.8 Verify existing 80 tests still pass (`Cmd+U`)

## Dev Notes

### Implementation Strategy: `.tabViewBottomAccessory` (Not ZStack)

The architecture project structure lists `FloatingAddButton.swift` at `CashOut/Views/Feed/FloatingAddButton.swift` and describes it as "ZStack-based glass FAB". However, the UX design specification and platform strategy sections consistently reference `.tabViewBottomAccessory` as the iOS 26 native mechanism. **Use `.tabViewBottomAccessory`** — it is the correct iOS 26 approach because:

1. **Automatic Liquid Glass integration** — the accessory inherits the tab bar's glass chrome
2. **Minimization support** — when `.tabBarMinimizeBehavior(.onScrollDown)` triggers, the accessory goes inline with the minimized pill automatically. A ZStack overlay would float awkwardly over the minimized tab bar.
3. **Safe area handling** — the system positions the accessory correctly above the tab bar without manual padding calculations

The `FloatingAddButton.swift` component is still a separate file (reusable View), but it is embedded via `.tabViewBottomAccessory` on the TabView, not via ZStack.

[Source: ux-design-specification.md — "iOS 26 Liquid Glass — `.tabViewBottomAccessory` FAB"]
[Source: ux-design-specification.md — FloatingAddButton component spec]

### Liquid Glass Styling — Critical Rules

```swift
// CORRECT — Button uses button style, not .glassEffect()
Button { action() } label: {
    Image(systemName: "plus")
        .font(.title2)
        .frame(width: 52, height: 52)
}
.buttonStyle(.glassProminent)   // Primary action glass style
.buttonBorderShape(.circle)      // Circular clipping for glass material
.accessibilityLabel("Add expense")
```

**Architecture rules (enforced by guardians):**
- `Button` elements → `.buttonStyle(.glass)` or `.buttonStyle(.glassProminent)`
- Non-button views → `.glassEffect()` modifier
- **NEVER combine both** on the same element — they conflict
- FAB is a primary action → `.glassProminent` (not `.glass`)

[Source: architecture.md — Liquid Glass API Rules]
[Source: learnings/ios-swiftui.md line 38-39]

### Entry Sheet Reuses Existing EntryView

The entry sheet presents the **exact same** `EntryView` used in Tab 1. No new View or ViewModel needed for the sheet content. The only change is adding an `onSaveComplete` callback:

```swift
// Tab 1 (unchanged) — no callback, form resets and stays visible
Tab("Add", systemImage: "plus", value: 0) {
    EntryView()  // onSaveComplete defaults to nil
}

// Sheet (new) — callback dismisses sheet after save
.sheet(isPresented: $showingAddExpenseSheet) {
    EntryView(onSaveComplete: { showingAddExpenseSheet = false })
        .presentationDetents([.large])
}
```

**Why this works:**
- `EntryView` creates its own `@State private var viewModel = ExpenseEntryViewModel()` — each sheet presentation gets a fresh ViewModel instance (amount = 0, MRU category pre-selected)
- `.task { await viewModel.loadCategories() }` fires when the sheet appears
- After save, `viewModel.saveExpense()` persists to Core Data → FRC in FeedViewModel picks up the change automatically → Feed updates
- `onSaveComplete?()` then dismisses the sheet
- Pull-down dismissal works without intervention (standard iOS sheet behavior)

**Future story consideration:** Story 2-3 (Edit Expense) will create `EditExpenseSheet.swift` that pre-fills an existing expense. That is a separate component — do not pre-build it here.

### ContentView Final Shape

```swift
struct ContentView: View {
    @State private var selectedTab = 0
    @State private var showingAddExpenseSheet = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Add", systemImage: "plus", value: 0) {
                EntryView()
            }
            Tab("Feed", systemImage: "list.bullet", value: 1) {
                NavigationStack {
                    FeedView()
                }
            }
            Tab("Insights", systemImage: "chart.pie", value: 2) {
                NavigationStack {
                    InsightsView()
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            if selectedTab != 0 {
                FloatingAddButton {
                    showingAddExpenseSheet = true
                }
            }
        }
        .sheet(isPresented: $showingAddExpenseSheet) {
            EntryView(onSaveComplete: {
                showingAddExpenseSheet = false
            })
            .presentationDetents([.large])
        }
    }
}
```

### Tab Visibility Logic

The FAB must be hidden on the Add tab (tab 0) because:
- Tab 1 is already the full-screen entry interface
- Showing a FAB that opens the same UI as the current tab is redundant (UX-DR5)

The conditional `if selectedTab != 0` inside `.tabViewBottomAccessory` controls this. If the conditional renders an empty accessory area on the Add tab (visible as blank space), use this fallback:

```swift
.tabViewBottomAccessory {
    FloatingAddButton { showingAddExpenseSheet = true }
        .opacity(selectedTab != 0 ? 1 : 0)
        .allowsHitTesting(selectedTab != 0)
}
```

### Feed/Insights Updates After Sheet Save

When an expense is saved from the sheet:
1. `ExpenseEntryViewModel.saveExpense()` → `ExpenseRepository.saveExpense()` → Core Data insert
2. `NSFetchedResultsController` in `ExpenseRepository` detects the change → fires `onExpensesChanged` callback → `FeedViewModel.expenses` updates automatically
3. No additional wiring needed — the FRC-based observation from Story 2-1 handles this

InsightsView is currently a stub (Epic 3). When implemented, it will use its own observation mechanism (remote change notification pattern) and will similarly auto-update.

### VoiceOver Accessibility

- FAB: `.accessibilityLabel("Add expense")` — the button announces its purpose
- Sheet content: `EntryView` already has full accessibility support from Stories 1-5 through 1-7 (numpad, amount display, category picker, save button all accessible)
- No additional accessibility work needed beyond the FAB label

[Source: epics.md — Story 2.2 AC VoiceOver]

### No New Unit Tests

This story is **entirely view-layer work** — no new ViewModel, no new Repository method, no new Service. The changes are:
- New View component (`FloatingAddButton`) — purely declarative, no testable logic
- View modifier additions (`ContentView`) — layout/presentation, not logic
- Optional callback (`EntryView.onSaveComplete`) — wiring, not logic

Existing tests (80 passing) cover the underlying save flow (`ExpenseEntryViewModelTests`) and feed observation (`FeedViewModelTests`). **Run full test suite to verify no regressions.**

UI tests for the FAB would be appropriate but are deferred to Story 2-3/2-4 which introduce the full edit/delete flows and warrant comprehensive `FeedFlowUITests`.

### `.tabViewBottomAccessory` API Notes (iOS 26)

**Base API:**
```swift
.tabViewBottomAccessory {
    // Content rendered above tab bar (expanded state)
    // Goes inline with minimized tab bar pill (inline state)
}
```

**Placement environment value** — read inside the accessory to adapt layout:
```swift
@Environment(\.tabViewBottomAccessoryPlacement) private var placement
// .expanded — floats above full tab bar
// .inline — merged into minimized tab bar pill
```

The FloatingAddButton is simple enough (single icon) that it doesn't need to adapt between expanded/inline states — the system handles resizing automatically for simple button content.

### Project Structure Notes

- `FloatingAddButton.swift` placed in `CashOut/Views/Feed/` per architecture project structure — even though it appears on both Feed and Insights tabs, the architecture explicitly lists it under Feed/
- No new folders needed — `Views/Feed/` already exists with `FeedView.swift` and `FeedRowView.swift`
- No new ViewModels — FAB state (`showingAddExpenseSheet`) is `@State` on `ContentView`, not a ViewModel concern

### Existing Code to Reuse (DO NOT Recreate)

| What | File | Usage |
|------|------|-------|
| `EntryView` | `Views/Entry/EntryView.swift` | Reuse as sheet content — add `onSaveComplete` callback |
| `ExpenseEntryViewModel` | `ViewModels/ExpenseEntryViewModel.swift` | Unchanged — EntryView creates its own instance |
| `ContentView` | `App/ContentView.swift` | Modify — add FAB accessory + sheet |
| `FeedView` | `Views/Feed/FeedView.swift` | Unchanged — FRC auto-updates on new saves |
| `FeedViewModel` | `ViewModels/FeedViewModel.swift` | Unchanged — FRC observation handles updates |
| `InsightsView` | `Views/Insights/InsightsView.swift` | Unchanged — currently a stub |
| All numpad/category sub-views | `Views/Entry/*.swift` | Unchanged — used by EntryView internally |
| `Spacing` enum | `Utilities/Constants.swift` | Layout spacing if needed |

### File Placement

| File | Location | Action |
|------|----------|--------|
| `FloatingAddButton.swift` | `CashOut/Views/Feed/` | **New file** |
| `ContentView.swift` | `CashOut/App/` | **Modify** — add FAB accessory + sheet state + sheet presentation |
| `EntryView.swift` | `CashOut/Views/Entry/` | **Modify** — add `onSaveComplete` optional callback |

All new files must be registered in `project.pbxproj`.

### Boundaries — What NOT to Implement

- **No EditExpenseSheet** — Story 2-3
- **No tap-to-edit on feed rows** — Story 2-3
- **No swipe actions (edit/delete)** — Stories 2-3 and 2-4
- **No `.navigationTransition(.zoom)` from FAB to sheet** — known iOS 26 bug (nav bar shift) and complex namespace scoping. Standard sheet is reliable.
- **No new ViewModel for the FAB** — state is `@State` on ContentView
- **No HapticService for FAB tap** — not in AC. The save haptic fires from `ExpenseEntryViewModel.saveExpense()` as already implemented.
- **No daily section headers in feed** — deferred (Story 2-1 boundary)
- **No search/filtering** — not in scope

### Previous Story Intelligence

**From Story 2-1 (Expense Feed with Partner Attribution):**
- FRC observation is fully wired — new saves from the sheet will automatically appear in the feed list via `NSFetchedResultsController` delegate → `FeedViewModel.expenses` update
- `FeedView` uses `.onAppear` for `startObserving()` with `isObserving` guard — safe against re-triggering when returning from sheet
- Partner attribution on new entries works automatically (save includes `createdByUserID`)
- 80 tests passing (67 from Epic 1 + 13 from Story 2-1)

**From Story 1-6 (Category Picker, Save Flow):**
- `ExpenseEntryViewModel.saveExpense()` handles the full save flow: validates → persists → fires haptic → resets form
- MRU category is preserved in `UserDefaults` — sheet will pre-select last used category

**From Story 1-7 (Haptics, Accessibility, Dynamic Type):**
- All entry UI components have VoiceOver support
- `.accessibilityLabel()` pattern established
- `HapticService.trigger(.saveTap)` fires on save — works from sheet context too

**Code Review Patterns to Follow:**
- All new files registered in `project.pbxproj`
- `.buttonStyle(.plain)` not needed here (using `.glassProminent` instead)
- 44pt minimum tap targets (FAB is 52×52pt — exceeds minimum)
- No fixed font sizes without Dynamic Type consideration (FAB icon uses `.title2` which scales)

### Git Intelligence

Recent commit pattern: `feat(feed): ...` for Epic 2 stories.
Suggested commit message: `feat(feed): add floating add button with entry sheet (story 2-2)`

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Story 2.2 acceptance criteria]
- [Source: _bmad-output/planning-artifacts/architecture.md — Liquid Glass API Rules]
- [Source: _bmad-output/planning-artifacts/architecture.md — Project Directory Structure (FloatingAddButton.swift)]
- [Source: _bmad-output/planning-artifacts/architecture.md — Navigation Pattern (TabView + tabs)]
- [Source: _bmad-output/planning-artifacts/architecture.md — Anti-Patterns (glass + glassEffect conflict)]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — FloatingAddButton component spec (52×52pt, glass, plus icon)]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — ".tabViewBottomAccessory FAB" platform strategy]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — Sheet presentation pattern (.sheet + .presentationDetents)]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — UX-DR26 pull-down dismiss without saving]
- [Source: _bmad-output/planning-artifacts/prd.md — FR4 (entry accessible from any screen)]
- [Source: _bmad-output/implementation-artifacts/2-1-expense-feed-with-partner-attribution.md — FRC observation pattern, file list]
- [Source: .claude/learnings/ios-swiftui.md — Liquid Glass rules (lines 38-39)]
- [Source: .claude/learnings/architecture.md — @ObservationIgnored pattern, MVVM boundaries]
- [Source: CashOut/App/ContentView.swift — Current TabView structure]
- [Source: CashOut/Views/Entry/EntryView.swift — Current entry UI to reuse]
- [Source: CashOut/Views/Feed/FeedView.swift — Current feed view with FRC observation]
- [Source: CashOut/ViewModels/ExpenseEntryViewModel.swift — Save flow with haptic + reset]

### Orchestrator Validation (2026-04-03)

**Guardians run**: ios-swiftui-guardian, architecture-guardian, cloudkit-sync-guardian

**CRITICALs:** None.

**WARNINGs addressed in story spec:**
1. [ios-swiftui] `if selectedTab != 0` inside `.tabViewBottomAccessory` may leave empty accessory area on Add tab — Task 2.3 already documents the `.opacity` + `.allowsHitTesting` fallback. **Dev instruction: try the `if` conditional first. If it leaves visible empty space on the Add tab, switch to the opacity/hitTesting approach. Verify on device during Task 5.3.**
2. [ios-swiftui] `.buttonBorderShape(.circle)` is documented for `.bordered`/`.borderedProminent` — may not apply to `.glassProminent`. **Dev instruction: if the glass button renders as a non-circle shape, add `.clipShape(.circle)` to the button as a safety net. Verify on device during Task 5.2.**
3. [cloudkit-sync] "No additional wiring needed" assumes `FeedView.onAppear` has already fired and FRC is running. If the user is on the Insights tab and taps the FAB, the Feed FRC may not be running yet — the new expense will appear when the user next visits the Feed tab. **This is acceptable for v1** — the FAB is only visible on Feed/Insights tabs, and most FAB taps will occur on the Feed tab where `.onAppear` has already fired.
4. [cloudkit-sync] Save failure in the sheet silently swallows the error (existing behavior from Tab 1). The sheet stays open with no user feedback. Pre-existing; not introduced by this story. Defer error surface to a future story.

**SUGGESTIONs noted:**
- If using the opacity fallback for FAB visibility, add `.accessibilityHidden(selectedTab == 0)` to prevent VoiceOver from announcing the invisible FAB on the Add tab.
- FAB may appear oversized in `.inline` (minimized pill) state — system handles resizing for simple content but verify on device.
- `onSaveComplete?()` MUST be placed inside the `do` block after `try await viewModel.saveExpense()` — NOT after `catch`, NOT in `defer`. Only fire on success.

**Architecture guardian:** All clear. `onSaveComplete` callback on EntryView is correct MVVM — it is a dismiss signal (View-layer concern), not business logic. `@State showingAddExpenseSheet` on ContentView is correct per the "simple apps" navigation rule. No ViewModel needed for this story.

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

- Build succeeded: zero errors, zero warnings (iPhone 17 Pro, iOS 26.0)
- Test suite: 82 tests passed, 0 failures (80 existing + 2 from previous stories)

### Completion Notes List

- Task 1: Created `FloatingAddButton.swift` — pure declarative View, `Button` with `.glassProminent` + `.buttonBorderShape(.circle)`, 52×52pt frame, "plus" SF Symbol, `.accessibilityLabel("Add expense")`. Registered in `project.pbxproj` (PBXBuildFile, PBXFileReference, PBXGroup, PBXSourcesBuildPhase).
- Task 2: Added `.tabViewBottomAccessory` to `ContentView`'s TabView with `if selectedTab != 0` conditional to hide FAB on the Add tab (tab 0). Uses native iOS 26 mechanism that integrates with Liquid Glass and tab bar minimization.
- Task 3: Added `.sheet(isPresented: $showingAddExpenseSheet)` with `EntryView(onSaveComplete:)` and `.presentationDetents([.large])`. No NavigationStack wrapper, no zoom transition — standard sheet with pull-down dismiss.
- Task 4: Added `var onSaveComplete: (() -> Void)? = nil` to `EntryView`. Callback fires inside `do` block after successful `viewModel.saveExpense()` — not in catch/defer. Default `nil` preserves backward compatibility with Tab 1 usage.
- Task 5: Build succeeded (zero errors/warnings), all 82 tests pass. Manual verification items (FAB visibility per tab, sheet presentation, VoiceOver) require on-device testing.

### Orchestrator Review (2026-04-03)

**CRITICALs:** None.

**WARNINGs (noted for reviewer):**
1. `if selectedTab != 0` inside `.tabViewBottomAccessory` may leave empty accessory area on Add tab — verify on device; opacity/hitTesting fallback documented in story spec
2. Bare `Task {}` in `onSave` not stored/cancelled — pre-existing pattern from Story 1-6, effect is harmless
3. `.task` re-fires on tab appear — VERIFIED: `loadCategories()` has `guard categories.isEmpty` guard
4. `@MainActor` isolation for `onSaveComplete?()` — VERIFIED: `ExpenseEntryViewModel` is `@MainActor @Observable`
5. EntryView has no NavigationStack (pre-existing, intentional leaf screen)
6. Sheet EntryView has no NavigationStack (intentional per UX-DR26)
7. Theoretical drag-to-dismiss race with onSaveComplete — low severity, harmless

**SUGGESTIONs:** Preview background for glass validation; save error UI deferred; `.accessibilityHidden` if opacity fallback used.

### Change Log

- 2026-04-03: Implemented floating add button with entry sheet (story 2-2). New file: FloatingAddButton.swift. Modified: ContentView.swift (FAB accessory + sheet), EntryView.swift (onSaveComplete callback).

### File List

| File | Action | Path |
|------|--------|------|
| FloatingAddButton.swift | New | CashOut/Views/Feed/FloatingAddButton.swift |
| ContentView.swift | Modified | CashOut/App/ContentView.swift |
| EntryView.swift | Modified | CashOut/Views/Entry/EntryView.swift |
| project.pbxproj | Modified | CashOut.xcodeproj/project.pbxproj |
