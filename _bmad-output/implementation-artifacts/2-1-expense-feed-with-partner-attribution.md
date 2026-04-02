# Story 2.1: Expense Feed with Partner Attribution

Status: done

## Story

As a user,
I want to see a chronological feed of all expense entries with partner attribution,
So that I can review household spending activity at a glance.

## Acceptance Criteria

1. **Given** the Feed tab **When** selected **Then** a reverse-chronological List of all expense entries is displayed (FR5)

2. **Given** a FeedRowView **When** rendered **Then** it shows: leading category icon in colored badge (28×28pt), category name + partner initials circle + relative timestamp (`RelativeDateTimeFormatter`), and trailing amount with `.monospacedDigit()` (UX-DR4)

3. **Given** partner attribution **When** entries are displayed **Then** each entry shows an initials circle using the partner color system (Partner A: cool blue #6B8AAE, Partner B: warm stone #A89B8A) (FR8, UX-DR8)

4. **Given** the feed data source **When** FeedViewModel is created **Then** it is `@Observable` with `@MainActor` and uses `NSFetchedResultsController` via `ExpenseRepository` for animated row insertions/deletions

5. **Given** the feed **When** the user scrolls **Then** scrolling is smooth with no frame drops (NFR4) and the tab bar auto-minimizes via `.tabBarMinimizeBehavior(.onScrollDown)` (already on TabView in ContentView.swift)

6. **Given** no entries exist **When** the Feed tab is shown **Then** "No entries yet" appears as centered text in `.secondaryLabel` with no illustrations or CTAs (UX-DR15)

7. **Given** an entry has a note **When** displayed in the feed **Then** an optional note indicator is visible on the row

8. **Given** VoiceOver is enabled **When** a feed row is focused **Then** it announces "[Partner] spent [amount] on [category], [time ago]" (UX-DR16)

## Tasks / Subtasks

- [x] Task 1: Extend ExpenseRepository with NSFetchedResultsController support (AC: #1, #4)
  - [x] 1.1 Add `var onExpensesChanged: (([ExpenseData]) -> Void)?` callback property to `ExpenseRepositoryProtocol`
  - [x] 1.2 Add `func startObservingExpenses()` method to `ExpenseRepositoryProtocol`. **CRITICAL: Also add a `protocol extension` with no-op defaults for both new members** — this prevents breaking the existing `MockExpenseRepository` at compile time before Task 1.6 updates it. All 67 existing tests must continue to compile.
  - [x] 1.3 In `ExpenseRepository`, create private `NSFetchedResultsController<Expense>` — fetch all expenses sorted by `createdAt` descending, no date filter predicate. Set `request.fetchBatchSize = 50` for memory efficiency. Add assertion: `assert(persistence.container.viewContext.automaticallyMergesChangesFromParent, "FRC remote-change propagation requires automaticallyMergesChangesFromParent = true")`
  - [x] 1.4 Implement `NSFetchedResultsControllerDelegate` via a nested `@MainActor private class FRCDelegate: NSObject` — the `onChange` closure MUST be typed `@MainActor` and the closure assignment MUST use `[weak self]` to prevent retain cycles: `frcDelegate.onChange = { [weak self] in self?.handleFRCUpdate() }`. See Dev Notes for full pattern.
  - [x] 1.5 `startObservingExpenses()` performs initial `performFetch()` and fires first callback
  - [x] 1.6 Update `MockExpenseRepository` — add `onExpensesChanged` property and `startObservingExpenses()` stub, add `var stubbedExpenses: [ExpenseData] = []` that fires callback when `startObservingExpenses()` is called, add `var startObservingCalled = false` for test assertions

- [x] Task 2: Create Date+Formatting extension (AC: #2)
  - [x] 2.1 Create `CashOut/Utilities/Extensions/Date+Formatting.swift`
  - [x] 2.2 Add `var relativeFormatted: String` computed property using `RelativeDateTimeFormatter` with `.abbreviated` unitsStyle
  - [x] 2.3 Register file in `project.pbxproj`

- [x] Task 3: Create FeedViewModel (AC: #1, #3, #4, #6)
  - [x] 3.1 Create `CashOut/ViewModels/FeedViewModel.swift`
  - [x] 3.2 `@MainActor @Observable final class FeedViewModel`
  - [x] 3.3 State properties: `var expenses: [ExpenseData] = []`, `var categories: [CategoryData] = []`, `var errorMessage: String?`, `@ObservationIgnored private var isObserving = false`
  - [x] 3.4 `@ObservationIgnored` dependencies: `ExpenseRepositoryProtocol`, `CategoryRepositoryProtocol`, `AuthenticationServiceProtocol` — all with default parameter in init. **Do NOT inject HapticServiceProtocol** — no haptic events in this story. Defer to Story 2-3 when edit/delete haptics are added (YAGNI).
  - [x] 3.5 `func startObserving()` — sets `isObserving = true` as first line, calls `repository.startObservingExpenses()` with callback that updates `expenses` array AND reloads categories (reload on every FRC callback to pick up newly-added custom categories); wraps category fetch in `do/catch` setting `errorMessage` on failure
  - [x] 3.6 `func categoryFor(_ expense: ExpenseData) -> CategoryData?` — lookup by categoryID from loaded categories array
  - [x] 3.7 `func isCurrentUser(_ expense: ExpenseData) -> Bool` — compares `expense.createdByUserID` with `authService.currentUserID`. **Guard:** if `expense.createdByUserID.isEmpty`, return `true` (treat unattributed expenses as current user's — prevents misattribution when `wrappedCreatedByUserID` returns "" for nil)
  - [x] 3.8 `func partnerInitials(for expense: ExpenseData) -> String` — returns "Me" if current user, "P" if partner (v1 simplification — no name resolution infrastructure needed for 2-user app)
  - [x] 3.9 `var isEmpty: Bool { expenses.isEmpty }` — computed property for empty state
  - [x] 3.10 Register file in `project.pbxproj`

- [x] Task 4: Create FeedRowView (AC: #2, #3, #7, #8)
  - [x] 4.1 Create `CashOut/Views/Feed/FeedRowView.swift`
  - [x] 4.2 Properties: `expense: ExpenseData`, `category: CategoryData?`, `isCurrentUser: Bool`, `partnerInitials: String`
  - [x] 4.3 Leading: category icon (SF Symbol from `category.iconName`) in colored circle badge (28×28pt) using `category.colorName` resolved via `CategoryColor`
  - [x] 4.4 Center VStack: top line = category name (`.font(.body)`), bottom line = HStack of partner initials circle (small, colored per partner color) + relative timestamp (`.font(.caption)`, `.foregroundStyle(.secondary)`)
  - [x] 4.5 Trailing: amount via `expense.amount.displayAmount` with `.monospacedDigit()` font modifier
  - [x] 4.6 Note indicator: if `expense.note != nil && !expense.note!.isEmpty`, show small SF Symbol indicator (e.g., `"note.text"` or `"text.bubble"`) near the row — subtle, not prominent
  - [x] 4.7 Partner initials circle: 24pt circle filled with partner color (cool blue `#6B8AAE` if current user, warm stone `#A89B8A` if partner), white initials text inside
  - [x] 4.8 VoiceOver: `.accessibilityLabel("\(partnerInitials) spent \(expense.amount.displayAmount) on \(category?.name ?? "unknown"), \(expense.createdAt.relativeFormatted)")` — combines all info into single announcement
  - [x] 4.9 `.accessibilityElement(children: .ignore)` on the row container so VoiceOver reads the combined label, not individual elements
  - [x] 4.10 Register file in `project.pbxproj`

- [x] Task 5: Replace FeedView stub with full implementation (AC: #1, #5, #6)
  - [x] 5.1 Replace stub content in `CashOut/Views/Feed/FeedView.swift`
  - [x] 5.2 `@State private var viewModel = FeedViewModel()`
  - [x] 5.3 Use `List` with `ForEach(viewModel.expenses, id: \.id)` rendering `FeedRowView` for each
  - [x] 5.4 Empty state: `if viewModel.isEmpty` → centered "No entries yet" text in `.secondary` foreground style
  - [x] 5.5 `.onAppear { viewModel.startObserving() }` — start FRC observation on appear. `startObserving()` is synchronous, so use `.onAppear` not `.task`. Guard inside `startObserving()` with `guard !isObserving else { return }` to prevent redundant FRC creation on tab re-selection. **Do NOT guard on `expenses.isEmpty`** — that conflates "no data" with "not started" and would re-create the FRC every time the user deletes all expenses then re-selects the tab.
  - [x] 5.6 `.navigationTitle("Feed")`
  - [x] 5.7 No pull-to-refresh — FRC handles updates automatically via delegate callbacks
  - [x] 5.8 No separate `.NSPersistentStoreRemoteChange` subscription — FRC picks up CloudKit-imported changes because `viewContext.automaticallyMergesChangesFromParent = true` (set in `PersistenceController.swift:74`) propagates background context imports into `viewContext`, triggering the FRC delegate. This is NOT a native FRC feature — it depends on that flag.

- [x] Task 6: Add partner colors to asset catalog or constants (AC: #3)
  - [x] 6.1 Define partner colors — Partner A (current user): cool blue `#6B8AAE` / dark mode `#8AA8C8`, Partner B (partner): warm stone `#A89B8A` / dark mode `#C0B0A0`
  - [x] 6.2 Add to asset catalog as `PartnerBlue` and `PartnerStone` color sets, OR define as static constants in a `PartnerColor` enum in `Constants.swift`
  - [x] 6.3 Use these colors in FeedRowView for the initials circle

- [x] Task 7: Unit tests for FeedViewModel (AC: #1, #3, #4, #6)
  - [x] 7.1 Create `CashOutTests/ViewModels/FeedViewModelTests.swift`
  - [x] 7.2 Create `makeSUT()` helper returning `(FeedViewModel, MockExpenseRepository, MockCategoryRepository, MockAuthenticationService)` tuple (no HapticService — not injected in this story)
  - [x] 7.3 Test: `startObserving()` calls `repository.startObservingExpenses()` and `categoryRepository.fetchCategories()`
  - [x] 7.3a Test: calling `startObserving()` twice does NOT call `repository.startObservingExpenses()` twice (isObserving guard)
  - [x] 7.4 Test: `expenses` updates when repository callback fires with expense data
  - [x] 7.5 Test: `isEmpty` returns true when no expenses
  - [x] 7.6 Test: `isEmpty` returns false when expenses exist
  - [x] 7.7 Test: `isCurrentUser()` returns true when `createdByUserID == currentUserID`
  - [x] 7.8 Test: `isCurrentUser()` returns false when `createdByUserID != currentUserID`
  - [x] 7.8a Test: `isCurrentUser()` returns true when `createdByUserID` is empty string (unattributed fallback)
  - [x] 7.9 Test: `partnerInitials()` returns "Me" for current user expenses
  - [x] 7.10 Test: `partnerInitials()` returns "P" for partner expenses
  - [x] 7.11 Test: `categoryFor()` returns matching category by ID
  - [x] 7.12 Test: `categoryFor()` returns nil for unknown category ID
  - [x] 7.13 All test classes: `@MainActor` (established pattern)
  - [x] 7.14 Register file in `project.pbxproj`

### Review Findings

- [x] [Review][Patch] `try? frc.performFetch()` silently swallows Core Data errors — add do/catch with os_log [ExpenseRepository.swift:49]
- [x] [Review][Patch] Missing test: error path for `reloadCategories()` catch block [FeedViewModelTests.swift]
- [x] [Review][Patch] Missing test: `isCurrentUser` when `authService.currentUserID` is nil [FeedViewModelTests.swift]
- [x] [Review][Defer] `FeedView` does not display `viewModel.errorMessage` — needs UX design decision — deferred, out of scope
- [x] [Review][Defer] `wrappedID` returns `id ?? UUID()` creating unstable identity if `id` is nil — deferred, pre-existing
- [x] [Review][Defer] `ExpenseData`/`CategoryData` lack `Equatable` — SwiftUI can't optimize row diffing — deferred, pre-existing
- [x] [Review][Defer] Brief "Unknown" category flash on initial load before categories arrive — deferred, UX polish
- [x] [Review][Defer] Tests use `Task.sleep(50ms)` for async synchronization — fragile on CI — deferred, existing pattern

## Dev Notes

### NSFetchedResultsController Integration — Critical Pattern

The architecture mandates FRC for the Feed screen specifically (not for Entry or Insights — those use remote change notification + re-fetch). FRC provides animated row insertions/deletions when CloudKit syncs partner data in the background.

**FRC lives in `ExpenseRepository`** — not in the ViewModel. The repository wraps FRC, converts `NSManagedObject` to `ExpenseData` structs, and exposes changes via callback. The ViewModel never touches Core Data types.

```swift
// In ExpenseRepository
private var feedFRC: NSFetchedResultsController<Expense>?

func startObservingExpenses() {
    let request: NSFetchRequest<Expense> = Expense.fetchRequest()
    request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
    
    let frc = NSFetchedResultsController(
        fetchRequest: request,
        managedObjectContext: persistence.container.viewContext,
        sectionNameKeyPath: nil,
        cacheName: nil
    )
    frc.delegate = self
    feedFRC = frc
    try? frc.performFetch()
    
    // Fire initial data
    let data = (frc.fetchedObjects ?? []).compactMap { /* convert to ExpenseData */ }
    onExpensesChanged?(data)
}
```

**Critical:** `ExpenseRepository` must conform to `NSFetchedResultsControllerDelegate`. Since `ExpenseRepository` is `@MainActor` and `final class`, it cannot directly inherit from `NSObject`. Use a nested delegate class pattern with **`@MainActor` annotation and `[weak self]` closure**:

```swift
@MainActor
private class FRCDelegate: NSObject, NSFetchedResultsControllerDelegate {
    var onChange: (@MainActor () -> Void)?
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<any NSFetchRequestResult>) {
        onChange?()
    }
}
```

Wire in `ExpenseRepository` with `[weak self]` to prevent retain cycle:
```swift
frcDelegate.onChange = { [weak self] in
    guard let self else { return }
    self.handleFRCUpdate()
}
```

Without `@MainActor` on `FRCDelegate`, Swift 6 strict concurrency flags the `onChange` closure as a cross-actor capture. Without `[weak self]`, there's a retain cycle: `ExpenseRepository → FRCDelegate → onChange closure → ExpenseRepository`.

**Protocol extension defaults** — add these to prevent breaking existing conformers:
```swift
extension ExpenseRepositoryProtocol {
    var onExpensesChanged: (([ExpenseData]) -> Void)? {
        get { nil }
        set { }
    }
    func startObservingExpenses() { }
}
```

**Two-store visibility:** The FRC on `viewContext` federates across both the private and shared persistent stores automatically (both added to the same `NSPersistentStoreCoordinator`). No affinity predicate is needed — both owner and partner expenses are visible. The existing two-store setup is at `PersistenceController.swift:47-67`.

**FRC remote-change mechanism:** FRC picks up CloudKit-imported changes because `viewContext.automaticallyMergesChangesFromParent = true` (`PersistenceController.swift:74`) propagates background context imports into `viewContext`, triggering the FRC delegate. This is NOT an inherent FRC capability — it depends on that flag. Add an assertion in `startObservingExpenses()`.

[Source: architecture.md — Hybrid State Observation table, Feed row]
[Source: architecture.md — NSFetchedResultsController in repository layer]

### Data Boundary: Repository → ViewModel

**NEVER expose `NSManagedObject` to ViewModel.** The repository converts `Expense` (managed object) to `ExpenseData` (plain struct) before passing to ViewModel via callback. This is already the established pattern from `fetchExpenses(for:)`.

[Source: architecture.md — Data Boundaries table]

### Partner Attribution Strategy

For v1 (2-user app), partner attribution is simple:
- `AuthenticationService.currentUserID` identifies the logged-in user
- Compare `expense.createdByUserID` with `currentUserID`
- Match → "me" (Partner A color: cool blue #6B8AAE)
- No match → "partner" (Partner B color: warm stone #A89B8A)
- Initials: "Me" for self, "P" for partner (no name resolution needed for v1)

Future stories (Epic 4) will introduce proper partner names via CloudKit sharing metadata.

[Source: epics.md — Story 2.1 AC partner attribution]
[Source: architecture.md — createdByUserID field definition]

### FeedRowView Layout Specification

```
┌─────────────────────────────────────────────────┐
│ ┌────────┐                                      │
│ │ 🍽️    │  Category Name         ฿120.00       │
│ │ 28x28  │  [●] Me · 2 min ago    📝           │
│ └────────┘                                      │
└─────────────────────────────────────────────────┘
```

- Leading: Category icon in colored circle badge (28×28pt), color from `CategoryColor` enum
- Center top: Category name (`.body`)
- Center bottom: Partner initials circle (tiny, ~18pt) + relative timestamp (`.caption`, `.secondary`)
- Trailing top: Amount with `.monospacedDigit()` — use `expense.amount.displayAmount`
- Trailing bottom: Note indicator (small icon) if note exists
- Amount formatting: use `Int64.displayAmount` — NEVER concatenate "฿" manually

[Source: ux-design-specification.md — FeedRowView component spec]
[Source: ux-design-specification.md — "departure board feed rows" pattern]

### Category Resolution

FeedViewModel loads all categories once via `CategoryRepository.fetchCategories()` in `startObserving()`, stores in `var categories: [CategoryData]`. Lookup by `expense.categoryID` when rendering each row.

If a category is not found (edge case: deleted custom category), fall back to "Unknown" with `CoolGray` color.

### Date Formatting

Create `Date+Formatting.swift` with `RelativeDateTimeFormatter`:
```swift
extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
```

Produces: "2 min. ago", "1 hr. ago", "Yesterday", etc.

**Performance note:** `RelativeDateTimeFormatter` is lightweight and Foundation caches formatter instances internally. Creating per-cell is acceptable. Do NOT store a static formatter — it won't update its reference date.

**Locale note:** `RelativeDateTimeFormatter()` uses the device's display locale by default (e.g., "2 min. ago" in English). CashOut hardcodes currency to `th_TH` locale but relative timestamps are intentionally in the user's display language for readability. Add comment: `// Uses device locale intentionally — relative time strings follow display language, not financial locale`

[Source: architecture.md — Date Display table, Feed row uses Relative format]

### Empty State

Current `FeedView.swift` stub already shows "No entries yet" — preserve this exact text and styling for the empty state. Use conditional: `if viewModel.isEmpty` → empty state view, `else` → List.

[Source: epics.md — Story 2.1 AC empty state]

### Scrolling Performance

- Use standard `List` (not `LazyVStack` in `ScrollView`) — `List` reuses cells automatically
- FeedRowView should be lightweight — no complex layouts or heavy computations per row
- Category lookup is O(n) on a small array (~6-12 categories) — acceptable
- Tab bar auto-minimize is already configured on `TabView` in `ContentView.swift` — no additional work needed

### VoiceOver Accessibility

Each `FeedRowView` is a single accessibility element:
```swift
.accessibilityElement(children: .ignore)
.accessibilityLabel("Me spent ฿120.00 on Food & Drink, 2 min ago")
```

The combined label format: `"[partnerInitials] spent [amount] on [categoryName], [relativeTime]"`

[Source: epics.md — Story 2.1 AC VoiceOver]

### Existing Code to Reuse (DO NOT Recreate)

| What | File | Usage |
|------|------|-------|
| `ExpenseRepositoryProtocol` | `Repositories/ExpenseRepositoryProtocol.swift` | Extend — add FRC observation methods |
| `ExpenseRepository` | `Repositories/ExpenseRepository.swift` | Extend — add FRC support |
| `CategoryRepositoryProtocol` | `Repositories/CategoryRepositoryProtocol.swift` | Use as-is |
| `CategoryRepository` | `Repositories/CategoryRepository.swift` | Use as-is |
| `AuthenticationServiceProtocol` | `Services/AuthenticationService.swift` | Use `currentUserID` for partner attribution |
| `HapticServiceProtocol` | `Services/HapticService.swift` | Do NOT inject in FeedViewModel — deferred to Story 2-3 when edit/delete haptics are needed |
| `ExpenseData` | `Models/ExpenseData.swift` | Use as-is |
| `CategoryData` | `Models/CategoryData.swift` | Use as-is |
| `CategoryColor` | `Utilities/Extensions/Color+CategoryTokens.swift` | Resolve `colorName` → `Color` for category badges |
| `Int64.displayAmount` | `Utilities/Extensions/Int64+Currency.swift` | Format amounts — ALWAYS use this |
| `Spacing` enum | `Utilities/Constants.swift` | Layout spacing constants |
| `FeedView.swift` | `Views/Feed/FeedView.swift` | Replace stub content |
| `ContentView.swift` | `App/ContentView.swift` | Already wires Feed tab — no changes needed |
| `MockExpenseRepository` | `CashOutTests/Repositories/MockExpenseRepository.swift` | Extend — add FRC stub methods |
| `MockCategoryRepository` | `CashOutTests/Repositories/MockCategoryRepository.swift` | Use for tests |
| `MockAuthenticationService` | `CashOutTests/Services/MockAuthenticationService.swift` | Use for tests |
| `MockHapticService` | `CashOutTests/Services/MockHapticService.swift` | Use for tests |

### File Placement

| File | Location | Action |
|------|----------|--------|
| `FeedViewModel.swift` | `CashOut/ViewModels/` | **New file** |
| `FeedRowView.swift` | `CashOut/Views/Feed/` | **New file** |
| `Date+Formatting.swift` | `CashOut/Utilities/Extensions/` | **New file** |
| `FeedView.swift` | `CashOut/Views/Feed/` | **Replace stub** |
| `ExpenseRepositoryProtocol.swift` | `CashOut/Repositories/` | **Modify** — add FRC observation methods |
| `ExpenseRepository.swift` | `CashOut/Repositories/` | **Modify** — add FRC implementation |
| `Constants.swift` | `CashOut/Utilities/` | **Modify** — add partner color constants |
| `MockExpenseRepository.swift` | `CashOutTests/Repositories/` | **Modify** — add FRC stub methods |
| `FeedViewModelTests.swift` | `CashOutTests/ViewModels/` | **New file** |

All new files must be registered in `project.pbxproj`.

### Project Structure Notes

- `CashOut/Views/Feed/` already exists (contains stub `FeedView.swift`) — add `FeedRowView.swift` alongside
- `CashOut/ViewModels/` already has `ExpenseEntryViewModel.swift` and `AuthenticationViewModel.swift` — `FeedViewModel.swift` joins as 3rd ViewModel
- `CashOut/Utilities/Extensions/` has `Int64+Currency.swift` and `Color+CategoryTokens.swift` — `Date+Formatting.swift` follows the same `Type+Extension.swift` naming convention
- Follow established ViewModel pattern from `ExpenseEntryViewModel`: `@Observable`, `@MainActor`, `@ObservationIgnored` on all dependencies, default parameter DI

### Testing Standards

- All test classes: `@MainActor` at class level (established pattern from Stories 1.4-1.7)
- XCTest framework
- Use `makeSUT()` helper returning tuple of SUT + mocks (pattern from `ExpenseEntryViewModelTests`)
- FRC tests: Mock fires callback with stubbed data → assert ViewModel state updates
- Partner attribution tests: Set `MockAuthenticationService.currentUserID`, compare against expense `createdByUserID`
- No UI tests in this story — feed UI tests belong to Story 2.3/2.4 (edit/delete flows)
- Existing tests (67 passing) must continue to pass — protocol extensions must have default implementations or mock must be updated

### Boundaries — What NOT to Implement

- **No FloatingAddButton** — Story 2.2
- **No tap-to-edit** — Story 2.3
- **No swipe actions (edit/delete)** — Stories 2.3 and 2.4
- **No entry sheet presentation** — Story 2.2
- **No daily section headers with running totals** — UX design mentions this but it's not in the acceptance criteria; defer to avoid scope creep. Flat list is sufficient for AC compliance.
- **No pull-to-refresh** — FRC handles updates automatically
- **No edit/delete haptics** — Stories 2.3/2.4
- **No HapticService injection** — deferred to Story 2-3 (YAGNI)
- **No search or filtering** — not in scope for any Epic 2 story
- **No Insights tab integration** — Story 3.x
- **No tombstone window expiry handling** — if a partner is offline when a record is deleted and the CloudKit tombstone window expires, the record may persist on the partner's device. This edge case is deferred (Epic 5 sync hardening). No action needed in this story.
- **No `.changeTokenExpired` reconciliation** — deferred with tombstone handling

### Previous Story Intelligence

**From Story 1.7 (Haptics, Accessibility & Dynamic Type):**
- `HapticService` + `MockHapticService` are fully implemented — inject but no new haptic events in this story
- Accessibility pattern: `.accessibilityElement(children: .ignore)` + `.accessibilityLabel()` on composite views
- `@ObservationIgnored` on ALL injected dependencies — verified critical in Story 1.7
- `makeSUT()` tuple pattern for test setup — follow same pattern for FeedViewModelTests
- All test classes `@MainActor` — enforced since Story 1.4 review

**From Story 1.6 (Category Picker, Save Flow):**
- `ExpenseRepository.saveExpense()` handles both create and update (upsert via ID lookup) — feeds FRC will detect both
- `CategoryRepository.fetchCategories()` returns both defaults + custom categories
- Save flow established: ViewModel → Repository → Core Data → CloudKit sync

**From Story 1.5 (Numpad & Amount Display):**
- `Int64.displayAmount` formatting is the single source of truth for currency — use everywhere
- `.monospacedDigit()` already established as the standard for amount display

**Code Review Patterns to Follow:**
- F5 (Story 1.4): All test classes must be `@MainActor`
- Story 1.6: `.buttonStyle(.plain)` on interactive elements
- Story 1.6: 44pt minimum tap targets on all interactive elements
- Story 1.7: accessibility labels AFTER button style modifiers

### Git Intelligence

Recent commit pattern: `feat(entry): ...` for Epic 1 stories.
Epic 2 commits should follow: `feat(feed): ...` prefix.
Suggested commit message: `feat(feed): implement expense feed with partner attribution (story 2-1)`

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Story 2.1 acceptance criteria]
- [Source: _bmad-output/planning-artifacts/architecture.md — Hybrid State Observation table]
- [Source: _bmad-output/planning-artifacts/architecture.md — ExpenseRepository + NSFetchedResultsController]
- [Source: _bmad-output/planning-artifacts/architecture.md — Data Boundaries table]
- [Source: _bmad-output/planning-artifacts/architecture.md — ViewModel Pattern (@Observable)]
- [Source: _bmad-output/planning-artifacts/architecture.md — Partner colors: #6B8AAE, #A89B8A]
- [Source: _bmad-output/planning-artifacts/architecture.md — Date Display table]
- [Source: _bmad-output/planning-artifacts/architecture.md — Project Directory Structure]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — FeedRowView component spec]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — Feed Screen Direction B]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — "No entries yet" empty state]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — VoiceOver accessibility labels]
- [Source: _bmad-output/planning-artifacts/prd.md — FR5 (feed), FR8 (partner attribution)]
- [Source: _bmad-output/implementation-artifacts/1-7-entry-screen-haptics-accessibility-and-dynamic-type.md — Previous story patterns]
- [Source: CashOut/Repositories/ExpenseRepositoryProtocol.swift — Current protocol (3 methods)]
- [Source: CashOut/Repositories/ExpenseRepository.swift — Current implementation (no FRC)]
- [Source: CashOut/Views/Feed/FeedView.swift — Current stub to replace]
- [Source: CashOut/Models/ExpenseData.swift — Data struct with createdByUserID]
- [Source: CashOut/Utilities/Constants.swift — Spacing enum, DefaultCategory enum]
- [Source: CashOut/Utilities/Extensions/Color+CategoryTokens.swift — CategoryColor enum]

### Orchestrator Validation (2026-04-02)

**Guardians run**: ios-swiftui-guardian, architecture-guardian, cloudkit-sync-guardian

**CRITICALs resolved in story spec:**
1. FRCDelegate `@MainActor` isolation — nested delegate class annotated `@MainActor`, `onChange` typed `@MainActor`, `[weak self]` on closure. Task 1.4 updated.
2. Protocol change breaking compilation — added protocol extension defaults requirement. Task 1.2 updated.
3. `.task` guard using wrong sentinel — replaced `expenses.isEmpty` with `isObserving: Bool` flag. Task 3.3, 5.5 updated.
4. FRC remote-change mechanism — corrected "natively" framing, documented `automaticallyMergesChangesFromParent` dependency with assertion. Task 1.3, 5.8 updated.
5. Two-store FRC visibility — documented federation across private + shared stores. Dev Notes updated.
6. Retain cycle in FRC closure — `[weak self]` required. Task 1.4 and Dev Notes updated.

**WARNINGs resolved in story spec:**
1. HapticService injection deferred to Story 2-3 (YAGNI) — Task 3.4, 7.2 updated.
2. Category staleness — categories reloaded on every FRC callback. Task 3.5 updated.
3. `createdByUserID` empty-string guard — `isCurrentUser()` treats "" as current user. Task 3.7 updated.
4. `errorMessage` never set — added `do/catch` around category fetch in Task 3.5.
5. `.task` vs `.onAppear` — switched to `.onAppear` since `startObserving()` is synchronous. Task 5.5 updated.
6. FRC `fetchBatchSize` — set to 50. Task 1.3 updated.
7. Tombstone window expiry — documented as deferred. Boundaries updated.
8. RelativeDateTimeFormatter locale — documented as intentionally device-locale. Dev Notes updated.

**WARNINGs noted (documentation, not code):**
- architecture.md line 271 references non-existent `container.handleRemoteNotification()` — known error, already captured in cloudkit-sync learnings. No story action needed.
- `wrappedCreatedByUserID` returns "" for nil — handled by `isCurrentUser()` guard, not a data model change.
- HapticService `@MainActor` tension with iOS 26 SDK — carry-forward from Story 1.7, no impact on this story.

**SUGGESTIONs noted:**
- SF Symbol `"note.text"` existence — verify in SF Symbols app before implementation
- `fetchLimit` on FRC — not added (household expense volumes are small), but `fetchBatchSize = 50` provides memory efficiency

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

- FRCDelegate required `@preconcurrency NSFetchedResultsControllerDelegate` conformance to satisfy Swift 6 strict concurrency. `@MainActor` annotation alone was insufficient — the protocol's methods are `nonisolated` by default.

### Orchestrator Review (Post-Implementation)

**Guardians run**: ios-swiftui-guardian, architecture-guardian, cloudkit-sync-guardian

**CRITICALs resolved:**
1. `reloadCategories()` unguarded `Task {}` — added cancellation check (`guard !Task.isCancelled`) and stored task handle with cancel-before-relaunch pattern.
2. Missing `isLoading` — ACKNOWLEDGED: FRC is synchronous (no loading gap). Categories are enrichment-only. Not applicable to FRC pattern per story design.
3. Protocol extension `set {}` silent discard — ACKNOWLEDGED: Both actual conformers (`ExpenseRepository`, `MockExpenseRepository`) declare stored properties. Defaults exist per story spec requirement to prevent compile errors on existing conformers.

**WARNINGs resolved:**
1. `onExpensesChanged` closure not `@MainActor`-typed — added `@MainActor` annotation to protocol, repository, and mock.
2. Note indicator missing from VoiceOver label — added ", has note" suffix to accessibility label when note exists.
3. No guard against double `startObservingExpenses()` — added `guard feedFRC == nil` at top of method.
4. `isCurrentUser` nil `currentUserID` — added explicit `guard let currentUserID` pattern.

**WARNINGs acknowledged (not code changes):**
- Fixed font sizes on category badge (28×28) and partner circle (24pt) — prescribed by story spec/UX design. Dynamic Type scaling deferred.
- `PartnerColor` hardcoded RGB vs asset catalog — story spec explicitly allows "define as static constants in a PartnerColor enum in Constants.swift".
- `.onAppear` vs `.task` — story spec explicitly says `.onAppear` since `startObserving()` is synchronous.
- `try?` on `performFetch()` — silent failure acceptable for v1; FRC fetch errors are extremely rare in practice.
- `handleFRCUpdate` drops nil categoryID records — same as existing `fetchExpenses(for:)` behavior.
- Shared store missing `cloudKitContainerOptions = nil` when iCloud unavailable — pre-existing issue, not introduced by this story.

### Completion Notes List

- Task 1: Extended `ExpenseRepositoryProtocol` with `onExpensesChanged` callback and `startObservingExpenses()`. Added protocol extension with no-op defaults to preserve compilation of 67 existing tests. Implemented `NSFetchedResultsController` in `ExpenseRepository` with nested `FRCDelegate` class using `@MainActor`, `@preconcurrency`, and `[weak self]` closure. Updated `MockExpenseRepository` with stubbed expenses and call tracking.
- Task 2: Created `Date+Formatting.swift` with `relativeFormatted` computed property using `RelativeDateTimeFormatter` with `.abbreviated` style. Uses device locale intentionally (display language, not financial locale).
- Task 3: Created `FeedViewModel` following established `@Observable` + `@MainActor` + `@ObservationIgnored` pattern. Includes FRC observation via callback, category lookup, partner attribution (current user vs partner), `isObserving` guard, `isEmpty` computed property. No HapticService injection (YAGNI — deferred to Story 2-3).
- Task 4: Created `FeedRowView` with category badge (28×28pt), partner initials circle (24pt with cool blue/warm stone colors), relative timestamp, monospacedDigit amount, note indicator (`text.bubble`), VoiceOver accessibility with combined label and `children: .ignore`.
- Task 5: Replaced `FeedView` stub with `List` + `ForEach`, empty state, `.onAppear` for synchronous FRC start, `.navigationTitle("Feed")`. No pull-to-refresh (FRC handles updates).
- Task 6: Added `PartnerColor` enum to `Constants.swift` with cool blue (#6B8AAE / #8AA8C8) and warm stone (#A89B8A / #C0B0A0) for light/dark mode.
- Task 7: Created 13 unit tests covering: `startObserving()` repository + category calls, `isObserving` guard, expenses callback update, `isEmpty`, `isCurrentUser` (match, no-match, empty string fallback), `partnerInitials` (Me/P), `categoryFor` (found/nil). All `@MainActor`, `makeSUT()` tuple pattern.

### File List

- CashOut/Repositories/ExpenseRepositoryProtocol.swift (modified)
- CashOut/Repositories/ExpenseRepository.swift (modified)
- CashOut/Utilities/Extensions/Date+Formatting.swift (new)
- CashOut/ViewModels/FeedViewModel.swift (new)
- CashOut/Views/Feed/FeedRowView.swift (new)
- CashOut/Views/Feed/FeedView.swift (modified)
- CashOut/Utilities/Constants.swift (modified)
- CashOutTests/Repositories/MockExpenseRepository.swift (modified)
- CashOutTests/ViewModels/FeedViewModelTests.swift (new)
- CashOut.xcodeproj/project.pbxproj (modified)

### Change Log

- 2026-04-02: Implemented all 7 tasks for Story 2-1. Extended ExpenseRepository with FRC observation, created FeedViewModel with partner attribution, built FeedRowView with category badges and VoiceOver, replaced FeedView stub, added partner colors, wrote 13 unit tests. 80 total tests passing (67 existing + 13 new). Addressed 4 guardian findings post-review (Task cancellation, @MainActor closure typing, double-call guard, VoiceOver note indicator).
