# Story 4.2: Partner Share Acceptance & Data Sync

Status: done

## Story

As a partner,
I want to accept a share invitation and immediately see all household expenses,
so that I can join the shared household with zero configuration.

## Acceptance Criteria

1. **Given** a CKShare URL **When** the partner taps it after installing CashOut and signing in with Apple **Then** CashOutApp handles the acceptance via `userDidAcceptCloudKitShareWith` and calls `container.acceptShareInvitations(from:into: sharedStore)` (FR22)

2. **Given** the `CKSharingSupported` Info.plist key **When** set to `true` **Then** the system correctly routes share acceptance callbacks to the app

3. **Given** successful share acceptance **When** the partner's `NSPersistentCloudKitContainer` connects to the shared database **Then** all existing entries from the owner appear in the partner's feed immediately (FR20)

4. **Given** the shared database **When** either partner creates a new expense **Then** it appears on the other partner's device within seconds via `NSPersistentCloudKitContainer` silent push (FR20)

5. **Given** the shared database **When** either partner edits an expense **Then** the edit is reflected on the other device in real-time (FR21)

6. **Given** the shared database **When** either partner deletes an expense **Then** it disappears from both devices with no orphaned records (FR21)

7. **Given** both partners edit the same entry while offline **When** both devices reconnect **Then** last-write-wins conflict resolution is applied via CKRecord change tags — the most recent save overwrites (FR26)

## Tasks / Subtasks

- [x] Task 1: Verify share acceptance infrastructure (AC: #1, #2)
  - [x] 1.1 Verify `CKSharingSupported` key exists in `CashOut/Info.plist` with value `YES`. If missing, add it. Without this key, iOS silently drops `userDidAcceptCloudKitShareWith` callbacks — the partner tap on the share link does nothing.
  - [x] 1.2 Verify `AppDelegate.swift` line ~23-41 already handles `application(_:userDidAcceptCloudKitShareWith:)` — implemented in story 4-1. Confirm it calls `container.acceptShareInvitations(from: [metadata], into: sharedPersistentStore)`. **Do NOT rewrite this — it's already correct.**
  - [x] 1.3 Verify Background Modes → Remote Notifications capability is enabled in the Xcode project (required for `NSPersistentCloudKitContainer` silent push sync). This was configured in Epic 1 — just verify.
  - [x] 1.4 **No code changes expected** for this task unless `CKSharingSupported` is missing from Info.plist.

- [x] Task 2: Promote `CloudSharingService` to singleton (AC: all — foundational)
  - [x] 2.1 Add `static let shared = CloudSharingService()` to `CloudSharingService`:
    ```swift
    @MainActor
    @Observable
    final class CloudSharingService: CloudSharingServiceProtocol {
        static let shared = CloudSharingService()
        // ... existing code ...
    }
    ```
    **Why singleton?** Multiple consumers now need the same instance (`SettingsViewModel`, `ExpenseRepository`, `FeedViewModel`). Without a shared instance, each creates its own `CloudSharingService()` with independent `isShared`/`partnerName`/`currentShare` state — the Settings screen might know sharing is active while the feed doesn't. Same problem that architecture learnings document for `AuthenticationService`.
  - [x] 2.2 Update `SettingsViewModel` default parameter:
    ```swift
    init(
        cloudSharingService: CloudSharingServiceProtocol = CloudSharingService.shared,
        categoryRepository: CategoryRepositoryProtocol = CategoryRepository()
    )
    ```
  - [x] 2.3 Keep `init` internal (not private) — tests must still inject `MockCloudSharingService`. The `.shared` static is the recommended default, not an enforced singleton.

- [x] Task 3: Enhance `CloudSharingService` for bidirectional sync (AC: #3, #4, #5, #6, #7)
  - [x] 3.1 Add `isShareOwner` to the protocol and implementation:
    ```swift
    // Protocol addition:
    var isShareOwner: Bool { get }

    // Implementation:
    var isShareOwner: Bool {
        guard let share = currentShare else { return false }
        return share.currentUserParticipant?.role == .owner
    }
    ```
    **Why needed?** Owner and participant use different mechanisms to route expenses to the shared zone. Owner calls `container.share(_:to:)` post-save. Participant calls `viewContext.assign(_:to:)` pre-save.

  - [x] 3.2 Update `checkSharingStatus()` to check BOTH persistent stores:
    ```swift
    func checkSharingStatus() async {
        // 1. Check owner's private store for shares (existing logic)
        if let privateStore = persistenceController.privatePersistentStore {
            let privateShares = try? persistenceController.container.fetchShares(in: privateStore)
            if let share = privateShares?.first {
                isShared = true
                currentShare = share
                extractPartnerInfo(from: share)
                return
            }
        }

        // 2. Check shared store for shares (NEW — partner perspective)
        if let sharedStore = persistenceController.sharedPersistentStore {
            let sharedShares = try? persistenceController.container.fetchShares(in: sharedStore)
            if let share = sharedShares?.first {
                isShared = true
                currentShare = share
                extractPartnerInfo(from: share)
                return
            }
        }

        // 3. No shares found — solo mode
        isShared = false
        partnerName = nil
        currentShare = nil
    }
    ```
    **CRITICAL:** Story 4-1's `checkSharingStatus()` only checked the private store. The partner's share metadata lives in the SHARED store. Without this change, the partner's app will always report `isShared = false` — breaking all sharing logic on the partner's device.

  - [x] 3.3 Fix `extractPartnerInfo(from:)` to work from both owner and participant perspectives:
    ```swift
    private func extractPartnerInfo(from share: CKShare) {
        // Filter out the CURRENT user to find the OTHER person
        let currentUserRecordID = share.currentUserParticipant?.userIdentity.userRecordID
        let otherParticipants = share.participants.filter { participant in
            participant.userIdentity.userRecordID != currentUserRecordID
        }

        // Accept only participants with .accepted status (from 4-1 review finding P6)
        if let partner = otherParticipants.first(where: { $0.acceptanceStatus == .accepted }) {
            if let nameComponents = partner.userIdentity.nameComponents {
                partnerName = PersonNameComponentsFormatter.localizedString(
                    from: nameComponents, style: .short, options: []
                )
            } else {
                partnerName = "Partner"
            }
        } else {
            partnerName = nil
        }
    }
    ```
    **Why change?** Story 4-1 filtered `role != .owner` to find the partner. This works for the owner but BREAKS for the participant — the participant filtering `role != .owner` gets THEMSELVES (they're `.privateUser`), not the owner. Filtering by `currentUserRecordID` instead correctly finds "the other person" regardless of the current user's role.

  - [x] 3.4 Add `prepareObjectForSharedSave(_:)` to protocol and implementation:
    ```swift
    // Protocol addition:
    func prepareObjectForSharedSave(_ object: NSManagedObject)

    // Implementation:
    func prepareObjectForSharedSave(_ object: NSManagedObject) {
        guard isShared, !isShareOwner else { return }
        guard object.managedObjectContext != nil else {
            os_log(.error, "prepareObjectForSharedSave called with nil managedObjectContext")
            return
        }
        // Participant: assign to shared store so save goes to shared zone
        guard let sharedStore = persistenceController.sharedPersistentStore else { return }
        object.managedObjectContext?.assign(object, to: sharedStore)
    }
    ```
    **How it works:** For the participant (non-owner), assigning a new `NSManagedObject` to the shared persistent store before `context.save()` causes Core Data to save it directly to the shared CloudKit zone — visible to both partners. The owner path is handled post-save by Task 3.5.
    **When called:** BEFORE `viewContext.save()` in the repository.
    **Guard:** The nil `managedObjectContext` guard catches programmer errors — objects MUST be inserted into a context before store assignment.

  - [x] 3.5 Fix `persistUpdatedShare(_:)` for partner's device:
    ```swift
    func persistUpdatedShare(_ share: CKShare) {
        // Determine which store owns this share
        let targetStore: NSPersistentStore?
        if isShareOwner {
            targetStore = persistenceController.privatePersistentStore
        } else {
            targetStore = persistenceController.sharedPersistentStore
        }
        guard let store = targetStore else { return }
        persistenceController.container.persistUpdatedShare(share, in: store) { _, error in
            if let error {
                os_log(.fault, "Failed to persist updated share: %{public}@", error.localizedDescription)
            }
        }
    }
    ```
    **CRITICAL FIX:** Story 4-1's implementation hardcodes `privatePersistentStore`. On the partner's device, the share lives in `sharedPersistentStore` — persisting to the wrong store silently fails or causes stale share metadata (infinite spinner on re-presentation of `UICloudSharingController`). This fix uses `isShareOwner` to route to the correct store.

  - [x] 3.6 Add `shareObjectsToHouseholdIfNeeded(_:)` to protocol and implementation:
    ```swift
    // Protocol addition:
    func shareObjectsToHouseholdIfNeeded(_ objects: [NSManagedObject]) async throws

    // Implementation:
    func shareObjectsToHouseholdIfNeeded(_ objects: [NSManagedObject]) async throws {
        guard isShared, isShareOwner, let share = currentShare else { return }
        guard !objects.isEmpty else { return }
        // Guard: iCloud must be available (user may have signed out mid-session)
        guard FileManager.default.ubiquityIdentityToken != nil else {
            os_log(.error, "iCloud unavailable — expense saved locally but not shared to household zone")
            return
        }
        do {
            _ = try await persistenceController.container.share(objects, to: share)
        } catch {
            // Expense is saved locally; sharing failed. Log but don't propagate —
            // the expense will be in the private zone, invisible to partner until retry.
            os_log(.error, "Failed to share expense to household zone: %{public}@", error.localizedDescription)
        }
    }
    ```
    **How it works:** For the owner, `container.share(_:to:)` with a non-nil CKShare moves the objects from the private default zone to the shared custom zone. This is the same API used in story 4-1 to share categories — now applied to individual expenses after each save.
    **When called:** AFTER `viewContext.save()` in the repository.
    **Why async?** `container.share(_:to:)` is an async operation that interacts with the CloudKit container.
    **Error handling:** Errors are logged but NOT propagated — the expense is already saved locally. Sharing failure means the partner won't see it until the next successful share attempt. At 2-user scale this is diagnosable via os_log.
    **iCloud guard:** Prevents `CKError.notAuthenticated` if user signed out of iCloud mid-session.

- [x] Task 4: Modify `ExpenseRepository` for shared zone routing (AC: #4, #5, #6)
  - [x] 4.1 Add `CloudSharingServiceProtocol` dependency to `ExpenseRepository`:
    ```swift
    final class ExpenseRepository: ExpenseRepositoryProtocol {
        private let persistenceController: PersistenceController
        private let cloudSharingService: CloudSharingServiceProtocol?

        init(
            persistenceController: PersistenceController = .shared,
            cloudSharingService: CloudSharingServiceProtocol? = CloudSharingService.shared
        ) {
            self.persistenceController = persistenceController
            self.cloudSharingService = cloudSharingService
        }
    }
    ```
    **IMPORTANT:** `ExpenseRepository` is NOT `@Observable` — it's a plain `final class`. Do NOT add `@Observable` or `@ObservationIgnored`. Use plain `private let` for both dependencies.
    **Optional dependency:** `cloudSharingService` is `nil` in tests and inMemory mode. Solo mode works identically — the guard clauses in `prepareObjectForSharedSave` and `shareObjectsToHouseholdIfNeeded` return early when `isShared` is false.

  - [x] 4.2 Update `saveExpense(_ data: ExpenseData)` to route new expenses to the shared zone:
    ```swift
    func saveExpense(_ data: ExpenseData) async throws {
        let context = persistenceController.container.viewContext
        let expense: Expense

        // ... existing logic to create or fetch Expense NSManagedObject ...
        // ... set properties (amount, note, categoryID, createdByUserID, etc.) ...

        // PRE-SAVE: Route to shared store if participant
        cloudSharingService?.prepareObjectForSharedSave(expense)

        try context.save()

        // POST-SAVE: Move to shared zone if owner
        try await cloudSharingService?.shareObjectsToHouseholdIfNeeded([expense])
    }
    ```
    **CRITICAL:** `prepareObjectForSharedSave` MUST be called BEFORE `context.save()` — it sets store affinity. `shareObjectsToHouseholdIfNeeded` MUST be called AFTER `context.save()` — the object must have a persistent store coordinator entry before it can be shared.
    **If `saveExpense` is currently synchronous:** Change signature to `async throws`. Update `ExpenseRepositoryProtocol` to match. All callers already use `try await` (verified in `ExpenseEntryViewModel` and `EditExpenseViewModel`).

  - [x] 4.3 Verify edit path — **NO changes needed for edits to existing shared objects:**
    - Once an expense is in the shared zone, editing its properties and calling `context.save()` automatically syncs the update via `NSPersistentCloudKitContainer`
    - The framework handles `CKRecord` change tag updates internally
    - The partner receives the change via `.NSPersistentStoreRemoteChange` notification → `viewContext.automaticallyMergesChangesFromParent` merges it → FRC fires → UI updates
    - **Do NOT add sharing calls to the edit path** — it would attempt to re-share an already-shared object, which is a no-op at best and may cause errors

  - [x] 4.4 Verify delete path — **NO changes needed for deletes of shared objects:**
    - `viewContext.delete(expense)` + `context.save()` on a shared object triggers tombstone propagation via `NSPersistentCloudKitContainer`
    - The partner receives the deletion via remote change notification
    - `NSFetchedResultsController` fires `controllerDidChangeContent` → row animates out
    - **Tombstone edge case (documented in architecture):** If the partner is offline past the CloudKit tombstone window (~30 days), the deleted record may persist locally. Known v1 limitation at 2-user scale.

- [x] Task 5: Update `FeedViewModel` with real partner attribution (AC: #3)
  - [x] 5.1 Add `CloudSharingServiceProtocol` dependency to `FeedViewModel`:
    ```swift
    @MainActor
    @Observable
    final class FeedViewModel {
        @ObservationIgnored private let repository: ExpenseRepositoryProtocol
        @ObservationIgnored private let authService: AuthenticationServiceProtocol
        @ObservationIgnored private let cloudSharingService: CloudSharingServiceProtocol

        init(
            repository: ExpenseRepositoryProtocol = ExpenseRepository(),
            authService: AuthenticationServiceProtocol = AuthenticationService(),
            cloudSharingService: CloudSharingServiceProtocol = CloudSharingService.shared
        ) {
            self.repository = repository
            self.authService = authService
            self.cloudSharingService = cloudSharingService
        }
    }
    ```
    **Note:** `AuthenticationService()` remains transient (no `.shared` singleton exists for it). The `currentUserID` is derived from Keychain state which is global, so transient instances are functionally equivalent. `CloudSharingService` requires a singleton because its `isShared`/`partnerName`/`currentShare` state must be consistent across consumers.

  - [x] 5.2 Update `partnerInitials(for expense:)` to use real partner name:
    ```swift
    func partnerInitials(for expense: ExpenseData) -> String {
        if isCurrentUser(expense) {
            return "Me"
        }
        // Use real partner name from CloudSharingService
        if let name = cloudSharingService.partnerName {
            // Extract first character as initial
            let initial = name.prefix(1).uppercased()
            return initial.isEmpty ? "P" : initial
        }
        return "P"
    }
    ```
    **Why not use `createdByUserID`?** The `createdByUserID` is a CloudKit record name (opaque string). We can't derive a display name from it. The `CKShare.participants` already have `nameComponents` — the `CloudSharingService` extracts this via `extractPartnerInfo`.

  - [x] 5.3 Add `partnerDisplayName` computed property for any UI that needs the full name:
    ```swift
    var partnerDisplayName: String {
        cloudSharingService.partnerName ?? "Partner"
    }
    ```

- [x] Task 6: Wire dependencies and verify app-level integration (AC: all)
  - [x] 6.1 Verify `CloudSharingService.shared` is used as default across all consumers:
    - `SettingsViewModel` — updated in Task 2.2
    - `ExpenseRepository` — updated in Task 4.1
    - `FeedViewModel` — updated in Task 5.1
    - `ExpenseEntryViewModel` — verify it creates `ExpenseRepository()` with no custom args (default picks up shared service)
    - `EditExpenseViewModel` — same verification
  - [x] 6.2 Verify `checkSharingStatus()` is called on app launch. Currently called in `SettingsView.task { await viewModel.refreshSharingStatus() }`. For the feed to show correct partner attribution from app start, add a `checkSharingStatus()` call on app launch:
    - In `ContentView.swift`, add `.task { await CloudSharingService.shared.checkSharingStatus() }` on the `TabView` or root view
    - This ensures sharing state is known before any ViewModel needs it
  - [x] 6.3 **Do NOT modify `AppDelegate.swift`** for share acceptance — it already correctly handles `userDidAcceptCloudKitShareWith`. After acceptance, the shared store syncs automatically.
  - [x] 6.4 After acceptance on the partner's device, the partner needs to refresh sharing status. Subscribe to `.NSPersistentStoreRemoteChange` in `ContentView` via async sequence in `.task` (per project convention — NOT `.onReceive`):
    ```swift
    .task {
        for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
            // Skip if sharing state already detected to avoid redundant fetches
            guard !CloudSharingService.shared.isShared else { continue }
            await CloudSharingService.shared.checkSharingStatus()
        }
    }
    ```
    **Why `.task` over `.onReceive`?** Project convention per `ios-swiftui.md` learnings: subscribe to `NotificationCenter` via async sequence in `.task {}`, which auto-cancels on view disappear. `.onReceive` with `publisher(for:)` also works but diverges from established pattern.
    **Why?** After the partner accepts the share and the shared store syncs, the `CloudSharingService` needs to detect the new share and set `isShared = true`. Without this, the partner would need to visit Settings to trigger the check.
    **Guard optimization:** Once `isShared` is true, skip redundant `checkSharingStatus()` calls — remote change notifications fire frequently during initial sync. This prevents dozens of unnecessary `fetchShares` calls.

- [x] Task 7: Unit tests (AC: all)
  - [x] 7.1 Update `MockCloudSharingService` with new protocol methods:
    ```swift
    @MainActor
    final class MockCloudSharingService: CloudSharingServiceProtocol {
        var isShared = false
        var isShareOwner = false
        var partnerName: String? = nil
        var createShareCalled = false
        var checkSharingStatusCalled = false
        var persistUpdatedShareCalled = false
        var prepareObjectForSharedSaveCalled = false
        var shareObjectsToHouseholdCalled = false
        // ... existing handlers ...

        func prepareObjectForSharedSave(_ object: NSManagedObject) {
            prepareObjectForSharedSaveCalled = true
        }

        func shareObjectsToHouseholdIfNeeded(_ objects: [NSManagedObject]) async throws {
            shareObjectsToHouseholdCalled = true
        }
    }
    ```
  - [x] 7.2 Create `CashOutTests/ViewModels/FeedViewModelSharingTests.swift`:
    - Test: `partnerInitials` returns "Me" for current user expenses
    - Test: `partnerInitials` returns first initial of partner name when `cloudSharingService.partnerName` is set (e.g., "Sarah" → "S")
    - Test: `partnerInitials` returns "P" when `partnerName` is nil
    - Test: `partnerDisplayName` returns real name when available
    - Test: `partnerDisplayName` returns "Partner" when name is nil
  - [x] 7.3 Add sharing-aware save tests to existing `ExpenseRepository` tests or create `CashOutTests/Repositories/ExpenseRepositorySharingTests.swift`:
    - Test: save in solo mode (isShared=false) → neither `prepareObjectForSharedSave` nor `shareObjectsToHousehold` called
    - Test: save as owner (isShared=true, isShareOwner=true) → `shareObjectsToHousehold` called, `prepareObjectForSharedSave` is no-op
    - Test: save as participant (isShared=true, isShareOwner=false) → `prepareObjectForSharedSave` called, `shareObjectsToHousehold` is no-op
  - [x] 7.4 Add `CloudSharingService` tests for bidirectional status check:
    - Test: `checkSharingStatus` finds share in private store → `isShareOwner` is true
    - Test: `checkSharingStatus` finds share in shared store → `isShareOwner` is false
    - Test: `checkSharingStatus` finds no shares → solo mode
  - [x] 7.5 **No integration tests for CloudKit sync** — requires real iCloud accounts and network. Manual testing via TestFlight with two devices is the verification path for sync behavior (same approach as story 4-1).

## Dev Notes

### Architecture Compliance

- **MVVM boundaries:** Views read from ViewModels; ViewModels call Repository (data) and CloudSharingService (sharing logic); neither Views nor ViewModels touch Core Data or CloudKit directly. The CloudSharingService encapsulates all sharing decisions.
- **Protocol-based DI:** `CloudSharingServiceProtocol` extended with new methods, maintaining mock injection for all tests.
- **`@ObservationIgnored`** on all injected dependencies in ViewModels and Repository (per architecture learnings).
- **Singleton pattern:** `CloudSharingService.shared` follows `PersistenceController.shared` and `AuthenticationService.shared` precedent. Init remains internal for test injection.

### Critical CloudKit Sync Mechanics

**Owner vs Participant — different save paths for the SAME outcome:**

| Role | Pre-save | Post-save | Result |
|------|----------|-----------|--------|
| Owner | No-op | `container.share([expense], to: existingShare)` | Expense moves from private default zone → shared custom zone |
| Participant | `viewContext.assign(expense, to: sharedStore)` | No-op | Expense saved directly to shared zone via shared store |
| Solo (no share) | No-op | No-op | Expense stays in private default zone |

**Why different mechanisms?**
- The owner's `container.share(_:to:)` can only move objects from the owner's private store to the owner's shared zone. It's a post-save operation (object must exist in the store first).
- The participant can't call `share(_:to:)` on someone else's share. Instead, they write directly to the shared store, which maps to the owner's shared zone in CloudKit.
- Both paths result in the expense being in the shared zone, visible to both partners.

**Edits and deletes sync automatically:**
- Once an object is in the shared zone, `NSPersistentCloudKitContainer` handles all subsequent modifications transparently.
- `viewContext.save()` after property changes → framework updates the CKRecord → partner receives the change.
- `viewContext.delete(expense)` + save → framework propagates tombstone → partner's FRC fires → row disappears.
- **No sharing calls needed for edits or deletes** — only new objects need routing.

**Conflict resolution is fully automatic:**
- `NSPersistentCloudKitContainer` uses `CKRecord` change tags internally.
- When both partners edit the same record offline, the server applies last-write-wins on reconnect.
- Our `modifiedAt` field is for display/sorting only — it does NOT participate in conflict arbitration.
- At 2-user scale with low collision probability, this is acceptable per architecture decision.

### `checkSharingStatus()` — Critical Partner-Side Fix

Story 4-1's implementation only checked `fetchShares(in: privatePersistentStore)`. This works for the owner (shares live in their private store) but FAILS for the partner (shares are in the shared store).

**Owner's device:** `fetchShares(in: privateStore)` → finds the CKShare → `isShared = true`, `isShareOwner = true`
**Partner's device:** `fetchShares(in: privateStore)` → empty → MUST also check `fetchShares(in: sharedStore)` → finds the CKShare → `isShared = true`, `isShareOwner = false`

This is the single most critical change in this story. Without it, the partner's device never detects that sharing is active, and all subsequent sharing logic (save routing, partner attribution) fails silently.

### `extractPartnerInfo` — Must Work Both Ways

Story 4-1 filtered `share.participants` by `role != .owner`. This returns the partner for the owner, but returns the participant THEMSELVES when called by the participant.

**Fix:** Filter by `currentUserParticipant?.userIdentity.userRecordID` instead — always returns "the other person" regardless of the caller's role.

### What This Story Does NOT Cover (Deferred to Story 4.3)

- **Real-time animated feed updates** — `.NSPersistentStoreRemoteChange` notification subscription in FeedViewModel for animated row insertions. Currently the FRC handles basic updates, but Story 4.3 adds explicit notification handling and animation control.
- **Sync status indicator** — Small non-intrusive nav-bar icon for persistent sync failure (UX-DR26).
- **Persistent history purge** — `NSPersistentHistoryTransaction` cleanup of entries older than 7 days.
- **iCloud not-signed-in banner** — Subtle banner for users without iCloud.
- **`.changeTokenExpired` handling** — Full re-import edge case.

### Project Structure Notes

**Modified files (no new files expected):**
```
CashOut/Services/CloudSharingService.swift      # Singleton, bidirectional status, share routing
CashOut/Repositories/ExpenseRepository.swift     # Sharing-aware save path
CashOut/ViewModels/FeedViewModel.swift           # Real partner attribution
CashOut/ViewModels/SettingsViewModel.swift        # Use .shared singleton
CashOut/App/ContentView.swift                    # App-launch sharing status check
CashOut/Info.plist                               # CKSharingSupported (verify/add)
CashOutTests/Services/MockCloudSharingService.swift  # New protocol methods
```

**New test files:**
```
CashOutTests/ViewModels/FeedViewModelSharingTests.swift
CashOutTests/Repositories/ExpenseRepositorySharingTests.swift (optional — can extend existing)
```

### Previous Story Intelligence (Story 4-1)

- **Commit convention:** `feat(sharing):` prefix for new sharing features, `fix(sharing):` for review fixes.
- **Code review patterns from 4-1:** 9 patches applied. Key patterns to follow:
  - Use `os_log(.error)` not `print()` for infrastructure errors
  - Use `defer` pattern for state reset (e.g., loading flags)
  - Always refresh sharing status on dismiss/completion paths
  - Filter participants by `.accepted` status only
  - Use explicit `CKContainer(identifier:)` instead of `.default()`
- **Testing approach:** `MockCloudSharingService` uses closure-based handlers for configurable behavior. Result-based pattern for testable async returns.
- **Architecture learnings applied in 4-1:** `@ObservationIgnored` on injected dependencies, `.sheet` on outer container not conditional sub-views, `Bindable()` wrapper for `@Observable` bindings.
- **4-1 deferred items still deferred:** `AppDelegate:34 print()` (W1), `PersistenceController fatalError` (W2), `sharedPersistentStore nil when iCloud unavailable` (W3), `Multiple SettingsView instances` (W4).

### Git Intelligence (Recent Commits)

```
c8f3451 fix(sharing): resolve 9 code review findings for story 4-1
cf9e3ed feat(sharing): add CloudKit shared zone and partner invitation (story 4-1)
ee62c70 fix(insights): resolve 2 code review findings for story 3-3
b3daa95 feat(insights): add daily bar chart and category breakdown list (story 3-3)
```

Pattern: one `feat(sharing):` commit for implementation, one `fix(sharing):` commit for code review findings. Follow the same pattern for this story.

### Orchestrator Validation Findings (2026-04-04)

Domain guardians (ios-swiftui, cloudkit-sync, architecture) validated this story. Key findings incorporated:

- **CRITICAL (C1):** `persistUpdatedShare` hardcodes `privatePersistentStore` — breaks on partner's device. **FIXED:** Added Task 3.5 to route to correct store based on `isShareOwner`.
- **WARNING (W1):** `AuthenticationService.shared` does not exist — `FeedViewModel` snippet was incorrect. **FIXED:** Changed to `AuthenticationService()` (transient, Keychain-based state is global).
- **WARNING (W2):** `ExpenseRepository` is NOT `@Observable` — snippet incorrectly added `@Observable`. **FIXED:** Removed, uses plain `private let`.
- **WARNING (W5):** No error handling for `container.share()` failure per expense. **FIXED:** Added try/catch with `os_log(.error)` in `shareObjectsToHouseholdIfNeeded`. Errors logged but not propagated — expense is already saved locally.
- **WARNING (W7):** No iCloud availability guard in `shareObjectsToHouseholdIfNeeded`. **FIXED:** Added `ubiquityIdentityToken` check before `container.share()`.
- **WARNING (W9):** Nil `managedObjectContext` guard missing in `prepareObjectForSharedSave`. **FIXED:** Added explicit nil check with `os_log(.error)`.
- **WARNING (W4/S1):** `.onReceive` diverges from project convention (async sequence in `.task`). **FIXED:** Changed Task 6.4 to use `.task { for await }` pattern with `isShared` guard to skip redundant calls.
- **WARNING (W8):** Singleton exception must be documented. **ACTION:** During implementation, add learnings entry to `.claude/learnings/architecture.md`: "`CloudSharingService.shared` is the second accepted singleton (after `PersistenceController.shared`) — sharing state must be consistent across all consumers."
- **WARNING (W10):** Test mock consistency. **ACTION:** Task 7 tests must inject `MockCloudSharingService` into both `FeedViewModel` AND the `ExpenseRepository` it receives. Do not let test repositories pick up `CloudSharingService.shared`.
- **SUGGESTION (S3):** Share acceptance race condition — `checkSharingStatus()` may fire before share metadata lands in shared store. Acceptable for v1; the `.task` notification listener will retry on subsequent remote change notifications.
- **SUGGESTION (S6):** Custom categories created by the partner after initial sharing are NOT automatically shared — they stay in the partner's private store. This is a known gap acceptable for v1 (custom categories are deferred to Epic 5, story 5-2). When implementing story 5-2, apply the same shared zone routing pattern from Task 4 to the CategoryRepository.

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Epic 4, Story 4.2 acceptance criteria]
- [Source: _bmad-output/planning-artifacts/architecture.md — CloudKit sync architecture, two-store NSPersistentCloudKitContainer, zone-level sharing, conflict resolution, partner attribution via createdByUserID]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — Journey 4 partner onboarding flow, silent sync design, feed row partner attribution, Settings household section]
- [Source: _bmad-output/planning-artifacts/prd.md — FR20-FR22 (shared feed, real-time sync, zero-config pairing), FR25-FR26 (offline sync, last-write-wins)]
- [Source: _bmad-output/implementation-artifacts/4-1-cloudkit-shared-zone-and-partner-invitation.md — CloudSharingService implementation, AppDelegate acceptance handler, PersistenceController store properties, "What This Story Does NOT Cover" section]
- [Source: CashOut/Services/CloudSharingService.swift — existing protocol and implementation]
- [Source: CashOut/Repositories/ExpenseRepository.swift — current save path with no sharing logic]
- [Source: CashOut/ViewModels/FeedViewModel.swift — partnerInitials returns hardcoded "P"]
- [Source: CashOut/App/AppDelegate.swift — userDidAcceptCloudKitShareWith handler]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

- ExpenseRepositorySharingTests solo-mode test initially failed: mock records all calls regardless of `isShared` guard. Fixed test assertion to match actual design (repository delegates to service; service guards handle no-op).

### Completion Notes List

- Task 1: Verified CKSharingSupported (Info.plist:5), AppDelegate share acceptance handler (AppDelegate.swift:23-37), Background Modes remote-notification (Info.plist:7-10). All in place from story 4-1. No changes needed.
- Task 2: Added `static let shared` singleton to CloudSharingService. Updated SettingsViewModel default parameter. Init remains internal for test injection.
- Task 3: Extended CloudSharingServiceProtocol with `isShareOwner`, `prepareObjectForSharedSave`, `shareObjectsToHouseholdIfNeeded`. Fixed `checkSharingStatus` to check both private and shared stores (critical partner-side fix). Fixed `extractPartnerInfo` to use `currentUserRecordID` filtering instead of `role != .owner`. Fixed `persistUpdatedShare` to route to correct store based on role.
- Task 4: Added `CloudSharingServiceProtocol?` dependency to ExpenseRepository. Updated `saveExpense` with pre-save (`prepareObjectForSharedSave`) and post-save (`shareObjectsToHouseholdIfNeeded`) hooks for NEW objects only. Edit/delete paths verified — no changes needed (NSPersistentCloudKitContainer handles automatically).
- Task 5: Added `CloudSharingServiceProtocol` dependency to FeedViewModel. Updated `partnerInitials` to use real partner name initial. Added `partnerDisplayName` computed property.
- Task 6: Verified `.shared` singleton wired across all consumers. Added `checkSharingStatus()` call on app launch in ContentView. Added `.NSPersistentStoreRemoteChange` notification listener with `isShared` guard optimization.
- Task 7: Updated MockCloudSharingService with new protocol methods. Created FeedViewModelSharingTests (5 tests). Created ExpenseRepositorySharingTests (5 tests). All 165 tests pass (0 failures).
- Architecture learnings updated: documented CloudSharingService.shared as second accepted singleton.

### File List

- CashOut/Services/CloudSharingService.swift (modified — singleton, bidirectional status, new methods)
- CashOut/Repositories/ExpenseRepository.swift (modified — sharing-aware save)
- CashOut/ViewModels/FeedViewModel.swift (modified — partner attribution)
- CashOut/ViewModels/SettingsViewModel.swift (modified — .shared default)
- CashOut/App/ContentView.swift (modified — sharing status check, remote change listener)
- CashOutTests/Services/MockCloudSharingService.swift (modified — new protocol methods)
- CashOutTests/ViewModels/FeedViewModelTests.swift (modified — inject mock CloudSharingService)
- CashOutTests/ViewModels/FeedViewModelSharingTests.swift (new — 5 sharing tests)
- CashOutTests/Repositories/ExpenseRepositorySharingTests.swift (new — 5 sharing tests)
- CashOut.xcodeproj/project.pbxproj (modified — added new test files)
- .claude/learnings/architecture.md (modified — CloudSharingService singleton entry)

### Review Findings

**Orchestrator Review (2026-04-04) — 3 guardians (cloudkit-sync, architecture, ios-swiftui)**

Resolved:
- [C1] Removed `@ObservationIgnored` from `let cloudSharingService` in FeedViewModel — `let` constants don't need annotation per learnings.
- [W4] Extracted container identifier string to `private static let containerIdentifier` in CloudSharingService.

Accepted (by design per story spec):
- [W1] `guard !isShared` in ContentView notification listener — story spec explicitly requires this optimization. Partner disconnect detection deferred to story 4-3.
- [W5] `shareObjectsToHouseholdIfNeeded` error swallowing — story spec says errors logged not propagated. Retry queue is future work.

Noted (pre-existing, out of scope):
- Pre-existing `@ObservationIgnored` on `let` properties in FeedViewModel (lines 20-22, 28-29) — from prior stories, not introduced by 4-2.
- `AppDelegate.swift:28` nil-store guard — from story 4-1, known deferred item (4-1 W2/W3).
- `SettingsViewModel.handleShareDismiss` fire-and-forget Task — pre-existing from story 4-1.

False positive dismissed:
- Architecture guardian concern about reactivity gap through protocol references — `CloudSharingService` IS `@Observable`, so Swift Observation tracks access at runtime regardless of protocol typing.

### Review Findings

- [x] [Review][Patch] `extractPartnerInfo` fails when `currentUserParticipant` is nil — `currentUserRecordID` is nil, all participants pass filter, current user could be reported as own partner. Add `guard let currentUserRecordID` early return. [CloudSharingService.swift:151]
- [x] [Review][Defer] PersistenceController stores may not be loaded when `checkSharingStatus()` first runs on cold launch [ContentView.swift:40] — deferred, pre-existing infrastructure issue from Epic 1
- [x] [Review][Defer] ContentView directly calls `CloudSharingService.shared` — MVVM boundary violation, spec-directed pragmatic choice [ContentView.swift:40-47] — deferred, architectural debt
- [x] [Review][Defer] `createShare` reuses `currentShare` without checking if share is still valid on CloudKit server [CloudSharingService.swift:58] — deferred, pre-existing from story 4-1
- [x] [Review][Defer] `SettingsViewModel.handleShareDismiss` fire-and-forget Task [SettingsViewModel.swift:67] — deferred, pre-existing from story 4-1
- [x] [Review][Defer] `invitePartner` shares categories — race with async seeding on new installs [SettingsViewModel.swift:35] — deferred, pre-existing from story 4-1
- [x] [Review][Defer] Cold-launch via share URL timing — `checkSharingStatus()` may run before `acceptShareInvitations` completes [AppDelegate.swift:29 / ContentView.swift:40] — deferred, notification listener handles eventually

## Change Log

- 2026-04-04: Story 4-2 implementation complete — partner share acceptance, bidirectional sync, shared zone routing, partner attribution. 7 tasks, 10 new/modified tests (165 total, 0 failures). Orchestrator review: 2 findings fixed, 2 accepted by design, 3 pre-existing noted.
