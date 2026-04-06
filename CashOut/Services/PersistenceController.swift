@preconcurrency import CoreData
import CloudKit
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "PersistenceController")

final class PersistenceController: @unchecked Sendable {
    static let shared = PersistenceController()

    static let preview = PersistenceController(inMemory: true)

    let container: NSPersistentCloudKitContainer
    private(set) var privatePersistentStore: NSPersistentStore?
    private(set) var sharedPersistentStore: NSPersistentStore?
    private(set) var storeLoadError: Error?

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "CashOut")

        guard let privateDesc = container.persistentStoreDescriptions.first else {
            fatalError("No persistent store descriptions found")
        }

        if inMemory {
            privateDesc.url = URL(fileURLWithPath: "/dev/null")
            privateDesc.cloudKitContainerOptions = nil
        }

        // Known v1 limitation: .changeTokenExpired triggers full re-import but cannot
        // reconcile records deleted past the CloudKit tombstone window (~30 days).
        // Orphaned local records may persist. Acceptable at 2-user scale.

        // History tracking + remote change notifications on private store
        privateDesc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        privateDesc.setOption(
            true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
        )
        // Lightweight migration support
        privateDesc.shouldMigrateStoreAutomatically = true
        privateDesc.shouldInferMappingModelAutomatically = true

        if !inMemory {
            let iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil

            // Explicitly set CloudKit container on private store
            if iCloudAvailable {
                privateDesc.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: "iCloud.com.wagneraz.CashOut"
                )
            } else {
                // Guard against iOS 18+ data-loss bug when iCloud is disabled/signed out
                // (Apple Developer Forums thread 772015)
                privateDesc.cloudKitContainerOptions = nil
            }

            // Shared store — MUST use a separate SQLite file
            let storeURL = privateDesc.url!
            let sharedStoreURL = storeURL.deletingLastPathComponent()
                .appendingPathComponent("CashOut-shared.sqlite")

            let sharedDesc = NSPersistentStoreDescription(url: sharedStoreURL)
            if iCloudAvailable {
                sharedDesc.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: "iCloud.com.wagneraz.CashOut"
                )
                sharedDesc.cloudKitContainerOptions?.databaseScope = .shared
            }
            sharedDesc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            sharedDesc.setOption(
                true as NSNumber,
                forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
            )
            sharedDesc.shouldMigrateStoreAutomatically = true
            sharedDesc.shouldInferMappingModelAutomatically = true

            container.persistentStoreDescriptions = [privateDesc, sharedDesc]
        }

        let sharedStoreURLForMatching = inMemory ? nil : privateDesc.url!
            .deletingLastPathComponent()
            .appendingPathComponent("CashOut-shared.sqlite")

        container.loadPersistentStores { [weak self] desc, error in
            if let error {
                logger.fault("Store load failed: \(error.localizedDescription)")
                self?.storeLoadError = error
                return
            }
            guard !inMemory, let self, let storeURL = desc.url else { return }
            let store = self.container.persistentStoreCoordinator.persistentStore(for: storeURL)
            if storeURL == sharedStoreURLForMatching {
                self.sharedPersistentStore = store
            } else {
                self.privatePersistentStore = store
            }
        }

        // Required: FRC in ExpenseRepository depends on this for CloudKit partner-change propagation
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy

        // History purge — MUST be after loadPersistentStores, not inside callback
        purgeOldHistory()

        // Observe iCloud account changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAccountChange),
            name: .CKAccountChanged,
            object: nil
        )

        #if DEBUG
        if !inMemory {
            do {
                try container.initializeCloudKitSchema(options: [])
            } catch {
                print("CloudKit schema init failed: \(error)")
            }
        }
        #endif
    }

    @objc private func handleAccountChange() {
        // NSPersistentCloudKitContainer handles re-sync automatically after account change.
        // This observer ensures the container is aware of the transition.
    }

    private func purgeOldHistory() {
        guard storeLoadError == nil else { return }
        let sevenDaysAgo = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let purgeRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: sevenDaysAgo)

        let context = container.newBackgroundContext()
        context.performAndWait {
            do {
                try context.execute(purgeRequest)
            } catch {
                logger.error("History purge failed: \(error.localizedDescription)")
            }
        }
    }
}
