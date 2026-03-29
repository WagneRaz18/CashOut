# Story 1.6: Category Picker, Save Flow & Expense Persistence

Status: ready-for-dev
Readiness: approved (2026-03-29)
Readiness Report: _bmad-output/planning-artifacts/implementation-readiness-report-2026-03-29-story-1-6.md

## Story

As a user,
I want to select a category and save my expense with one tap,
So that logging a purchase is fast and the data is immediately stored.

## Acceptance Criteria

1. **Given** CategoryPickerView **When** displayed above the numpad **Then** it shows a horizontal ScrollView of category chips with color dot (8pt circle) + label, and the most-recently-used category is pre-selected (UX-DR3, UX-DR9)

2. **Given** MRU category tracking **When** the user saves an expense **Then** the selected categoryID is persisted to UserDefaults as the MRU default, and restored on next app launch or entry screen appearance

3. **Given** a category chip **When** tapped **Then** it becomes selected with tinted background + colored border

4. **Given** the Save button **When** amount is ฿0.00 **Then** the button is inactive (grayed, does not respond to taps) — no error message, no haptic (UX-DR26)

5. **Given** the Save button **When** amount > ฿0 and tapped **Then** the expense is saved to Core Data via ExpenseRepository with amount (Int64 satang), categoryID, createdByUserID, createdAt, modifiedAt, and optional note **And** the screen resets to ฿0.00 with the just-used category as the new MRU default **And** no confirmation banner, toast, or animation is shown (UX-DR26)

6. **Given** the optional note field **When** accessed via a small icon near the save button **Then** the user can add free text to the entry via a sheet (FR2)

7. **Given** the device is offline **When** the user saves an entry **Then** it persists locally via Core Data and the local save experience is identical to online — partner sync occurs when connectivity returns (FR23, FR24)

8. **Given** ExpenseEntryViewModel **When** created **Then** it is @Observable with @MainActor, uses @ObservationIgnored on repository/service references, and does not import SwiftUI

## Tasks / Subtasks

- [ ] Task 1: Expand ExpenseEntryViewModel with dependencies and save logic (AC: #2, #5, #8)
  - [ ] 1.1 Add `@ObservationIgnored private let expenseRepository: ExpenseRepositoryProtocol` with default `ExpenseRepository()`
  - [ ] 1.2 Add `@ObservationIgnored private let categoryRepository: CategoryRepositoryProtocol` with default `CategoryRepository()`
  - [ ] 1.3 Add `@ObservationIgnored private let authService: AuthenticationServiceProtocol` with default `AuthenticationService()` — NOTE: existing 9 tests use zero-arg init which will create real AuthenticationService; this is acceptable (Keychain returns nil in test, observers are harmless) but new tests MUST inject MockAuthenticationService
  - [ ] 1.4 Add `var categories: [CategoryData] = []` observable property
  - [ ] 1.5 Add `var selectedCategoryID: UUID?` observable property
  - [ ] 1.6 Add `var noteText: String = ""` observable property
  - [ ] 1.7 Add `var isSaving: Bool = false` guard to prevent double-tap
  - [ ] 1.8 Add `@ObservationIgnored private let userDefaults: UserDefaults` with default `.standard` — injectable for test isolation
  - [ ] 1.9 Implement `loadCategories()` async — guard `categories.isEmpty` (prevents re-fetch on tab re-appear), fetches from `categoryRepository.fetchCategories()`, guard `!Task.isCancelled` after await, sets `categories`, restores MRU from UserDefaults, falls back to first category if no MRU
  - [ ] 1.10 Implement `selectCategory(_ id: UUID)` — sets `selectedCategoryID`
  - [ ] 1.11 Implement `saveExpense()` async throws — set `isSaving = true` then `defer { isSaving = false }` (ensures reset even on throw), guards `!isAmountZero && selectedCategoryID != nil`, guard `let userID = authService.currentUserID` (throw if nil — never use `?? ""`), builds `ExpenseData`, calls `expenseRepository.saveExpense(_:)`, persists MRU to UserDefaults, calls `resetAmount()`, clears `noteText`
  - [ ] 1.12 MRU key: `"lastUsedCategoryID"` — store/restore `UUID.uuidString` via injected `userDefaults` [Source: architecture.md line 296]
  - [ ] 1.13 Validate `amountInCents > 0` at persistence boundary (Deferred D1 from story 1.5)

- [ ] Task 2: Create CategoryPickerView (AC: #1, #3)
  - [ ] 2.1 Create `Views/Entry/CategoryPickerView.swift`
  - [ ] 2.2 Accept `categories: [CategoryData]`, `selectedCategoryID: UUID?`, `onSelect: (UUID) -> Void`
  - [ ] 2.3 `ScrollView(.horizontal, showsIndicators: false)` with `HStack(spacing: Spacing.sm)`
  - [ ] 2.4 Each chip: `Button` with `HStack` of color dot (`Circle().fill(Color(category.colorName)).frame(width: 8, height: 8)`) + `Text(category.name)` in `.subheadline`
  - [ ] 2.5 Selected state: tinted background using `Color(category.colorName).opacity(0.15)` + colored border `RoundedRectangle` stroke, `.capsule` shape
  - [ ] 2.6 Unselected state: `.secondary` text, no background tint, subtle border or none
  - [ ] 2.7 Auto-scroll to selected chip using `ScrollViewReader` + `.id(category.id)` + `.task(id: selectedCategoryID) { proxy.scrollTo(selectedCategoryID, anchor: .center) }` — use `.task(id:)` NOT `.onAppear` (synchronous onAppear fires before layout, scroll silently ignored)
  - [ ] 2.8 Chip minimum 44pt height (accessibility tap target)
  - [ ] 2.9 No haptic on tap (deferred to Story 1.7 — HapticService does not exist yet)
  - [ ] 2.10 Add `#Preview` with `.frame(height: 60)` to prevent blank preview (established pattern from Story 1.5 NumpadView preview fix)
  - [ ] 2.11 Plain `HStack` is intentional for 6 predefined categories — use `LazyHStack` if Story 5.2 (custom categories) grows the list significantly

- [ ] Task 3: Create NoteEntrySheet (AC: #6)
  - [ ] 3.1 Create `Views/Entry/NoteEntrySheet.swift`
  - [ ] 3.2 Accept `@Binding var noteText: String` and `dismiss` environment action
  - [ ] 3.3 Simple layout: `TextField("Add a note", text: $noteText, axis: .vertical)` with `.lineLimit(3...6)` + Done button
  - [ ] 3.4 Done button dismisses the sheet
  - [ ] 3.5 No cancel/discard logic — text binding updates live

- [ ] Task 4: Create SaveButtonView (AC: #4, #5)
  - [ ] 4.1 Create `Views/Entry/SaveButtonView.swift`
  - [ ] 4.2 Accept `isDisabled: Bool`, `onSave: () -> Void`, `onNoteTap: () -> Void`
  - [ ] 4.3 Layout: `HStack` — small note icon (`Image(systemName: "square.and.pencil")` button, leading) + full-width Save `Button` (`.buttonStyle(.glassProminent)`, `.headline` text)
  - [ ] 4.4 Save button disabled when `isDisabled` is true — grayed out, not tappable
  - [ ] 4.5 Note icon: subtle `.secondary` color, tapping opens note sheet
  - [ ] 4.6 No haptic on save (deferred to Story 1.7)

- [ ] Task 5: Wire EntryView composition (AC: #1, #2, #4, #5, #6)
  - [ ] 5.1 Replace `Spacer()` comment in `EntryView.swift` with `CategoryPickerView`
  - [ ] 5.2 Add `SaveButtonView` below `NumpadView`
  - [ ] 5.3 Add `@State private var showingNoteSheet = false`
  - [ ] 5.4 Add `.sheet(isPresented: $showingNoteSheet) { NoteEntrySheet(noteText: $viewModel.noteText).presentationDetents([.large]) }` — `.presentationDetents([.large])` required per UX nav patterns; `$viewModel.noteText` works because `@State` on `@Observable` supports `$` binding syntax
  - [ ] 5.5 Wire save action: `Task { try await viewModel.saveExpense() }` — do NOT use `try?` (errors need logging); wrap in `do/catch` with `print()` in DEBUG for save failure diagnostics
  - [ ] 5.6 Wire note tap to toggle `showingNoteSheet`
  - [ ] 5.7 Add `.task { await viewModel.loadCategories() }` for initial category load — `loadCategories()` has an internal `guard categories.isEmpty` to prevent re-fetch on tab re-appear
  - [ ] 5.8 Let ViewModel create its own `AuthenticationService()` instance via default parameter (reads `currentUserID` from Keychain — same value regardless of instance; the app-level `authViewModel` is not needed here)

- [ ] Task 6: Unit tests for ExpenseEntryViewModel save flow (AC: #2, #5, #8)
  - [ ] 6.1 Create mock: `MockExpenseRepository` in `CashOutTests/Repositories/MockExpenseRepository.swift` implementing `ExpenseRepositoryProtocol` with call tracking
  - [ ] 6.2 Create mock: `MockCategoryRepository` in `CashOutTests/Repositories/MockCategoryRepository.swift` implementing `CategoryRepositoryProtocol` with configurable return data
  - [ ] 6.3 Test: `saveExpense()` calls `expenseRepository.saveExpense(_:)` with correct amount, categoryID, createdByUserID
  - [ ] 6.4 Test: `saveExpense()` resets `amountInCents` to 0 after save
  - [ ] 6.5 Test: `saveExpense()` clears `noteText` after save
  - [ ] 6.6 Test: `saveExpense()` does NOT save when `isAmountZero` (guard)
  - [ ] 6.7 Test: `saveExpense()` does NOT save when `selectedCategoryID` is nil (guard)
  - [ ] 6.8 Test: `loadCategories()` populates `categories` array from mock repository
  - [ ] 6.9 Test: `loadCategories()` restores MRU categoryID from UserDefaults
  - [ ] 6.10 Test: `saveExpense()` persists selected categoryID as MRU to UserDefaults
  - [ ] 6.11 Test: `selectCategory(_:)` updates `selectedCategoryID`
  - [ ] 6.12 Test: double-tap guard — `saveExpense()` during active save is no-op
  - [ ] 6.13 Test: `saveExpense()` when repository throws — verify `isSaving` resets to `false` (defer pattern)
  - [ ] 6.14 Test: `saveExpense()` when `authService.currentUserID == nil` — verify throws, does NOT save with empty string

## Dev Notes

### Save Flow Architecture

The save flow is the app's critical path — it must feel instant. The pattern:

```
User taps Save
    → View calls Task { do { try await viewModel.saveExpense() } catch { print(error) } }
        → ViewModel sets isSaving = true, defer { isSaving = false }
        → ViewModel guards: !isAmountZero, selectedCategoryID != nil
        → ViewModel guards: let userID = authService.currentUserID (throws if nil)
        → ViewModel builds ExpenseData(id: UUID(), amount: amountInCents, ...)
        → ViewModel calls repository.saveExpense(data)
            → Repository writes to Core Data viewContext (private store)
            → NSPersistentCloudKitContainer syncs to CloudKit private DB (background)
            → Partner receives via shared DB (CKShare)
        → ViewModel persists MRU categoryID to UserDefaults
        → ViewModel resets: amountInCents = 0, noteText = ""
        → selectedCategoryID stays (MRU principle — just-used category is new default)
    On throw → isSaving resets via defer, error logged, UI unchanged (no user-visible error)
```

No confirmation UI. No toast. No banner. Screen reset IS the feedback (UX-DR26). Haptic feedback is Story 1.7.

### MRU Category Tracking

UserDefaults key: `"lastUsedCategoryID"` storing `UUID.uuidString` [Source: architecture.md line 296].
UserDefaults is device-local (not CloudKit-synced) — each partner maintains their own MRU, which is the correct UX intent.

- On `loadCategories()`: guard `categories.isEmpty` (prevents re-fetch on tab re-appear per TabView `.task` re-fire behavior), read from `userDefaults`, find matching category in fetched list, set `selectedCategoryID`. If not found or first launch, default to first category (Food & Drink, sortOrder 0).
- On `saveExpense()`: write `selectedCategoryID?.uuidString` to `userDefaults` immediately after successful save.
- MRU survives app restart (UserDefaults is persistent).

### Dependency Injection Pattern (Must Follow)

```swift
@MainActor
@Observable
final class ExpenseEntryViewModel {
    var amountInCents: Int64 = 0
    var categories: [CategoryData] = []
    var selectedCategoryID: UUID?
    var noteText: String = ""
    var isSaving: Bool = false

    @ObservationIgnored
    private let expenseRepository: ExpenseRepositoryProtocol
    @ObservationIgnored
    private let categoryRepository: CategoryRepositoryProtocol
    @ObservationIgnored
    private let authService: AuthenticationServiceProtocol
    @ObservationIgnored
    private let userDefaults: UserDefaults

    init(
        expenseRepository: ExpenseRepositoryProtocol = ExpenseRepository(),
        categoryRepository: CategoryRepositoryProtocol = CategoryRepository(),
        authService: AuthenticationServiceProtocol = AuthenticationService(),
        userDefaults: UserDefaults = .standard
    ) {
        self.expenseRepository = expenseRepository
        self.categoryRepository = categoryRepository
        self.authService = authService
        self.userDefaults = userDefaults
    }
}
```

- DO NOT import SwiftUI in the ViewModel
- DO NOT use @ObservableObject or @Published
- ALL injected dependencies marked `@ObservationIgnored`
- Default parameters provide real implementations — tests inject mocks
- `AuthenticationService` reads `currentUserID` from Keychain — each instance returns the same value, so creating a new instance via default parameter is safe
- `userDefaults: UserDefaults = .standard` is injectable — tests use `UserDefaults(suiteName:)` to avoid pollution
- NOTE: Existing 9 tests use `ExpenseEntryViewModel()` with zero args. This now creates a real `AuthenticationService()` (reads Keychain, starts notification observers). In test environment, Keychain returns nil and observers are harmless — acceptable trade-off. New save-flow tests MUST inject `MockAuthenticationService`.

### createdByUserID Attribution

`ExpenseData.createdByUserID` must be set from `authService.currentUserID`. Use `guard let userID = authService.currentUserID else { throw }` — never use `?? ""` (silent empty string corrupts partner attribution data). The authentication is guaranteed at this point (app won't show `ContentView` unless `authViewModel.isAuthenticated == true`), but throw defensively to catch any edge case.

**Important**: `AuthenticationService.currentUserID` is the Apple ID identifier (`ASAuthorizationAppleIDCredential.user`), NOT the CloudKit `userRecordID.recordName`. Architecture.md line 68 prescribes CloudKit `userRecordID`, but `AuthenticationService` only stores the Apple ID credential. For Epic 1 (solo entry, pre-sharing), the Apple ID identifier is sufficient and stable. Epic 4 (sharing) may need to add CloudKit `userRecordID` fetch to `AuthenticationService` — flag this as a deferred architecture decision, not a Story 1.6 concern.

[Source: architecture.md — "Partner Attribution" cross-cutting concern, line 68]

### CategoryPickerView Design

```
[ ● Food & Drink ] [ ● Transport ] [ ● Entertainment ] [ ● Household ] [ ● Shopping ] [ ● Other ]
  ↑ selected (tint bg + border)    ↑ unselected (muted)
```

- `ScrollView(.horizontal, showsIndicators: false)` with `HStack(spacing: Spacing.sm)`
- Each chip is a `Button` with `.buttonBorderShape(.capsule)`
- Selected chip: `Color(category.colorName).opacity(0.15)` background + `Color(category.colorName)` 1pt border stroke
- Color dot: `Circle().fill(Color(category.colorName)).frame(width: 8, height: 8)`
- Use `ScrollViewReader` + `.task(id: selectedCategoryID) { proxy.scrollTo(selectedCategoryID, anchor: .center) }` — NOT `.onAppear` (synchronous `.onAppear` fires before layout, scroll silently ignored; `.task(id:)` defers to next run loop and re-fires on selection change)
- Minimum 44pt chip height for accessibility
- Category colors come from `CategoryData.colorName` → `Color("Sage")`, `Color("Slate")`, etc. (asset catalog colors from Story 1.4)

[Source: ux-design-specification.md — "CategoryPickerView" component spec, lines 765-771]

### Save Button Design

- `.buttonStyle(.glassProminent)` — primary action button per Liquid Glass rules. NOTE: UX spec says "filled accent color" but architecture.md resolves this as `.glassProminent` — the iOS 26 API equivalent. `.glassProminent` renders as a prominent glass-tinted button which IS the iOS 26 primary button style.
- `.headline` font weight per UX typography spec
- Full-width, anchored at bottom of entry screen
- Disabled state when `isAmountZero`: grayed out, not tappable, no error message
- **NEVER** combine `.buttonStyle(.glassProminent)` with `.glassEffect()` — they conflict

[Source: architecture.md — Liquid Glass API Rules, lines 788-794]

### Note Field Design

- Hidden by default — accessible via pencil icon (`"square.and.pencil"`) near save button
- Opens as a sheet with `.presentationDetents([.large])` (per UX navigation patterns: "note entry" is a sheet)
- Simple `TextField("Add a note", text: $noteText, axis: .vertical)` with multiline support
- No required field indicators, no validation
- Text updates via binding — dismissing the sheet retains the text
- `$viewModel.noteText` works from `@State var viewModel` because `@State` on `@Observable` supports `$` binding syntax in Swift 5.9+ — no separate `@Bindable` declaration needed
- If user doesn't tap the note icon, `noteText` remains empty string → `ExpenseData.note` set to `noteText.isEmpty ? nil : noteText`

[Source: ux-design-specification.md — Form Patterns, lines 847-864; Navigation Patterns, line 871]

### Existing Code to Reuse (DO NOT Recreate)

| What | File | Usage |
|------|------|-------|
| `Int64.displayAmount` | `Utilities/Extensions/Int64+Currency.swift` | Format satang to "฿X.XX" |
| `Spacing` enum | `Utilities/Constants.swift` | `Spacing.sm` (8pt), `Spacing.md` (16pt) |
| `DefaultCategory` enum | `Utilities/Constants.swift` | Reference only — categories come from Core Data |
| `CategoryColor` enum | `Utilities/Extensions/Color+CategoryTokens.swift` | Reference only — use `Color(category.colorName)` directly |
| `ExpenseRepositoryProtocol` | `Repositories/ExpenseRepositoryProtocol.swift` | Already exists with `saveExpense(_:)` |
| `ExpenseRepository` | `Repositories/ExpenseRepository.swift` | Already exists — do NOT modify |
| `CategoryRepositoryProtocol` | `Repositories/CategoryRepositoryProtocol.swift` | Already exists with `fetchCategories()` |
| `CategoryRepository` | `Repositories/CategoryRepository.swift` | Already exists — do NOT modify |
| `ExpenseData` | `Models/ExpenseData.swift` | Already exists with all needed fields |
| `CategoryData` | `Models/CategoryData.swift` | Already exists with `id`, `name`, `iconName`, `colorName`, `isDefault`, `sortOrder` |
| `AuthenticationServiceProtocol` | `Services/AuthenticationService.swift` | `currentUserID: String?` property |
| `MockAuthenticationService` | `CashOutTests/Services/MockAuthenticationService.swift` | Already exists — reuse for ViewModel tests |
| `TestPersistenceHelper` | `CashOutTests/Helpers/TestPersistenceHelper.swift` | `makeInMemoryController()` — not needed for mock-based tests |
| `AmountDisplayView` | `Views/Entry/AmountDisplayView.swift` | Already exists from Story 1.5 |
| `NumpadView` | `Views/Entry/NumpadView.swift` | Already exists from Story 1.5 |
| `EntryView` | `Views/Entry/EntryView.swift` | Modify in place — do NOT recreate |

### Deferred Items from Story 1.5 to Address

- **D1: Negative `amountInCents` not guarded** — Add `guard amountInCents > 0` in `saveExpense()` as the persistence boundary validation
- **D2: `appendDigit` accepts multi-character strings** — Not addressed this story (still only called from hardcoded NumpadKey)

### View Composition Pattern (Updated from Story 1.5)

```
EntryView (container)
├── AmountDisplayView(amount: viewModel.amountInCents)       // top ~20%
├── CategoryPickerView(                                       // ~60pt strip
│     categories: viewModel.categories,
│     selectedCategoryID: viewModel.selectedCategoryID,
│     onSelect: { viewModel.selectCategory($0) }
│   )
├── NumpadView(                                               // ~45%
│     onDigit: { viewModel.appendDigit($0) },
│     onDecimal: { viewModel.appendDecimalPoint() },
│     onBackspace: { viewModel.deleteLastDigit() }
│   )
├── SaveButtonView(                                           // bottom
│     isDisabled: viewModel.isAmountZero,
│     onSave: { Task { do { try await viewModel.saveExpense() } catch { print(error) } } },
│     onNoteTap: { showingNoteSheet = true }
│   )
└── .sheet(isPresented: $showingNoteSheet) {
      NoteEntrySheet(noteText: $viewModel.noteText)
          .presentationDetents([.large])
    }
```

EntryView does NOT use NavigationStack — it's a flat screen within the TabView.
[Source: architecture.md — "each tab owns its own NavigationStack" / ContentView.swift shows EntryView is NOT wrapped in NavigationStack]

### Liquid Glass API Rules (Critical)

- Numpad keys: `.buttonStyle(.glass)` — they are `Button` elements (from Story 1.5)
- Save button: `.buttonStyle(.glassProminent)` — primary action
- Category chips: plain `Button` — no glass (they use category color tint, not glass)
- **NEVER** combine `.buttonStyle(.glass*)` with `.glassEffect()` on the same element
- [Source: architecture.md, lines 788-794]

### File Placement

| File | Location | Action |
|------|----------|--------|
| `ExpenseEntryViewModel.swift` | `CashOut/ViewModels/` | Modify existing |
| `CategoryPickerView.swift` | `CashOut/Views/Entry/` | New file |
| `NoteEntrySheet.swift` | `CashOut/Views/Entry/` | New file |
| `SaveButtonView.swift` | `CashOut/Views/Entry/` | New file |
| `EntryView.swift` | `CashOut/Views/Entry/` | Modify existing |
| `MockExpenseRepository.swift` | `CashOutTests/Repositories/` | New file |
| `MockCategoryRepository.swift` | `CashOutTests/Repositories/` | New file |
| `ExpenseEntryViewModelTests.swift` | `CashOutTests/ViewModels/` | Modify existing (add save flow tests) |

All new files must be registered in `project.pbxproj`.

### Testing Standards

- All test classes: `@MainActor` at class level (established in Story 1.5 review, F5)
- XCTest framework
- Tests for `saveExpense()` and `loadCategories()` are `async` (repository calls are async)
- Mock repositories and services — do NOT use real Core Data for ViewModel tests
- `MockAuthenticationService` already exists — set `currentUserID = "test-user"` in test setup
- For UserDefaults MRU testing: inject `UserDefaults(suiteName: "com.cashout.tests.\(name)")` via the `userDefaults` init parameter; call `suiteName.removePersistentDomain(forName:)` in `tearDown` to prevent pollution
- Existing 9 ViewModel tests must continue to pass — the new init parameters have defaults, so `ExpenseEntryViewModel()` still works with no arguments
- Test `saveExpense()` with repository that throws — verify `isSaving` resets to `false` via `defer`
- Test `saveExpense()` when `authService.currentUserID == nil` — verify it throws (not silently saves with empty string)

### Readiness Check Findings (2026-03-29)

3 minor issues identified — no critical or major blockers:

1. **`CategoryData` lacks `Identifiable` conformance**: Has `id: UUID` but no `Identifiable`. Use `ForEach(categories, id: \.id)` or add conformance during implementation.
2. **`ExpenseData` lacks `Identifiable` conformance**: Same pattern. Not blocking for Story 1.6 (not used in ForEach).
3. **Currency notation in epics.md**: Lines 396, 400–401 still reference "$"/"cents" — story spec correctly uses "฿"/"satang". Cosmetic only.

All 14 codebase dependencies verified against actual source files. FR coverage, UX alignment, and architecture alignment confirmed.

### Boundaries — What NOT to Implement

- **No haptic feedback** — Story 1.7 (HapticService does not exist yet; DO NOT create it)
- **No VoiceOver labels** — Story 1.7
- **No Dynamic Type scaling for chips** — Story 1.7
- **No edit flow** — Story 2.3 (edit sheet with pre-filled values)
- **No feed integration** — Story 2.1 (saved expenses appear in feed)
- **No insights update** — Story 3.x
- **No CloudKit sync logic** — handled automatically by `NSPersistentCloudKitContainer`
- **No custom categories** — Story 5.2 (this story shows predefined categories only)
- **No animation on save** — UX-DR26 explicitly prohibits confirmation animation

### Previous Story Intelligence

**From Story 1.5 (Numpad & Amount Display):**
- `ExpenseEntryViewModel` is `@MainActor @Observable final class` — extend, do not replace
- Existing tests create `ExpenseEntryViewModel()` with no arguments — new init must preserve default parameters
- `EntryView` has `@State private var viewModel = ExpenseEntryViewModel()` — this works with default params
- `amountInCents` is public `var` — read/write access from ViewModel and test
- `isAmountZero` is computed from `amountInCents == 0`
- `resetAmount()` sets `amountInCents = 0`
- GeometryReader wraps NumpadView body — interposed VStack between GeometryReader and LazyVGrid (Review F1)
- `displayAmount` uses `Decimal(self) / 100` — no floating-point (Review F2)

**Review Findings from 1.5 relevant to 1.6:**
- D1: Validate `amountInCents > 0` at persistence boundary → do this in `saveExpense()` guard
- D5: InsightsView calls `.displayAmount` directly — not our concern, placeholder view

**From Story 1.4 (Design Tokens, Categories, Repository Layer):**
- Core Data entity creation: use `Entity(context: viewContext)` — never parameterless `Entity()`
- `CategoryRepository.seedDefaultCategoriesIfNeeded()` runs at app launch (CashOutApp.swift)
- Repository methods are `async throws` with `@MainActor`
- DI via init parameter: `init(persistence: PersistenceController = .shared)`
- F1: Always throw `RepositoryError.missingRequiredField` on nil — never use fallback UUID()
- F5: Always add `@MainActor` to test methods/classes

### Git Intelligence

Recent commits show established patterns:
- Feature commits: `feat(scope): description (story X-Y)`
- Fix commits: `fix(scope): description`
- Refactor commits: `refactor(scope): description`
- All 50 existing tests pass — zero regressions expected
- Story 1.5 created: `ExpenseEntryViewModel.swift`, `AmountDisplayView.swift`, `NumpadView.swift`, modified `EntryView.swift`
- Story 1.5 review created 50th test (9 ViewModel + 6 Currency + 6 Repo + other + 3 UI)

### Project Structure Notes

- All new `Views/Entry/*.swift` files follow existing pattern (AmountDisplayView, NumpadView are in this directory)
- `CashOutTests/Repositories/` directory exists (contains `CategoryRepositoryTests.swift`, `ExpenseRepositoryTests.swift`)
- `CashOutTests/Services/` directory exists (contains `MockAuthenticationService.swift`)
- `CashOutTests/ViewModels/` directory exists (contains `ExpenseEntryViewModelTests.swift`, `AuthenticationViewModelTests.swift`)

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Story 1.6 acceptance criteria, lines 374-414]
- [Source: _bmad-output/planning-artifacts/architecture.md — MVVM patterns, Liquid Glass rules, DI pattern, save pattern]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — CategoryPickerView spec (lines 765-771), button hierarchy (lines 814-826), form patterns (lines 847-864), navigation patterns (lines 866-880)]
- [Source: _bmad-output/planning-artifacts/prd.md — FR1-FR4 expense entry, FR9/FR12 categories, FR23-FR24 offline]
- [Source: _bmad-output/implementation-artifacts/1-5-numpad-and-amount-display.md — Previous story learnings, review findings, deferred items]
- [Source: CashOut/ViewModels/ExpenseEntryViewModel.swift — Existing ViewModel to extend]
- [Source: CashOut/Views/Entry/EntryView.swift — Existing view to modify]
- [Source: CashOut/Repositories/ExpenseRepository.swift — Existing saveExpense implementation]
- [Source: CashOut/Repositories/CategoryRepository.swift — Existing fetchCategories implementation]
- [Source: CashOut/Models/ExpenseData.swift — Data transfer object with all required fields]
- [Source: CashOut/Models/CategoryData.swift — Category data transfer object]
- [Source: CashOut/Services/AuthenticationService.swift — AuthenticationServiceProtocol with currentUserID]
- [Source: CashOutTests/Services/MockAuthenticationService.swift — Existing mock to reuse]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
