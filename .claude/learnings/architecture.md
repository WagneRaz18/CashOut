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

## Data Layer
- All Repository methods must be @MainActor-isolated when using viewContext (main-thread-only context).
- For insights aggregation: single NSFetchRequest with date-range predicate + in-memory grouping by categoryID in Swift. No NSExpression aggregate queries.
- Use versioned .xcdatamodeld with lightweight (inferred) migration as default strategy.

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

## Navigation Coordination
- For simple apps (3 tabs + sheets): TabView selection is @State in ContentView, sheet presentation is @State on presenting View. Full Coordinator pattern is unnecessary.
- Each tab owns its own NavigationStack. Never wrap TabView inside NavigationStack.
