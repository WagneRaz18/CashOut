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
- App must implement `userDidAcceptCloudKitShareWith` and call `container.accept(metadata)` for partner join flow.

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
