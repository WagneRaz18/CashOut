# Code Review Checklist

Quick reference checklist for CashOut code reviews.

---

## Guardian Delegation

- [ ] `ios-swiftui-guardian` — for SwiftUI views, SwiftData models, Sign in with Apple, iOS platform
- [ ] `cloudkit-sync-guardian` — for CloudKit operations, CKRecord/CKShare, sync, offline queue, conflicts
- [ ] `architecture-guardian` — for ViewModels, state, DI, navigation, data layer

---

## Security & Privacy

- [ ] No household data in public CloudKit database
- [ ] User identifier stored in Keychain, not UserDefaults
- [ ] No spending data logged or sent to third-party services
- [ ] CKShare participant permission is `.readWrite` for partner, not `.readOnly`
- [ ] Sign in with Apple credential state checked on launch

---

## SwiftUI (delegate to ios-swiftui-guardian)

- [ ] NavigationStack path is `@State` on view, not on external object
- [ ] No nested NavigationStack instances
- [ ] `@State` only on owner view — children use `let` or `@Bindable`
- [ ] No expensive work in `@Observable` init
- [ ] Services on ViewModels marked `@ObservationIgnored`
- [ ] Using `@Observable`, not `ObservableObject`/`@Published`

---

## SwiftData (delegate to ios-swiftui-guardian)

- [ ] Models use `VersionedSchema` from day one
- [ ] No `#Predicate` on computed properties or `.externalStorage` properties
- [ ] Models not passed across actors — only `PersistentIdentifier`
- [ ] UI-driving writes via `container.mainContext`
- [ ] Relationships not assigned in model `init()`
- [ ] Cascade delete + autosave interaction handled
- [ ] `@Attribute(.externalStorage)` for Data > ~100KB

---

## Architecture (delegate to architecture-guardian)

- [ ] Owner view: `@State var vm`. Children: `let` or `@Bindable`
- [ ] ViewModels do NOT import SwiftUI or hold NavigationPath
- [ ] No `@Query` in ViewModel (only works in views)
- [ ] No single `enum ViewState` — use independent properties
- [ ] DI: app-wide via `.environment()`, ViewModel-local via `init()`
- [ ] ViewModels not injected through environment

---

## Async & Tasks

- [ ] Prefer `.task {}` for view-lifetime async work
- [ ] No `Task {}` in body/onAppear without stored reference on ViewModel
- [ ] Task cancellation is cooperative — `Task.isCancelled` checked
- [ ] `.task` on view OR stored Task on ViewModel — not both

---

## CloudKit Sync (delegate to cloudkit-sync-guardian)

- [ ] All records in custom zone, never default zone
- [ ] Zone existence checked before record saves
- [ ] `CKModifyRecordsOperation.savePolicy` explicitly set
- [ ] `CKError.serverRecordChanged` handled — extract server record, apply changes, retry
- [ ] Offline operations persisted to disk, not in-memory
- [ ] CKRecord system fields persisted via `encodeSystemFields`
- [ ] Server change tokens persisted (database-level AND zone-level)
- [ ] Token committed only after records saved locally
- [ ] Batch operations max 400 records
- [ ] `CKDatabaseSubscription` with `shouldSendContentAvailable = true`
- [ ] Subscription creation is idempotent (check flag before saving)
- [ ] Parent-child hierarchy uses `setParent()`, not custom reference only

---

## Sign in with Apple

- [ ] Credential state checked on every app launch
- [ ] `.revoked` and `.notFound` handled properly
- [ ] Registered for `credentialRevokedNotification`
- [ ] User info (email, name) saved on FIRST authorization only
- [ ] User identifier in Keychain, not UserDefaults

---

## Offline Queue

- [ ] Pending ops persisted as model objects, not in-memory
- [ ] Network changes via `NWPathMonitor` on background queue
- [ ] Retry uses `CKErrorRetryAfterKey` when present, else exponential backoff
- [ ] Both `.requestRateLimited` and `.serviceUnavailable` handled

---

## Logging & Observability (see [logging.md](logging.md))

- [ ] Changed files with business logic have `import os.log` and a `Logger` instance
- [ ] Logger uses `subsystem: "com.wagneraz.CashOut"` and `category:` matching the type name
- [ ] Every `catch` block and error branch logs at `.error` or `.fault` level
- [ ] Sensitive data (userID, email, names, amounts) uses `privacy: .private` annotation
- [ ] Non-sensitive operational data (counts, status, durations) uses `privacy: .public`
- [ ] Public/internal methods with business logic have entry-point logs
- [ ] Async operations (network, CloudKit, background tasks) log at start AND completion
- [ ] Log levels match severity: `.debug` for diagnostics, `.info` for events, `.error` for failures
- [ ] Log messages follow format: `"methodName: description — details"`
- [ ] No `print()` or `debugPrint()` statements — use Logger instead

---

## KISS Metrics

| Metric | Max |
|--------|-----|
| Function lines | 30 |
| Type lines | 200 |
| File lines | 500 |
| Parameters | 5 |
| Nesting depth | 3 |

---

## Verdict Criteria

| Verdict | Condition |
|---------|-----------|
| **APPROVE** | Zero critical, zero warnings |
| **APPROVE WITH CHANGES** | Zero critical, minor warnings |
| **REQUEST CHANGES** | Non-critical issues requiring changes |
| **BLOCK** | ANY critical violation present |
