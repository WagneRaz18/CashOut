@preconcurrency import CoreData
import CloudKit

final class PersistenceController: @unchecked Sendable {
    static let shared = PersistenceController()

    static let preview = PersistenceController(inMemory: true)

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "CashOut")

        guard let privateDesc = container.persistentStoreDescriptions.first else {
            fatalError("No persistent store descriptions found")
        }

        if inMemory {
            privateDesc.url = URL(fileURLWithPath: "/dev/null")
            privateDesc.cloudKitContainerOptions = nil
        }

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

        container.loadPersistentStores { _, error in
            if let error { fatalError("Store load failed: \(error)") }
        }

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
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let purgeRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: sevenDaysAgo)

        let context = container.newBackgroundContext()
        context.performAndWait {
            do {
                try context.execute(purgeRequest)
            } catch {
                print("History purge failed: \(error)")
            }
        }
    }
}
