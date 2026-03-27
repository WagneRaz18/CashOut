---
stepsCompleted: [1, 2, 3, 4, 5, 6, 7, 8]
lastStep: 8
status: 'complete'
completedAt: '2026-03-27'
inputDocuments:
  - prd.md
  - product-brief-CashOut.md
  - product-brief-CashOut-distillate.md
  - ux-design-specification.md
workflowType: 'architecture'
project_name: 'CashOut'
user_name: 'Boss'
date: '2026-03-27'
---

# Architecture Decision Document

_This document builds collaboratively through step-by-step discovery. Sections are appended as we work through each architectural decision together._

## Project Context Analysis

### Requirements Overview

**Functional Requirements:**
26 FRs across 6 domains. The core data flow is simple — create/edit/delete expense entries with category, amount, optional note, and partner attribution. The complexity lives not in the data model but in the sync and sharing layer: CloudKit shared database must keep two devices in real-time lockstep with offline resilience.

- **Expense Entry (FR1-FR4):** Amount-first creation with zero-navigation launch. Local persistence is immediate. This is the hot path — performance-critical.
- **Expense Management (FR5-FR8):** Chronological feed with edit/delete. Edit mirrors create UI (same components, pre-filled). Partner attribution on every entry.
- **Spending Categories (FR9-FR12):** 6 predefined defaults + user-created custom categories. Categories are shared data — custom categories created by one partner must sync to the other.
- **Spending Insights (FR13-FR18):** Daily/weekly/monthly aggregations by category. All computed from local data — no server-side aggregation. Swift Charts (SectorMark, BarMark).
- **Household & Sharing (FR19-FR22):** Sign in with Apple for auth. CloudKit CKShare for household pairing. Frictionless partner join — install, sign in, accept share link.
- **Offline & Sync (FR23-FR26):** Full offline CRUD. Automatic background sync on connectivity. Last-write-wins conflict resolution.

**Non-Functional Requirements:**
- **Performance:** Near-instant launch, immediate local save, instant view switching, smooth feed scrolling, background-only sync. No loading states anywhere.
- **Security & Privacy:** Apple Data Protection (at rest), CloudKit TLS (in transit). No third-party SDKs, no analytics, no telemetry. Data stays within device/iCloud boundary.
- **Data Management:** 6-month rolling retention window. No data loss during sync. Edits and deletes propagate fully — no orphaned records.

**Scale & Complexity:**
- Primary domain: Native iOS mobile (SwiftUI + CloudKit)
- Complexity level: Low — 2 users, single platform, no backend, no regulated data
- Estimated architectural components: ~12-15 (3 tab views, 6 custom UI components, data layer, sync layer, auth service, category management)

### Technical Constraints & Dependencies

| Constraint | Source | Architectural Impact |
|-----------|--------|---------------------|
| iOS 26+ only | PRD | Can use latest SwiftUI APIs without backwards compatibility. Enables Liquid Glass, `.tabViewBottomAccessory`, Swift Charts. |
| SwiftUI only | PRD | Declarative UI, no UIKit interop needed except for haptics (`UIImpactFeedbackGenerator`) and `UICloudSharingController` wrapper. |
| CloudKit shared database | PRD | CKShare for pairing, shared zone for data. `NSPersistentCloudKitContainer` manages its own subscriptions and sync internally. Primary technical risk. |
| **SwiftData cannot be used** | Research | SwiftData does NOT support CloudKit shared databases (confirmed through iOS 26). Must use Core Data + `NSPersistentCloudKitContainer` or raw CKSyncEngine. Apple DTS is directing developers to Core Data for cross-user sync. |
| Sign in with Apple | PRD | Authentication via `AuthenticationServices`. Email/name only available on first sign-in — must cache immediately to CloudKit. |
| No custom backend | PRD | All server-side logic is CloudKit. No REST APIs, no Firebase, no custom sync protocol. |
| Local-first persistence | PRD | Core Data as local store. UI reads from local, never waits on network. |
| Last-write-wins conflict resolution | PRD | `NSPersistentCloudKitContainer` uses `CKRecord` change tags for framework-level last-write-wins. Our `modifiedAt` field is for display/sorting only, not conflict arbitration. |
| MVVM architecture | CLAUDE.md | View → ViewModel → Model. `@Observable` ViewModels (not `@ObservableObject`). Repository pattern over Core Data. |
| Portrait-only | UX Spec | No landscape layout considerations. |
| CKShare requires custom zone | Research | Cannot use Default Zone. Must create a custom `CKRecordZone` ("HouseholdZone") before any sharing. |
| `UICloudSharingController` is UIKit | Research | Needs `UIViewControllerRepresentable` wrapper for SwiftUI integration. |
| Remote Notifications capability required | Research | `NSPersistentCloudKitContainer` uses silent pushes internally — must enable Background Modes → Remote Notifications. |
| `CKSharingSupported` Info.plist key required | Research | Must be `true` for system to route `userDidAcceptCloudKitShareWith` callbacks. Without it, partner join silently fails. |

### Cross-Cutting Concerns Identified

1. **Sync Lifecycle** — Every data mutation (create, edit, delete) must: (a) persist to Core Data first, (b) `NSPersistentCloudKitContainer` syncs to CloudKit automatically in background, (c) offline changes queue automatically and sync on reconnect, (d) conflicts resolved by framework via `CKRecord` change tags. No manual sync service needed — the framework handles everything.

2. **Partner Attribution** — Every expense carries "who logged it" metadata. Use CloudKit `userRecordID` (stable per iCloud account per app) stored as `createdByRef` field on each `Expense` record. System `modifiedBy` field provides automatic authorship tracking.

3. **Category System** — Categories are shared household data. Predefined defaults are identical on both devices. Custom categories must sync via the shared CloudKit zone. Categories appear in entry, feed, and insights — a shared data model referenced across all screens.

4. **Haptic Feedback** — Consistent haptic patterns across numpad entry, category selection, save, edit, and delete. A centralized haptic service ensures consistency and respects accessibility settings (Reduce Motion).

5. **Data Aggregation** — Insights (daily/weekly/monthly totals by category) are computed from local Core Data store. The aggregation logic is shared across three time scales and must update when entries are created, edited, or deleted.

### Research-Informed Architecture Decisions

| Decision | Rationale | Source |
|----------|-----------|--------|
| **Core Data + NSPersistentCloudKitContainer** over SwiftData | SwiftData has no shared database support. Apple DTS recommends Core Data for cross-user CloudKit sync. | Apple Developer Forums, DTS advisories |
| **Zone-level sharing** (not record-level) | One `CKShare` per custom zone. All household records live in one shared zone. Simpler than hierarchical record sharing. | Apple Zone Sharing Sample |
| **`@Observable` ViewModels** (not `@ObservableObject`) | Finer-grained view updates, no `@Published` boilerplate, `@State` in views. | iOS 17+ best practice |
| **Repository pattern** over Core Data | Abstracts persistence from ViewModels. Enables testing with mock repositories. `NSFetchedResultsController` in repository layer. | Community consensus |
| **`UICloudSharingController`** for partner invitation | System share sheet handles AirDrop/iMessage. Sidesteps iCloud discoverability requirements. | Apple Tech Talk 10874 |
| **Two database scopes** in `NSPersistentCloudKitContainer` | Private store (owner's data + zone they own) + shared store (partner's view). | Apple WWDC21 Session 10015 |
| **`NSPersistentCloudKitContainer` manages sync internally** | Framework handles its own `CKDatabaseSubscription`, change token persistence, and retry logic. No manual subscription or token management needed. | Apple Docs, WWDC21 |
| **iOS 26 Liquid Glass APIs confirmed** | `.tabViewBottomAccessory`, `.tabBarMinimizeBehavior(.onScrollDown)`, `.glassEffect()`, `.buttonStyle(.glassProminent)` all confirmed in WWDC25 Session 323. | Donny Wals, Apple WWDC25 |

### Known Risks from Research

| Risk | Impact | Mitigation |
|------|--------|------------|
| `NSPersistentCloudKitContainer` sharing has known bugs (zone migration on un-share, cache staleness) | Medium | Test against real devices with two iCloud accounts. Run `initializeCloudKitSchema()` in DEBUG. |
| Sign in with Apple email/name only available on first sign-in | Low | Cache user profile to CloudKit `UserProfile` record immediately on first auth. |
| Zone ID differs between owner (private DB) and participant (shared DB) | Medium | Store `encodeSystemFields` data with each record. Use correct database reference per user role. |
| `tabViewBottomAccessory` may be TabView-level only (not per-tab) | Low | Use conditional rendering inside the accessory view. Hide on Add tab. |
| No CKSyncEngine + CKShare combined sample from Apple | Medium | If using CKSyncEngine approach, requires two engine instances (private + shared). Documentation gap requires empirical exploration. |

## Starter Template Evaluation

### Primary Technology Domain

Native iOS mobile app (iOS 26+, SwiftUI, CloudKit). No cross-platform, no web, no third-party starter templates applicable.

### Starter Options Considered

| Option | Description | Verdict |
|--------|-------------|---------|
| **Xcode "App" template (SwiftUI)** | Default Xcode new project. Creates SwiftUI app with basic structure. | **Selected** — correct foundation for a native iOS app. |
| **Apple CloudKit sample projects** | Apple's `sample-cloudkit-zonesharing` and `CoreDataCloudKitShare`. | Reference only — valuable for CloudKit patterns, not a project starter. |
| **Third-party iOS boilerplates** | Community-maintained project templates with pre-configured architecture. | Rejected — introduces opinions and dependencies that conflict with CashOut's zero-dependency philosophy. |

### Selected Starter: Xcode SwiftUI App Template

**Rationale for Selection:**
CashOut has a zero third-party dependency mandate. The Xcode App template provides the correct minimal foundation: a SwiftUI lifecycle app with `@main` entry point. All additional architecture (Core Data stack, CloudKit configuration, MVVM folder structure) is added manually to maintain full control over the stack.

**Initialization:**

```
Xcode → File → New → Project → App
- Interface: SwiftUI
- Language: Swift
- Storage: Core Data (NOT SwiftData)
- Host in CloudKit: Yes
- Include Tests: Yes (Unit + UI)
- Deployment Target: iOS 26.0
```

**Required Xcode Capabilities:**

| Capability | Purpose |
|-----------|---------|
| CloudKit | `NSPersistentCloudKitContainer` sync + `CKShare` for household sharing |
| Sign in with Apple | Authentication |
| Background Modes → Remote notifications | Silent push for `NSPersistentCloudKitContainer` real-time sync |
| iCloud → CloudKit container | Container identifier for the app's CloudKit database |

**Architectural Decisions Provided by Starter:**

- **Language & Runtime:** Swift (latest stable), iOS 26+ SDK, SwiftUI app lifecycle (`@main` / `App` protocol)
- **Persistence:** Core Data with `NSPersistentCloudKitContainer` (two store configuration: private + shared scopes)
- **Build Tooling:** Xcode build system, Swift Package Manager, Debug/Release schemes
- **Testing Framework:** XCTest for unit tests, XCUITest for UI tests
- **Development Experience:** Xcode Previews, CloudKit Dashboard, Xcode Instruments

**Code Organization (MVVM project structure):**

```
CashOut/
├── App/
│   ├── CashOutApp.swift              # @main entry point
│   └── ContentView.swift             # Root TabView
├── Models/
│   ├── CashOut.xcdatamodeld          # Core Data model
│   ├── Expense+CoreDataClass.swift   # Generated entity class
│   └── Category+CoreDataClass.swift  # Generated entity class
├── ViewModels/
│   ├── ExpenseEntryViewModel.swift   # Entry screen logic
│   ├── FeedViewModel.swift           # Feed screen logic
│   └── InsightsViewModel.swift       # Insights screen logic
├── Views/
│   ├── Entry/                        # Tab 1: numpad entry
│   ├── Feed/                         # Tab 2: shared feed
│   ├── Insights/                     # Tab 3: charts
│   └── Settings/                     # Categories, household
├── Services/
│   ├── PersistenceController.swift   # Core Data + CloudKit stack
│   ├── CloudSharingService.swift     # CKShare, UICloudSharingController wrapper
│   ├── AuthenticationService.swift   # Sign in with Apple
│   └── HapticService.swift           # Centralized haptic feedback
├── Repositories/
│   ├── ExpenseRepository.swift       # Protocol + Core Data implementation
│   └── CategoryRepository.swift      # Protocol + Core Data implementation
└── Utilities/
    ├── Extensions/                   # Date, NumberFormatter, etc.
    └── Constants.swift               # Category defaults, design tokens
```

**Note:** Project initialization using Xcode should be the first implementation story.

## Core Architectural Decisions

### Decision Priority Analysis

**Critical Decisions (Block Implementation):**
1. CloudKit sync via `NSPersistentCloudKitContainer` (automatic, not manual CKSyncEngine)
2. Core Data model: Expense + Category entities, amount as Int64 cents, hard deletes
3. Sign in with Apple: once, persist in Keychain, silent verification on subsequent launches

**Important Decisions (Shape Architecture):**
4. Hybrid state observation: `NSFetchedResultsController` for Feed, remote change notification + re-fetch for Entry/Insights
5. Error handling: invisible sync errors, subtle banners for persistent issues only, no modals

**Deferred Decisions (Post-MVP):**
6. Data archival: deferred — 6-month volume (~6,000 records) is negligible for Core Data + CloudKit free tier

### Data Architecture

**Persistence Stack:** Core Data with `NSPersistentCloudKitContainer`
- Two `NSPersistentStoreDescription` configurations: private scope + shared scope
- `NSPersistentHistoryTrackingKey` enabled for remote change detection
- `initializeCloudKitSchema()` in DEBUG builds for schema deployment

**Expense Entity:**

| Attribute | Type | Notes |
|-----------|------|-------|
| `id` | UUID | Primary identifier, maps to CloudKit `recordName` |
| `amount` | Int64 | Cents — e.g., $12.50 → 1250. No floating-point issues. |
| `note` | String? | Optional free-text |
| `categoryID` | UUID | FK to Category |
| `createdByUserID` | String | CloudKit `userRecordID.recordName` for partner attribution |
| `createdAt` | Date | When logged |
| `modifiedAt` | Date | Display/sorting timestamp (conflict resolution handled by CKRecord change tags) |

**Category Entity:**

| Attribute | Type | Notes |
|-----------|------|-------|
| `id` | UUID | Primary identifier |
| `name` | String | Display name |
| `iconName` | String | SF Symbol name |
| `colorName` | String | Design token key |
| `isDefault` | Bool | Predefined vs. custom |
| `sortOrder` | Int16 | Display order |

**Deletion strategy:** Hard delete. `NSPersistentCloudKitContainer` handles CloudKit tombstone propagation automatically via `NSPersistentHistoryTracking`.

**Data archival:** Deferred for v1. Volume is negligible at 2-user scale.

**Schema migration:** Use versioned `.xcdatamodeld` model files with lightweight (inferred) migration as the default strategy. `NSPersistentStoreDescription` should set `NSMigratePersistentStoresAutomaticallyOption` and `NSInferMappingModelAutomaticallyOption` to `true`. For any post-launch schema changes that cannot be inferred (type changes, complex transformations), create a custom `NSMappingModel`.

### Authentication & Security

**Sign in with Apple — single sign-in flow:**
- First launch: present `ASAuthorizationAppleIDProvider` sign-in UI
- Cache `userIdentifier` in Keychain using `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (survives app reinstall within same iCloud account)
- Cache display name + email to CloudKit `UserProfile` record immediately on first auth (only available once)
- Subsequent launches: `getCredentialState(forUserID:)` silent check
- Credential state handling:
  - `.authorized`: straight to numpad (zero delay)
  - `.revoked`: clear Keychain, clear local user profile data, present modal Sign in with Apple screen (blocking)
  - `.notFound`: present Sign in with Apple screen (no Keychain clearance needed — user may be a fresh install or different device)
  - `.transferred`: treat as `.notFound` (enterprise account migration edge case)
- **Mid-session revocation detection:** Register for `ASAuthorizationAppleIDProvider.credentialRevokedNotification` in `AuthenticationService` on app launch. If fired while app is in foreground or background, immediately terminate the session and present Sign in with Apple screen.
- **iCloud account change:** Observe `CKAccountChanged` notification to detect when the iCloud account changes on device. Flush cached credentials, tokens, and reconcile local data.

**Security (handled by platform):**
- Encryption at rest: Apple Data Protection (automatic)
- Encryption in transit: CloudKit TLS (automatic)
- No custom credential storage, no third-party SDKs, no analytics

### CloudKit Sync Architecture

**Sync engine:** `NSPersistentCloudKitContainer` (fully automatic)
- Owner's data lives in private database, custom `HouseholdZone`
- Partner accesses via shared database
- `CKShare` attached to zone (zone-level sharing, not record-level)
- Remote change notifications via `.NSPersistentStoreRemoteChange`
- Conflict resolution: framework-level last-write-wins via `CKRecord` change tags (managed automatically by `NSPersistentCloudKitContainer`). Our `modifiedAt` field is for display/sorting only — it does not participate in conflict arbitration.
- **No manual `CKDatabaseSubscription`** — the framework manages its own subscriptions, change token persistence, and retry logic internally. Do not create separate subscriptions.
- Zone existence: verify `HouseholdZone` exists on every fresh launch (users can delete zones via iOS Settings → iCloud)
- iCloud account change: observe `CKAccountChanged` notification in `PersistenceController` to flush stale tokens and reconcile local state

**Partner invitation:** `UICloudSharingController` (wrapped in `UIViewControllerRepresentable`) — system share sheet for AirDrop/iMessage. No custom invite flow.

**CKShare acceptance:** `CashOutApp.swift` must handle the share acceptance callback. Use `userDidAcceptCloudKitShareWith` via the `WindowGroup` scene delegate or SwiftUI user activity handler. Call `container.accept(metadata)` to connect the partner to the shared zone.

**Real-time updates:** `NSPersistentCloudKitContainer` handles silent push subscriptions internally. Requires Background Modes → Remote Notifications capability. The app must call `container.handleRemoteNotification(_:)` in the app delegate's `didReceiveRemoteNotification` method.

**Hard delete propagation:** `NSPersistentCloudKitContainer` handles tombstone propagation via `NSPersistentHistoryTracking`. Edge case: if a partner is offline when a record is deleted and the CloudKit tombstone window expires, the record may persist on the partner's device. On `.changeTokenExpired` recovery (full re-fetch), reconcile local records against the server to remove orphaned entries.

**Persistent history purge:** Periodically purge old `NSPersistentHistoryTransaction` entries to prevent unbounded growth. Purge transactions older than 7 days on app launch.

**Required Info.plist keys:**

| Key | Value | Purpose |
|-----|-------|---------|
| `CKSharingSupported` | `true` | Routes `userDidAcceptCloudKitShareWith` callbacks to the app |
| `UIBackgroundModes` | `remote-notification` | Silent push for sync |

### State Management

**Hybrid observation pattern:**

| Screen | Pattern | Rationale |
|--------|---------|-----------|
| Feed | `NSFetchedResultsController` in repository | Animated row insertions/deletions when synced data arrives |
| Entry | Remote change notification + re-fetch | Simple — only needs current category state |
| Insights | Remote change notification + re-fetch | Re-aggregates on change — data volume is tiny |

**ViewModels:** `@Observable` (macro), held in views via `@State`. Repository protocol injected at init. `@ObservationIgnored` on repository references to prevent spurious view refreshes.

### Error Handling

| Error Type | Handling | User Visibility |
|-----------|---------|----------------|
| Transient sync (network, throttle) | Auto-retry by `NSPersistentCloudKitContainer` | None |
| iCloud not signed in | Check on launch | Subtle banner: "Sign in to iCloud to sync" |
| CKShare acceptance failure | Retry, log | Settings: "Sharing not connected" |
| Core Data save failure | Assert DEBUG, log release | None |
| Credential revocation | Block UI | Modal Sign in with Apple |
| CloudKit quota exceeded | Ignore for v1 | None |

**Principle:** No modals for sync errors. No red alerts. Small nav-bar indicator only for persistent issues.

### Decision Impact Analysis

**Implementation Sequence:**
1. Xcode project + capabilities configuration
2. Core Data model (Expense + Category entities)
3. `NSPersistentCloudKitContainer` with two-store configuration
4. Sign in with Apple + Keychain persistence
5. Repository layer (ExpenseRepository with `NSFetchedResultsController`, CategoryRepository)
6. ViewModels (`@Observable`) + Views (SwiftUI)
7. CloudKit sharing (`CKShare` + `UICloudSharingController` wrapper)
8. Haptic service

**Cross-Component Dependencies:**
- Repositories depend on `PersistenceController` (Core Data stack)
- ViewModels depend on Repository protocols (injectable)
- CloudSharingService depends on `PersistenceController` + AuthenticationService
- All Views depend on ViewModels only (no direct data layer access)

## Implementation Patterns & Consistency Rules

### Critical Conflict Points Identified

8 areas where AI agents could make divergent choices if not specified.

### Naming Patterns

**Core Data Naming:**

| Element | Convention | Example |
|---------|-----------|---------|
| Entity names | PascalCase, singular | `Expense`, `Category` |
| Attribute names | camelCase | `createdAt`, `categoryID`, `createdByUserID` |
| Relationship names | camelCase, descriptive | `category` (to-one), `expenses` (to-many) |

**Swift Code Naming:**

| Element | Convention | Example |
|---------|-----------|---------|
| Types (class, struct, enum, protocol) | PascalCase | `ExpenseRepository`, `FeedViewModel`, `NumpadView` |
| Protocol names | PascalCase, noun or `-able`/`-ing` suffix | `ExpenseRepositoryProtocol` or `ExpenseStoring` |
| Functions/methods | camelCase, verb-first | `fetchExpenses(for:)`, `saveExpense(_:)` |
| Variables/properties | camelCase | `selectedCategory`, `totalAmount` |
| Constants | camelCase (not SCREAMING_CASE) | `let defaultCategories`, `let maxNoteLength` |
| Enum cases | camelCase | `.foodAndDrink`, `.transport` |
| Boolean properties | `is`/`has`/`should` prefix | `isDefault`, `hasPartner`, `shouldSync` |

**File Naming:**

| Element | Convention | Example |
|---------|-----------|---------|
| SwiftUI Views | PascalCase + `View` suffix | `FeedView.swift`, `NumpadView.swift` |
| ViewModels | PascalCase + `ViewModel` suffix | `FeedViewModel.swift` |
| Services | PascalCase + `Service` suffix | `HapticService.swift`, `AuthenticationService.swift` |
| Repositories | PascalCase + `Repository` suffix | `ExpenseRepository.swift` |
| Extensions | `Type+Extension.swift` | `Date+Formatting.swift`, `Int64+Currency.swift` |
| Protocols | Same as type name + `Protocol` suffix | `ExpenseRepositoryProtocol.swift` |

### Structure Patterns

**Project Organization:**

```
Views/Entry/       # All views for the Entry tab
Views/Feed/        # All views for the Feed tab
Views/Insights/    # All views for the Insights tab
Views/Settings/    # Settings views
ViewModels/        # Flat — one ViewModel per screen
Services/          # Flat — one file per service
Repositories/      # Flat — protocol + implementation per file
Models/            # Core Data model + generated classes
Utilities/Extensions/  # Type extensions
```

**Rules:**
- One SwiftUI `View` per file — no multi-view files
- One `ViewModel` per screen (not per component)
- Sub-views (components) live in the same feature folder as their parent
- Services and Repositories are flat (no nesting)
- No `Helpers/`, `Utils/`, or `Common/` catch-all folders

**Test Organization:**

```
CashOutTests/
├── ViewModels/
│   ├── ExpenseEntryViewModelTests.swift
│   ├── FeedViewModelTests.swift
│   └── InsightsViewModelTests.swift
├── Repositories/
│   ├── ExpenseRepositoryTests.swift
│   └── CategoryRepositoryTests.swift
└── Services/
    ├── AuthenticationServiceTests.swift
    └── HapticServiceTests.swift

CashOutUITests/
├── EntryFlowUITests.swift
├── FeedFlowUITests.swift
└── InsightsFlowUITests.swift
```

- Unit tests mirror the source folder structure
- UI tests organized by user journey, not by screen
- Test files named `{SourceFile}Tests.swift`

### Format Patterns

**Amount Display (Int64 cents → String):**

```swift
extension Int64 {
    var displayAmount: String {
        let dollars = Double(self) / 100.0
        return dollars.formatted(.currency(code: "USD"))
    }
}
```

- Amounts stored as Int64 cents everywhere in the data layer
- Conversion to display string happens only at the View/ViewModel boundary
- Use `Foundation.FormatStyle` — never manually concatenate "$" + string

**Date Display:**

| Context | Format | Example |
|---------|--------|---------|
| Feed row timestamp | Relative | "2 min ago", "Yesterday" |
| Insights section header | Medium date | "Mar 27, 2026" |
| Core Data storage | `Date` (native) | No string conversion |

- Use `RelativeDateTimeFormatter` for feed timestamps
- Use `.formatted(date: .abbreviated, time: .omitted)` for section headers
- Never store dates as strings

**Category Color Tokens:**

```swift
enum CategoryColor: String, CaseIterable {
    case sage       // Food & Drink — #7BA08A / #5C8A6E
    case slate      // Transport — #7B8FA8 / #5A7490
    case lavender   // Entertainment — #9B8AB0 / #7D6E95
    case amber      // Household — #B09A7B / #957F60
    case dustyRose  // Shopping — #A8848B / #8E6B73
    case coolGray   // Other — #8A8D94 / #6E7178
}
```

- Colors defined in asset catalog with light/dark variants
- Referenced by `colorName` string in Core Data, resolved to `Color` via extension
- Same color everywhere for the same category (feed row, chart slice, picker)

### Communication Patterns

**ViewModel → View Communication:**

```swift
@MainActor
@Observable
final class FeedViewModel {
    var expenses: [ExpenseData] = []
    var errorMessage: String?

    @ObservationIgnored
    private let repository: ExpenseRepositoryProtocol
    @ObservationIgnored
    private let hapticService: HapticServiceProtocol
}
```

**Rules:**
- ViewModels are always `@MainActor` + `@Observable`
- Views hold ViewModels via `@State private var viewModel = FeedViewModel()`
- ALL injected service and repository references marked `@ObservationIgnored` — this includes repositories, `HapticService`, `AuthenticationService`, and any other injected dependency
- No `Combine` publishers — use `@Observable` properties and `async/await`
- No `NotificationCenter` between ViewModel and View — only `@Observable` properties
- No `@EnvironmentObject` for ViewModels — each View creates its own via `@State`

**Core Data → ViewModel Communication:**
- Remote change notification (`.NSPersistentStoreRemoteChange`) for Entry/Insights
- `NSFetchedResultsController` delegate only in `ExpenseRepository` for Feed
- Never observe Core Data changes from Views directly

**Haptic Feedback Events:**

```swift
enum HapticEvent {
    case numpadKey      // .light impact
    case categorySelect // .light impact
    case saveTap        // .success notification
    case deleteTap      // .success notification
    case error          // .error notification
}
```

- All haptics go through `HapticServiceProtocol.trigger(_ event: HapticEvent)`
- `HapticService` wraps both `UIImpactFeedbackGenerator` (for `.light` impacts) and `UINotificationFeedbackGenerator` (for `.success`/`.error` notifications)
- Use the view-associated initializer `UIImpactFeedbackGenerator(style:view:)` for iOS 26+ (correct Taptic Engine routing)
- Never call `UIFeedbackGenerator` subclasses directly from Views
- Respects `UIAccessibility.isReduceMotionEnabled`
- `MockHapticService` in test targets — records triggered events without calling UIKit

### Process Patterns

**Core Data Save Pattern:**

```swift
func saveExpense(_ expense: ExpenseData) async throws {
    let context = persistenceController.viewContext
    let entity = Expense(context: context)
    entity.id = UUID()
    entity.amount = expense.amount
    entity.categoryID = expense.categoryID
    entity.createdAt = Date()
    entity.modifiedAt = Date()
    entity.createdByUserID = currentUserID
    try context.save()
}
```

- All Core Data writes go through Repository methods
- ViewModels never touch `NSManagedObjectContext` directly
- All Repository methods are `@MainActor`-isolated (use `viewContext` which is main-thread-only)
- `ExpenseRepository` is `@MainActor`-isolated — `NSFetchedResultsController` delegate callbacks fire on main thread
- `modifiedAt` set on every save (create and edit) for display/sorting purposes

**Insights Aggregation Strategy:**
- Use a single `NSFetchRequest` with a date-range predicate (`createdAt` within period)
- Perform in-memory aggregation by `categoryID` in Swift (group, sum, sort)
- Do NOT use `NSExpression`-based aggregate queries — unnecessary complexity for ~6,000 records
- Re-aggregate on every `.NSPersistentStoreRemoteChange` notification

**Dependency Injection Pattern:**

```swift
protocol ExpenseRepositoryProtocol {
    func fetchExpenses(for period: DateInterval) async throws -> [ExpenseData]
    func saveExpense(_ data: ExpenseData) async throws
    func deleteExpense(id: UUID) async throws
}

@MainActor
@Observable
final class FeedViewModel {
    var expenses: [ExpenseData] = []
    var errorMessage: String?

    @ObservationIgnored
    private let repository: ExpenseRepositoryProtocol
    @ObservationIgnored
    private let hapticService: HapticServiceProtocol

    init(
        repository: ExpenseRepositoryProtocol = ExpenseRepository(),
        hapticService: HapticServiceProtocol = HapticService()
    ) {
        self.repository = repository
        self.hapticService = hapticService
    }
}
```

- All services and repositories defined as protocols (including `HapticServiceProtocol`)
- Default parameter in ViewModel `init` provides **transient** real implementation (not `.shared` singleton)
- `PersistenceController` is the only singleton — repositories receive it via `init(persistence:)` parameter
- ALL injected service and repository references marked `@ObservationIgnored`
- Tests inject mock implementations (e.g., `MockExpenseRepository`, `MockHapticService`)
- No DI container/framework — protocol + default parameter is sufficient

**SwiftUI View Pattern:**

```swift
struct FeedView: View {
    @State private var viewModel = FeedViewModel()

    var body: some View {
        List { /* ... */ }
            .task { await viewModel.loadExpenses() }
    }
}
```

- Views are thin — display state, forward actions
- Use `.task { }` for async initialization (not `.onAppear`)
- No business logic in Views — not even filtering or sorting
- `.task` handlers in TabView-hosted views must guard against redundant re-loads (`.task` re-fires on every tab appear):
  ```swift
  .task { guard viewModel.expenses.isEmpty else { return }; await viewModel.loadExpenses() }
  ```

**Remote Change Notification Subscription Pattern:**

```swift
// In ViewModel — subscribe via async sequence inside .task (auto-cancels on view disappear)
func observeRemoteChanges() async {
    for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
        try? Task.checkCancellation()
        await loadExpenses()  // re-fetch from repository
    }
}
```

- Always subscribe via `NotificationCenter.notifications(named:)` async sequence inside `.task { }`
- Never use `NotificationCenter.addObserver` in ViewModels — observers won't auto-cancel
- Check `Task.checkCancellation()` at natural boundaries in async methods

**App-Root Dependency Injection Pattern:**

```swift
@main
struct CashOutApp: App {
    @State private var persistenceController = PersistenceController.shared
    @State private var authService = AuthenticationService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(persistenceController)
        }
        .userActivity(NSUserActivityTypeBrowsingWeb) { _ in }
        // Handle CKShare acceptance
        .onCKShareAccepted { metadata in
            let container = persistenceController.container
            Task {
                try await container.accept(metadata)
            }
        }
    }
}
```

- `PersistenceController.shared` is the only singleton — instantiated at app root
- Repositories are transient — created by ViewModels with `ExpenseRepository(persistence: .shared)`
- Services are lightweight — instantiated per-ViewModel or passed from app root via `.environment()`

**Navigation Pattern:**

CashOut uses simple navigation (3 tabs + a few sheets). A full Coordinator pattern is unnecessary at this scale.

```swift
struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Add", systemImage: "plus", value: 0) {
                EntryView()  // No NavigationStack needed — no push navigation
            }
            Tab("Feed", systemImage: "list.bullet", value: 1) {
                NavigationStack {  // Each tab owns its own NavigationStack
                    FeedView()
                }
            }
            Tab("Insights", systemImage: "chart.pie", value: 2) {
                NavigationStack {  // Each tab owns its own NavigationStack
                    InsightsView()
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
```

**Navigation rules:**
- **Never** wrap `TabView` inside `NavigationStack` — each tab owns its own `NavigationStack` inside itself
- `NavigationPath` is `@State` on the tab root view, never on a ViewModel
- Sheet presentation uses `@State private var isShowingSheet = false` on the presenting View
- `EntryView` does not need `NavigationStack` (no push navigation — it's a single screen)
- `FeedView` needs `NavigationStack` for filtered views (tap donut slice → filtered feed)
- `.tabBarMinimizeBehavior(.onScrollDown)` applied on `TabView` — only triggers on tabs with scrollable content (Feed, Insights). Entry tab (numpad, no scroll) won't trigger minimize, which is correct.

**ViewModel State Properties Pattern:**

```swift
@MainActor
@Observable
final class FeedViewModel {
    // State — independent properties, NOT a combined enum
    var expenses: [ExpenseData] = []
    var errorMessage: String?       // nil = no error. Stale data preserved on error.

    // On error: data stays populated, errorMessage gets set.
    // View shows both stale data AND error indicator simultaneously.
    func loadExpenses() async {
        do {
            expenses = try await repository.fetchExpenses(for: currentPeriod)
            errorMessage = nil
        } catch {
            // expenses retains stale data — do NOT clear it
            errorMessage = error.localizedDescription
        }
    }
}
```

- Use independent `data` + `errorMessage` properties — never a combined `enum ViewState`
- On error, preserve stale data and set error — view shows both
- `isLoading` is unnecessary for v1 (local-first, no loading states) but can be added if needed

### Enforcement Guidelines

**All AI Agents MUST:**

1. Follow Swift naming conventions exactly as specified — no deviations
2. Route all data operations through Repository protocols — never access Core Data from Views or ViewModels directly
3. Use `@Observable` (not `@ObservableObject`) for all ViewModels
4. Route all haptic feedback through `HapticService`
5. Format amounts using the `Int64.displayAmount` extension — no ad-hoc formatting
6. Keep Views declarative and thin — all logic lives in ViewModels
7. Place files in the correct folder per the structure patterns
8. Write unit tests for every ViewModel and Repository method

**Anti-Patterns (Never Do This):**

```swift
// BAD: Business logic in View
struct FeedView: View {
    var body: some View {
        let filtered = expenses.filter { $0.categoryID == selected } // NO
    }
}

// BAD: Direct Core Data access from ViewModel
class FeedViewModel {
    func load() {
        let request = NSFetchRequest<Expense>() // NO — use repository
    }
}

// BAD: Ad-hoc amount formatting
Text("$\(Double(amount) / 100.0)") // NO — use .displayAmount

// BAD: Direct haptic call from View
Button("Save") {
    UINotificationFeedbackGenerator().notificationOccurred(.success) // NO
}

// BAD: @ObservableObject instead of @Observable
class FeedViewModel: ObservableObject { // NO — use @Observable macro
    @Published var expenses: [Expense] = []
}

// BAD: Child view holding ViewModel via @State
struct FeedRowView: View {
    @State private var viewModel = FeedRowViewModel() // NO — use let or @Bindable
}

// BAD: ViewModel importing SwiftUI
import SwiftUI // NO — ViewModels must not import SwiftUI
class FeedViewModel { }

// BAD: NotificationCenter.addObserver in ViewModel
init() {
    NotificationCenter.default.addObserver(self, ...) // NO — use async sequence in .task
}

// BAD: Creating Task in onAppear without cancellation
.onAppear { Task { await load() } } // NO — use .task { } which auto-cancels

// BAD: Mutating state after await without cancellation check
func load() async {
    let data = await fetchData()
    self.items = data // NO — check Task.isCancelled first
}

// BAD: Singleton repository
ExpenseRepository.shared // NO — use transient ExpenseRepository()

// BAD: Mixing .buttonStyle(.glass) with .glassEffect() on same Button
Button("Save") { }
    .buttonStyle(.glassProminent) // Use ONE of these
    .glassEffect(.regular.interactive()) // NOT both — they conflict

// BAD: Wrapping TabView inside NavigationStack
NavigationStack { TabView { ... } } // NO — each tab owns its own NavigationStack
```

**Liquid Glass API Rules:**
- `Button` elements use `.buttonStyle(.glass)` or `.buttonStyle(.glassProminent)` — these are `ButtonStyle` replacements that auto-apply glass
- Non-button views use `.glassEffect()` modifier directly
- **Never** combine `.buttonStyle(.glass*)` with `.glassEffect()` on the same element — they conflict
- Numpad keys: use `.buttonStyle(.glass)` (secondary interactive)
- FAB: use `.buttonStyle(.glassProminent)` with `.buttonBorderShape(.circle)`
- Save button: use `.buttonStyle(.glassProminent)` (primary action)

## Project Structure & Boundaries

### Complete Project Directory Structure

```
CashOut/
├── CashOut.xcodeproj/
│   └── project.pbxproj
│
├── CashOut/
│   ├── App/
│   │   ├── CashOutApp.swift                    # @main, scene config, CKShare acceptance
│   │   ├── ContentView.swift                    # Root TabView (3 tabs)
│   │   └── Info.plist                           # App configuration
│   │
│   ├── Models/
│   │   ├── CashOut.xcdatamodeld/                # Core Data model (Expense, Category entities)
│   │   ├── Expense+CoreDataClass.swift          # Generated managed object subclass
│   │   ├── Expense+CoreDataProperties.swift     # Generated properties
│   │   ├── Category+CoreDataClass.swift         # Generated managed object subclass
│   │   ├── Category+CoreDataProperties.swift    # Generated properties
│   │   └── ExpenseData.swift                    # Plain struct for ViewModel ↔ Repository transfer
│   │
│   ├── ViewModels/
│   │   ├── ExpenseEntryViewModel.swift           # Entry screen: amount, category, save
│   │   ├── FeedViewModel.swift                   # Feed screen: expense list, edit, delete
│   │   ├── InsightsViewModel.swift               # Insights screen: aggregations, chart data
│   │   ├── SettingsViewModel.swift               # Settings: categories, household, sharing
│   │   └── AuthenticationViewModel.swift         # Sign in with Apple flow
│   │
│   ├── Views/
│   │   ├── Entry/
│   │   │   ├── EntryView.swift                   # Tab 1: entry screen container
│   │   │   ├── NumpadView.swift                  # Custom 3x4 numpad grid
│   │   │   ├── AmountDisplayView.swift           # Hero amount display
│   │   │   └── CategoryPickerView.swift          # Horizontal scrolling category chips
│   │   │
│   │   ├── Feed/
│   │   │   ├── FeedView.swift                    # Tab 2: shared expense feed
│   │   │   ├── FeedRowView.swift                 # Individual expense row
│   │   │   ├── FloatingAddButton.swift           # Glass FAB for quick entry
│   │   │   └── EditExpenseSheet.swift            # Edit sheet (reuses numpad/category)
│   │   │
│   │   ├── Insights/
│   │   │   ├── InsightsView.swift                # Tab 3: charts and breakdowns
│   │   │   ├── InsightsSummaryView.swift         # Donut chart + headline metric
│   │   │   ├── DailyBarChartView.swift           # Bar chart (BarMark)
│   │   │   └── CategoryBreakdownView.swift       # Category list with proportion bars
│   │   │
│   │   ├── Settings/
│   │   │   ├── SettingsView.swift                # Settings form (gear icon access)
│   │   │   ├── CategoryManagementView.swift      # Add/edit custom categories
│   │   │   ├── HouseholdView.swift               # Partner info, invite
│   │   │   └── CloudSharingSheet.swift           # UICloudSharingController wrapper
│   │   │
│   │   └── Auth/
│   │       └── SignInView.swift                  # Sign in with Apple screen
│   │
│   ├── Services/
│   │   ├── PersistenceController.swift           # NSPersistentCloudKitContainer setup + history purge
│   │   ├── CloudSharingService.swift             # CKShare creation, UICloudSharingController
│   │   ├── AuthenticationService.swift           # Sign in with Apple + Keychain + revocation
│   │   ├── HapticServiceProtocol.swift           # Protocol definition
│   │   └── HapticService.swift                   # Implementation (UIImpact + UINotification)
│   │
│   ├── Repositories/
│   │   ├── ExpenseRepositoryProtocol.swift        # Protocol definition
│   │   ├── ExpenseRepository.swift                # Core Data impl + NSFetchedResultsController
│   │   ├── CategoryRepositoryProtocol.swift       # Protocol definition
│   │   └── CategoryRepository.swift               # Core Data implementation
│   │
│   ├── Utilities/
│   │   ├── Extensions/
│   │   │   ├── Int64+Currency.swift               # .displayAmount formatting
│   │   │   ├── Date+Formatting.swift              # Relative + abbreviated formatters
│   │   │   └── Color+CategoryTokens.swift         # Category color resolution
│   │   └── Constants.swift                        # Default categories, design tokens
│   │
│   ├── Assets.xcassets/
│   │   ├── AccentColor.colorset/                  # App tint (blue-gray)
│   │   ├── AppIcon.appiconset/                    # App icon
│   │   └── CategoryColors/                        # Per-category color sets
│   │       ├── Sage.colorset/
│   │       ├── Slate.colorset/
│   │       ├── Lavender.colorset/
│   │       ├── Amber.colorset/
│   │       ├── DustyRose.colorset/
│   │       └── CoolGray.colorset/
│   │
│   └── CashOut.entitlements                       # CloudKit, Sign in with Apple, Background Modes
│
├── CashOutTests/
│   ├── ViewModels/
│   │   ├── ExpenseEntryViewModelTests.swift
│   │   ├── FeedViewModelTests.swift
│   │   ├── InsightsViewModelTests.swift
│   │   └── SettingsViewModelTests.swift
│   ├── Repositories/
│   │   ├── MockExpenseRepository.swift            # Mock for testing
│   │   ├── MockCategoryRepository.swift           # Mock for testing
│   │   ├── ExpenseRepositoryTests.swift
│   │   └── CategoryRepositoryTests.swift
│   └── Services/
│       ├── MockHapticService.swift                # Mock — records events, no UIKit calls
│       └── AuthenticationServiceTests.swift
│
├── CashOutUITests/
│   ├── EntryFlowUITests.swift                     # Journey 1: Quick Log
│   ├── FeedFlowUITests.swift                      # Journey 2: Fix-Up
│   ├── InsightsFlowUITests.swift                  # Journey 3: Insights
│   └── OnboardingFlowUITests.swift                # Journey 4/5: Auth + Partner
│
└── .gitignore
```

### Architectural Boundaries

**Layer Boundaries (strict, never cross):**

```
┌─────────────────────────────────────────────┐
│  Views (SwiftUI)                            │
│  Read state from ViewModel, forward actions │
│  NEVER access Repositories or Services      │
├─────────────────────────────────────────────┤
│  ViewModels (@Observable)                   │
│  Own business logic, call Repository methods│
│  NEVER access NSManagedObjectContext        │
├─────────────────────────────────────────────┤
│  Repositories (Protocol + Implementation)   │
│  Own Core Data queries and mutations        │
│  Expose domain data, hide Core Data details │
├─────────────────────────────────────────────┤
│  Services (Persistence, Auth, Sharing)      │
│  Own infrastructure concerns                │
│  PersistenceController owns the CD stack    │
├─────────────────────────────────────────────┤
│  Core Data + CloudKit (Apple frameworks)    │
│  Automatic sync, conflict resolution        │
│  Never accessed directly above Repository   │
└─────────────────────────────────────────────┘
```

**Service Boundaries:**

| Service | Owns | Consumed By |
|---------|------|-------------|
| `PersistenceController` | `NSPersistentCloudKitContainer`, both store descriptions, `viewContext` | Repositories |
| `AuthenticationService` | Sign in with Apple, Keychain, credential state | `AuthenticationViewModel`, `CloudSharingService` |
| `CloudSharingService` | `CKShare` creation, `UICloudSharingController` wrapping | `SettingsViewModel` |
| `HapticService` | `UIImpactFeedbackGenerator` + `UINotificationFeedbackGenerator`, accessibility checks. Defined as `HapticServiceProtocol` for testability. | All ViewModels (injected via `init`) |

**Data Boundaries:**

| Boundary | Rule |
|----------|------|
| Core Data → ViewModel | Repositories ALWAYS convert `NSManagedObject` to plain structs (`ExpenseData`). Never expose `NSManagedObject` instances to ViewModels — they are not `Sendable` and create Core Data type dependencies across the boundary. |
| ViewModel → View | Views read `@Observable` properties. No Core Data types in View layer. |
| CloudKit ↔ Core Data | Fully managed by `NSPersistentCloudKitContainer` — no manual `CKRecord` handling |

### Requirements to Structure Mapping

| FR Category | ViewModels | Views | Repositories/Services |
|-------------|-----------|-------|----------------------|
| Expense Entry (FR1-FR4) | `ExpenseEntryViewModel` | `Views/Entry/*` | `ExpenseRepository` |
| Expense Management (FR5-FR8) | `FeedViewModel` | `Views/Feed/*` | `ExpenseRepository` |
| Spending Categories (FR9-FR12) | `SettingsViewModel` | `Views/Settings/CategoryManagementView` | `CategoryRepository` |
| Spending Insights (FR13-FR18) | `InsightsViewModel` | `Views/Insights/*` | `ExpenseRepository` |
| Household & Sharing (FR19-FR22) | `AuthenticationViewModel`, `SettingsViewModel` | `Views/Auth/*`, `Views/Settings/HouseholdView` | `CloudSharingService`, `AuthenticationService` |
| Offline & Sync (FR23-FR26) | — (transparent) | — | `PersistenceController` (automatic) |

### Cross-Cutting Concerns → Location

| Concern | Location |
|---------|----------|
| Sync lifecycle | `PersistenceController` (automatic via `NSPersistentCloudKitContainer`) |
| Partner attribution | `ExpenseRepository` (sets `createdByUserID` on save) |
| Category system | `CategoryRepository` + `Constants.swift` (defaults) |
| Haptic feedback | `HapticService` (called from ViewModels) |
| Amount formatting | `Int64+Currency.swift` extension |
| Date formatting | `Date+Formatting.swift` extension |

### Data Flow

```
User taps Save
    → View calls viewModel.saveExpense()
        → ViewModel calls repository.saveExpense(data)
            → Repository creates Expense in viewContext
            → Repository calls context.save()
                → Core Data persists locally (immediate)
                → NSPersistentCloudKitContainer syncs to CloudKit (background)
                    → Partner's device receives silent push
                    → Partner's container imports changes
                    → .NSPersistentStoreRemoteChange fires
                    → Partner's ViewModel re-fetches / FRC updates
                    → Partner's View updates automatically
```

### Development Workflow

- **DEBUG:** `initializeCloudKitSchema()` enabled, assertions on Core Data save failures
- **RELEASE:** Schema initialization disabled, failures logged silently
- **CloudKit Dashboard:** Inspect records, verify sync, debug sharing during development
- **TestFlight:** Distribution method for v1

## Architecture Validation Results

### Domain Guardian Validation

Validated by three domain guardians in parallel: iOS/SwiftUI Guardian, CloudKit Sync Guardian, Architecture Guardian.

| Guardian | Critical Found | Warnings Found | Verified OK | All Resolved |
|----------|---------------|----------------|-------------|-------------|
| CloudKit Sync | 6 | 6 | 13 | Yes |
| Architecture | 3 | 12 | 16 | Yes |
| iOS/SwiftUI | 4 | 4 | 17 | Yes |
| **Total** | **13** | **22** | **46** | **Yes** |

### Critical Issues Resolved

1. **CKDatabaseSubscription conflict** — Removed manual subscription. `NSPersistentCloudKitContainer` manages its own subscriptions internally.
2. **Missing `CKSharingSupported` Info.plist key** — Added to constraints and required Info.plist keys section.
3. **No CKShare acceptance handler** — Added explicit `userDidAcceptCloudKitShareWith` pattern in `CashOutApp.swift`.
4. **Conflict resolution misattributed** — Clarified: `CKRecord` change tags handle conflicts at framework level. `modifiedAt` is display/sorting only.
5. **No server change token management** — Moot: `NSPersistentCloudKitContainer` manages tokens internally.
6. **No `.changeTokenExpired` handling** — Moot: framework handles. Added reconciliation step for full re-fetch edge case.
7. **Singleton `.shared` repository** — Changed to transient `ExpenseRepository()`. Only `PersistenceController` is singleton.
8. **No app-root DI pattern** — Added explicit `CashOutApp` pattern with service instantiation.
9. **No navigation pattern** — Added per-tab `NavigationStack` ownership, sheet `@State` rules, `NavigationPath` on view not ViewModel.
10. **`NavigationStack` placement** — Explicit rule: each tab owns its own `NavigationStack`. Never wrap `TabView`.
11. **`credentialRevokedNotification` missing** — Added mid-session revocation detection.
12. **`.notFound` vs `.revoked` conflated** — Added distinct handling for all credential states.
13. **`NSPersistentCloudKitContainer` conflict resolution opaque** — Documented that framework uses `CKRecord` change tags, not app `modifiedAt`.

### Warning Issues Resolved

1. `HapticServiceProtocol` added with `MockHapticService` in test targets
2. `@ObservationIgnored` rule expanded to ALL injected dependencies
3. `.task` TabView re-fire guard pattern documented
4. Remote change notification: async sequence in `.task {}`, not `addObserver`
5. ViewModel error state: independent `data` + `errorMessage` properties
6. Repository output: always `ExpenseData` DTOs, never `NSManagedObject`
7. All Repository methods `@MainActor`-isolated
8. Zone existence check on fresh launch
9. iCloud account change (`CKAccountChanged`) handling added
10. `NSPersistentHistoryTransaction` purge strategy (7-day window)
11. Hard delete tombstone edge case with reconciliation on full re-fetch
12. Insights aggregation: single fetch + in-memory grouping by `categoryID`
13. `.glassEffect()` vs `.buttonStyle(.glass*)` usage rules clarified — never combine
14. `ExpenseRepository` explicitly `@MainActor` for FRC delegate
15. Haptics: view-associated `UIImpactFeedbackGenerator(style:view:)` for iOS 26+
16. Schema migration: versioned `.xcdatamodeld`, lightweight migration default
17. Five additional anti-patterns added (child `@State` ViewModel, ViewModel importing SwiftUI, `addObserver` in init, `Task` in `onAppear`, state mutation without cancellation check)

### Architecture Completeness Checklist

**Requirements Analysis**
- [x] Project context thoroughly analyzed
- [x] Scale and complexity assessed
- [x] Technical constraints identified (SwiftData limitation discovered via research)
- [x] Cross-cutting concerns mapped

**Architectural Decisions**
- [x] Critical decisions documented with rationale
- [x] Technology stack fully specified (Core Data + NSPersistentCloudKitContainer + SwiftUI + @Observable)
- [x] CloudKit sync architecture specified with no internal contradictions
- [x] Authentication flow covers all credential states + mid-session revocation
- [x] Navigation pattern defined (per-tab NavigationStack, sheet @State ownership)

**Implementation Patterns**
- [x] Naming conventions established (Core Data, Swift, files)
- [x] Structure patterns defined with complete directory tree
- [x] Communication patterns specified (ViewModel → View, Core Data → ViewModel, haptics)
- [x] Process patterns documented (save, DI, view, navigation, error handling, aggregation)
- [x] 12 anti-patterns documented with code examples
- [x] Liquid Glass API usage rules clarified

**Project Structure**
- [x] Complete directory structure defined (all files)
- [x] Component boundaries established (5-layer diagram)
- [x] Integration points mapped (data flow diagram)
- [x] Requirements to structure mapping complete (FR → files)

**Validation**
- [x] Three domain guardians ran in parallel
- [x] All 13 CRITICAL issues resolved
- [x] All 22 WARNING issues resolved
- [x] 46 patterns verified correct

### Architecture Readiness Assessment

**Overall Status:** READY FOR IMPLEMENTATION

**Confidence Level:** High

**Key Strengths:**
- Zero third-party dependencies — pure Apple platform stack
- Research-validated CloudKit sharing approach (SwiftData limitation caught pre-implementation)
- Clear 5-layer boundaries with testable architecture (protocol DI, mock services)
- Comprehensive pattern enforcement with 12 documented anti-patterns
- Domain guardian validation caught 13 critical specification gaps before implementation

**First Implementation Priority:**
1. Create Xcode project with capabilities (CloudKit, Sign in with Apple, Background Modes)
2. Configure `NSPersistentCloudKitContainer` with two-store setup (private + shared)
3. Create Core Data model (Expense + Category entities)
4. Verify CloudKit schema deployment via `initializeCloudKitSchema()` in DEBUG
