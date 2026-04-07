@preconcurrency import CoreData
import CloudKit
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "PersistenceController")

final class PersistenceController: @unchecked Sendable {
    static let shared = PersistenceController()

    static let preview = PersistenceController(inMemory: true)

    /// `private(set) var` (not `let`) to allow replacement during DEBUG destructive-migration fallback.
    /// The swap happens entirely within `init`, before `shared` is visible to any caller.
    private(set) var container: NSPersistentCloudKitContainer
    private(set) var privatePersistentStore: NSPersistentStore?
    private(set) var sharedPersistentStore: NSPersistentStore?
    private(set) var storeLoadError: Error?

    init(inMemory: Bool = false) {
        logger.info("PersistenceController.init — inMemory=\(inMemory)")

        let iCloudAvailable = !inMemory && FileManager.default.ubiquityIdentityToken != nil
        if !inMemory { logger.info("iCloud available: \(iCloudAvailable)") }

        container = Self.configuredContainer(inMemory: inMemory, iCloudAvailable: iCloudAvailable)
        loadStores(inMemory: inMemory)

        // Destructive fallback — if stores failed to load (e.g. model changed during
        // development), destroy the SQLite files and retry with a fresh container.
        // Only in DEBUG to avoid silently deleting user data in production.
        #if DEBUG
        if storeLoadError != nil, !inMemory {
            logger.warning("Store load failed — destroying stores and retrying (DEBUG only)")
            destroyStoreFiles()
            storeLoadError = nil
            privatePersistentStore = nil
            sharedPersistentStore = nil
            container = Self.configuredContainer(inMemory: inMemory, iCloudAvailable: iCloudAvailable)
            loadStores(inMemory: inMemory)

            if storeLoadError != nil {
                logger.fault("Store load FAILED even after destroying stores — giving up")
            } else {
                logger.info("Store load succeeded after rebuild")
            }
        }
        #endif

        // Known v1 limitation: .changeTokenExpired triggers full re-import but cannot
        // reconcile records deleted past the CloudKit tombstone window (~30 days).
        // Orphaned local records may persist. Acceptable at 2-user scale.

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
        if !inMemory, storeLoadError == nil {
            do {
                try container.initializeCloudKitSchema(options: [])
            } catch {
                logger.error("CloudKit schema init failed: \(error.localizedDescription)")
            }
        }
        #endif
    }

    // MARK: - Container Factory

    /// Creates and configures an `NSPersistentCloudKitContainer` with private and
    /// (optionally) shared store descriptions. Does NOT call `loadPersistentStores`.
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

        return container
    }

    // MARK: - Store Loading

    /// Calls `loadPersistentStores` and populates `privatePersistentStore`,
    /// `sharedPersistentStore`, and `storeLoadError`.
    ///
    /// `loadPersistentStores` fires its completion handler synchronously (on the calling
    /// thread) for on-disk SQLite stores. All properties are set by the time this method
    /// returns. The `[weak self]` capture is intentional — it is safe here because `self`
    /// is retained by the caller (init or the static let assignment) for the duration of
    /// the synchronous callback.
    private func loadStores(inMemory: Bool) {
        let sharedStoreURL: URL? = {
            guard !inMemory, container.persistentStoreDescriptions.count > 1 else { return nil }
            return container.persistentStoreDescriptions[1].url
        }()

        let loadStart = CFAbsoluteTimeGetCurrent()
        container.loadPersistentStores { [weak self] desc, error in
            let elapsed = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000
            if let error {
                logger.fault("Store load FAILED in \(elapsed, format: .fixed(precision: 1))ms: \(error.localizedDescription)")
                Self.logUnderlyingErrors(error)
                self?.storeLoadError = error
                return
            }
            guard !inMemory, let self, let storeURL = desc.url else { return }
            let store = self.container.persistentStoreCoordinator.persistentStore(for: storeURL)
            if storeURL == sharedStoreURL {
                self.sharedPersistentStore = store
                logger.info("Shared store loaded in \(elapsed, format: .fixed(precision: 1))ms")
            } else {
                self.privatePersistentStore = store
                logger.info("Private store loaded in \(elapsed, format: .fixed(precision: 1))ms")
            }
        }
    }

    // MARK: - Error Logging

    /// Traverses the Core Data error chain to surface the real underlying error.
    /// Core Data wraps failures inside `NSUnderlyingErrorKey` / `NSUnderlyingErrors`.
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
    /// Removes all SQLite and CloudKit metadata files for every store description.
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
    #endif

    // MARK: - Account Changes

    static let accountDidChange = Notification.Name("PersistenceController.accountDidChange")

    @objc private func handleAccountChange() {
        // CKAccountChanged may fire on an arbitrary thread — dispatch to main for thread safety
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            logger.info("iCloud account changed — clearing shared store reference")
            self.sharedPersistentStore = nil
            NotificationCenter.default.post(name: Self.accountDidChange, object: self)
        }
    }

    // MARK: - History Management

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
