@preconcurrency import CoreData
import CloudKit
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "PersistenceController")

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    static let preview = PersistenceController(inMemory: true)

    /// `private(set) var` (not `let`) to allow replacement during DEBUG destructive-migration fallback.
    /// The swap happens entirely within `init`, before `shared` is visible to any caller.
    private(set) var container: NSPersistentCloudKitContainer
    private(set) var privatePersistentStore: NSPersistentStore?
    private(set) var storeLoadError: Error?

    /// Key for the UserDefaults sentinel that records which Core Data model version
    /// has already had its CloudKit schema deployed via `initializeCloudKitSchema`.
    private static let schemaInitializedVersionKey = "ckSchemaInitializedForModelVersion"

    init(inMemory: Bool = false) {
        logger.info("PersistenceController.init — inMemory=\(inMemory)")

        let iCloudAvailable = !inMemory && FileManager.default.ubiquityIdentityToken != nil
        if !inMemory { logger.info("iCloud available: \(iCloudAvailable)") }

        container = Self.configuredContainer(inMemory: inMemory, iCloudAvailable: iCloudAvailable)
        loadStores(inMemory: inMemory)

        #if DEBUG
        if storeLoadError != nil, !inMemory {
            logger.warning("Store load failed — destroying stores and retrying (DEBUG only)")
            destroyStoreFiles()
            storeLoadError = nil
            privatePersistentStore = nil
            container = Self.configuredContainer(inMemory: inMemory, iCloudAvailable: iCloudAvailable)
            loadStores(inMemory: inMemory)

            if storeLoadError != nil {
                logger.fault("Store load FAILED even after destroying stores — giving up")
            } else {
                logger.info("Store load succeeded after rebuild")
            }
        }
        #endif

        // Required: FRC in ExpenseRepository depends on this for background-context
        // change propagation from PublicSyncService merges into the viewContext.
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy

        #if DEBUG
        if !inMemory, storeLoadError == nil {
            deploySchemaIfModelChanged()
        }
        #endif
    }

    // MARK: - Container Factory

    /// Creates and configures an `NSPersistentCloudKitContainer` with a single private
    /// store description. Does NOT call `loadPersistentStores`.
    ///
    /// **Shared store removed (2026-04-18):** the prior CKShare-based sharing model
    /// required a second store with `.shared` scope. After switching to
    /// `PublicSyncService` + household code pairing, there is no shared zone to mirror —
    /// each device has a single private store, and partner sync runs through the public
    /// CloudKit database via raw `CKDatabase` operations.
    private static func configuredContainer(
        inMemory: Bool,
        iCloudAvailable: Bool
    ) -> NSPersistentCloudKitContainer {
        let container = NSPersistentCloudKitContainer(name: "CashOut")

        guard let privateDesc = container.persistentStoreDescriptions.first else {
            fatalError("No persistent store descriptions found")
        }

        if inMemory {
            privateDesc.url = URL(fileURLWithPath: "/dev/null")
            privateDesc.cloudKitContainerOptions = nil
        }

        privateDesc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        privateDesc.setOption(
            true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
        )
        privateDesc.shouldMigrateStoreAutomatically = true
        privateDesc.shouldInferMappingModelAutomatically = true
        privateDesc.shouldAddStoreAsynchronously = false

        if !inMemory {
            if iCloudAvailable {
                privateDesc.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: "iCloud.com.wagneraz.CashOut"
                )
            } else {
                // Guard against iOS 18+ data-loss bug when iCloud is disabled/signed out
                // (Apple Developer Forums thread 772015)
                privateDesc.cloudKitContainerOptions = nil
            }
        }

        container.persistentStoreDescriptions = [privateDesc]
        return container
    }

    // MARK: - Store Loading

    private func loadStores(inMemory: Bool) {
        for desc in container.persistentStoreDescriptions {
            precondition(
                desc.shouldAddStoreAsynchronously == false,
                "shouldAddStoreAsynchronously must be false — loadStores relies on synchronous callback"
            )
        }

        let loadStart = CFAbsoluteTimeGetCurrent()
        container.loadPersistentStores { desc, error in
            MainActor.assumeIsolated {
                let elapsed = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000
                if let error {
                    logger.fault("Store load FAILED in \(elapsed, format: .fixed(precision: 1))ms: \(error.localizedDescription)")
                    Self.logUnderlyingErrors(error)
                    if self.storeLoadError == nil {
                        self.storeLoadError = error
                    }
                    return
                }
                if inMemory {
                    self.privatePersistentStore = self.container.persistentStoreCoordinator.persistentStores.first
                    return
                }
                guard let storeURL = desc.url else { return }
                let store = self.container.persistentStoreCoordinator.persistentStore(for: storeURL)
                self.privatePersistentStore = store
                logger.info("Private store loaded in \(elapsed, format: .fixed(precision: 1))ms")
            }
        }
    }

    // MARK: - Error Logging

    private static func logUnderlyingErrors(_ error: Error) {
        let nsError = error as NSError
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            logger.fault("  Underlying: \(underlying.domain) \(underlying.code) — \(underlying.localizedDescription)")
        }
        if let underlyingMultiple = nsError.userInfo["NSUnderlyingErrors"] as? [NSError] {
            for (i, ue) in underlyingMultiple.enumerated() {
                logger.fault("  Underlying[\(i)]: \(ue.domain) \(ue.code) — \(ue.localizedDescription)")
            }
        }
    }

    // MARK: - DEBUG Store Recovery

    #if DEBUG
    private func destroyStoreFiles() {
        for desc in container.persistentStoreDescriptions {
            guard let url = desc.url else { continue }
            for suffix in ["", "-wal", "-shm", "-ckAssets"] {
                let fileURL = URL(fileURLWithPath: url.path + suffix)
                do {
                    try FileManager.default.removeItem(at: fileURL)
                } catch let error as NSError
                    where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
                    // File doesn't exist — expected for fresh installs or partial state
                } catch {
                    logger.fault("Failed to remove \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
    }

    private func deploySchemaIfModelChanged() {
        let stringIdentifiers = container.managedObjectModel.versionIdentifiers
            .compactMap { $0 as? String }
            .sorted()
        let currentVersion = stringIdentifiers.isEmpty
            ? container.managedObjectModel.entityVersionHashesByName.keys.sorted().joined(separator: "|")
            : stringIdentifiers.joined(separator: "|")
        let lastDeployed = UserDefaults.standard.string(forKey: Self.schemaInitializedVersionKey)
        guard lastDeployed != currentVersion else {
            logger.debug("initializeCloudKitSchema: skipped — version '\(currentVersion, privacy: .public)' already deployed")
            return
        }
        do {
            try container.initializeCloudKitSchema(options: [])
            UserDefaults.standard.set(currentVersion, forKey: Self.schemaInitializedVersionKey)
            logger.info("initializeCloudKitSchema: deployed for model version '\(currentVersion, privacy: .public)'")
        } catch {
            logger.error("CloudKit schema init failed: \(error.localizedDescription)")
        }
    }
    #endif

    // MARK: - Account Changes

    static let accountDidChange = Notification.Name("PersistenceController.accountDidChange")

    func observeAccountChanges() async {
        for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
            if Task.isCancelled { break }
            logger.info("iCloud account changed — clearing store reference")
            privatePersistentStore = nil
            storeLoadError = nil
            NotificationCenter.default.post(name: Self.accountDidChange, object: self)
        }
    }

    // MARK: - History Management

    func purgeOldHistory() async {
        guard storeLoadError == nil else {
            logger.debug("purgeOldHistory: skipped — store load error present")
            return
        }
        guard let privateStore = privatePersistentStore else {
            logger.debug("purgeOldHistory: skipped — private store unavailable")
            return
        }
        let sevenDaysAgo = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let purgeRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: sevenDaysAgo)
        purgeRequest.affectedStores = [privateStore]

        let context = container.newBackgroundContext()
        await context.perform {
            do {
                try context.execute(purgeRequest)
                logger.debug("purgeOldHistory: purged private-store history older than 7 days")
            } catch {
                logger.error("History purge failed: \(error.localizedDescription)")
            }
        }
    }
}
