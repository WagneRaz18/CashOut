# Architecture, Patterns, State

<!-- One line per learning, brief and actionable -->

## MVVM with @Observable
- Injected `var` service/repository references in @Observable ViewModels must be `@ObservationIgnored`. `let` constants do NOT need it — they are never tracked by `@Observable`.
- **2026-04-04**: `fetchShares(in:)` returns `[CKShare]` (array), not a dictionary. Use `if let share = shares.first` not `.values.first!`.
- **2026-04-04**: Store classification in `loadPersistentStores` should use URL matching, not `databaseScope` — when iCloud is unavailable, `cloudKitContainerOptions` is nil and databaseScope check fails.
- ViewModels must never import SwiftUI — they live in the ViewModel layer with no UI dependency.
- Repository protocols must return plain structs (DTOs like ExpenseData), never NSManagedObject — they are not Sendable and leak Core Data types across boundaries.
- **Exception:** `SettingsViewModel` accesses `viewContext` directly for `container.share(objects, to:)` which requires `[NSManagedObject]`. Accepted MVVM exception for CloudKit sharing (Story 4-1 decision D2, 2026-04-04).
- **2026-04-04**: Boolean flag guards (`isInviting`, `isSaving`) must use `defer` for reset: `guard !isInviting else { return }; isInviting = true; defer { isInviting = false }`. Manual resets on each path are fragile.
- **2026-04-04**: `.sheet(isPresented:onDismiss:)` — always provide `onDismiss` when bridging UIKit controllers. UIKit delegate methods may not fire on interactive dismiss (swipe-down), leaving stale state.
- **2026-04-03**: `@ObservationIgnored` is only for `var` stored properties — `let` constants are never tracked by `@Observable`, so annotating them is redundant and semantically misleading. Only annotate `var` dependencies.
- **2026-04-06**: Child views receiving an `@Observable` ViewModel should use `@Bindable var` (not plain `var`/`let`) when they read reactive state AND mutate ViewModel properties (e.g., clearing `categorySaveError` on appear). `@Bindable` enables both observation tracking and direct property assignment.

- **2026-04-06**: Use `.whitespacesAndNewlines` not `.whitespaces` in `trimmingCharacters(in:)` for user text input validation — `.whitespaces` only covers spaces and tabs, so a paste containing only newlines passes the `.isEmpty` check and creates a visually blank record.
- **2026-04-06**: ViewModel upsert methods accepting `existingID: UUID?` must guard against unintended entity-type demotion — `saveCategory` hardcoded `isDefault: false`, which would silently convert a default category to custom if a default's UUID were passed. Add an early-return guard checking the existing entity's type before mutation.

## Async & Task Lifecycle
- Long-running async ViewModel methods must check Task.checkCancellation() at natural boundaries.
- Remote change notification subscriptions must use NotificationCenter.notifications(named:) async sequence inside .task {} — never addObserver in init().
- .task handlers in TabView-hosted views re-fire on every tab appear — guard with loaded-state check.
- **2026-03-28**: When a service handles async events (notifications) that must propagate to the ViewModel, add an `onSessionInvalidated`-style callback closure to the protocol — @Observable tracking doesn't flow through @ObservationIgnored protocol references, so the ViewModel has no other way to learn about service-side state changes.
- **2026-04-04**: When a `@MainActor @Observable` singleton fans out state to multiple ViewModels via callbacks, use an array of closures (`[(@MainActor (T) -> Void)]`) not a single optional — a single slot is silently overwritten by the last subscriber's `init`, leaving earlier subscribers permanently stale. Safe for `@State`-owned VMs in TabView (created once, persist for app lifetime).
- **2026-03-28**: `CheckedContinuation` must never be overwritten — storing a new continuation before the previous is resumed crashes in debug. Guard with `signInContinuation != nil` before starting a new async bridge.
- **2026-03-29**: Apply `@MainActor` at the XCTestCase class level, not per-method, when testing `@MainActor`-isolated ViewModels — prevents actor-boundary issues in future `setUp()`/`tearDown()` overrides.
- **2026-03-29**: After `try await repository.save()`, add `guard !Task.isCancelled else { return }` before post-save state mutations (UI reset, UserDefaults write) — the view that spawned the Task may be gone (tab switch/dismiss), making the mutations pointless or dangerously late.
- **2026-04-03**: `guard !Task.isCancelled` must also appear in `catch` blocks of async ViewModel methods before setting `errorMessage` — the catch fires after an awaited call fails, and the view may be gone by then. Symmetric with the success-path guard.
- **2026-03-29**: Boolean flag guards (`isSaving`) must be checked BEFORE the flag is set: `guard !isSaving else { return }; isSaving = true; defer { isSaving = false }`. Without the upfront guard, a second @MainActor Task can start between suspension points and bypass the flag — `isSaving = true` + `defer` alone is a lifecycle signal, not a concurrency lock.
- **2026-04-06**: Unstructured `Task {}` in SwiftUI button actions must store the handle in `@State var task: Task<Void, Never>?` and cancel in `.onDisappear` — otherwise `dismiss()` runs against a dead `Environment` reference if the user navigates away mid-save.

## Data Layer
- **2026-04-02**: `NSFetchedResultsController` must live in the Repository layer, not the ViewModel — FRC converts `NSManagedObject` to DTO structs via callback, preserving MVVM boundaries. Use nested `@MainActor private class FRCDelegate: NSObject` with `[weak self]` closure to avoid retain cycles and satisfy Swift 6 actor isolation.
- **2026-04-02**: Protocol callback closures that update `@MainActor`-isolated ViewModel state must be typed `@MainActor` on the protocol (e.g., `var onExpensesChanged: (@MainActor ([ExpenseData]) -> Void)?`) — a plain closure type compiles but silently allows cross-actor mutation in Swift 6.
- **2026-04-02**: Fire-and-forget `Task {}` inside callback-driven methods (e.g., category reload on FRC change) must store the task handle and cancel-before-relaunch — otherwise rapid FRC callbacks cause racing Tasks that mutate state after cancellation. Pattern: `categoryTask?.cancel(); categoryTask = Task { ... guard !Task.isCancelled ... }`.
- **2026-04-02**: Never use `try?` on infrastructure-critical Core Data operations (FRC `performFetch`, store loads) — replace with `do/catch` + `os_log(.fault)` so failures leave a durable trace in the unified log. `try?` produces "silently empty" UI states that are impossible to diagnose without a debugger attached.
- **2026-04-06**: Always wrap `context.save()` with `do { try context.save() } catch { context.rollback(); throw error }` — a failed save leaves pending mutations (inserts/deletes/updates) in the context. Without `rollback()`, the next successful save from any operation silently commits those orphaned changes.
- All Repository methods must be @MainActor-isolated when using viewContext (main-thread-only context).
- For insights aggregation: single NSFetchRequest with date-range predicate + in-memory grouping by categoryID in Swift. No NSExpression aggregate queries.
- Use versioned .xcdatamodeld with lightweight (inferred) migration as default strategy.
- **2026-03-28**: Repository `save` methods must always use fetch-or-create (upsert) pattern — fetch by `id` first, update existing or create new. Never unconditionally `init(context:)` — causes duplicates on retry or re-sync.
- **2026-03-28**: Bootstrap-only methods like `seedDefaultCategoriesIfNeeded()` belong on the concrete repository class, NOT on the protocol — they are app-startup concerns, not part of the repository contract for consumers.
- **2026-03-28**: When mapping optional Core Data attributes to non-optional DTO fields, throw `RepositoryError.missingRequiredField` — never use `?? UUID()` (generates different value each fetch) or nil UUID sentinel (silently produces lookup misses). The DTO should represent a valid domain object; if it exists, it is complete.
- **2026-03-28**: Date range predicates in `fetchExpenses(for:)` must use exclusive upper bound (`createdAt < end`) not inclusive (`<= end`). Inclusive upper bound double-counts expenses at period boundaries when using contiguous intervals.

- **2026-04-03**: When a ViewModel method calls the same repository method N times per invocation (e.g., `fetchExpenses` for current + previous period), the mock must track calls in an array (`fetchPeriods: [DateInterval]`), not a single optional — otherwise only the last call is captured and earlier calls are lost for assertions.

## Dependency Injection
- **2026-04-04**: `CloudSharingService.shared` is the second accepted singleton (after `PersistenceController.shared`) — sharing state (`isShared`, `partnerName`, `currentShare`) must be consistent across all consumers (`SettingsViewModel`, `ExpenseRepository`, `FeedViewModel`). Init remains internal for test injection.
- **2026-04-04**: `SyncMonitorService.shared` is the third accepted singleton — sync status must be consistent across Feed and Insights screens. Same pattern: `static let shared`, internal init for test injection, `@MainActor @Observable`.
- Repositories should be transient instances (not singletons) — only PersistenceController, CloudSharingService, and SyncMonitorService are singletons.
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
- On error, preserve stale data and set errorMessage — view shows both simultaneously. **Exception**: aggregation screens (Insights) should clear state on error — stale totals from a different time period are misleading. Clear `totalAmount`, `categoryTotals`, `previousPeriodTotal` before setting `errorMessage`.
- **2026-04-03**: When a method computes multiple related date intervals (current + previous period), capture `Date()` once and pass to all helpers — two independent `Date()` calls can straddle midnight, producing inconsistent intervals (e.g., both pointing to the same month).
- **2026-03-29**: Fixed-point satang cap: `guard amountInCents < 1_000_000` before `amount * 10 + digit` enforces a ceiling of 9_999_999 (฿99,999.99) — the guard fires before multiply, so max(999_999) * 10 + 9 = 9_999_999. Extract guard threshold as a named constant (`maxBeforeAppend`) to make the math self-documenting.
- **2026-03-29**: Currency display formatting must use `Decimal(self) / 100` not `Double(self) / 100.0` — enforces "no floating-point for money" even in display-only contexts. `Decimal.FormatStyle.Currency` works identically to `FloatingPointFormatStyle.Currency`.
- **2026-03-29**: In `@Observable` classes, declare constants as `private static let` not `private let` — instance `let` occupies heap per instance unnecessarily. Access via `Self.constant`.
- **2026-04-04**: Never use `Dictionary(uniqueKeysWithValues:)` on data from external sources (Core Data, CloudKit) — it calls `fatalError` on duplicate keys. Use `Dictionary(..., uniquingKeysWith: { _, last in last })` instead. Data corruption or sync conflicts can produce duplicates.
- **2026-04-04**: `DateFormatter` is expensive to instantiate (loads ICU locale data). In `@Observable` ViewModels, cache as `private static let` with closure initializer, not as a method-local variable recreated on every call. Same applies to `NumberFormatter`.
- **2026-04-04**: `Calendar.range(of: .weekOfMonth, in: .month, for:)` returns nil on non-Gregorian calendars (e.g., Buddhist calendar, default on Thai devices). Always use `guard let` — never force-unwrap. Return empty array as graceful degradation.
- **2026-04-06**: All date arithmetic in ViewModels must use `Calendar(identifier: .gregorian)` as a `private static let` — never `Calendar.current`. Thai devices default to Buddhist calendar where `dateInterval(of:for:)` and `date(byAdding:)` can return nil. Add `logger.fault()` before nil-coalescing fallbacks so regressions are detectable.
- **2026-04-06**: Core Data `wrappedID` must use a stable sentinel (not `UUID()`) when `id` is nil. Use distinct static sentinel UUIDs per entity type to prevent cross-entity `ForEach` identity collisions. Avoid the RFC 4122 nil UUID (`00000000-...0000`) as a sentinel — it can collide with corrupted records.
- **2026-04-04**: `DateFormatter.dateFormat = "EEE"` produces locale-dependent day abbreviations — Thai devices output Thai-script ("จ.", "อ.") not English ("Mon", "Tue"). Pin `locale = Locale(identifier: "en_US_POSIX")` when labels must be English regardless of device locale.

## Authentication & DI
- **2026-04-04**: Never create a new `AuthenticationService()` instance in a View — it will be disconnected from the app's shared instance and `currentUserID` will always be `nil`. Always inject `AuthenticationServiceProtocol` through the ViewModel init, matching the pattern used by `FeedViewModel` and `ExpenseEntryViewModel`.

## Navigation Coordination
- For simple apps (3 tabs + sheets): TabView selection is @State in ContentView, sheet presentation is @State on presenting View. Full Coordinator pattern is unnecessary.
- Each tab owns its own NavigationStack. Never wrap TabView inside NavigationStack.
