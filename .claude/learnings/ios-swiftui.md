# iOS, SwiftUI, SwiftData

<!-- One line per learning, brief and actionable -->

## SwiftUI Navigation
- Never wrap TabView inside NavigationStack — each tab must own its own NavigationStack inside itself.
- NavigationPath must be @State on the tab root view, never on a ViewModel.

## SwiftUI State & Observation
- .task re-fires on every tab appear in TabView — guard with loaded-state check (e.g., `guard items.isEmpty else { return }`).
- Subscribe to NotificationCenter via async sequence in .task {} — auto-cancels on view disappear. Never use addObserver in ViewModels.

## SwiftUI Performance
- Use List (not ScrollView+VStack) for Feed — provides swipe actions and built-in row recycling. Switch to LazyVStack only if custom row layouts require leaving List.
- .tabBarMinimizeBehavior(.onScrollDown) must be applied on TabView itself, not on tab content. Only triggers on tabs with scrollable content.

## Sign in with Apple
- Email/name data only available on FIRST sign-in — cache to CloudKit UserProfile record immediately.
- Store userIdentifier in Keychain with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly.
- Register for ASAuthorizationAppleIDProvider.credentialRevokedNotification for mid-session revocation detection.
- Handle .revoked (clear Keychain + cleanup) separately from .notFound (just show sign-in, no cleanup).

## SwiftData Migrations
- N/A — CashOut uses Core Data, not SwiftData (shared CloudKit database not supported in SwiftData).

## SwiftData Relationships
- N/A — CashOut uses Core Data.

## SwiftData Threading
- N/A — CashOut uses Core Data.

## Core Data Testing
- **2026-03-28**: `PersistenceController(inMemory: true)` already disables CloudKit (sets `cloudKitContainerOptions = nil` and URL to `/dev/null`) — no need for a separate plain `NSPersistentContainer` test helper. Reuse the existing controller.
- **2026-03-28**: Asset catalog colorset group folders (e.g., `CategoryColors/`) are NOT part of the `Color(_ name:)` lookup — Xcode resolves by colorset name only. `Color("Sage")` works regardless of folder nesting depth.

## iOS Platform Patterns
- For Liquid Glass buttons: use .buttonStyle(.glass) or .buttonStyle(.glassProminent) — never combine with .glassEffect() modifier on the same element.
- .glassEffect() is for non-button views. Button styles auto-apply glass.
- Use view-associated UIImpactFeedbackGenerator(style:view:) for iOS 26+ (correct Taptic Engine routing), not legacy initializer.

## Testing Async Notification Handlers
- **2026-03-28**: `Task { }` on `@MainActor` doesn't start until the caller yields. `NotificationCenter.notifications(named:)` only receives notifications posted AFTER `for await` begins iteration. In tests: `await Task.yield()` before posting notifications so observer Tasks register their async sequence listeners first. Without this, tests pass as false positives (asserting on already-default-nil state).

## Swift 6 Strict Concurrency
- `static var` with closure init is not concurrency-safe — use `static let` for singletons/previews.
- CoreData's `NSMergeByPropertyStoreTrumpMergePolicy` triggers "shared mutable state" error in Swift 6 — use `@preconcurrency import CoreData`.
- XCUITest methods (`launch()`, `.staticTexts[]`, `.exists`) are MainActor-isolated in Swift 6 — annotate test methods with `@MainActor`.
- `NSPersistentCloudKitContainerOptionsKey` is NOT a public API — don't try to read CloudKit options from persistent store's options dict. Identify stores by URL instead.
- Core Data `codeGenerationType` absent from `.xcdatamodel` XML defaults to Manual/None when using xcodegen — do NOT add `codeGenerationType="category"` as it causes duplicate symbol errors with manually written +CoreDataProperties files.
- `@preconcurrency import CoreData` should be used on ALL files that reference Core Data types, not just PersistenceController — keeps Swift 6 strict concurrency consistent across model files.
