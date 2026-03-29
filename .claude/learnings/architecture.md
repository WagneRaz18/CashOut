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

## Data Layer
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

## Project Generation
- xcodegen (project.yml) can fully replace manual Xcode project creation including Core Data + CloudKit setup. Generates valid .xcodeproj with proper build phases for .xcdatamodeld files.
- .xcdatamodeld is a directory with XML contents that can be created programmatically — no Xcode GUI required.

## State Modeling
- Use independent data + errorMessage properties, never a combined enum ViewState.
- On error, preserve stale data and set errorMessage — view shows both simultaneously.
- **2026-03-29**: Fixed-point satang cap: `guard amountInCents < 1_000_000` before `amount * 10 + digit` enforces a ceiling of 9_999_999 (฿99,999.99) — the guard fires before multiply, so max(999_999) * 10 + 9 = 9_999_999. Extract guard threshold as a named constant (`maxBeforeAppend`) to make the math self-documenting.

## Navigation Coordination
- For simple apps (3 tabs + sheets): TabView selection is @State in ContentView, sheet presentation is @State on presenting View. Full Coordinator pattern is unnecessary.
- Each tab owns its own NavigationStack. Never wrap TabView inside NavigationStack.
