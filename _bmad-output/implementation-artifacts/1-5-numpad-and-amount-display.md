# Story 1.5: Numpad & Amount Display

Status: ready-for-dev (readiness check passed 2026-03-29)

## Story

As a user,
I want a numpad and amount display on the entry screen,
So that I can type cash amounts quickly with a calculator-style interface.

## Acceptance Criteria

1. **Given** the entry screen (Add tab) **When** displayed **Then** NumpadView shows a 3x4 grid of digit keys (1-9, ".", 0, backspace) with `.buttonStyle(.glass)` and 60pt+ key height with 8pt gaps (UX-DR1 — corrected from original `.glassEffect()` wording per architecture Liquid Glass rules)

2. **Given** the entry screen **When** displayed **Then** AmountDisplayView shows "$0.00" in SF Pro Rounded 48pt medium weight, centered horizontally, in `.secondary` color (UX-DR2 — `.monospacedDigit()` is reserved for feed rows per UX spec, not entry display)

3. **Given** a numpad key tap **When** a digit is pressed **Then** the amount display updates immediately in primary color (UX-DR2)

4. **Given** amount entry **When** digits are typed **Then** amounts are stored as Int64 cents (e.g., typing "1250" displays "$12.50")

5. **Given** the backspace key **When** tapped **Then** the last digit is removed from the amount

## Tasks / Subtasks

- [ ] Task 1: Create ExpenseEntryViewModel (AC: #3, #4, #5)
  - [ ] 1.1 Create `ViewModels/ExpenseEntryViewModel.swift` — `@MainActor @Observable final class`
  - [ ] 1.2 Implement `amountInCents: Int64` property (default 0)
  - [ ] 1.3 Implement `appendDigit(_ digit: String)` — appends digit to raw cents integer; guard `amountInCents < 1_000_000` before append to enforce cap of 9_999_999 ($99,999.99); use `guard let value = Int64(digit) else { return }` (no force-unwrap)
  - [ ] 1.4 Implement `deleteLastDigit()` — removes rightmost digit via integer division by 10
  - [ ] 1.5 Implement `appendDecimalPoint()` — no-op (decimal is implicit in fixed-point; included for grid completeness)
  - [ ] 1.6 Implement computed `isAmountZero: Bool`
  - [ ] 1.7 Implement `resetAmount()`

- [ ] Task 2: Create AmountDisplayView (AC: #2, #3)
  - [ ] 2.1 Create `Views/Entry/AmountDisplayView.swift`
  - [ ] 2.2 Accept `amount: Int64` as parameter (read-only display)
  - [ ] 2.3 Display via `Int64.displayAmount` extension (already exists)
  - [ ] 2.4 Apply SF Pro Rounded 48pt medium weight: `.font(.system(size: 48, weight: .medium, design: .rounded))` — do NOT add `.monospacedDigit()` (UX spec reserves that for feed rows, not entry display; rounded + monospaced may conflict)
  - [ ] 2.5 Center horizontally, color: `.secondary` when amount == 0, `.primary` when amount > 0
  - [ ] 2.6 Apply `.minimumScaleFactor(0.7)` for small screens (UX-DR17 preparation)

- [ ] Task 3: Create NumpadView (AC: #1, #3, #4, #5)
  - [ ] 3.1 Create `Views/Entry/NumpadView.swift`
  - [ ] 3.2 Accept action closures: `onDigit: (String) -> Void`, `onDecimal: () -> Void`, `onBackspace: () -> Void`
  - [ ] 3.3 Build 3x4 grid layout: rows [1,2,3], [4,5,6], [7,8,9], [".",0,backspace]
  - [ ] 3.4 Use `LazyVGrid` with 3 flexible columns and `Spacing.sm` (8pt) gaps
  - [ ] 3.5 Each key: `Button` with `.buttonStyle(.glass)` — NOT `.glassEffect()` (Liquid Glass rule)
  - [ ] 3.6 Key height: wrap NumpadView body in `GeometryReader`, calculate `max(60, (geo.size.height - Spacing.sm * 3) / 4)` — three gaps between four rows; do NOT wrap LazyVGrid directly in GeometryReader (circular layout)
  - [ ] 3.7 Backspace key: SF Symbol `"delete.backward"`, same styling as digit keys
  - [ ] 3.8 Decimal key: displays "." — calls `onDecimal` (no-op in ViewModel, grid visual completeness)

- [ ] Task 4: Wire EntryView composition (AC: #1, #2)
  - [ ] 4.1 Replace `Color.clear` in `Views/Entry/EntryView.swift`
  - [ ] 4.2 Add `@State private var viewModel = ExpenseEntryViewModel()`
  - [ ] 4.3 Compose vertical layout: AmountDisplayView (top) → spacer → NumpadView (bottom)
  - [ ] 4.4 No NavigationStack (EntryView is a flat screen, no push navigation)
  - [ ] 4.5 Leave space between AmountDisplay and NumpadView for CategoryPickerView (Story 1.6)

- [ ] Task 5: Unit tests for ExpenseEntryViewModel (AC: #3, #4, #5)
  - [ ] 5.1 Create `CashOutTests/ViewModels/ExpenseEntryViewModelTests.swift`
  - [ ] 5.2 Test: appendDigit "1" then "2" then "5" then "0" → amountInCents == 1250 (displays "$12.50")
  - [ ] 5.3 Test: deleteLastDigit from 1250 → amountInCents == 125 (displays "$1.25")
  - [ ] 5.4 Test: deleteLastDigit from 0 → stays 0 (no crash)
  - [ ] 5.5 Test: appendDigit when amountInCents >= 1_000_000 → no change (cap at 9_999_999 / $99,999.99)
  - [ ] 5.6 Test: resetAmount → amountInCents == 0
  - [ ] 5.7 Test: isAmountZero returns true when 0, false when > 0
  - [ ] 5.8 Test: appendDecimalPoint is no-op (amountInCents unchanged)

## Dev Notes

### Amount-as-Cents Architecture

The numpad uses **fixed-point integer arithmetic** — NOT floating-point. The Int64 `amountInCents` represents the full value in cents. Typing digits appends to this integer:

- Type "1" → `amountInCents = 1` → displays "$0.01"
- Type "2" → `amountInCents = 12` → displays "$0.12"
- Type "5" → `amountInCents = 125` → displays "$1.25"
- Type "0" → `amountInCents = 1250` → displays "$12.50"

The decimal point button is a **visual no-op** — it exists for grid layout completeness and user expectation, but the cents-based model handles decimal positioning implicitly. This matches the architecture mandate: "No floating-point for money."

Digit append: `guard amountInCents < 1_000_000 else { return }` then `guard let value = Int64(digit) else { return }` then `amountInCents = amountInCents * 10 + value`
Digit delete: `amountInCents = amountInCents / 10`
Cap: 9_999_999 cents ($99,999.99) — guard checks *before* multiplication to prevent any single digit pushing past the cap

### Liquid Glass API Rules (Critical)

- Numpad keys: `.buttonStyle(.glass)` — they are `Button` elements
- **NEVER** combine `.buttonStyle(.glass)` with `.glassEffect()` on the same element
- Save button (Story 1.6): `.buttonStyle(.glassProminent)` — primary action
- Non-button views: `.glassEffect()` modifier directly
- [Source: architecture.md, lines 788-794]

### Existing Code to Reuse (DO NOT Recreate)

| What | File | Usage |
|------|------|-------|
| `Int64.displayAmount` | `Utilities/Extensions/Int64+Currency.swift` | Format cents to "$X.XX" — call `amountInCents.displayAmount` |
| `Spacing` enum | `Utilities/Constants.swift` | `Spacing.sm` (8pt) for numpad gaps, `Spacing.md` (16pt) for padding |
| `CategoryColor` | `Utilities/Extensions/Color+CategoryTokens.swift` | Not needed this story — Story 1.6 |
| `ExpenseRepositoryProtocol` | `Repositories/ExpenseRepositoryProtocol.swift` | Not needed this story — Story 1.6 |

### ViewModel Pattern (Must Follow)

```swift
@MainActor
@Observable
final class ExpenseEntryViewModel {
    var amountInCents: Int64 = 0

    // DO NOT import SwiftUI in this file
    // DO NOT use @ObservableObject or @Published
    // DO NOT use Combine
    // Mark all injected dependencies @ObservationIgnored (none needed yet for this story)
}
```

[Source: architecture.md — "@Observable (not @ObservableObject) for all ViewModels"]

### View Composition Pattern

```
EntryView (container)
├── AmountDisplayView(amount: viewModel.amountInCents)  // top ~25%
├── Spacer  // reserved for CategoryPickerView (Story 1.6)
├── NumpadView(                                          // bottom ~50%
│     onDigit: { viewModel.appendDigit($0) },
│     onDecimal: { viewModel.appendDecimalPoint() },
│     onBackspace: { viewModel.deleteLastDigit() }
│   )
└── [Save button area — Story 1.6]
```

EntryView does NOT use NavigationStack — it's a flat screen within the TabView.
[Source: architecture.md — "each tab owns its own NavigationStack" / ContentView.swift shows EntryView is NOT wrapped in NavigationStack]

### NumpadView Grid Layout

```
[ 1 ] [ 2 ] [ 3 ]
[ 4 ] [ 5 ] [ 6 ]
[ 7 ] [ 8 ] [ 9 ]
[ . ] [ 0 ] [ ← ]
```

- Use `LazyVGrid` with 3 `GridItem(.flexible())` columns
- Key height: `GeometryReader` wraps NumpadView body → `max(60, (geo.size.height - Spacing.sm * 3) / 4)` (three gaps, four rows)
- Do NOT wrap LazyVGrid in GeometryReader directly — causes circular layout. GeometryReader is the outermost container; key height is passed into `.frame(height: keyHeight)` per button
- Full-width grid with `Spacing.sm` (8pt) horizontal and vertical spacing
- Backspace icon: SF Symbol `"delete.backward"`

### Screen Size Adaptation

- NumpadView: `GeometryReader` wraps body → `max(60, (geo.size.height - Spacing.sm * 3) / 4)` → key height (60pt standard, 52pt SE, 68pt Max)
- AmountDisplayView: Fixed 48pt font + `.minimumScaleFactor(0.7)` for SE + `.lineLimit(1)`
- [Source: ux-design-specification.md — screen adaptation table]

### HapticService (Deferred to Story 1.7)

`HapticServiceProtocol` and `HapticService.swift` do not exist yet in the codebase. Story 1.7 creates the entire haptic system and will add the `hapticService` init parameter to `ExpenseEntryViewModel` at that time. Do NOT create haptic files or inject haptic dependencies in this story.

### File Placement

| File | Location |
|------|----------|
| `ExpenseEntryViewModel.swift` | `CashOut/ViewModels/` |
| `AmountDisplayView.swift` | `CashOut/Views/Entry/` |
| `NumpadView.swift` | `CashOut/Views/Entry/` |
| `EntryView.swift` | `CashOut/Views/Entry/` (modify existing) |
| `ExpenseEntryViewModelTests.swift` | `CashOutTests/ViewModels/` |

All new files must be registered in `project.pbxproj`.

### Testing Standards

- All test methods: `@MainActor` (established pattern from Stories 1.2, 1.4)
- XCTest framework, synchronous tests (no async needed — ViewModel logic is synchronous)
- No mock dependencies needed for this story (no repository or service calls)
- Test file naming: `ExpenseEntryViewModelTests.swift` in `CashOutTests/ViewModels/`
- [Source: architecture.md — "Write unit tests for every ViewModel and Repository method"]

### Boundaries — What NOT to Implement

- **No category picker** — Story 1.6
- **No save button** — Story 1.6
- **No haptic feedback** — Story 1.7 (HapticService integration)
- **No VoiceOver labels** — Story 1.7
- **No Dynamic Type key scaling** — Story 1.7 (GeometryReader key scaling IS in scope for basic layout; Dynamic Type text scaling is Story 1.7)
- **No note field** — Story 1.6

### Previous Story Intelligence

**From Story 1.4 (Design Tokens, Categories, Repository Layer):**
- Core Data entity creation: use `Entity(context: viewContext)` — never parameterless `Entity()`
- Color asset lookup: `Color("Sage")` — rawValue must match colorset name exactly (case-sensitive)
- `Int64.displayAmount` uses Foundation `.formatted(.currency(code: "USD"))` with en_US locale
- All repository methods are `async throws` with `@MainActor`
- DI via init parameter: `init(persistence: PersistenceController = .shared)` — no DI container
- Test infrastructure: `TestPersistenceHelper.makeInMemoryContainer()` available (not needed for this story's pure logic tests)

**Review Findings Applied in 1.4:**
- F1: Always throw `RepositoryError.missingRequiredField` on nil — never use fallback UUID()
- F2: Use `async let` for parallel execution in `.task {}`
- F5: Always add `@MainActor` to test methods

### Git Intelligence

Recent commits show established patterns:
- Feature commits: `feat(scope): description (story X-Y)`
- Fix commits: `fix(scope): description`
- Story 1.4 had 2 commits (feat + fix from code review)
- All 36 existing tests pass — zero regressions expected

### Project Structure Notes

- Alignment: Files placed exactly per architecture directory structure
- EntryView.swift already exists as placeholder — modify in place, do not recreate
- `CashOutTests/ViewModels/` directory already exists (contains `AuthenticationViewModelTests.swift`)

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Story 1.5 acceptance criteria]
- [Source: _bmad-output/planning-artifacts/architecture.md — MVVM patterns, Liquid Glass rules, testing standards]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — Entry screen layout, NumpadView spec, AmountDisplayView spec]
- [Source: _bmad-output/implementation-artifacts/1-4-design-tokens-predefined-categories-and-repository-layer.md — Previous story learnings]
- [Source: CashOut/Utilities/Extensions/Int64+Currency.swift — Existing displayAmount extension]
- [Source: CashOut/Utilities/Constants.swift — Spacing enum]
- [Source: CashOut/Views/Entry/EntryView.swift — Existing placeholder to replace]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
