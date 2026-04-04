# CloudKit Sync & Sharing

<!-- One line per learning, brief and actionable -->

## Shared Database Setup
- SwiftData does NOT support CloudKit shared databases (confirmed through iOS 26). Must use Core Data + NSPersistentCloudKitContainer.
- NSPersistentCloudKitContainer requires two NSPersistentStoreDescription configs: private scope + shared scope.
- The shared zone is framework-managed via `NSPersistentCloudKitContainer.share(_:to: nil)` — do NOT create a raw `CKRecordZone("HouseholdZone")`. The framework names the zone internally.
- Info.plist must contain `CKSharingSupported = true` or partner join callbacks silently fail.
- Zone existence must be re-verified on every fresh launch — users can delete zones via iOS Settings → iCloud.

## CKRecord Types & Schema
- Run `initializeCloudKitSchema()` only in DEBUG builds to deploy schema to CloudKit container.
- Store `encodeSystemFields` data with each record to preserve zone metadata and prevent infinite conflict loops.

## CKShare & Participant Management
- Use zone-level sharing (CKShare per zone), not hierarchical record sharing — simpler for 2-user household.
- UICloudSharingController is UIKit — needs UIViewControllerRepresentable wrapper for SwiftUI.
- **CAUTION (iOS 17 only):** `container.share()` was reported to deadlock on iOS 17 unless called from `CKShareTransferRepresentation.prepareShare`. Tested and working on iOS 26+ with `UICloudSharingController(share:container:)` pattern. Risk accepted for iOS 26+ minimum target (Story 4-1 decision D1, 2026-04-04).
- Always use `CKContainer(identifier: "iCloud.com.wagneraz.CashOut")` — never `CKContainer.default()` — to ensure container matches `PersistenceController` config.
- Before calling `container.share()`, check `FileManager.default.ubiquityIdentityToken != nil` — if iCloud is signed out, throw a user-friendly error instead of letting `CKError.notAuthenticated` propagate.
- Reuse existing `CKShare` when re-presenting share sheet — calling `container.share(objects, to: nil)` multiple times creates duplicate CKShares in separate zones.
- Filter `CKShare.participants` for `.accepted` acceptance status when displaying partner info — pending/removed participants should not show as connected.
- App must implement `userDidAcceptCloudKitShareWith` and call `container.acceptShareInvitations(from:into:)` for partner join flow. There is NO `container.accept(metadata)` convenience method on NSPersistentCloudKitContainer.
- `.onCKShareAccepted` is NOT a real SwiftUI scene modifier — use `UIApplicationDelegate.userDidAcceptCloudKitShareWith` for share acceptance.
- **2026-04-04**: `checkSharingStatus()` must check BOTH `privatePersistentStore` and `sharedPersistentStore` — the owner's share metadata lives in the private store, but the partner's share metadata lives in the shared store. Checking only private store silently fails for the partner.
- **2026-04-04**: `extractPartnerInfo` must filter by `currentUserParticipant?.userIdentity.userRecordID` (not `role != .owner`) to find "the other person" — filtering by role breaks for the participant (they're `.privateUser`, not `.owner`, so they get themselves back instead of the owner). Guard for nil `currentUserParticipant`/`userRecordID` — when nil (identity not yet resolved), the filter passes ALL participants and the current user could be reported as their own partner.
- **2026-04-04**: Owner and participant use different save paths for shared zone routing: Owner calls `container.share(objects, to: existingShare)` AFTER `context.save()` (post-save). Participant calls `context.assign(object, to: sharedStore)` BEFORE `context.save()` (pre-save). Both result in the expense in the shared zone. Edits/deletes need no sharing calls — `NSPersistentCloudKitContainer` handles them automatically.
- **2026-04-04**: `persistUpdatedShare` must route to the correct store based on `isShareOwner` — owner's share is in `privatePersistentStore`, partner's share is in `sharedPersistentStore`. Hardcoding `privatePersistentStore` silently fails on the partner's device.

## Conflict Resolution (Last-Write-Wins)
- NSPersistentCloudKitContainer uses CKRecord change tags for framework-level LWW — NOT any custom `modifiedAt` field.
- Custom `modifiedAt` field is for display/sorting only — it does not participate in conflict arbitration.

## Offline Queue & Background Sync
- NSPersistentCloudKitContainer manages offline queue, retry logic, and change token persistence internally.
- Hard delete propagation works via NSPersistentHistoryTracking — but tombstone window expiry can leave orphaned records on offline partner.
- Purge NSPersistentHistoryTransaction entries older than 7 days on app launch to prevent unbounded growth.

## CKSubscription & Real-Time Updates
- Do NOT create manual CKDatabaseSubscription when using NSPersistentCloudKitContainer — the framework manages its own subscriptions internally.
- Creating a separate subscription causes double-processing, token conflicts, and missed updates.
- Use `.NSPersistentStoreRemoteChange` notification to detect partner changes, not manual CKFetchDatabaseChangesOperation.
- Must enable Background Modes → Remote Notifications capability for silent push.

## Security & Zone Permissions
- Observe CKAccountChanged notification to detect iCloud account change — flush cached tokens and reconcile local state.
- Household data must never be stored in publicCloudDatabase — only private + shared scopes.

## Known Bugs
- **iOS 18+ data-loss bug (ACTIVE, no fix):** When iCloud is disabled/signed out, NSPersistentCloudKitContainer can delete local data on first init (Apple Forums thread 772015). Guard with `FileManager.default.ubiquityIdentityToken != nil` check before setting cloudKitContainerOptions.
- **mergePolicy:** Use `NSMergeByPropertyStoreTrumpMergePolicy` (not ObjectTrump) on viewContext — lets the persistent store's CloudKit-merged state win over stale in-memory copies.
- All Core Data attributes MUST be Optional in the model editor — NSPersistentCloudKitContainer cannot sync non-optional attributes (silent failure).
- UUID attributes must have "Uses Scalar Type" UNCHECKED in Xcode model editor.
- `CKSharingSupported` Info.plist key must be added manually — not in Xcode autocomplete dropdown.
- Deploy schema from Development to Production in CloudKit Console before TestFlight — `initializeCloudKitSchema()` only pushes to Development.
- `usesScalarValueType` in .xcdatamodel does NOT affect CloudKit sync — it only controls Swift codegen (Bool vs NSNumber?). What CloudKit requires is `optional="YES"` on the attribute in the model editor. Scalar types with `optional="YES"` are valid for CloudKit sync.
- The iOS 18+ iCloud data-loss guard (`ubiquityIdentityToken == nil`) must protect BOTH the private AND shared store descriptions — don't nil out only the private store's cloudKitContainerOptions while leaving the shared store's options active.
- Must call `UIApplication.shared.registerForRemoteNotifications()` in `didFinishLaunchingWithOptions` — without it, silent push for CloudKit sync is never delivered.
- `NSPersistentCloudKitContainer` has NO `handleRemoteNotification` method. It auto-processes silent pushes via `NSPersistentStoreRemoteChangeNotificationPostOptionKey`. The `didReceiveRemoteNotification` delegate just needs to call `completionHandler(.newData)`.
- Explicitly set `cloudKitContainerOptions` with `containerIdentifier` on BOTH private and shared store descriptions — do not rely on auto-detection from the model/entitlements.
