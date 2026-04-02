# Architecture, Patterns, State

<!-- One line per learning, brief and actionable -->

## MVVM with @Observable
- ALL injected service and repository references in @Observable ViewModels must be @ObservationIgnored — not just repositories, also HapticService, AuthenticationService, etc.
- ViewModels must never import SwiftUI — they live in the ViewModel layer with no UI dependency.
- Repository protocols must return plain structs (DTOs like ExpenseData), never NSManagedObject — they are not Sendable and leak Core Data types across boundaries.

## Async & Task Lifecycle
- Long-running async ViewModel methods must check Task.checkCancellation() at natural boundaries.
- Remote change notification subscriptions must use NotificationCenter.notifications(named:) async sequence inside .task {} — never addObserver in init().
- .task handlers in TabView-hosted views re-fire on every tab appear — guard with loaded-state check.
- **2026-03-28**: When a service handles async events (notifications) that must propagate to the ViewModel, add an `onSessionInvalidated`-style callback closure to the protocol — @Observable tracking doesn't flow through @ObservationIgnored protocol references, so the ViewModel has no other way to learn about service-side state changes.
- **2026-03-28**: `CheckedContinuation` must never be overwritten — storing a new continuation before the previous is resumed crashes in debug. Guard with `signInContinuation != nil` before starting a new async bridge.
- **2026-03-29**: Apply `@MainActor` at the XCTestCase class level, not per-method, when testing `@MainActor`-isolated ViewModels — prevents actor-boundary issues in future `setUp()`/`tearDown()` overrides.
- **2026-03-29**: After `try await repository.save()`, add `guard !Task.isCancelled else { return }` before post-save state mutations (UI reset, UserDefaults write) — the view that spawned the Task may be gone (tab switch/dismiss), making the mutations pointless or dangerously late.
- **2026-03-29**: Boolean flag guards (`isSaving`) must be checked BEFORE the flag is set: `guard !isSaving else { return }; isSaving = true; defer { isSaving = false }`. Without the upfront guard, a second @MainActor Task can start between suspension points and bypass the flag — `isSaving = true` + `defer` alone is a lifecycle signal, not a concurrency lock.

## Data Layer
- **2026-04-02**: `NSFetchedResultsController` must live in the Repository layer, not the ViewModel — FRC converts `NSManagedObject` to DTO structs via callback, preserving MVVM boundaries. Use nested `@MainActor private class FRCDelegate: NSObject` with `[weak self]` closure to avoid retain cycles and satisfy Swift 6 actor isolation.
- **2026-04-02**: Protocol callback closures that update `@MainActor`-isolated ViewModel state must be typed `@MainActor` on the protocol (e.g., `var onExpensesChanged: (@MainActor ([ExpenseData]) -> Void)?`) — a plain closure type compiles but silently allows cross-actor mutation in Swift 6.
- **2026-04-02**: Fire-and-forget `Task {}` inside callback-driven methods (e.g., category reload on FRC change) must store the task handle and cancel-before-relaunch — otherwise rapid FRC callbacks cause racing Tasks that mutate state after cancellation. Pattern: `categoryTask?.cancel(); categoryTask = Task { ... guard !Task.isCancelled ... }`.
- All Repository methods must be @MainActor-isolated when using viewContext (main-thread-only context).
- For insights aggregation: single NSFetchRequest with date-range predicate + in-memory grouping by categoryID in Swift. No NSExpression aggregate queries.
- Use versioned .xcdatamodeld with lightweight (inferred) migration as default strategy.
- **2026-03-28**: Repository `save` methods must always use fetch-or-create (upsert) pattern — fetch by `id` first, update existing or create new. Never unconditionally `init(context:)` — causes duplicates on retry or re-sync.
- **2026-03-28**: Bootstrap-only methods like `seedDefaultCategoriesIfNeeded()` belong on the concrete repository class, NOT on the protocol — they are app-startup concerns, not part of the repository contract for consumers.
- **2026-03-28**: When mapping optional Core Data attributes to non-optional DTO fields, throw `RepositoryError.missingRequiredField` — never use `?? UUID()` (generates different value each fetch) or nil UUID sentinel (silently produces lookup misses). The DTO should represent a valid domain object; if it exists, it is complete.
- **2026-03-28**: Date range predicates in `fetchExpenses(for:)` must use exclusive upper bound (`createdAt < end`) not inclusive (`<= end`). Inclusive upper bound double-counts expenses at period boundaries when using contiguous intervals.

## Dependency Injection
- Repositories should be transient instances (not singletons) — only PersistenceController is a singleton.
- Use init(repository: Protocol = ConcreteType()) — transient, not .shared.
- Every service consumed by ViewModels must have a protocol (including HapticServiceProtocol) with a Mock in test targets.
- App-wide services (PersistenceController) injected at @main App via .environment(\.managedObjectContext). Add EnvironmentKey for PersistenceController itself when repositories need both viewContext and newBackgroundContext().
- **2026-03-29**: Inject `UserDefaults` via init parameter (`userDefaults: UserDefaults = .standard`) for test isolation ��� tests use `UserDefaults(suiteName:)` with `removePersistentDomain(forName:)` in tearDown to avoid cross-test pollution of MRU/preference state.

## Services
- **2026-04-02**: `HapticService` uses the standard `UIImpactFeedbackGenerator(style:)` initializer, not the view-associated `(style:view:)` variant (iOS 17+). The service is injected into ViewModels which have no `UIView` reference — acceptable trade-off. View-associated variant only improves Taptic Engine routing on multi-engine devices (iPhone 16+). If a UIView reference becomes available in the future, upgrade then.

## Project Generation
- xcodegen (project.yml) can fully replace manual Xcode project creation including Core Data + CloudKit setup. Generates valid .xcodeproj with proper build phases for .xcdatamodeld files.
- .xcdatamodeld is a directory with XML contents that can be created programmatically — no Xcode GUI required.

- **2026-03-29**: Button `isDisabled` must mirror ALL silent-return guards in the ViewModel action — if `saveExpense()` returns silently on `selectedCategoryID == nil` (e.g., categories failed to load), the Save button must include `selectedCategoryID == nil` in its disabled condition. Otherwise the user sees an enabled button that does nothing on tap.

## State Modeling
- Use independent data + errorMessage properties, never a combined enum ViewState.
- On error, preserve stale data and set errorMessage — view shows both simultaneously.
- **2026-03-29**: Fixed-point satang cap: `guard amountInCents < 1_000_000` before `amount * 10 + digit` enforces a ceiling of 9_999_999 (฿99,999.99) — the guard fires before multiply, so max(999_999) * 10 + 9 = 9_999_999. Extract guard threshold as a named constant (`maxBeforeAppend`) to make the math self-documenting.
- **2026-03-29**: Currency display formatting must use `Decimal(self) / 100` not `Double(self) / 100.0` — enforces "no floating-point for money" even in display-only contexts. `Decimal.FormatStyle.Currency` works identically to `FloatingPointFormatStyle.Currency`.
- **2026-03-29**: In `@Observable` classes, declare constants as `private static let` not `private let` — instance `let` occupies heap per instance unnecessarily. Access via `Self.constant`.

## Navigation Coordination
- For simple apps (3 tabs + sheets): TabView selection is @State in ContentView, sheet presentation is @State on presenting View. Full Coordinator pattern is unnecessary.
- Each tab owns its own NavigationStack. Never wrap TabView inside NavigationStack.
