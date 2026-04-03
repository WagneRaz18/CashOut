# Story 2.4: Delete Expense Flow

Status: review

## Story

As a user,
I want to delete an expense entry with a quick confirmation,
So that I can remove duplicates or erroneous entries while preventing accidents.

## Acceptance Criteria

1. **Given** a feed row **When** the user swipes right **Then** a destructive delete action appears as an inline swipe action (not a modal dialog) (UX-DR11, UX-DR21)

2. **Given** the delete swipe action **When** the user taps the delete button to confirm **Then** the entry is hard-deleted from Core Data via `ExpenseRepository.deleteExpense(id:)`, a `.deleteTap` haptic fires, and the row animates out via system List default (FR7)

3. **Given** the delete swipe action **When** the user swipes back or does not confirm **Then** the entry is not deleted and the row returns to its normal state

4. **Given** a hard delete **When** executed **Then** `NSPersistentCloudKitContainer` handles tombstone propagation automatically via `NSPersistentHistoryTracking` (NFR14)

5. **Given** VoiceOver is enabled **When** swipe actions are available **Then** edit and delete actions are discoverable via the VoiceOver rotor

## Tasks / Subtasks

- [x] Task 1: Add `HapticServiceProtocol` dependency to `FeedViewModel` (AC: #2)
  - [x] 1.1 In `CashOut/ViewModels/FeedViewModel.swift`, add `@ObservationIgnored private let hapticService: HapticServiceProtocol` property
  - [x] 1.2 Add `hapticService: HapticServiceProtocol = HapticService()` parameter to `init()`
  - [x] 1.3 Assign `self.hapticService = hapticService` in init body

- [x] Task 2: Add `deleteExpense(_:)` method to `FeedViewModel` (AC: #2)
  - [x] 2.1 Add `func deleteExpense(_ expense: ExpenseData) async` method
  - [x] 2.2 Body: `do { try await repository.deleteExpense(id: expense.id); guard !Task.isCancelled else { return }; hapticService.trigger(.deleteTap) } catch { #if DEBUG print("Delete failed: \(error)") #endif }`
  - [x] 2.3 **No `isDeleting` guard needed** — the swipe action auto-dismisses after tap, preventing double-invoke. FRC removes the row from the `expenses` array, so the row can't be interacted with again.
  - [x] 2.4 **No row removal from `expenses` array** — FRC callback handles this automatically: `context.delete()` + `context.save()` → FRC delegate fires → `onExpensesChanged` with updated list → row animates out.

- [x] Task 3: Add swipe-right delete action to `FeedView` (AC: #1, #3, #5)
  - [x] 3.1 In `CashOut/Views/Feed/FeedView.swift`, add `.swipeActions(edge: .leading, allowsFullSwipe: false)` on the same `Button` row that already has the trailing edit swipe action
  - [x] 3.2 Inside the swipe action: `Button(role: .destructive) { Task { await viewModel.deleteExpense(expense) } } label: { Label("Delete", systemImage: "trash") }`
  - [x] 3.3 **`edge: .leading`** — swipe right (drag rightward) reveals buttons on the left side. This is the opposite of the trailing edit action.
  - [x] 3.4 **`allowsFullSwipe: false`** — delete requires explicit tap on the button. Full-swipe-to-delete is too risky for a finance app — user must deliberately confirm. (UX-DR21: "single tap to confirm")
  - [x] 3.5 **`Button(role: .destructive)`** — provides automatic red styling. Do NOT add `.tint(.red)` — the `role` handles it. Using `role:` is the semantic approach and ensures correct VoiceOver behavior (announces "delete" as a destructive action).
  - [x] 3.6 **VoiceOver** — `.swipeActions` are automatically discoverable via the VoiceOver Actions rotor. No additional accessibility code needed. Both Edit (trailing) and Delete (leading) will appear in the rotor.

- [x] Task 4: Update `MockExpenseRepository` for delete ID tracking (AC: #2)
  - [x] 4.1 In `CashOutTests/Repositories/MockExpenseRepository.swift`, add `var lastDeletedExpenseID: UUID?` property
  - [x] 4.2 In `deleteExpense(id:)`, add `lastDeletedExpenseID = id` before the throw guard

- [x] Task 5: Update `FeedViewModelTests` for delete + haptics (AC: #2)
  - [x] 5.1 In `CashOutTests/ViewModels/FeedViewModelTests.swift`, update `makeSUT()` to create a `MockHapticService` and inject it into `FeedViewModel`
  - [x] 5.2 Update `makeSUT()` return tuple to include `MockHapticService`: `(viewModel: FeedViewModel, expenseRepo: MockExpenseRepository, categoryRepo: MockCategoryRepository, authService: MockAuthenticationService, hapticService: MockHapticService)`
  - [x] 5.3 **CRITICAL:** Update ALL existing test call sites that destructure the `makeSUT()` tuple — add `_` placeholder for the new hapticService element: `let (viewModel, expenseRepo, categoryRepo, _) = makeSUT()` → `let (viewModel, expenseRepo, categoryRepo, _, _) = makeSUT()`. There are ~14 existing tests that use this pattern.
  - [x] 5.4 Test: `deleteExpense` calls `repository.deleteExpense` with correct ID — create expense, call `viewModel.deleteExpense(expense)`, assert `expenseRepo.deleteExpenseCalled == true` and `expenseRepo.lastDeletedExpenseID == expense.id`
  - [x] 5.5 Test: `deleteExpense` triggers `.deleteTap` haptic on success — call `viewModel.deleteExpense(expense)`, assert `hapticService.lastEvent == .deleteTap`
  - [x] 5.6 Test: `deleteExpense` does NOT trigger haptic on failure — set `expenseRepo.shouldThrow = true`, call `viewModel.deleteExpense(expense)`, assert `hapticService.triggeredEvents.isEmpty`
  - [x] 5.7 Test: `deleteExpense` does not throw (error swallowed) — set `expenseRepo.shouldThrow = true`, call `await viewModel.deleteExpense(expense)`, assert test does not crash (method returns silently)
  - [x] 5.8 Import `MockHapticService` — ensure `@testable import CashOut` is present (already is) and `MockHapticService.swift` is in the test target (already registered in `project.pbxproj`)
  - [x] 5.9 All test classes: `@MainActor` (established pattern)

- [x] Task 6: Verify build and test suite (AC: #1–#5)
  - [x] 6.1 Build the project — verify zero errors, zero warnings
  - [x] 6.2 Run full test suite — verify all existing 102 tests pass plus new tests (~4 new = ~106 total)
  - [ ] 6.3 Manual verification: swipe-right on feed row → delete button appears (red, leading edge)
  - [ ] 6.4 Manual verification: tap delete → row animates out, success haptic fires
  - [ ] 6.5 Manual verification: swipe back without tapping → row returns to normal
  - [ ] 6.6 Manual verification: VoiceOver rotor shows both Edit and Delete actions on feed rows
  - [ ] 6.7 Manual verification: both Edit (swipe-left) and Delete (swipe-right) work independently without interfering

## Dev Notes

### No New Files — Modifications Only

This story creates **zero new files**. All changes are modifications to existing files:

| File | Location | Action |
|------|----------|--------|
| `FeedViewModel.swift` | `CashOut/ViewModels/` | **Modify** — add hapticService dependency + `deleteExpense(_:)` method |
| `FeedView.swift` | `CashOut/Views/Feed/` | **Modify** — add `.swipeActions(edge: .leading)` with delete button |
| `MockExpenseRepository.swift` | `CashOutTests/Repositories/` | **Modify** — add `lastDeletedExpenseID` tracking |
| `FeedViewModelTests.swift` | `CashOutTests/ViewModels/` | **Modify** — add hapticService to makeSUT + 4 new delete tests |

**No `project.pbxproj` changes needed** — no new files to register.

### Repository — Already Complete

`ExpenseRepository.deleteExpense(id:)` already implements the hard-delete pattern:
```swift
func deleteExpense(id: UUID) async throws {
    let context = persistence.container.viewContext
    let request: NSFetchRequest<Expense> = Expense.fetchRequest()
    request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
    request.fetchLimit = 1
    guard let expense = try context.fetch(request).first else { return }
    context.delete(expense)
    try context.save()
}
```
**No repository changes needed.** The method already handles "not found" gracefully (guard returns silently).

[Source: CashOut/Repositories/ExpenseRepository.swift:135-145]

### FRC Auto-Update After Delete

After `context.delete()` + `context.save()`:
1. `NSFetchedResultsController` delegate fires → `FRCDelegate.controllerDidChangeContent`
2. `ExpenseRepository.handleFRCUpdate()` converts remaining objects to `ExpenseData` structs
3. `onExpensesChanged?` callback fires → `FeedViewModel.expenses` updates (minus deleted entry)
4. SwiftUI `List` + `ForEach` animates the row removal automatically

No additional wiring needed — same FRC observation from Story 2-1.

[Source: CashOut/Repositories/ExpenseRepository.swift:58-73]
[Source: CashOut/ViewModels/FeedViewModel.swift:46-55]

### HapticEvent.deleteTap — Already Defined

`HapticEvent.deleteTap` already exists in the enum (added in Story 1-7, reserved for this story):
```swift
case deleteTap // UINotificationFeedbackGenerator(.success)
```
`HapticService.trigger()` already handles it: `.saveTap, .deleteTap` → `.success` notification feedback.

[Source: CashOut/Services/HapticService.swift:3-9, 21]

### SwiftUI Swipe Direction Mapping

| User gesture | SwiftUI modifier | Button position |
|-------------|-----------------|-----------------|
| Swipe left (drag leftward) | `.swipeActions(edge: .trailing)` | Right side — **Edit** (Story 2-3) |
| Swipe right (drag rightward) | `.swipeActions(edge: .leading)` | Left side — **Delete** (this story) |

Both modifiers can coexist on the same row. They are independent — iOS handles the gesture disambiguation.

### Delete Button Styling — `role: .destructive`

Use `Button(role: .destructive)` — NOT `.tint(.red)`. The `role` parameter:
- Applies system red automatically
- Announces "destructive action" to VoiceOver
- Integrates with system accessibility settings (high contrast, etc.)

```swift
.swipeActions(edge: .leading, allowsFullSwipe: false) {
    Button(role: .destructive) {
        Task {
            await viewModel.deleteExpense(expense)
        }
    } label: {
        Label("Delete", systemImage: "trash")
    }
}
```

### CloudKit Tombstone Propagation

Hard delete → `context.save()` → `NSPersistentCloudKitContainer` propagates via `NSPersistentHistoryTracking`:
- Partner's device receives silent push → record removed from shared store
- **Edge case:** If partner is offline and CloudKit tombstone window expires, the deleted record may persist. On `.changeTokenExpired` recovery (full re-fetch), reconcile by removing local records not on server. **No dev action needed for this story** — handled by framework and future reconciliation story.

[Source: _bmad-output/planning-artifacts/architecture.md — line 273]
[Source: .claude/learnings/cloudkit-sync.md — "Hard delete propagation works via NSPersistentHistoryTracking"]

### FeedViewModel — Adding HapticService Dependency

`FeedViewModel` currently has 3 dependencies (repository, categoryRepository, authService). This story adds a 4th: `hapticService`. Follow the established DI pattern:

```swift
@ObservationIgnored
private let hapticService: HapticServiceProtocol

init(
    repository: ExpenseRepositoryProtocol = ExpenseRepository(),
    categoryRepository: CategoryRepositoryProtocol = CategoryRepository(),
    authService: AuthenticationServiceProtocol = AuthenticationService(),
    hapticService: HapticServiceProtocol = HapticService()
) {
    self.repository = repository
    self.categoryRepository = categoryRepository
    self.authService = authService
    self.hapticService = hapticService
}
```

**`@ObservationIgnored` on `let`**: Per architecture learnings (2026-04-03), `@ObservationIgnored` is only necessary on `var` stored properties. `let` constants are never tracked by `@Observable`. However, the existing codebase has `@ObservationIgnored` on `let` properties in `FeedViewModel` (e.g., `categoryRepository`, `authService`). **For consistency with the existing FeedViewModel style, add `@ObservationIgnored` to `hapticService` even though it's technically redundant on `let`.** Don't refactor the existing ones — that's beyond story scope.

[Source: .claude/learnings/architecture.md — "@ObservationIgnored is only for var stored properties"]

### makeSUT Tuple Expansion — CRITICAL

The `FeedViewModelTests.makeSUT()` currently returns a 4-element tuple. Adding `MockHapticService` makes it 5. **Every existing test that destructures the tuple must be updated.** There are ~14 test methods.

Pattern: `let (viewModel, expenseRepo, categoryRepo, _) = makeSUT()` becomes `let (viewModel, expenseRepo, categoryRepo, _, _) = makeSUT()` (extra `_` for hapticService).

Alternatively, since most existing tests don't need `authService` or `hapticService`, they use `_` for both trailing positions. Only the new delete tests will name `hapticService` in their destructuring.

### Boundaries — What NOT to Implement

- **No confirmation dialog/alert** — UX-DR21 specifies inline swipe action, not a modal
- **No undo support** — hard delete, no soft delete/archive. If undo is needed, it's a future story
- **No `isDeleting` loading state** — swipe action auto-dismisses; FRC removes the row
- **No changes to FeedRowView** — swipe actions are applied externally in FeedView
- **No changes to ExpenseRepository** — `deleteExpense(id:)` already exists and works
- **No changes to HapticService** — `.deleteTap` case already exists
- **No changes to ContentView** — delete is within FeedView scope
- **No changes to EditExpenseSheet** — delete and edit are independent features
- **No changes to project.pbxproj** — no new files
- **No `allowsFullSwipe: true`** — deliberate tap required for destructive finance action
- **No batch delete** — one row at a time per UX spec

### Previous Story Intelligence

**From Story 2-3 (Edit Expense Flow):**
- `FeedView` row structure: `Button { ... } label: { FeedRowView(...) }.buttonStyle(.plain)` with `.swipeActions(edge: .trailing)` for edit
- Adding `.swipeActions(edge: .leading)` goes on the same `Button` element, adjacent to the existing trailing swipe
- `expenseToEdit: ExpenseData?` is `@State` on FeedView — delete doesn't need a similar state variable (no sheet to present)
- 102 tests passing (82 from Epic 1 + 20 from Story 2-3)
- Code review deferred items: save failure silent in release, haptic on rejected digit, whitespace-only note — all pre-existing, not this story's concern

**From Story 2-1 (Expense Feed):**
- FRC observation fully wired — deletes trigger automatic feed updates
- `FeedView` uses `List` + `ForEach` — row removal animated by system
- Mock pattern: `MockExpenseRepository` already has `deleteExpenseCalled` boolean

**Code Review Patterns to Follow:**
- `guard !Task.isCancelled` after every async operation (architecture learnings)
- All new test methods: `@MainActor` class (already on `FeedViewModelTests`)
- Commit message: `feat(feed): add delete expense flow with swipe-right action (story 2-4)`

### Git Intelligence

Recent commit pattern: `feat(feed): ...` for Epic 2 stories.
Suggested commit message: `feat(feed): add delete expense flow with swipe-right action (story 2-4)`

### Project Structure Notes

- No new files or directories — all modifications to existing paths
- Alignment with unified project structure confirmed — FeedViewModel is in `ViewModels/`, FeedView is in `Views/Feed/`, tests are in `CashOutTests/ViewModels/`
- No detected conflicts or variances

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Story 2.4 acceptance criteria]
- [Source: _bmad-output/planning-artifacts/architecture.md — Deletion strategy: hard delete (line 229)]
- [Source: _bmad-output/planning-artifacts/architecture.md — HapticEvent enum with .deleteTap (line 497-501)]
- [Source: _bmad-output/planning-artifacts/architecture.md — ExpenseRepositoryProtocol.deleteExpense(id:) (line 548)]
- [Source: _bmad-output/planning-artifacts/architecture.md — Hard delete tombstone propagation (line 273)]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — UX-DR11 swipe actions on feed]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — UX-DR21 delete with inline confirmation]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — Destructive button style (line 820)]
- [Source: _bmad-output/planning-artifacts/prd.md — FR7 delete with confirmation prompt]
- [Source: _bmad-output/implementation-artifacts/2-3-edit-expense-flow.md — swipe action patterns, FeedView structure]
- [Source: .claude/learnings/architecture.md — @ObservationIgnored, Task.isCancelled, guard patterns]
- [Source: .claude/learnings/ios-swiftui.md — Button + .buttonStyle(.plain) for List rows with swipe actions]
- [Source: .claude/learnings/cloudkit-sync.md — Hard delete propagation via NSPersistentHistoryTracking]
- [Source: CashOut/Repositories/ExpenseRepository.swift:135-145 — deleteExpense implementation]
- [Source: CashOut/ViewModels/FeedViewModel.swift — current structure (no hapticService yet)]
- [Source: CashOut/Views/Feed/FeedView.swift — current swipe actions structure]
- [Source: CashOut/Services/HapticService.swift:3-9 — HapticEvent enum with .deleteTap]
- [Source: CashOutTests/Repositories/MockExpenseRepository.swift — deleteExpenseCalled tracking]
- [Source: CashOutTests/ViewModels/FeedViewModelTests.swift — makeSUT pattern to extend]

### Orchestrator Validation (2026-04-03)

**Guardians run**: ios-swiftui-guardian, architecture-guardian, cloudkit-sync-guardian

**CRITICALs:** None.

**WARNINGs addressed in story spec:**
1. [architecture] PRD FR7 says "confirmation prompt" — UX-DR21 clarifies this is an inline swipe-button tap, NOT a modal dialog. UX spec overrides ambiguous PRD wording (line 145, 622). **No action needed** — flagging the discrepancy for awareness.
2. [architecture] `MockExpenseRepository.deleteExpense(id:)` does not simulate FRC callback (row removal). This is acceptable for unit testing — ViewModel behavior is tested, not FRC integration. FRC chain verified via manual testing (Task 6). **Dev note:** If future tests need to verify the full delete → row-removal chain, add `stubbedExpenses.removeAll { $0.id == id }; onExpensesChanged?(stubbedExpenses)` to the mock's `deleteExpense()`.
3. [ios-swiftui + architecture] `MockHapticService` is nonisolated while `FeedViewModel.deleteExpense` runs on `@MainActor`. Safe in practice (tests are `@MainActor`), but a Swift 6 strict concurrency gap. Cannot add `@MainActor` to mock without breaking nonisolated `HapticServiceProtocol` conformance (known trade-off per learnings 2026-04-02). **Low risk for test-only code.**

**SUGGESTIONs noted:**
- `deleteExpense(_:)` takes `ExpenseData` but only uses `expense.id` — could take `UUID` directly. Kept as `ExpenseData` for ergonomic View-layer usage (consistent with how rows iterate over `[ExpenseData]`).
- Consider struct return type for `makeSUT()` instead of positional tuple — deferred refactoring, beyond story scope.
- `#if DEBUG print(...)` for error handling is acceptable; `os_log(.fault)` would be more consistent with repository layer but is not required for ViewModel non-critical errors.
- No `isDeleting` guard needed — swipe action auto-dismisses and FRC removes the row. Sound design for single-row-at-a-time constraint.

**Architecture guardian:** All clear. DI pattern correct. FRC chain verified. Repository already complete. No business logic in Views.

**iOS/SwiftUI guardian:** All clear. Swipe actions correct (leading for delete, trailing for edit). `Button(role: .destructive)` is semantic. VoiceOver rotor auto-discovers swipe actions.

**CloudKit sync guardian:** All clear. Hard delete + `NSPersistentCloudKitContainer` tombstone propagation via `NSPersistentHistoryTracking`. Tombstone window edge case acknowledged and deferred.

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

- Build succeeded with zero errors
- 106 tests passed (102 existing + 4 new delete tests), 0 failures

### Completion Notes List

- ✅ Task 1: Added `hapticService: HapticServiceProtocol` dependency to `FeedViewModel` following established DI pattern with `@ObservationIgnored` for consistency
- ✅ Task 2: Added `deleteExpense(_:)` async method — calls repository, fires `.deleteTap` haptic on success, swallows errors with `#if DEBUG` print
- ✅ Task 3: Added `.swipeActions(edge: .leading, allowsFullSwipe: false)` with `Button(role: .destructive)` for semantic red styling and VoiceOver support
- ✅ Task 4: Added `lastDeletedExpenseID` tracking to `MockExpenseRepository` for test assertions
- ✅ Task 5: Expanded `makeSUT()` to 5-element tuple with `MockHapticService`, updated all 15 existing test call sites, added 4 new delete tests
- ✅ Task 6: Build clean, 106/106 tests pass. Manual verification tasks deferred to user.

### Change Log

- 2026-04-03: Implemented delete expense flow — swipe-right delete action with haptic feedback, 4 new unit tests (Story 2-4)

### File List

- `CashOut/ViewModels/FeedViewModel.swift` — Modified: added hapticService dependency + deleteExpense method
- `CashOut/Views/Feed/FeedView.swift` — Modified: added leading swipe delete action
- `CashOutTests/Repositories/MockExpenseRepository.swift` — Modified: added lastDeletedExpenseID tracking
- `CashOutTests/ViewModels/FeedViewModelTests.swift` — Modified: expanded makeSUT tuple, updated 15 call sites, added 4 delete tests

### Orchestrator Review (2026-04-03)

**Guardians run**: ios-swiftui-guardian, architecture-guardian (cloudkit-sync-guardian N/A — no sync code modified)

**CRITICALs:** None.

**WARNINGs (10 total, all dispositioned):**
- 5 by-design per story spec (leading edge, allowsFullSwipe:false, haptic timing, error swallowing, @ObservationIgnored on let)
- 2 pre-existing (Task.sleep in tests, MockHapticService concurrency)
- 3 acknowledged trade-offs (fire-and-forget Task, VoiceOver label context, mock ID tracking order)

All WARNINGs reviewed and documented — no blockers for code review.
