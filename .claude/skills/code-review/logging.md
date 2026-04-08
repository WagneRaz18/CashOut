# Logging Validation Reference

Rules and patterns for validating meaningful logging in CashOut code changes.

---

## Logging Standard

CashOut uses Apple's unified logging (`os.log`) with:
- **Subsystem**: `"com.wagneraz.CashOut"` (always)
- **Category**: matches the type name (e.g., `"ExpenseRepository"`, `"FeedViewModel"`)
- **Declaration**: file-level `private let logger = Logger(subsystem:category:)`

---

## Required Log Coverage

Every changed `.swift` file that contains **business logic, service calls, or state mutations** must have a `Logger` instance and meaningful logs at these points:

### 1. Error Paths (CRITICAL — LOG-002)

Every `catch` block and error-handling branch MUST log at `.error` or `.fault` level.

```swift
// CORRECT: Error path logged
do {
    try context.save()
} catch {
    logger.error("saveExpense: context.save() failed — \(error.localizedDescription)")
}

// CORRECT: Result failure branch logged
case .failure(let error):
    logger.error("fetchRecords: CKQuery failed — \(error.localizedDescription)")

// WRONG: Silent catch — invisible failures
do {
    try context.save()
} catch {
    // Nothing logged — failure is invisible in production
}
```

### 2. Privacy Annotations (CRITICAL — LOG-003)

User-identifiable data (names, emails, userIDs, amounts) MUST use privacy annotations. Non-sensitive operational data (counts, status enums, durations) should be `.public` for debuggability.

```swift
// CORRECT: Sensitive data redacted by default
logger.info("signIn: authenticated userID=\(userID, privacy: .private)")

// CORRECT: Operational data marked public for debugging
logger.info("fetchExpenses: returned \(count, privacy: .public) records in \(elapsed, privacy: .public)ms")
logger.debug("syncStatus changed: \(String(describing: newStatus), privacy: .public)")

// WRONG: Sensitive data with no annotation (redacted by default — OK for privacy,
//        but if you need to debug, explicitly mark .private to signal intent)
logger.info("signIn: user=\(email)")  // Ambiguous — intentionally private or forgotten?

// WRONG: Sensitive data explicitly made public
logger.info("signIn: email=\(email, privacy: .public)")  // PII exposed in log stream
```

### 3. Function Entry Points (WARNING — LOG-004)

Public/internal methods that perform meaningful work should log at entry with key parameters. This enables execution flow tracing.

```swift
// CORRECT: Entry point with context
func saveExpense(_ data: ExpenseData) async throws {
    logger.info("saveExpense: amount=\(data.amount, privacy: .public) category=\(data.categoryName, privacy: .public)")
    // ...
}

// CORRECT: Guard/early-return logged
func checkAuth() async {
    guard !hasChecked else {
        logger.debug("checkAuth: already checked — skipped")
        return
    }
    logger.info("checkAuth: checking cached credential state")
    // ...
}

// WRONG: No entry log — can't tell if method was called
func saveExpense(_ data: ExpenseData) async throws {
    try context.save()  // If this fails, you don't know what was being saved
}
```

### 4. Async Operations (WARNING — LOG-005)

Async work (network calls, CloudKit operations, background tasks) should log at start AND completion/failure. This reveals timing issues and stuck operations.

```swift
// CORRECT: Async operation bracketed
func syncPendingChanges() async {
    logger.info("syncPendingChanges: starting — \(pendingOps.count, privacy: .public) ops queued")
    do {
        let result = try await cloudKitService.pushChanges(pendingOps)
        logger.info("syncPendingChanges: completed — \(result.saved, privacy: .public) saved, \(result.failed, privacy: .public) failed")
    } catch {
        logger.error("syncPendingChanges: failed — \(error.localizedDescription)")
    }
}

// WRONG: No completion log — can't distinguish "slow" from "stuck"
func syncPendingChanges() async {
    logger.info("syncPendingChanges: starting")
    try? await cloudKitService.pushChanges(pendingOps)
    // Did it finish? How long did it take? Did it succeed?
}
```

### 5. State Changes (SUGGESTION — LOG-006)

Important state transitions (auth state, sync status, connectivity) should be logged to diagnose user-reported issues.

```swift
// CORRECT: State transition logged
func updateSyncStatus(_ newStatus: SyncStatus) {
    let oldStatus = syncStatus
    syncStatus = newStatus
    logger.info("syncStatus: \(String(describing: oldStatus), privacy: .public) -> \(String(describing: newStatus), privacy: .public)")
}
```

---

## Log Level Guide

| Level | Use For | Persistence |
|-------|---------|-------------|
| `.debug` | Detailed diagnostics, loop iterations, intermediate values | Discarded unless streaming |
| `.info` | Significant events: method entry, operation results, state changes | Persisted until storage pressure |
| `.notice` | Notable but expected events (default level) | Persisted until storage pressure |
| `.error` | Recoverable errors: failed saves, network errors, bad input | Persisted longer |
| `.fault` | Programmer errors, unrecoverable states, assertion-level issues | Persisted across reboots |
| `.warning` | Unexpected but handled conditions: fallbacks, deprecation paths | Persisted until storage pressure |

**Rules of thumb:**
- Happy path entry/exit: `.info`
- Guard/early-return skips: `.debug`
- Error/catch branches: `.error`
- "This should never happen": `.fault`
- Verbose loop/iteration detail: `.debug`

---

## Files Exempt from Logging Requirements

Not every file needs a Logger. Skip logging validation for:
- **Pure model files** (`@Model` classes, simple structs/enums with no logic)
- **SwiftUI view files** that only compose other views (no business logic)
- **Protocol definitions** and extensions that only add computed properties
- **Test files** (`*Tests.swift`, `Mock*.swift`)
- **App entry point** (`@main` struct) — unless it contains setup logic

**Files that MUST have logging:**
- ViewModels (`*ViewModel.swift`)
- Services (`*Service.swift`)
- Repositories (`*Repository.swift`)
- Controllers (`*Controller.swift`)
- Any file with `async` methods, `try`/`catch`, or CloudKit operations

---

## Naming Convention

```swift
// File-level declaration — ALWAYS this pattern
private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "TypeName")

// Log message format: "methodName: description — details"
logger.info("saveExpense: saved successfully — id=\(id, privacy: .public)")
logger.error("saveExpense: context.save() failed — \(error.localizedDescription)")
logger.debug("fetchCategories: found \(count, privacy: .public) results (pre-dedup)")
```

**Message format rules:**
- Start with method name for greppability
- Use `:` after method name
- Use `—` (em dash) to separate description from details
- Include relevant context values (counts, IDs, status)
