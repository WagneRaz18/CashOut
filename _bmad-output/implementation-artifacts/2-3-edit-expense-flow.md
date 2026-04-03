# Story 2.3: Edit Expense Flow

Status: review

## Story

As a user,
I want to edit an existing expense entry,
So that I can fix mistakes and keep my spending data accurate.

## Acceptance Criteria

1. **Given** a feed row **When** the user taps it **Then** an edit sheet opens with the same numpad/category UI pre-filled with the entry's amount, category, and note (FR6, UX-DR20)

2. **Given** a feed row **When** the user swipes left **Then** an "Edit" swipe action appears; tapping it opens the edit sheet (same behavior as tap) (UX-DR11)

3. **Given** the edit sheet **When** the user modifies the amount, category, or note and taps Save **Then** the entry is updated in Core Data via ExpenseRepository, a success haptic fires, and the sheet dismisses

4. **Given** the edited entry **When** saved **Then** `modifiedAt` is updated to current time and the feed row reflects the changes immediately via NSFetchedResultsController

5. **Given** the edit sheet **When** the user pulls down to dismiss without saving **Then** changes are abandoned with no "unsaved changes" warning (UX-DR26)

6. **Given** VoiceOver is enabled **When** the edit sheet opens **Then** pre-filled values are announced and all controls are accessible

## Tasks / Subtasks

- [x] Task 1: Add `Identifiable` conformance to `ExpenseData` (AC: #1)
  - [x] 1.1 In `CashOut/Models/ExpenseData.swift`, add `Identifiable` to the struct declaration: `struct ExpenseData: Sendable, Identifiable`. The existing `id: UUID` property satisfies the protocol automatically.
  - [x] 1.2 Verify all existing code compiles — `Identifiable` is additive, no breaking changes.

- [x] Task 2: Create `EditExpenseViewModel` (AC: #1, #3, #4)
  - [x] 2.1 Create `CashOut/ViewModels/EditExpenseViewModel.swift`
  - [x] 2.2 `@MainActor @Observable final class EditExpenseViewModel`
  - [x] 2.3 Observable properties: `var amountInCents: Int64 = 0`, `var categories: [CategoryData] = []`, `var selectedCategoryID: UUID?`, `var noteText: String = ""`, `var isSaving: Bool = false`
  - [x] 2.4 Computed: `var isAmountZero: Bool { amountInCents == 0 }`
  - [x] 2.5 `@ObservationIgnored` dependencies: `ExpenseRepositoryProtocol`, `CategoryRepositoryProtocol`, `HapticServiceProtocol` — all with default parameter in init. **No AuthenticationService** (createdByUserID preserved from original). **No UserDefaults** (MRU not updated on edit).
  - [x] 2.6 `private let originalExpense: ExpenseData` — stores the unmodified expense for preserving `id`, `createdAt`, `createdByUserID` on save. **No `@ObservationIgnored`** — `@Observable` does not track `let` constants, so the annotation is redundant and semantically misleading. Only `var` stored properties need `@ObservationIgnored`.
  - [x] 2.7 `private static let maxBeforeAppend: Int64 = 1_000_000` — same satang cap as `ExpenseEntryViewModel`
  - [x] 2.8 Init takes `expense: ExpenseData` as first parameter. Pre-fill: `amountInCents = expense.amount`, `selectedCategoryID = expense.categoryID`, `noteText = expense.note ?? ""`
  - [x] 2.9 Numpad actions — identical logic to `ExpenseEntryViewModel`: `appendDigit(_:)`, `deleteLastDigit()`, `appendDecimalPoint()`, `resetAmount()`. Each triggers `hapticService.trigger(.numpadKey)`. Guard: `amountInCents < Self.maxBeforeAppend` before append.
  - [x] 2.10 `func loadCategories() async` — fetch from CategoryRepository, guard `categories.isEmpty`, guard `!Task.isCancelled` after fetch. **Do NOT set `selectedCategoryID`** — it's already pre-filled from init.
  - [x] 2.11 `func selectCategory(_ id: UUID)` — triggers `.categorySelect` haptic, sets `selectedCategoryID`
  - [x] 2.12 `func saveExpense() async throws` — guard `!isSaving`, set `isSaving = true` with `defer { isSaving = false }`, guard `amountInCents > 0`, guard `selectedCategoryID`. Create `ExpenseData` preserving `originalExpense.id`, `originalExpense.createdByUserID`, `originalExpense.createdAt`, setting `modifiedAt` to `Date()` and using current form values for `amount`, `categoryID`, `note`. Call `expenseRepository.saveExpense(updatedExpense)`. After success: `guard !Task.isCancelled`, then `hapticService.trigger(.saveTap)`. **No form reset, no MRU update** — sheet dismisses after save.
  - [x] 2.13 Register file in `project.pbxproj`

- [x] Task 3: Create `EditExpenseSheet` (AC: #1, #5, #6)
  - [x] 3.1 Create `CashOut/Views/Feed/EditExpenseSheet.swift`
  - [x] 3.2 Properties: `let expense: ExpenseData`, `var onSaveComplete: (@MainActor @Sendable () -> Void)? = nil`
  - [x] 3.3 State: `@State private var viewModel: EditExpenseViewModel` — initialized in init from the `expense` parameter. **Pattern:** use `init(expense:onSaveComplete:)` with `_viewModel = State(initialValue: EditExpenseViewModel(expense: expense))`
  - [x] 3.4 `@State private var showingNoteSheet = false`
  - [x] 3.5 Body: same VStack layout as `EntryView` — `AmountDisplayView` → `CategoryPickerView` → `NumpadView` → `SaveButtonView`. Reuse all four sub-views with identical modifiers and spacing.
  - [x] 3.6 SaveButtonView `onSave` closure: `Task { do { try await viewModel.saveExpense(); guard !Task.isCancelled else { return }; onSaveComplete?() } catch { #if DEBUG print("Edit save failed: \(error)") #endif } }`
  - [x] 3.7 SaveButtonView `isDisabled`: `viewModel.isAmountZero || viewModel.isSaving || viewModel.selectedCategoryID == nil`
  - [x] 3.8 SaveButtonView `onNoteTap`: `{ showingNoteSheet = true }`
  - [x] 3.9 `.task { await viewModel.loadCategories() }` — loads categories for the picker
  - [x] 3.10 `.sheet(isPresented: $showingNoteSheet)` for `NoteEntrySheet(noteText: $viewModel.noteText)` with `.presentationDetents([.large])`
  - [x] 3.11 **No NavigationStack wrapper, no toolbar cancel button** — pull-down dismissal is standard iOS behavior (UX-DR26)
  - [x] 3.12 Accessibility: all sub-views already have VoiceOver support from Stories 1-5 through 1-7. Pre-filled values are announced because they're the same SwiftUI views with the same accessibility labels — the amount display announces the pre-filled amount, the selected category chip announces "selected", etc.
  - [x] 3.13 Register file in `project.pbxproj`

- [x] Task 4: Add tap and swipe-edit actions to FeedView (AC: #1, #2)
  - [x] 4.1 Add `@State private var expenseToEdit: ExpenseData?` to `FeedView`
  - [x] 4.2 Wrap each `FeedRowView` inside `ForEach` in a `Button` with `.buttonStyle(.plain)`: `Button { expenseToEdit = expense } label: { FeedRowView(...) }.buttonStyle(.plain)`. **Do NOT use `.contentShape(Rectangle()).onTapGesture`** — it conflicts with swipe actions in `List` (gesture recognizer interference). `Button` + `.buttonStyle(.plain)` is the canonical pattern for tappable List rows with swipe actions.
  - [x] 4.3 On each row (inside ForEach, on the `Button` or `FeedRowView`), add `.swipeActions(edge: .trailing, allowsFullSwipe: false)` with a single `Button { expenseToEdit = expense } label: { Label("Edit", systemImage: "pencil") }` styled as `.tint(.blue)`. **`allowsFullSwipe: false`** — edit opens a sheet, which is not a "safe, instantly reversible" action like archive; full-swipe should require explicit tap. **`edge: .trailing`** means swipe-left reveals the button on the right side. **Verify on device:** if `.swipeActions` on a `Button`-wrapped row does not trigger correctly, move the `.swipeActions` modifier to the `FeedRowView` directly and keep the `Button` wrapper only for tap.
  - [x] 4.4 Add `.sheet(item: $expenseToEdit)` on the outer `Group` container (NOT on the `List`) — this ensures the sheet modifier is always in the view hierarchy regardless of empty state: `EditExpenseSheet(expense: expense, onSaveComplete: { expenseToEdit = nil }).presentationDetents([.large])`
  - [x] 4.5 **Do NOT add swipe-right delete action** — that is Story 2-4. Only the trailing (swipe-left) edit action in this story.

- [x] Task 5: Unit tests for EditExpenseViewModel (AC: #1, #3, #4)
  - [x] 5.1 Create `CashOutTests/ViewModels/EditExpenseViewModelTests.swift`
  - [x] 5.2 Create `makeSUT(expense:)` helper returning `(EditExpenseViewModel, MockExpenseRepository, MockCategoryRepository, MockHapticService)` tuple
  - [x] 5.3 Test: init pre-fills `amountInCents` from expense
  - [x] 5.4 Test: init pre-fills `selectedCategoryID` from expense
  - [x] 5.5 Test: init pre-fills `noteText` from expense (with nil → empty string fallback)
  - [x] 5.6 Test: `saveExpense()` preserves original `id` on saved data
  - [x] 5.7 Test: `saveExpense()` preserves original `createdAt` on saved data
  - [x] 5.8 Test: `saveExpense()` preserves original `createdByUserID` on saved data
  - [x] 5.9 Test: `saveExpense()` sets `modifiedAt` to approximately current time (within 1-second tolerance)
  - [x] 5.10 Test: `saveExpense()` uses current `amountInCents` (not original) on saved data
  - [x] 5.11 Test: `saveExpense()` uses current `selectedCategoryID` (not original) on saved data
  - [x] 5.12 Test: `saveExpense()` uses current `noteText` (not original) on saved data
  - [x] 5.13 Test: `saveExpense()` triggers `.saveTap` haptic on success
  - [x] 5.14 Test: `saveExpense()` does not trigger haptic on failure (repository throws)
  - [x] 5.15 Test: `saveExpense()` returns silently when `amountInCents == 0`
  - [x] 5.16 Test: `saveExpense()` returns silently when `selectedCategoryID == nil`
  - [x] 5.17 Test: `isSaving` guard prevents concurrent saves
  - [x] 5.18 Test: `appendDigit()` modifies pre-filled amount correctly (e.g., 12300 → 123005 after "5")
  - [x] 5.19 Test: `resetAmount()` clears to zero (user can retype from scratch)
  - [x] 5.20 Test: `loadCategories()` fetches from repository and does NOT overwrite `selectedCategoryID`
  - [x] 5.21 Test: `selectCategory()` triggers `.categorySelect` haptic
  - [x] 5.22 All test classes: `@MainActor` (established pattern)
  - [x] 5.23 Register file in `project.pbxproj`

- [x] Task 6: Register files and verify build (AC: #1–#6)
  - [x] 6.1 Register `EditExpenseViewModel.swift` in `project.pbxproj` (PBXBuildFile, PBXFileReference, PBXGroup for ViewModels)
  - [x] 6.2 Register `EditExpenseSheet.swift` in `project.pbxproj` (PBXBuildFile, PBXFileReference, PBXGroup for Views/Feed)
  - [x] 6.3 Register `EditExpenseViewModelTests.swift` in `project.pbxproj` (PBXBuildFile, PBXFileReference, PBXGroup for CashOutTests/ViewModels)
  - [x] 6.4 Build the project — verify zero errors, zero warnings
  - [x] 6.5 Run full test suite — verify all existing tests (82) pass plus new tests
  - [ ] 6.6 Manual verification: tap feed row → edit sheet opens with pre-filled values
  - [ ] 6.7 Manual verification: swipe-left on feed row → edit button appears → tapping opens edit sheet
  - [ ] 6.8 Manual verification: modify amount + save → feed row updates, sheet dismisses, success haptic
  - [ ] 6.9 Manual verification: pull-down dismiss → no changes saved
  - [ ] 6.10 Manual verification: VoiceOver announces pre-filled amount and selected category on edit sheet open

## Dev Notes

### Architecture Decision: Separate EditExpenseViewModel (Not Reusing ExpenseEntryViewModel)

Create a **separate `EditExpenseViewModel`** — do NOT add an "edit mode" to `ExpenseEntryViewModel`. The differences justify separation:

| Concern | ExpenseEntryViewModel (create) | EditExpenseViewModel (edit) |
|---------|-------------------------------|----------------------------|
| Init | Empty form (amount=0, MRU category) | Pre-filled from `ExpenseData` |
| Expense ID | `UUID()` — new | Preserved from original |
| `createdAt` | `Date()` — now | Preserved from original |
| `createdByUserID` | From `AuthenticationService` | Preserved from original |
| `modifiedAt` | `Date()` — same as createdAt | `Date()` — updated to now |
| Post-save | Reset form + persist MRU | No reset, no MRU update |
| Dependencies | Auth + UserDefaults + Repo + Cat + Haptic | Repo + Cat + Haptic (fewer) |

Adding a mode flag would pollute every method with conditionals. Separate ViewModels = clean SRP.

[Source: _bmad-output/implementation-artifacts/2-2-floating-add-button.md — "Story 2-3 will create EditExpenseSheet.swift"]
[Source: _bmad-output/planning-artifacts/architecture.md — ViewModel State Properties pattern]

### Repository Upsert — No Repository Changes Needed

`ExpenseRepository.saveExpense()` already implements the upsert pattern:
```swift
let request: NSFetchRequest<Expense> = Expense.fetchRequest()
request.predicate = NSPredicate(format: "id == %@", data.id as CVarArg)
let existing = try context.fetch(request).first
let expense = existing ?? Expense(context: context)
// ... update all fields ...
try context.save()
```

When editing: pass the original `id` → fetch finds the existing record → updates in-place. No new repository method needed.

[Source: CashOut/Repositories/ExpenseRepository.swift:114-133]

### FRC Auto-Update After Edit Save

After `context.save()`:
1. `NSFetchedResultsController` delegate fires → `FRCDelegate.controllerDidChangeContent`
2. `ExpenseRepository.handleFRCUpdate()` converts updated objects to `ExpenseData` structs
3. `onExpensesChanged?` callback fires → `FeedViewModel.expenses` updates
4. SwiftUI re-renders `FeedView` with updated row data

No additional wiring needed — this is the same FRC observation established in Story 2-1.

[Source: CashOut/Repositories/ExpenseRepository.swift:58-73]
[Source: CashOut/ViewModels/FeedViewModel.swift:46-55]

### EditExpenseSheet Init Pattern

`EditExpenseSheet` must initialize its `@State` ViewModel from the `expense` parameter. Use the `State(initialValue:)` pattern in the View's init:

```swift
struct EditExpenseSheet: View {
    let expense: ExpenseData
    var onSaveComplete: (@MainActor @Sendable () -> Void)? = nil

    @State private var viewModel: EditExpenseViewModel
    @State private var showingNoteSheet = false

    init(
        expense: ExpenseData,
        onSaveComplete: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.expense = expense
        self.onSaveComplete = onSaveComplete
        _viewModel = State(initialValue: EditExpenseViewModel(expense: expense))
    }
}
```

**Why `State(initialValue:)`**: SwiftUI only uses the initial value on first appearance. If the parent re-creates the sheet (same `expense.id`), the ViewModel retains its current state. This is correct because the user's in-progress edits should not be overwritten by parent re-renders.

### Swipe Actions — Trailing Edge for Edit

SwiftUI swipe direction mapping:
- **Swipe left** (drag row leftward) → reveals `.swipeActions(edge: .trailing)` buttons on the right
- **Swipe right** (drag row rightward) → reveals `.swipeActions(edge: .leading)` buttons on the left

This story adds **only** `.swipeActions(edge: .trailing)` for Edit. Story 2-4 will add `.swipeActions(edge: .leading)` for Delete.

```swift
ForEach(viewModel.expenses, id: \.id) { expense in
    Button {
        expenseToEdit = expense
    } label: {
        FeedRowView(
            expense: expense,
            category: viewModel.categoryFor(expense),
            isCurrentUser: viewModel.isCurrentUser(expense),
            partnerInitials: viewModel.partnerInitials(for: expense)
        )
    }
    .buttonStyle(.plain)
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
        Button {
            expenseToEdit = expense
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .tint(.blue)
    }
}
```

**Why `Button` + `.buttonStyle(.plain)` instead of `.onTapGesture`:** Inside a `List`, `.contentShape(Rectangle()).onTapGesture` conflicts with `.swipeActions` — the gesture recognizer intercepts swipe initiation on the leading edge of the hit area. `Button` with `.buttonStyle(.plain)` integrates cleanly with the List gesture system.

**Why `allowsFullSwipe: false`:** iOS convention reserves `allowsFullSwipe: true` for safe, instantly reversible actions (Mail's archive). Edit opens a sheet — an action with visual weight — so explicit tap is more appropriate.

[Source: _bmad-output/planning-artifacts/ux-design-specification.md — UX-DR11 swipe-left to edit]

### FeedView Sheet Binding with `.sheet(item:)`

Use `.sheet(item: $expenseToEdit)` on the **outer `Group`** — not on `List`. This ensures the sheet modifier is always in the view hierarchy even when the empty state is shown:

```swift
Group {
    if viewModel.isEmpty {
        Text("No entries yet") ...
    } else {
        List {
            ForEach(viewModel.expenses, id: \.id) { expense in
                Button { expenseToEdit = expense } label: {
                    FeedRowView(...)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) { ... }
            }
        }
    }
}
.sheet(item: $expenseToEdit) { expense in
    EditExpenseSheet(expense: expense, onSaveComplete: {
        expenseToEdit = nil
    })
    .presentationDetents([.large])
}
```

`ExpenseData` needs `Identifiable` conformance for `.sheet(item:)`. Task 1 adds this — it already has `id: UUID`, so the conformance is automatic. **Task 1 must be completed before Task 4** — `.sheet(item:)` will not compile without `Identifiable`.

### Liquid Glass Rules — Same as EntryView

The edit sheet reuses the same sub-views, so all Liquid Glass rules are already handled:
- **NumpadView keys** → `.buttonStyle(.glass)` (already applied in NumpadView)
- **Save button** → `.buttonStyle(.glassProminent)` (already applied in SaveButtonView)
- **Note button** → `.buttonStyle(.plain)` (already applied in SaveButtonView)
- **No `.glassEffect()` on any buttons** — architecture rule enforced
- **Category chips** → `.buttonStyle(.plain)` with custom background (already applied in CategoryPickerView)

No new Liquid Glass decisions needed. The edit sheet inherits all styling from reused sub-views.

[Source: _bmad-output/planning-artifacts/architecture.md — Liquid Glass API Rules]
[Source: .claude/learnings/ios-swiftui.md — line 39]

### Haptic Feedback

Edit flow uses existing haptic events:
- **Numpad key tap** → `.numpadKey` (light impact) — same as entry
- **Category select** → `.categorySelect` (light impact) — same as entry
- **Save after edit** → `.saveTap` (success notification) — same as entry

No new `HapticEvent` cases needed. The `.deleteTap` case (already in enum) is reserved for Story 2-4.

[Source: CashOut/Services/HapticServiceProtocol.swift — HapticEvent enum]

### No MRU Update on Edit

When editing, the selected category reflects the user's correction (e.g., fixing "Food & Drink" → "Transport"). This should NOT update the MRU preference because:
- MRU represents "what category do I usually spend on?" — a correction doesn't change that
- Only new entries (via `ExpenseEntryViewModel`) update MRU via UserDefaults

The `EditExpenseViewModel` has no `UserDefaults` dependency — intentionally omitted.

### `modifiedAt` Semantics

`modifiedAt` is updated to `Date()` on every save — this is for **display/sorting only**. CloudKit conflict resolution uses `CKRecord` change tags (framework-managed), NOT `modifiedAt`.

[Source: .claude/learnings/cloudkit-sync.md — "Custom modifiedAt field is for display/sorting only"]

### Project Structure Notes

| File | Location | Action |
|------|----------|--------|
| `ExpenseData.swift` | `CashOut/Models/` | **Modify** — add `Identifiable` conformance |
| `EditExpenseViewModel.swift` | `CashOut/ViewModels/` | **New file** |
| `EditExpenseSheet.swift` | `CashOut/Views/Feed/` | **New file** |
| `FeedView.swift` | `CashOut/Views/Feed/` | **Modify** — add tap/swipe actions + sheet |
| `EditExpenseViewModelTests.swift` | `CashOutTests/ViewModels/` | **New file** |

All new files must be registered in `project.pbxproj`.

### Existing Code to Reuse (DO NOT Recreate)

| What | File | Usage |
|------|------|-------|
| `AmountDisplayView` | `Views/Entry/AmountDisplayView.swift` | Reuse in edit sheet — shows pre-filled amount |
| `CategoryPickerView` | `Views/Entry/CategoryPickerView.swift` | Reuse in edit sheet — shows pre-selected category |
| `NumpadView` | `Views/Entry/NumpadView.swift` | Reuse in edit sheet — modifies pre-filled amount |
| `SaveButtonView` | `Views/Entry/SaveButtonView.swift` | Reuse in edit sheet — save + note button |
| `NoteEntrySheet` | `Views/Entry/NoteEntrySheet.swift` | Reuse in edit sheet — note editing |
| `ExpenseRepository` | `Repositories/ExpenseRepository.swift` | Unchanged — upsert handles update |
| `FeedViewModel` | `ViewModels/FeedViewModel.swift` | Unchanged — FRC observation handles updates |
| `FeedRowView` | `Views/Feed/FeedRowView.swift` | Unchanged — read-only display component |
| `HapticService` | `Services/HapticService.swift` | Unchanged — `.saveTap` event reused |
| `MockExpenseRepository` | Tests — call tracking: `saveExpenseCalled`, `lastSavedExpense` |
| `MockCategoryRepository` | Tests — stubbed categories |
| `MockHapticService` | Tests — `triggeredEvents` tracking |
| `Spacing` enum | `Utilities/Constants.swift` | Layout spacing tokens |

### Boundaries — What NOT to Implement

- **No swipe-right delete action** — Story 2-4
- **No delete confirmation** — Story 2-4
- **No "unsaved changes" warning on dismiss** — UX-DR26 explicitly forbids this
- **No new ViewModel for FeedView** — edit sheet state (`expenseToEdit`) is `@State` on `FeedView`
- **No changes to FeedRowView internals** — swipe actions are applied externally in FeedView
- **No changes to ContentView** — edit sheet is presented from FeedView, not ContentView
- **No changes to ExpenseRepository** — upsert already handles updates
- **No changes to FeedViewModel** — FRC observation handles updates automatically
- **No daily section headers** — deferred (Story 2-1 boundary)
- **No new HapticEvent cases** — `.saveTap` reused for edit save
- **No MRU update on edit** — intentional, not a bug

### Previous Story Intelligence

**From Story 2-2 (Floating Add Button):**
- `EntryView` now has `onSaveComplete: (@MainActor @Sendable () -> Void)?` parameter — the same pattern should be used in `EditExpenseSheet`
- Sheet dismissal pattern: parent sets `@State` bool/item to nil in `onSaveComplete` callback
- Sheet content has no NavigationStack wrapper (UX-DR26)
- `.presentationDetents([.large])` is the standard sheet size
- 82 tests passing (80 from Epic 1 + 2 verification from Story 2-1)
- Code review validated `.onSaveComplete` must be called inside `do` block after `try await`, NOT in `catch`/`defer`

**From Story 2-1 (Expense Feed):**
- FRC observation is fully wired — saves trigger automatic feed updates
- `FeedView` uses `.onAppear` for `startObserving()` with `isObserving` guard
- `FeedRowView` is a pure display component with accessibility — receives data via init parameters
- Partner attribution works automatically (createdByUserID preserved on edit)

**From Story 1-6 (Category Picker, Save Flow):**
- `ExpenseEntryViewModel` pattern: `guard !isSaving else { return }; isSaving = true; defer { isSaving = false }`
- `guard !Task.isCancelled` after async save before state mutations
- `hapticService.trigger(.saveTap)` fires after successful save

**Code Review Patterns to Follow:**
- `onSaveComplete` closure typed `@MainActor @Sendable` (Story 2-2 fix)
- All new files registered in `project.pbxproj`
- `guard !Task.isCancelled` after every async operation
- Boolean flag guard checked BEFORE the flag is set (architecture learnings)

### Git Intelligence

Recent commit pattern: `feat(feed): ...` for Epic 2 stories.
Suggested commit message: `feat(feed): add edit expense flow with tap and swipe actions (story 2-3)`

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Story 2.3 acceptance criteria]
- [Source: _bmad-output/planning-artifacts/architecture.md — ViewModel State Properties pattern]
- [Source: _bmad-output/planning-artifacts/architecture.md — Liquid Glass API Rules]
- [Source: _bmad-output/planning-artifacts/architecture.md — Anti-Patterns]
- [Source: _bmad-output/planning-artifacts/architecture.md — Haptic Feedback Events]
- [Source: _bmad-output/planning-artifacts/architecture.md — Core Data Save Pattern (upsert)]
- [Source: _bmad-output/planning-artifacts/architecture.md — Data Boundaries table]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — UX-DR11 swipe-left to edit]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — UX-DR20 edit flow same UI as entry]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — UX-DR26 no unsaved changes warning]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — UX-DR10 haptic patterns]
- [Source: _bmad-output/implementation-artifacts/2-2-floating-add-button.md — onSaveComplete pattern]
- [Source: _bmad-output/implementation-artifacts/2-1-expense-feed-with-partner-attribution.md — FRC observation]
- [Source: .claude/learnings/architecture.md — upsert pattern, isSaving guard, Task.isCancelled]
- [Source: .claude/learnings/ios-swiftui.md — Liquid Glass rules, buttonStyle patterns]
- [Source: .claude/learnings/cloudkit-sync.md — modifiedAt is display-only, not conflict resolution]
- [Source: CashOut/Repositories/ExpenseRepository.swift — saveExpense upsert (lines 114-133)]
- [Source: CashOut/ViewModels/ExpenseEntryViewModel.swift — numpad logic, save pattern]
- [Source: CashOut/Views/Entry/EntryView.swift — onSaveComplete callback, sub-view layout]
- [Source: CashOut/Views/Feed/FeedView.swift — current structure to modify]
- [Source: CashOut/Models/ExpenseData.swift — struct to add Identifiable]

### Orchestrator Validation (2026-04-03)

**Guardians run**: ios-swiftui-guardian, architecture-guardian, cloudkit-sync-guardian

**CRITICALs:** None for this story. (CloudKit guardian flagged a pre-existing `handleAccountChange` no-op in `PersistenceController.swift:100-103` — iCloud account change handler is empty. This does not block Story 2-3 but should be addressed before TestFlight in a dedicated story.)

**WARNINGs addressed in story spec:**
1. [ios-swiftui] `.contentShape(Rectangle()).onTapGesture` conflicts with `.swipeActions` in `List` — **FIXED in Task 4.2**: use `Button` + `.buttonStyle(.plain)` wrapper instead.
2. [ios-swiftui] `allowsFullSwipe: true` is unconventional for sheet-opening actions — **FIXED in Task 4.3**: changed to `allowsFullSwipe: false`. Edit requires explicit tap on the swipe button.
3. [ios-swiftui] `.sheet(item:)` on `List` is absent when empty state shows — **FIXED in Task 4.4**: moved `.sheet(item:)` to outer `Group` container.
4. [architecture] `@ObservationIgnored` on `let originalExpense` is redundant — **FIXED in Task 2.6**: removed annotation. `@Observable` does not track `let` constants.
5. [ios-swiftui] `NoteEntrySheet` contains its own `NavigationStack` internally — this is correct for sheet-over-sheet presentation. Each sheet gets its own window; no nested NavigationStack violation. **Dev instruction: verify on device that the note sheet presents correctly from within the edit sheet.**
6. [cloudkit-sync] FRC shared-store behavior: for partner-created expenses synced into the shared store, `context.save()` writes back to the shared store because the fetched managed object's store affinity follows the record's origin. No explicit store-affinity code needed. **Dev instruction: no action required, but be aware that the upsert operates on whichever store the original record lives in.**
7. [cloudkit-sync] Simultaneous same-record edits by both partners produce silent LWW resolution via `NSMergeByPropertyStoreTrumpMergePolicy`. No conflict UI needed — the framework resolves before the app sees it. **Do NOT add any conflict detection or user notification.**
8. [architecture] `ForEach(id: \.id)` becomes redundant after `Identifiable` — harmless but can optionally be simplified to `ForEach(viewModel.expenses)`.
9. [architecture] Task 5.17 (concurrent save test) may need a slow-save mock stub. **Dev instruction: if testing concurrent saves, add a `saveDelay` property to `MockExpenseRepository` that uses `Task.sleep` to simulate slow save. If not practical, test that `isSaving` is `true` during save execution and `false` after.**

**SUGGESTIONs noted:**
- `@Sendable` on a `@MainActor`-isolated closure is technically redundant but consistent with the codebase pattern from Story 2-2. Keep it.
- `State(initialValue:)` does not re-run when parent re-renders with a different expense — this is correct behavior for edit sheet (preserves in-progress edits).
- VoiceOver announces pre-filled values automatically via the same sub-view accessibility labels from Stories 1-5 through 1-7. No additional accessibility work needed.
- Consider adding `errorMessage: String?` to `EditExpenseViewModel` for category load failures — deferred, same design choice as `ExpenseEntryViewModel`.

**Architecture guardian:** All clear. Separate `EditExpenseViewModel` is the correct SRP decision. Protocol-based DI with concrete defaults. No `import SwiftUI` in ViewModel. No business logic in Views. Test coverage adequate.

**CloudKit sync guardian:** All clear for this story. Upsert propagates correctly via `NSPersistentCloudKitContainer`. FRC auto-updates. Offline edits handled by framework. `modifiedAt` semantics correctly understood.

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

None — clean implementation, no blocking issues encountered.

### Completion Notes List

- ✅ Task 1: Added `Identifiable` conformance to `ExpenseData` struct — enables `.sheet(item:)` binding
- ✅ Task 2: Created `EditExpenseViewModel` with pre-fill from expense, numpad actions, save preserving original identity fields (id, createdAt, createdByUserID), no Auth/UserDefaults dependencies
- ✅ Task 3: Created `EditExpenseSheet` reusing all four Entry sub-views (AmountDisplay, CategoryPicker, Numpad, SaveButton), `State(initialValue:)` pattern for ViewModel init
- ✅ Task 4: Added tap (Button + .buttonStyle(.plain)) and swipe-left edit action to FeedView rows, `.sheet(item:)` on outer Group
- ✅ Task 5: 20 unit tests covering pre-fill, save preservation, current form values, haptics, guards, numpad, loadCategories
- ✅ Task 6: All 3 files registered in project.pbxproj, build succeeded, 102 tests pass (82 existing + 20 new), 0 regressions
- Tasks 6.6–6.10 require manual on-device verification by the developer

### Implementation Plan

- Separate `EditExpenseViewModel` (not reusing `ExpenseEntryViewModel`) per SRP — different init, save, and dependency profiles
- `EditExpenseSheet` mirrors `EntryView` layout exactly, reusing all sub-views
- FeedView uses `Button` + `.buttonStyle(.plain)` wrapper (not `.onTapGesture`) to avoid gesture conflict with `.swipeActions`
- `.sheet(item:)` on outer `Group` ensures sheet modifier persists even when empty state shows
- Repository upsert pattern handles updates transparently via existing `saveExpense()` method
- FRC auto-updates feed after `context.save()` — no additional wiring needed

### File List

- CashOut/Models/ExpenseData.swift (modified — added Identifiable)
- CashOut/ViewModels/EditExpenseViewModel.swift (new)
- CashOut/Views/Feed/EditExpenseSheet.swift (new)
- CashOut/Views/Feed/FeedView.swift (modified — tap, swipe, sheet)
- CashOutTests/ViewModels/EditExpenseViewModelTests.swift (new)
- CashOut.xcodeproj/project.pbxproj (modified — registered 3 new files)

### Change Log

- 2026-04-03: Implemented edit expense flow — tap/swipe-to-edit on feed rows, edit sheet with pre-filled values, 20 unit tests (Story 2-3)
