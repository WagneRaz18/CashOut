# Story 1.7: Entry Screen Haptics, Accessibility & Dynamic Type

Status: ready-for-dev
Readiness: approved (2026-03-29)
Readiness Report: _bmad-output/planning-artifacts/implementation-readiness-report-2026-03-29-story-1-7.md

## Story

As a user,
I want haptic feedback on every interaction and full accessibility support,
So that the entry experience feels responsive and is usable by everyone.

## Acceptance Criteria

1. **Given** a numpad key tap **When** any key is pressed (digit, decimal, backspace) **Then** a light haptic fires via HapticService (UX-DR10)

2. **Given** a category chip **When** tapped **Then** a light haptic fires via HapticService (UX-DR10)

3. **Given** the Save button **When** tapped successfully (amount > 0, category selected, save completes) **Then** a success haptic fires via HapticService (`UINotificationFeedbackGenerator` `.success`) (UX-DR10)

4. **Given** HapticService **When** any haptic event is triggered **Then** all haptics route through `HapticServiceProtocol.trigger(_:)` and respect `UIAccessibility.isReduceMotionEnabled` — when Reduce Motion is on, no haptics fire

5. **Given** VoiceOver is enabled **When** the entry screen is focused **Then** numpad keys announce their digit (e.g., "1", "2", "Decimal point", "Delete"), amount display announces "Amount: ฿X.XX", category chips announce "[name], selected" or "[name], not selected" (UX-DR16)

6. **Given** Dynamic Type scaling **When** the user increases text size **Then** all text scales via SwiftUI text styles and numpad keys scale proportionally via GeometryReader (UX-DR17)

## Tasks / Subtasks

- [ ] Task 1: Create HapticService protocol and implementation (AC: #4)
  - [ ] 1.1 Create `CashOut/Services/HapticService.swift`
  - [ ] 1.2 Define `HapticEvent` enum with cases: `numpadKey`, `categorySelect`, `saveTap`, `deleteTap` (reserved for Story 2.4 feed row swipe-to-delete — NOT used for numpad backspace), `error` — define ALL cases from architecture even though only 3 are used in this story
  - [ ] 1.3 Define `HapticServiceProtocol` with single method: `func trigger(_ event: HapticEvent)`
  - [ ] 1.4 Implement `HapticService` class — NOT `@Observable`, NOT `@MainActor` (UIKit haptic generators are thread-safe)
  - [ ] 1.5 In `trigger(_:)`: early return if `UIAccessibility.isReduceMotionEnabled` is true
  - [ ] 1.6 For `.numpadKey` and `.categorySelect`: use `UIImpactFeedbackGenerator(style: .light)` → `.impactOccurred()`
  - [ ] 1.7 For `.saveTap`: use `UINotificationFeedbackGenerator()` → `.notificationOccurred(.success)`
  - [ ] 1.8 For `.deleteTap`: use `UINotificationFeedbackGenerator()` → `.notificationOccurred(.success)`
  - [ ] 1.9 For `.error`: use `UINotificationFeedbackGenerator()` → `.notificationOccurred(.error)`
  - [ ] 1.10 Import UIKit (not SwiftUI) in the service file — `UIImpactFeedbackGenerator` and `UINotificationFeedbackGenerator` live in UIKit

- [ ] Task 2: Create MockHapticService for tests (AC: #4)
  - [ ] 2.1 Create `CashOutTests/Services/MockHapticService.swift`
  - [ ] 2.2 Implement `MockHapticService: HapticServiceProtocol` with `var triggeredEvents: [HapticEvent] = []`
  - [ ] 2.3 `trigger(_:)` appends to `triggeredEvents` — no UIKit calls
  - [ ] 2.4 Add `var lastEvent: HapticEvent? { triggeredEvents.last }` convenience
  - [ ] 2.5 Add `func reset() { triggeredEvents.removeAll() }` for test teardown

- [ ] Task 3: Add HapticService dependency to ExpenseEntryViewModel (AC: #1, #2, #3)
  - [ ] 3.1 Add `@ObservationIgnored private let hapticService: HapticServiceProtocol` to ExpenseEntryViewModel
  - [ ] 3.2 Add `hapticService: HapticServiceProtocol = HapticService()` to init — default parameter preserves backward compatibility with existing 59 tests
  - [ ] 3.3 In `appendDigit(_:)`: call `hapticService.trigger(.numpadKey)` as FIRST line (haptic fires even if guard rejects input)
  - [ ] 3.4 In `deleteLastDigit()`: call `hapticService.trigger(.numpadKey)` as first line
  - [ ] 3.5 In `appendDecimalPoint()`: call `hapticService.trigger(.numpadKey)` as first line (decimal is a no-op functionally but the KEY PRESS still gets haptic feedback per UX-DR10 "light impact per numpad key tap")
  - [ ] 3.6 In `selectCategory(_:)`: call `hapticService.trigger(.categorySelect)` as first line
  - [ ] 3.7 In `saveExpense()`: call `hapticService.trigger(.saveTap)` AFTER the `guard !Task.isCancelled` check (line 130) but BEFORE `resetAmount()` (line 136). This placement means: repo save succeeded + task not cancelled → fire haptic → then reset state. Do NOT trigger on failed/guarded saves (amount zero, no category, not authenticated, task cancelled)

- [ ] Task 4: Add accessibility labels to NumpadView (AC: #5)
  - [ ] 4.1 Digit keys: `.accessibilityLabel(value)` (e.g., "1", "2", ... "9", "0")
  - [ ] 4.2 Decimal key: `.accessibilityLabel("Decimal point")`
  - [ ] 4.3 Backspace key: `.accessibilityLabel("Delete")`
  - [ ] 4.4 Apply labels to the `Button` element AFTER `.buttonStyle(.glass)` — modifier order matters; placing accessibility before button style can cause the style to alter accessibility traits
  - [ ] 4.5 Create helper: `private func accessibilityLabel(for key: NumpadKey) -> Text` — must explicitly return `Text` type (not `@ViewBuilder` or `some View`) to match `.accessibilityLabel(_: Text)` overload

- [ ] Task 5: Add accessibility to AmountDisplayView (AC: #5)
  - [ ] 5.1 Add `.accessibilityLabel("Amount: \(amount.displayAmount)")` — uses the THB-formatted string (e.g., "Amount: ฿12.50")
  - [ ] 5.2 Add `.accessibilityAddTraits(.updatesFrequently)` — amount changes with each keypress

- [ ] Task 6: Add accessibility to CategoryPickerView (AC: #5)
  - [ ] 6.1 Each chip button: `.accessibilityLabel("\(category.name), \(isSelected ? "selected" : "not selected")")`
  - [ ] 6.2 Add `.accessibilityAddTraits(isSelected ? [.isSelected] : [])` to each chip button

- [ ] Task 7: Add accessibility to SaveButtonView (AC: #5)
  - [ ] 7.1 Save button: `.accessibilityLabel("Save expense")`
  - [ ] 7.2 Note button: `.accessibilityLabel("Add note")`
  - [ ] 7.3 Save button disabled state is automatically conveyed by SwiftUI's `.disabled()` modifier to VoiceOver — no extra work needed

- [ ] Task 8: Verify Dynamic Type support (AC: #6)
  - [ ] 8.1 NumpadView: Already uses `GeometryReader` for key height scaling — verify `.font(.title)` on digit labels scales with Dynamic Type. If keys truncate at AX sizes, add `.minimumScaleFactor(0.8)` to key labels
  - [ ] 8.2 AmountDisplayView: Already uses `.font(.system(size: 48, ...))` + `.minimumScaleFactor(0.7)` — fixed-size font does NOT scale with Dynamic Type. This is intentional per UX spec line 928: "Font size stays 48pt. Truncates with `.minimumScaleFactor(0.7)` on SE." No change needed.
  - [ ] 8.3 CategoryPickerView: Uses `.font(.subheadline)` — this is a SwiftUI text style and scales automatically. Verify no truncation at larger sizes.
  - [ ] 8.4 SaveButtonView: Uses `.font(.headline)` — scales automatically. Verify.
  - [ ] 8.5 Add `#Preview` with `.dynamicTypeSize(.accessibility3)` to EntryView for verifying large type rendering

- [ ] Task 9: Unit tests for haptic integration (AC: #1, #2, #3, #4)
  - [ ] 9.1 Inject `MockHapticService` into `ExpenseEntryViewModel` in test setup
  - [ ] 9.2 Test: `appendDigit("5")` triggers exactly one `.numpadKey` event
  - [ ] 9.3 Test: `deleteLastDigit()` triggers exactly one `.numpadKey` event
  - [ ] 9.4 Test: `appendDecimalPoint()` triggers exactly one `.numpadKey` event
  - [ ] 9.5 Test: `selectCategory(id)` triggers exactly one `.categorySelect` event
  - [ ] 9.6 Test: `saveExpense()` after setting valid amount + category triggers `.saveTap` — requires MockExpenseRepository, MockCategoryRepository, MockAuthenticationService injected alongside MockHapticService
  - [ ] 9.7 Test: `saveExpense()` with zero amount does NOT trigger `.saveTap` (guard exits before haptic)
  - [ ] 9.8 Test: `saveExpense()` with nil `selectedCategoryID` does NOT trigger `.saveTap`
  - [ ] 9.9 Test: `appendDigit` at max overflow still triggers `.numpadKey` haptic (guard rejects value but haptic fires)

## Dev Notes

### HapticService Architecture

```swift
import UIKit

enum HapticEvent {
    case numpadKey      // UIImpactFeedbackGenerator(.light)
    case categorySelect // UIImpactFeedbackGenerator(.light)
    case saveTap        // UINotificationFeedbackGenerator(.success)
    case deleteTap      // UINotificationFeedbackGenerator(.success)
    case error          // UINotificationFeedbackGenerator(.error)
}

protocol HapticServiceProtocol {
    func trigger(_ event: HapticEvent)
}

final class HapticService: HapticServiceProtocol {
    func trigger(_ event: HapticEvent) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        switch event {
        case .numpadKey, .categorySelect:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .saveTap, .deleteTap:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
```

[Source: architecture.md — "Haptic Feedback Events", lines 493-510]

**Key decisions:**
- `HapticService` is NOT `@Observable` — it has no observable state. It's a stateless service.
- NOT `@MainActor` �� UIKit feedback generators are thread-safe and can fire from any thread.
- NOT a singleton — each ViewModel creates its own instance via default parameter.
- The view-associated initializer `UIImpactFeedbackGenerator(style:view:)` (iOS 17+) requires a UIView reference. Since `HapticService` is injected into ViewModels (no UIView access), use the standard `UIImpactFeedbackGenerator(style:)` initializer. This is acceptable — the view-associated version only improves Taptic Engine routing on multi-engine devices (iPhone 16+).
- Import `UIKit`, not `SwiftUI` — the service has no SwiftUI dependency.

### Haptic Trigger Placement in ViewModel

Haptics fire in the **ViewModel** (not the View) per architecture rule: "Never call UIFeedbackGenerator subclasses directly from Views."

**Critical nuance — haptic fires on KEY PRESS, not on data mutation:**
- `appendDigit()` → haptic fires as FIRST LINE, before the `guard amountInCents < maxBeforeAppend` check. If the guard rejects the input (amount too large), the key still gives tactile feedback. User pressed a key → they feel it.
- `appendDecimalPoint()` → haptic fires even though the method is a no-op. The decimal key IS a numpad key. User pressed it → they feel it.
- `deleteLastDigit()` → haptic fires even when amount is already 0.
- `selectCategory()` → haptic fires before setting the ID.

**Save haptic is different — it fires on SUCCESS only:**
- `saveExpense()` → haptic fires AFTER successful repository save and `guard !Task.isCancelled` check, but BEFORE `resetAmount()` and `noteText = ""` state cleanup. Exact position: between line 130 (`guard !Task.isCancelled`) and line 132 (`userDefaults.set(...)`) of the current `ExpenseEntryViewModel.swift`. If any guard fails (zero amount, nil category, not authenticated, task cancelled), no haptic. The save haptic confirms "your expense was recorded."

### ViewModel Init Change (Backward Compatibility)

```swift
init(
    expenseRepository: ExpenseRepositoryProtocol = ExpenseRepository(),
    categoryRepository: CategoryRepositoryProtocol = CategoryRepository(),
    authService: AuthenticationServiceProtocol = AuthenticationService(),
    userDefaults: UserDefaults = .standard,
    hapticService: HapticServiceProtocol = HapticService()  // NEW — append at end
) {
    self.expenseRepository = expenseRepository
    self.categoryRepository = categoryRepository
    self.authService = authService
    self.userDefaults = userDefaults
    self.hapticService = hapticService
}
```

- New parameter added at END of parameter list with default value — all 59 existing tests calling `ExpenseEntryViewModel()` or partial inits continue to work unchanged.
- `@ObservationIgnored` on the property — haptic service is not observable state.
- Tests inject `MockHapticService` to verify haptic events without UIKit side effects.

### Accessibility Labels — Entry Screen Components

**NumpadView** — labels go on the `Button`, not the inner label:
```swift
Button {
    handleTap(key)
} label: {
    keyLabel(key)
        .frame(maxWidth: .infinity)
        .frame(height: keyHeight)
}
.buttonStyle(.glass)
.accessibilityLabel(accessibilityLabel(for: key))
```

Helper (explicit `-> Text` return type required — do NOT use `@ViewBuilder`):
```swift
private func accessibilityLabel(for key: NumpadKey) -> Text {
    switch key {
    case .digit(let value): Text(value)
    case .decimal: Text("Decimal point")
    case .backspace: Text("Delete")
    }
}
```

**Modifier order on Button (accessibility AFTER button style):**
```swift
Button { handleTap(key) } label: { ... }
    .buttonStyle(.glass)              // 1. visual style first
    .accessibilityLabel(accessibilityLabel(for: key))  // 2. accessibility after
```

**AmountDisplayView:**
```swift
Text(amount.displayAmount)
    .font(.system(size: 48, weight: .medium, design: .rounded))
    .accessibilityLabel("Amount: \(amount.displayAmount)")
    .accessibilityAddTraits(.updatesFrequently)
```

Note: Uses `amount.displayAmount` which produces THB-formatted string (e.g., "฿12.50"). The epics file says "dollars" — this is a documentation error; the app uses Thai Baht per CLAUDE.md.

**CategoryPickerView** — on each chip button:
```swift
Button { onSelect(category.id) } label: { ... }
    .buttonStyle(.plain)
    .accessibilityLabel("\(category.name), \(isSelected ? "selected" : "not selected")")
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
```

**SaveButtonView:**
- Save button: `.accessibilityLabel("Save expense")`
- Note button: `.accessibilityLabel("Add note")`
- `.disabled(isDisabled)` already communicates disabled state to VoiceOver — no extra work.

### Dynamic Type — Already Mostly Supported

| Component | Font | Scales? | Notes |
|-----------|------|---------|-------|
| NumpadView digits | `.title` | Yes | SwiftUI text style, auto-scales |
| NumpadView backspace | `.title2` | Yes | SwiftUI text style, auto-scales |
| NumpadView key height | GeometryReader | Yes | Already proportional — `max(60, available / 4)` |
| AmountDisplayView | `.system(size: 48, ...)` | No (intentional) | Fixed 48pt + `.minimumScaleFactor(0.7)` per UX spec |
| CategoryPickerView | `.subheadline` | Yes | Auto-scales |
| SaveButton | `.headline` | Yes | Auto-scales |
| NoteEntrySheet | TextField default | Yes | System default scales |

**No changes needed** for Dynamic Type — the existing implementation already handles it correctly. The key insight: `AmountDisplayView` intentionally uses a fixed font size (not a text style), which is per UX spec line 928. It does NOT scale with Dynamic Type but uses `.minimumScaleFactor(0.7)` to prevent truncation. This is the correct behavior.

Task 8 is a verification task, not a code change task. Add a preview variant for visual QA.

### Existing Code to Reuse (DO NOT Recreate)

| What | File | Usage |
|------|------|-------|
| `ExpenseEntryViewModel` | `ViewModels/ExpenseEntryViewModel.swift` | Modify — add hapticService dependency and trigger calls |
| `NumpadView` | `Views/Entry/NumpadView.swift` | Modify — add accessibility labels |
| `AmountDisplayView` | `Views/Entry/AmountDisplayView.swift` | Modify — add accessibility label |
| `CategoryPickerView` | `Views/Entry/CategoryPickerView.swift` | Modify — add accessibility labels |
| `SaveButtonView` | `Views/Entry/SaveButtonView.swift` | Modify — add accessibility labels |
| `EntryView` | `Views/Entry/EntryView.swift` | No changes expected |
| `NoteEntrySheet` | `Views/Entry/NoteEntrySheet.swift` | Verify — TextField has reasonable default VoiceOver |
| `MockAuthenticationService` | `CashOutTests/Services/MockAuthenticationService.swift` | Reuse for save-haptic tests |
| `MockExpenseRepository` | `CashOutTests/Repositories/MockExpenseRepository.swift` | Reuse for save-haptic tests |
| `MockCategoryRepository` | `CashOutTests/Repositories/MockCategoryRepository.swift` | Reuse for save-haptic tests |
| `Spacing` enum | `Utilities/Constants.swift` | Reference only |
| `Int64.displayAmount` | `Utilities/Extensions/Int64+Currency.swift` | Used in accessibility label |

### File Placement

| File | Location | Action |
|------|----------|--------|
| `HapticService.swift` | `CashOut/Services/` | New file |
| `MockHapticService.swift` | `CashOutTests/Services/` | New file |
| `ExpenseEntryViewModel.swift` | `CashOut/ViewModels/` | Modify existing |
| `NumpadView.swift` | `CashOut/Views/Entry/` | Modify existing |
| `AmountDisplayView.swift` | `CashOut/Views/Entry/` | Modify existing |
| `CategoryPickerView.swift` | `CashOut/Views/Entry/` | Modify existing |
| `SaveButtonView.swift` | `CashOut/Views/Entry/` | Modify existing |
| `ExpenseEntryViewModelTests.swift` | `CashOutTests/ViewModels/` | Modify existing (add haptic tests) |

All new files must be registered in `project.pbxproj`.

### Testing Standards

- All test classes: `@MainActor` at class level (established pattern from Story 1.5 review)
- XCTest framework
- Haptic tests are synchronous for `appendDigit`, `deleteLastDigit`, `appendDecimalPoint`, `selectCategory`
- `saveExpense()` haptic test is `async` (repository call is async)
- Inject `MockHapticService` alongside existing mocks — save-haptic tests need all 5 mocks (expenseRepo, categoryRepo, authService, userDefaults, hapticService)
- Existing 59 tests must continue to pass — new `hapticService` parameter has default value
- `MockHapticService` records events in an array — assert on `triggeredEvents.count` and `triggeredEvents.last`
- No need to test `UIAccessibility.isReduceMotionEnabled` in unit tests — that's a system API read in the real `HapticService`, not testable without UI testing. The protocol boundary is the test seam.

### Boundaries — What NOT to Implement

- **No feed row haptics** — Story 2.x (edit haptic, delete haptic)
- **No error haptic usage** — `HapticEvent.error` is defined but not used in this story. Available for validation error feedback in future stories.
- **No VoiceOver for feed rows** — Story 2.1
- **No chart accessibility** — Story 3.x
- **No settings accessibility** — Story 5.x
- **No Reduce Motion impact on animations** — this story is haptics only; animation reduction is a separate concern
- **No Dynamic Type testing infrastructure** — visual verification via Xcode Previews only

### Previous Story Intelligence

**From Story 1.6 (Category Picker, Save Flow & Expense Persistence):**
- ExpenseEntryViewModel has 4 injected dependencies already — hapticService will be 5th
- `appendDigit()` has a `guard amountInCents < maxBeforeAppend` — haptic must fire BEFORE this guard
- `saveExpense()` uses `defer { isSaving = false }` — haptic trigger should be after the save, before the defer executes (i.e., before `resetAmount()` + `noteText = ""` cleanup, or after — doesn't matter, both are in the success path after the repository call)
- CategoryPickerView uses `.buttonStyle(.plain)` — confirmed no `.glass` to conflict with
- SaveButtonView note icon has 44pt tap target and `.buttonStyle(.plain)` — add accessibility label without changing style
- `$viewModel.noteText` binding pattern works with `@State` on `@Observable`

**From Story 1.5 (Numpad & Amount Display):**
- NumpadView uses `GeometryReader` for proportional key heights — Dynamic Type already handled
- `NumpadKey` enum is `private` — accessibility helper function goes inside `NumpadView`
- `.buttonStyle(.glass)` is on the `Button` — accessibility label also goes on `Button`
- Review F1: VStack interposed between GeometryReader and LazyVGrid — no impact on accessibility

**Code Review Patterns to Follow:**
- F5 (Story 1.4): All test classes must be `@MainActor`
- Story 1.6 review: `.buttonStyle(.plain)` on interactive elements that shouldn't get glass styling
- Story 1.6 review: 44pt minimum tap targets on all interactive elements

### Git Intelligence

Recent commit pattern: `feat(entry): ...`, `fix(entry): ...`, `docs(entry): ...`
This story's commits should follow: `feat(entry): implement haptics, accessibility and dynamic type (story 1-7)`

### Project Structure Notes

- `CashOut/Services/` currently has: `AuthenticationService.swift`, `PersistenceController.swift` — `HapticService.swift` joins as 3rd service
- `CashOutTests/Services/` currently has: `MockAuthenticationService.swift` — `MockHapticService.swift` joins alongside
- No protocol file separation for HapticService — protocol and implementation in same file (matches `AuthenticationService.swift` which has `AuthenticationServiceProtocol` in same file)

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Story 1.7 acceptance criteria, lines 416-447]
- [Source: _bmad-output/planning-artifacts/architecture.md — HapticEvent enum and HapticServiceProtocol, lines 493-510]
- [Source: _bmad-output/planning-artifacts/architecture.md — DI pattern with HapticService, lines 542-577]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — Haptic feedback patterns, lines 832-845]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — VoiceOver strategy, lines 940-947]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — Dynamic Type strategy, lines 949-954]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — NumpadView haptic/accessibility spec, lines 754-756]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — CategoryPickerView accessibility, line 771]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — Reduce Motion, line 518]
- [Source: _bmad-output/implementation-artifacts/1-6-category-picker-save-flow-and-expense-persistence.md — Previous story learnings and patterns]
- [Source: CashOut/ViewModels/ExpenseEntryViewModel.swift — Current ViewModel to modify]
- [Source: CashOut/Views/Entry/NumpadView.swift — Current view to modify]
- [Source: CashOut/Views/Entry/AmountDisplayView.swift — Current view to modify]
- [Source: CashOut/Views/Entry/CategoryPickerView.swift — Current view to modify]
- [Source: CashOut/Views/Entry/SaveButtonView.swift — Current view to modify]

### Orchestrator Validation (2026-03-29)

**Guardians run**: ios-swiftui-guardian, architecture-guardian (cloudkit-sync-guardian skipped — no CloudKit in scope)

**CRITICALs**: None

**WARNINGs resolved in story spec:**
1. Save haptic placement clarified: after `guard !Task.isCancelled`, before `resetAmount()` — Task 3.7 updated
2. `.deleteTap` enum case annotated as reserved for Story 2.4 — Task 1.2 updated
3. Accessibility label modifier order: must go AFTER `.buttonStyle(.glass)` — Task 4.4 updated
4. `accessibilityLabel(for:)` helper must return `-> Text` explicitly — Task 4.5 added

**WARNINGs noted (documentation, not code):**
- architecture.md line 507 recommends view-associated `UIImpactFeedbackGenerator(style:view:)` — not feasible in service-layer DI pattern. Story uses legacy initializer with documented rationale. Add learning after implementation.
- `.accessibilityAddTraits(isSelected ? [.isSelected] : [])` — additive-only in SwiftUI, but safe here because ForEach recreates views (not toggling in-place)
- "฿" symbol VoiceOver pronunciation — iOS reads as "Thai baht" in en-US locale. Verify on physical device.

**SUGGESTIONs noted:**
- Note button `.accessibilityHint("Opens a note entry sheet")` — nice-to-have
- Update `makeSUT` in tests to return MockHapticService as 5th tuple member

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
