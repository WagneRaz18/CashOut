# CloudKit Sync & Sharing

<!-- One line per learning, brief and actionable -->

## Shared Database Setup
- SwiftData does NOT support CloudKit shared databases (confirmed through iOS 26). Must use Core Data + NSPersistentCloudKitContainer.
- NSPersistentCloudKitContainer requires two NSPersistentStoreDescription configs: private scope + shared scope.
- All synced records must target a custom CKRecordZone ("HouseholdZone"), never the default zone — CKShare requires a custom zone.
- Info.plist must contain `CKSharingSupported = true` or partner join callbacks silently fail.
- Zone existence must be re-verified on every fresh launch — users can delete zones via iOS Settings → iCloud.

## CKRecord Types & Schema
- Run `initializeCloudKitSchema()` only in DEBUG builds to deploy schema to CloudKit container.
- Store `encodeSystemFields` data with each record to preserve zone metadata and prevent infinite conflict loops.

## CKShare & Participant Management
- Use zone-level sharing (CKShare per zone), not hierarchical record sharing — simpler for 2-user household.
- UICloudSharingController is UIKit — needs UIViewControllerRepresentable wrapper for SwiftUI.
- **CAUTION:** `container.share()` deadlocks on iOS 17+ unless called from `CKShareTransferRepresentation.prepareShare`. Prefer `ShareLink` + `CKShareTransferRepresentation` over `UICloudSharingController` for new SwiftUI code.
- App must implement `userDidAcceptCloudKitShareWith` and call `container.acceptShareInvitations(from:into:)` for partner join flow. There is NO `container.accept(metadata)` convenience method on NSPersistentCloudKitContainer.
- `.onCKShareAccepted` is NOT a real SwiftUI scene modifier — use `UIApplicationDelegate.userDidAcceptCloudKitShareWith` for share acceptance.

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
