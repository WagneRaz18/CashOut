# Code Patterns Reference

Correct and incorrect code examples for CashOut review scenarios.

---

## MVVM Ownership

```swift
// CORRECT: Owner view uses @State
struct ExpenseEntryScreen: View {
    @State var vm = ExpenseEntryViewModel()

    var body: some View {
        AmountInputView(vm: vm)  // Child receives as let
    }
}

struct AmountInputView: View {
    let vm: ExpenseEntryViewModel  // Read-only — NOT @State

    var body: some View { ... }
}

// CORRECT: Two-way binding in child
struct ExpenseEditView: View {
    @Bindable var vm: ExpenseEntryViewModel  // Two-way binding

    var body: some View {
        TextField("Note", text: $vm.note)
    }
}

// WRONG: @State in child creates duplicate ViewModel
struct BadChildView: View {
    @State var vm = ExpenseEntryViewModel()  // VIOLATION! Second instance
}
```

---

## @Observable ViewModel

```swift
// CORRECT: @Observable with @ObservationIgnored for services
@Observable
class InsightsViewModel {
    var expenses: [ExpenseEntry] = []
    var isLoading = false
    var error: Error?  // Independent properties, NOT ViewState enum

    @ObservationIgnored private let cloudKitService: CloudKitService
    @ObservationIgnored private let modelContext: ModelContext

    init(cloudKitService: CloudKitService, modelContext: ModelContext) {
        self.cloudKitService = cloudKitService
        self.modelContext = modelContext
    }
}

// WRONG: ViewState enum — can't represent overlapping states
@Observable
class BadViewModel {
    enum ViewState { case idle, loading, loaded([ExpenseEntry]), error(Error) }
    var state: ViewState = .idle  // Can't show stale data + loading spinner
}

// WRONG: ViewModel imports SwiftUI
import SwiftUI  // VIOLATION!
@Observable
class BadViewModel {
    var path = NavigationPath()  // VIOLATION! Navigation belongs in Coordinator
}
```

---

## Navigation Coordinator

```swift
// CORRECT: Coordinator owns navigation, ViewModel emits events
@Observable
class AppCoordinator {
    var path: [Route] = []

    func handle(_ event: ExpenseEntryViewModel.Event) {
        switch event {
        case .expenseSaved: path.removeLast()
        case .categoryTapped: path.append(.categoryPicker)
        }
    }
}

@Observable
class ExpenseEntryViewModel {
    enum Event { case expenseSaved, categoryTapped }
    // ViewModel emits events, does NOT navigate
}

struct MainScreen: View {
    @State var coordinator = AppCoordinator()

    var body: some View {
        NavigationStack(path: $coordinator.path) { ... }
    }
}
```

---

## Async Task Lifecycle

```swift
// CORRECT: Stored task on ViewModel with cancel in deinit
@Observable
class SyncViewModel {
    var syncStatus: SyncStatus?
    var isSyncing = false

    @ObservationIgnored private var syncTask: Task<Void, Never>?

    func startSync() {
        syncTask?.cancel()
        syncTask = Task {
            isSyncing = true
            defer { isSyncing = false }

            guard !Task.isCancelled else { return }
            let result = try? await cloudKitService.syncPendingChanges()
            guard !Task.isCancelled else { return }

            syncStatus = result
        }
    }

    deinit { syncTask?.cancel() }
}

// WRONG: Task in body not tied to ViewModel
var body: some View {
    Button("Sync") {
        Task { await vm.startSync() }  // Outlives view if navigated away
    }
}
```

---

## SwiftData Patterns

```swift
// CORRECT: VersionedSchema from day one
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] = [
        ExpenseEntry.self, Category.self, Household.self
    ]

    @Model
    class ExpenseEntry {
        var amount: Double
        var note: String?
        var timestamp: Date
        var categoryName: String
        var createdBy: String  // User identifier
        var cloudKitRecordData: Data?  // Encoded system fields
        var household: Household?

        init(amount: Double, categoryName: String, createdBy: String) {
            self.amount = amount
            self.categoryName = categoryName
            self.createdBy = createdBy
            self.timestamp = .now
            // Do NOT assign relationships here
        }
    }
}

// WRONG: No VersionedSchema
@Model
class BadExpenseEntry {
    var amount: Double  // Unversioned — adding schema later causes crash
}
```

---

## Cross-Actor Safety

```swift
// CORRECT: Pass PersistentIdentifier, re-fetch on receiving side
func saveExpenseInBackground(expenseID: PersistentIdentifier) {
    Task.detached {
        let context = ModelContext(container)
        guard let expense = context.model(for: expenseID) as? ExpenseEntry else { return }
        expense.amount = newAmount
        try context.save()
    }
}

// WRONG: Passing model object across actors
func badSave(expense: ExpenseEntry) {  // ExpenseEntry is NOT Sendable
    Task.detached {
        expense.amount = newAmount  // CRASH or data race
    }
}
```

---

## CloudKit Sync Patterns

```swift
// CORRECT: Batch save with explicit policy and conflict handling
func saveExpenses(_ records: [CKRecord]) async throws {
    let operation = CKModifyRecordsOperation(
        recordsToSave: records,
        recordIDsToDelete: nil
    )
    operation.savePolicy = .changedKeys  // Field-level merge
    operation.perRecordSaveBlock = { recordID, result in
        switch result {
        case .success(let savedRecord):
            self.persistSystemFields(savedRecord)
        case .failure(let error):
            if let ckError = error as? CKError,
               ckError.code == .serverRecordChanged,
               let serverRecord = ckError.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
                self.resolveConflict(local: records.first { $0.recordID == recordID }!,
                                     server: serverRecord)
            }
        }
    }
    try await database.add(operation)
}

// WRONG: Individual saves in a loop
for record in records {
    try await database.save(record)  // N network calls, no batching
}

// WRONG: No conflict handling
operation.savePolicy = .ifServerRecordUnchanged  // Default — rejects concurrent edits
// No perRecordSaveBlock — conflicts silently dropped
```

---

## CloudKit Record Patterns

```swift
// CORRECT: Record in custom zone with parent hierarchy
let zoneID = CKRecordZone.ID(zoneName: "HouseholdZone", ownerName: CKCurrentUserDefaultName)
let recordID = CKRecord.ID(recordName: expense.id.uuidString, zoneID: zoneID)
let record = CKRecord(recordType: "Expense", recordID: recordID)
record["amount"] = expense.amount as CKRecordValue
record["note"] = expense.note as CKRecordValue?
record["categoryName"] = expense.categoryName as CKRecordValue
record["createdBy"] = expense.createdBy as CKRecordValue
record.setParent(householdRecord)  // System parent for sharing hierarchy

// CORRECT: Zone-based sharing for household
let share = CKShare(recordZoneID: zoneID)
share[CKShare.SystemFieldKey.title] = "CashOut Household"
share.publicPermission = .none

// WRONG: Record in default zone
let badRecord = CKRecord(recordType: "Expense")  // Default zone — can't share or sync

// WRONG: Public database for household data
let publicDB = container.publicCloudDatabase  // VIOLATION! No access control
```

---

## Sign in with Apple

```swift
// CORRECT: Credential state check on launch
func checkCredentialState() async {
    guard let userID = KeychainService.getUserIdentifier() else {
        showSignIn()
        return
    }
    let provider = ASAuthorizationAppleIDProvider()
    do {
        let state = try await provider.credentialState(forUserID: userID)
        switch state {
        case .authorized: break  // Good
        case .revoked:
            KeychainService.clearAll()
            showSignIn()
        case .notFound:
            showSignIn()
        default: break
        }
    } catch {
        // Network error — proceed with cached state
    }
}

// CORRECT: Register for mid-session revocation
NotificationCenter.default.addObserver(
    forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
    object: nil, queue: .main
) { _ in
    handleRevocation()
}

// WRONG: Storing credentials in UserDefaults
UserDefaults.standard.set(userID, forKey: "appleUserID")  // Not encrypted
```

---

## Offline Queue

```swift
// CORRECT: Persistent pending operations
@Model
class PendingCloudKitOperation {
    var recordData: Data  // Encoded CKRecord system fields + changes
    var operationType: String  // "save", "delete"
    var status: String  // "pending", "inFlight", "failed"
    var retryCount: Int
    var createdAt: Date

    init(recordData: Data, operationType: String) {
        self.recordData = recordData
        self.operationType = operationType
        self.status = "pending"
        self.retryCount = 0
        self.createdAt = .now
    }
}

// CORRECT: NWPathMonitor for connectivity
import Network
let monitor = NWPathMonitor()
monitor.pathUpdateHandler = { path in
    if path.status == .satisfied {
        Task { await syncQueue.drainPending() }
    }
}
monitor.start(queue: DispatchQueue(label: "network-monitor"))  // Background queue

// WRONG: In-memory queue (lost on app kill)
var pendingOps: [CKRecord] = []  // Gone after force-quit

// WRONG: Monitor on main queue
monitor.start(queue: .main)  // Blocks UI updates
```

---

## Dynamic Queries (Subview Pattern)

```swift
// CORRECT: Parent passes date, child creates @Query in init
struct InsightsScreen: View {
    @State var selectedPeriod = Date()

    var body: some View {
        PeriodExpensesView(date: selectedPeriod)
    }
}

struct PeriodExpensesView: View {
    @Query private var expenses: [ExpenseEntry]

    init(date: Date) {
        let start = Calendar.current.startOfDay(for: date)
        let end = start.addingTimeInterval(86400)
        _expenses = Query(filter: #Predicate<ExpenseEntry> {
            $0.timestamp >= start && $0.timestamp < end
        })
    }

    var body: some View {
        ForEach(expenses) { expense in ... }
    }
}

// WRONG: Dynamic predicate in same view (doesn't recompute)
struct BadView: View {
    @State var date = Date()
    @Query var expenses: [ExpenseEntry]  // Can't change predicate at runtime
}
```

---

## DI Without Framework

```swift
// CORRECT: Two-tier injection
@main
struct CashOutApp: App {
    let container = try! ModelContainer(for: SchemaV1.self)
    @State var cloudKitService = CloudKitService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .environment(cloudKitService)  // Tier 1: app-wide
        }
    }
}

struct ExpenseEntryScreen: View {
    @Environment(CloudKitService.self) var cloudKitService

    @State var vm: ExpenseEntryViewModel

    var body: some View { ... }
        .task { vm.configure(cloudKitService: cloudKitService) }
}
```
