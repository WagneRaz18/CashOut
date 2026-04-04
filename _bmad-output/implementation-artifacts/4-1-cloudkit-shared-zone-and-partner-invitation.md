# Story 4.1: CloudKit Shared Zone & Partner Invitation

Status: review

## Story

As a user,
I want to invite my partner to a shared household via a system share sheet,
So that we can both see each other's cash expenses in real-time.

## Acceptance Criteria

1. **Given** the app's CloudKit configuration **When** the first user sets up sharing **Then** a custom CKRecordZone is created for zone-level sharing (not record-level) via `NSPersistentCloudKitContainer.share(_:to:)` — the framework names the zone internally; do NOT create a raw `CKRecordZone("HouseholdZone")`

2. **Given** the Settings screen Household section **When** the user taps "Invite Partner" **Then** `UICloudSharingController` (wrapped in `UIViewControllerRepresentable`) presents the system share sheet for AirDrop/iMessage

3. **Given** the share sheet **When** the user sends a CKShare URL via AirDrop or iMessage **Then** the partner receives a functional share invitation link (FR22)

4. **Given** `CloudSharingService` **When** created **Then** it depends on `PersistenceController` (injected via init)

5. **Given** the shared zone **When** the app launches fresh **Then** sharing status is verified (users can delete zones via iOS Settings > iCloud) and the UI reflects the current state accurately

6. **Given** no partner has been invited **When** the app is used solo **Then** all features work fully without sharing — solo mode is never degraded

7. **Given** the Settings Household section **When** a partner is already connected **Then** partner info (name/initials from CKShare.Participant) is displayed instead of the invite button

## Tasks / Subtasks

- [x] Task 1: Expose persistent store references from PersistenceController (AC: #1, #4)
  - [x] 1.1 In `PersistenceController.swift`, add two private stored properties after the `container` declaration:
    ```swift
    private(set) var privatePersistentStore: NSPersistentStore?
    private(set) var sharedPersistentStore: NSPersistentStore?
    ```
  - [x] 1.2 In the `loadPersistentStores` callback, capture store references by checking `databaseScope`:
    ```swift
    container.loadPersistentStores { [weak self] desc, error in
        if let error { fatalError("Store load failed: \(error)") }
        if desc.cloudKitContainerOptions?.databaseScope == .shared {
            self?.sharedPersistentStore = container.persistentStoreCoordinator.persistentStore(for: desc.url!)
        } else {
            self?.privatePersistentStore = container.persistentStoreCoordinator.persistentStore(for: desc.url!)
        }
    }
    ```
    **Note:** `[weak self]` is technically unnecessary for a singleton, but the `self` capture in a closure stored during init requires it. The closure is synchronous (`loadPersistentStores` calls it inline), so `self` will always be valid.
  - [x] 1.3 In `inMemory` mode, set both store references to nil (no CloudKit in previews/tests).
  - [x] 1.4 Verify `AppDelegate.swift` line 29–31: replace the URL-based store lookup with the new property:
    ```swift
    guard let sharedStore = PersistenceController.shared.sharedPersistentStore else { return }
    ```
    This is safer than matching on URL path components.

- [x] Task 2: Create `CloudSharingService` (AC: #1, #4, #5, #6, #7)
  - [x] 2.1 Create file `CashOut/Services/CloudSharingService.swift` — `import Foundation; import CloudKit; import CoreData`
  - [x] 2.2 Define protocol:
    ```swift
    @MainActor
    protocol CloudSharingServiceProtocol {
        var isShared: Bool { get }
        var partnerName: String? { get }
        func createShare(for objects: [NSManagedObject]) async throws -> (CKShare, CKContainer)
        func checkSharingStatus() async
        func persistUpdatedShare(_ share: CKShare)
    }
    ```
    **Note:** `currentShare` is intentionally NOT on the protocol — it's an implementation detail used only for internal plumbing. Views access share data through `SettingsViewModel.activeShare` instead. `persistUpdatedShare` IS on the protocol so mocks can verify it's called.
  - [x] 2.3 Implement `CloudSharingService`:
    ```swift
    @MainActor
    @Observable
    final class CloudSharingService: CloudSharingServiceProtocol {
        var isShared: Bool = false
        var partnerName: String? = nil
        @ObservationIgnored private var currentShare: CKShare? = nil

        @ObservationIgnored private let persistenceController: PersistenceController

        init(persistenceController: PersistenceController = .shared) {
            self.persistenceController = persistenceController
        }
    }
    ```
    **Why no `authService` dependency?** `AuthenticationService` is not used in any CloudSharingService method for this story. Adding it would create a disconnected instance (architecture learnings: "Never create a new `AuthenticationService()` — it will be disconnected from the app's shared instance"). If needed in a future story, inject the shared instance from the app root.
  - [x] 2.4 Implement `createShare(for:)`:
    - Call `persistenceController.container.share(objects, to: nil)` — this creates the zone + CKShare automatically
    - Store the returned `CKShare` in `currentShare`
    - Set `share[CKShare.SystemFieldKey.title] = "CashOut Household"`
    - Return `(share, CKContainer.default())`
    - **CRITICAL:** If `objects` is empty, throw a descriptive error — `share(_:to:)` requires at least one object
  - [x] 2.5 Implement `checkSharingStatus()`:
    - Use `persistenceController.container.fetchShares(in: persistenceController.privatePersistentStore!)` to find ALL existing shares in a single call — O(1) instead of per-object iteration
    - If the private store is nil (inMemory/preview mode), set solo state and return early
    - If shares dictionary is non-empty: set `isShared = true`, extract the first `CKShare` as `currentShare`, extract partner name via `extractPartnerInfo(from:)`
    - If shares dictionary is empty: set `isShared = false`, `partnerName = nil`, `currentShare = nil`
    - **CRITICAL:** Do NOT fetch Expense objects for share checking — we share Category objects (Task 4.3), so categories are the anchor entities. `fetchShares(in:)` returns all shares regardless of entity type, which is what we want.
    - **Edge case:** If the zone was deleted (user cleared iCloud data), `fetchShares(in:)` returns empty — handle gracefully, reset to solo mode
  - [x] 2.6 Implement `persistUpdatedShare(_:)` — called after `UICloudSharingController` saves:
    ```swift
    func persistUpdatedShare(_ share: CKShare) {
        guard let privateStore = persistenceController.privatePersistentStore else { return }
        persistenceController.container.persistUpdatedShare(share, in: privateStore) { _, error in
            if let error {
                // Infrastructure-critical: stale share causes infinite spinner on re-present
                os_log(.fault, "Failed to persist updated share: %{public}@", error.localizedDescription)
            }
        }
    }
    ```
    **CRITICAL:** Without this call, the local Core Data store holds a stale CKShare snapshot and `UICloudSharingController` will spin forever on re-presentation. Use `os_log(.fault)` not `print()` — this is infrastructure-critical per architecture learnings. Add `import os` at the top of the file.
  - [x] 2.7 Add `extractPartnerInfo(from share: CKShare)` private helper:
    - Filter `share.participants` where `role != .owner`
    - Extract `acceptedPermissions`, `userIdentity.nameComponents` for display
    - Use `PersonNameComponentsFormatter.localizedString(from:style:options:)` for localized name display
    - If no name available (privacy choice), fall back to "Partner"

- [x] Task 3: Create `CloudSharingSheet` (AC: #2, #3)
  - [x] 3.1 Create file `CashOut/Views/Settings/CloudSharingSheet.swift` — `import SwiftUI; import CloudKit`
  - [x] 3.2 Implement as `UIViewControllerRepresentable`:
    ```swift
    struct CloudSharingSheet: UIViewControllerRepresentable {
        let share: CKShare
        let container: CKContainer
        let onDismiss: (CKShare?) -> Void

        func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

        func makeUIViewController(context: Context) -> UICloudSharingController {
            let controller = UICloudSharingController(share: share, container: container)
            controller.availablePermissions = [.allowReadWrite, .allowPrivate]
            controller.delegate = context.coordinator
            return controller
        }

        func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}
    }
    ```
    **CRITICAL:** Use `init(share:container:)` — NEVER use `init(preparationHandler:)`. The closure constructor causes infinite spinner bugs inside `UIViewControllerRepresentable`. Always create the CKShare first via `container.share(_:to:)`, then present the controller.
  - [x] 3.3 Implement `Coordinator` as `UICloudSharingControllerDelegate`:
    ```swift
    class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onDismiss: (CKShare?) -> Void

        init(onDismiss: @escaping (CKShare?) -> Void) { self.onDismiss = onDismiss }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            print("Share save failed: \(error)")
            onDismiss(nil)
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            onDismiss(csc.share)
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onDismiss(nil)
        }

        func itemTitle(for csc: UICloudSharingController) -> String? { "CashOut Household" }
    }
    ```
  - [x] 3.4 In the `onDismiss` handler (called from SettingsViewModel), call `cloudSharingService.persistUpdatedShare(share)` if a share was returned. Then call `checkSharingStatus()` to refresh UI.

- [x] Task 4: Create `SettingsViewModel` (AC: #5, #6, #7)
  - [x] 4.1 Create file `CashOut/ViewModels/SettingsViewModel.swift`
  - [x] 4.2 Implement:
    ```swift
    @MainActor
    @Observable
    final class SettingsViewModel {
        var isShowingShareSheet = false
        var hasPartner: Bool { cloudSharingService.isShared }
        var partnerDisplayName: String? { cloudSharingService.partnerName }
        var errorMessage: String?

        @ObservationIgnored private let cloudSharingService: CloudSharingServiceProtocol
        @ObservationIgnored private let categoryRepository: CategoryRepositoryProtocol

        // Share data for presenting CloudSharingSheet
        var activeShare: CKShare?
        var activeContainer: CKContainer?

        init(
            cloudSharingService: CloudSharingServiceProtocol = CloudSharingService(),
            categoryRepository: CategoryRepositoryProtocol = CategoryRepository()
        ) {
            self.cloudSharingService = cloudSharingService
            self.categoryRepository = categoryRepository
        }
    }
    ```
  - [x] 4.3 Implement `invitePartner()`:
    - Fetch all categories from `categoryRepository` (default categories are always seeded — guaranteed non-empty)
    - Convert `CategoryData` results to `NSManagedObject` references via `NSFetchRequest<Category>` on PersistenceController's viewContext
    - Call `cloudSharingService.createShare(for: categoryObjects)` — sharing categories creates the zone; expenses will be shared in Story 4.2
    - On success: set `activeShare` and `activeContainer`, set `isShowingShareSheet = true`
    - On error: set `errorMessage`
    - **Why categories?** Categories are always present (6 defaults seeded on first launch), providing a guaranteed non-empty anchor for zone creation. Expenses may not exist yet if the user invites their partner before logging anything.
  - [x] 4.4 Implement `refreshSharingStatus()` — calls `cloudSharingService.checkSharingStatus()`
  - [x] 4.5 Implement `handleShareDismiss(_ share: CKShare?)`:
    - If share is non-nil: call `cloudSharingService.persistUpdatedShare(share)`, then `refreshSharingStatus()`
    - If share is nil (cancelled/failed): no-op
    - Set `isShowingShareSheet = false`

- [x] Task 5: Create `SettingsView` (AC: #6, #7)
  - [x] 5.1 Create file `CashOut/Views/Settings/SettingsView.swift`
  - [x] 5.2 Standard `Form` / `List` with grouped sections following UX spec:
    ```swift
    struct SettingsView: View {
        @State private var viewModel = SettingsViewModel()

        var body: some View {
            Form {
                // Section 1: Categories (placeholder for Epic 5)
                Section("Categories") {
                    // Epic 5 will add CategoryManagementView here
                    Text("6 default categories active")
                        .foregroundStyle(.secondary)
                }

                // Section 2: Household
                Section("Household") {
                    HouseholdSectionView(viewModel: viewModel)
                }

                // Section 3: About
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.appVersion)
                    Text("Your data stays on your devices and iCloud. No analytics, no third-party access.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .task { await viewModel.refreshSharingStatus() }
            .sheet(isPresented: Bindable(viewModel).isShowingShareSheet) {
                if let share = viewModel.activeShare,
                   let container = viewModel.activeContainer {
                    CloudSharingSheet(share: share, container: container) { updatedShare in
                        viewModel.handleShareDismiss(updatedShare)
                    }
                }
            }
        }
    }
    ```
    **CRITICAL `.sheet()` placement:** The `.sheet` modifier MUST be on the `Form` (outer container), NOT inside `HouseholdSectionView`. Per iOS SwiftUI learnings: when a conditional branch replaces a view, any `.sheet` modifier on that branch disappears from the hierarchy and can never trigger.
    **CRITICAL `Bindable` usage:** `@State` on `@Observable` does NOT expose `$viewModel` for bindings. Use `Bindable(viewModel).isShowingShareSheet` to get a `Binding<Bool>` for the sheet. Per iOS SwiftUI learnings entry.
  - [x] 5.3 Add `Bundle` extension for app version:
    ```swift
    extension Bundle {
        var appVersion: String {
            infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        }
    }
    ```
    Place in `CashOut/Utilities/Extensions/Bundle+Version.swift`.
  - [x] 5.4 **No settings that affect the core entry flow** — UX rule. This screen is informational + household management only.

- [x] Task 6: Create `HouseholdSectionView` (AC: #2, #6, #7)
  - [x] 6.1 Create as a private sub-view within `SettingsView.swift` (it's a section component, not a standalone screen — one ViewModel per screen rule):
    ```swift
    private struct HouseholdSectionView: View {
        @Bindable var viewModel: SettingsViewModel

        var body: some View {
            if viewModel.hasPartner {
                // Partner connected state
                HStack {
                    partnerAvatar
                    VStack(alignment: .leading) {
                        Text(viewModel.partnerDisplayName ?? "Partner")
                            .font(.body)
                        Text("Connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                // Solo mode — invite button
                Button("Invite Partner") {
                    Task { await viewModel.invitePartner() }
                }
            }
        }
    }
    ```
  - [x] 6.2 Partner avatar: 32x32pt circle with partner initials, using Partner B color `#A89B8A` (warm stone) per UX-DR8. The current user is Partner A (`#6B8AAE`); the invited partner is always Partner B.
  - [x] 6.3 **Do NOT place `.sheet()` on HouseholdSectionView** — it's already on the `Form` in Task 5.2. The sub-view only contains the invite button and partner info display.
  - [x] 6.4 Error display: if `viewModel.errorMessage` is non-nil, show inline text below the button. No modals, no alerts (UX: non-intrusive errors only). If `invitePartner()` fails, set `errorMessage` and do NOT set `activeShare`/`activeContainer` — the sheet won't present.

- [x] Task 7: Add gear icon to FeedView and InsightsView navigation bars (AC: #7)
  - [x] 7.1 In `FeedView.swift`, add a `.toolbar` modifier with a `NavigationLink` to `SettingsView`:
    ```swift
    .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink(destination: SettingsView()) {
                Image(systemName: "gearshape")
            }
        }
    }
    ```
    **Check:** FeedView must already be inside a `NavigationStack`. Verify in `ContentView.swift` — each tab should wrap its content in `NavigationStack`. If FeedView already has toolbar items, add the gear icon alongside existing items.
  - [x] 7.2 In `InsightsView.swift`, add the identical toolbar modifier. Same NavigationStack check applies.
  - [x] 7.3 **Do NOT add the gear icon to EntryView** (Tab 1) — the entry screen must remain distraction-free per UX spec.

- [x] Task 8: Write unit tests for CloudSharingService and SettingsViewModel (AC: all)
  - [x] 8.1 Create `CashOutTests/Services/MockCloudSharingService.swift`:
    ```swift
    @MainActor
    final class MockCloudSharingService: CloudSharingServiceProtocol {
        var isShared = false
        var partnerName: String? = nil
        var createShareCalled = false
        var checkSharingStatusCalled = false
        var persistUpdatedShareCalled = false
        var createShareHandler: (([NSManagedObject]) async throws -> (CKShare, CKContainer))?

        func createShare(for objects: [NSManagedObject]) async throws -> (CKShare, CKContainer) {
            createShareCalled = true
            if let handler = createShareHandler {
                return try await handler(objects)
            }
            throw NSError(domain: "MockCloudSharingService", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "No handler set"])
        }

        func checkSharingStatus() async {
            checkSharingStatusCalled = true
        }

        func persistUpdatedShare(_ share: CKShare) {
            persistUpdatedShareCalled = true
        }
    }
    ```
    **Note:** Uses a closure-based `createShareHandler` instead of `fatalError` — avoids crashing the test runner if accidentally called without setup.
  - [x] 8.2 Create `CashOutTests/ViewModels/SettingsViewModelTests.swift`:
    - Test: solo mode shows invite button (hasPartner == false when not shared)
    - Test: partner connected shows partner info (hasPartner == true, partnerDisplayName set)
    - Test: invitePartner() calls createShare on service
    - Test: invitePartner() on success sets activeShare and activeContainer (prerequisites for sheet presentation — verifies AC #2)
    - Test: invitePartner() on error sets errorMessage and does NOT set activeShare
    - Test: refreshSharingStatus() calls checkSharingStatus on service
    - Test: handleShareDismiss with valid share calls persistUpdatedShare and refreshes status
    - Test: handleShareDismiss with nil does not crash, sets isShowingShareSheet = false
  - [x] 8.3 **No integration tests for CloudKit** — CloudKit requires a real iCloud account and network. Unit tests mock the service protocol. Manual testing via TestFlight is the verification path for CloudKit sharing (documented in architecture).

## Dev Notes

### Architecture Compliance

- **MVVM boundaries enforced:** `SettingsView` reads from `SettingsViewModel`; ViewModel calls `CloudSharingService`; Service interacts with `PersistenceController` and CloudKit. Views never touch Core Data or CloudKit directly.
- **Protocol-based DI:** `CloudSharingServiceProtocol` enables mock injection for tests. Default parameter in ViewModel `init` provides real implementation.
- **`@ObservationIgnored`** on all injected service/repository references in ViewModels — per architecture learnings.
- **One ViewModel per screen:** `SettingsViewModel` owns all Settings screen state. `HouseholdSectionView` is a sub-view, not a separate screen.

### Critical CloudKit Technical Details

**NSPersistentCloudKitContainer.share(_:to:) behavior:**
- Creates a NEW custom CKRecordZone internally (framework-named, NOT "HouseholdZone")
- Creates a zone-level CKShare for that zone
- Moves the specified managed objects from private store to shared zone
- Returns `(Set<NSManagedObjectID>, CKShare, CKContainer)`
- **Requires at least one managed object** — throws if array is empty
- The managed objects MUST be from the private persistent store

**UICloudSharingController gotchas:**
- **MUST use `init(share:container:)`** — the closure `init(preparationHandler:)` causes infinite spinner bugs in UIViewControllerRepresentable
- **MUST call `persistUpdatedShare(_:in:)` after `cloudSharingControllerDidSaveShare`** — without this, the local CKShare snapshot goes stale and the controller spins forever on re-presentation
- On iPad, `popoverPresentationController?.sourceView` must be set or the controller dismisses immediately. Since CashOut is iPhone-portrait-only per Info.plist `UISupportedInterfaceOrientations`, this is not a concern for v1.

**Zone verification on launch:**
- `fetchShares(matching:)` returns empty if the zone was deleted externally
- Handle gracefully: reset to solo mode, show "Invite Partner" button
- Do NOT attempt to recreate the zone automatically — user action (re-invite) is required

**Share acceptance (already implemented):**
- `AppDelegate.swift` line 23–41 already handles `userDidAcceptCloudKitShareWith`
- Uses `container.acceptShareInvitations(from:into:)` into the shared store
- Task 1.4 improves the store lookup to use the new property instead of URL matching

### What This Story Does NOT Cover (Deferred to Stories 4.2 and 4.3)

- **Automatic sharing of new expenses** — After initial zone creation, new expenses saved to the private store are NOT automatically in the shared zone. Story 4.2 will handle `share([newExpense], to: existingShare)` on every save.
- **Partner's view of shared data** — Story 4.2 covers the partner accepting the invitation and seeing data in their shared store.
- **Real-time feed updates from partner** — Story 4.3 covers `.NSPersistentStoreRemoteChange` notification handling and animated feed updates.
- **Conflict resolution** — Story 4.2 covers last-write-wins via CKRecord change tags (automatic with NSPersistentCloudKitContainer).
- **Sync error indicators** — Story 4.3 covers the small nav bar icon for persistent sync failure.

### Project Structure Notes

New files follow established directory conventions:
```
CashOut/Services/CloudSharingService.swift          # Service layer (flat)
CashOut/Views/Settings/SettingsView.swift            # Settings screen container
CashOut/Views/Settings/CloudSharingSheet.swift       # UIKit bridge
CashOut/ViewModels/SettingsViewModel.swift            # Settings state management
CashOut/Utilities/Extensions/Bundle+Version.swift    # Lightweight extension
CashOutTests/Services/MockCloudSharingService.swift  # Test mock
CashOutTests/ViewModels/SettingsViewModelTests.swift # Unit tests
```

Modified files:
```
CashOut/Services/PersistenceController.swift         # Add store reference properties
CashOut/App/AppDelegate.swift                        # Use new store reference property
CashOut/Views/Feed/FeedView.swift                    # Add gear icon toolbar item
CashOut/Views/Insights/InsightsView.swift            # Add gear icon toolbar item
```

### Previous Story Intelligence (Epic 3 → Epic 4 Transition)

- **Git convention:** Commit messages use `feat(domain):` and `fix(domain):` prefixes. For this story use `feat(sharing):` prefix.
- **Code review pattern:** Previous stories had 2-6 code review findings per story. Common issues: missing `@ObservationIgnored`, guard-before-division, Buddhist calendar locale handling. These are already addressed in the task descriptions above.
- **Testing pattern:** Unit tests mock repository/service protocols. No integration tests for Apple framework behaviors (CloudKit, Core Data). Manual TestFlight testing for sync verification.
- **Sub-view pattern:** Presentation sub-views (like `DailyBarChartView`, `CategoryBreakdownView`) take data via init parameters, not environment. Follow the same pattern for `HouseholdSectionView` and `CloudSharingSheet`.

### Orchestrator Validation Findings (2026-04-04)

Domain guardians (ios-swiftui, cloudkit-sync, architecture) validated this story. Key findings incorporated:
- **WARNING:** After implementing this story, update `.claude/learnings/cloudkit-sync.md` to clarify that the "HouseholdZone" is framework-managed via `NSPersistentCloudKitContainer.share(_:to:)`, not manually created with `CKRecordZone("HouseholdZone")`. Current learnings entry is misleading.
- **SUGGESTION:** For v1, assume exactly 1 partner (owner + 1 participant). Multi-party sharing is not supported — `extractPartnerInfo` should handle 0 or 1 non-owner participants only.
- **VERIFIED:** ContentView.swift wraps FeedView and InsightsView in NavigationStack (lines 13 and 18), so Task 7 toolbar additions will render correctly. EntryView (Tab 0) has no NavigationStack — correct, as it should be distraction-free.

### Latest Technical Research (2026-04-04)

- `NSPersistentCloudKitContainer.share(_:to:)` confirmed present in iOS 26 SDK (verified via .NET iOS 26.2 binding reference)
- `UICloudSharingController` is NOT deprecated as of iOS 26 — still the recommended UIKit-based sharing controller
- SwiftUI-native alternative `ShareLink` + `CKShareTransferRepresentation` exists (iOS 16+) but cannot manage existing share participants — only suitable for initial invite. For full share management (our needs), `UICloudSharingController` remains the correct choice.
- Known Apple bug: `UICloudSharingController` shows infinite spinner when re-presenting for an already-shared object (iOS 16–18+, unresolved). Mitigation: always call `persistUpdatedShare` after save, and refetch share before re-presenting.
- Known Apple bug: `userDidAcceptCloudKitShareWith` cold-launch delivery is unreliable on some iOS 17 configurations. The AppDelegate implementation is correct; this is an Apple-side issue. Our current implementation handles it correctly.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic 4, Story 4.1 — lines 709-743]
- [Source: _bmad-output/planning-artifacts/architecture.md — CloudKit sync architecture, persistence stack, service boundaries, project structure]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — Settings pattern (lines 900-912), Journey 4 partner onboarding (lines 659-687), flow optimization (lines 726-730)]
- [Source: _bmad-output/planning-artifacts/prd.md — FR19-FR22, FR25-FR26, offline/sync requirements]
- [Source: CashOut/Services/PersistenceController.swift — existing dual-store setup]
- [Source: CashOut/App/AppDelegate.swift — existing share acceptance handler]
- [Source: CashOut/Services/AuthenticationService.swift — AuthenticationServiceProtocol, currentUserID]
- [Web: Apple sample-cloudkit-zonesharing — zone-level CKShare pattern]
- [Web: Kodeco — Sharing Core Data with CloudKit in SwiftUI (pages 2-4)]
- [Web: fatbobman.com — Core Data with CloudKit: Sharing — persistUpdatedShare requirement]
- [Web: Apple Developer Forums thread 691087 — UICloudSharingController spinner bug]

## Dev Agent Record

### Agent Model Used
Claude Opus 4.6 (1M context)

### Debug Log References
- Fixed `fetchShares(in:)` return type — returns `[CKShare]` not dictionary, changed `.values.first!` to `.first!`
- Used `Result<>` pattern instead of closure handler for MockCloudSharingService to avoid Swift 6 sendability issues with `[NSManagedObject]`
- Created Settings PBXGroup in Xcode project via xcodeproj Ruby gem (not present in original project)

### Completion Notes List
- Task 1: Added `privatePersistentStore`/`sharedPersistentStore` properties to PersistenceController, captured during loadPersistentStores callback. Updated AppDelegate to use property instead of URL-matching.
- Task 2: Created CloudSharingService with protocol-based DI. Implements zone-level sharing via `NSPersistentCloudKitContainer.share(_:to:)`, sharing status verification via `fetchShares(in:)`, and partner info extraction from CKShare participants.
- Task 3: Created CloudSharingSheet as UIViewControllerRepresentable wrapping UICloudSharingController. Uses `init(share:container:)` (not preparationHandler). Coordinator handles delegate callbacks.
- Task 4: Created SettingsViewModel with invitePartner (fetches categories, creates share), refreshSharingStatus, and handleShareDismiss methods. Injects CloudSharingServiceProtocol for testability.
- Task 5: Created SettingsView with Form-based layout: Categories (placeholder), Household, About sections. Sheet modifier on Form (not sub-view) for correct presentation. Added Bundle+Version extension.
- Task 6: HouseholdSectionView as private sub-view in SettingsView. Shows invite button (solo) or partner avatar with name (connected). Partner B avatar uses #A89B8A warm stone color per UX-DR8.
- Task 7: Added gear icon toolbar item to FeedView and InsightsView. Both are inside NavigationStack in ContentView. EntryView left distraction-free per UX spec.
- Task 8: MockCloudSharingService with Result-based createShare. 11 SettingsViewModelTests covering solo mode, partner connected, invite flow (success/error/no categories), refresh status, and share dismiss handling. All pass with zero regressions.

### File List
**New files:**
- CashOut/Services/CloudSharingService.swift
- CashOut/Views/Settings/CloudSharingSheet.swift
- CashOut/Views/Settings/SettingsView.swift
- CashOut/ViewModels/SettingsViewModel.swift
- CashOut/Utilities/Extensions/Bundle+Version.swift
- CashOutTests/Services/MockCloudSharingService.swift
- CashOutTests/ViewModels/SettingsViewModelTests.swift

**Modified files:**
- CashOut/Services/PersistenceController.swift — added store reference properties
- CashOut/App/AppDelegate.swift — updated store lookup to use property
- CashOut/Views/Feed/FeedView.swift — added gear icon toolbar item
- CashOut/Views/Insights/InsightsView.swift — added gear icon toolbar item
- CashOut.xcodeproj/project.pbxproj — added new files and Settings group

## Change Log
- 2026-04-04: Initial implementation of all 8 tasks — CloudSharingService, CloudSharingSheet, SettingsViewModel, SettingsView + HouseholdSectionView, Bundle+Version extension, gear icon toolbar on Feed/Insights, MockCloudSharingService + 11 unit tests
- 2026-04-04: Addressed orchestrator guardian findings (8 items) — removed redundant @ObservationIgnored on let constants, fixed optional-nil init pattern, replaced force unwrap with guard let, added Task.isCancelled guard, added isInviting double-tap guard, fixed store classification when iCloud unavailable (URL matching vs databaseScope), pinned category fetch to private store, restricted share permissions to readWrite only
