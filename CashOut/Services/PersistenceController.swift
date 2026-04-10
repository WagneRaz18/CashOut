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
    private(set) var sharedPersistentStore: NSPersistentStore?
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

        #if DEBUG
        if !inMemory, storeLoadError == nil {
            deploySchemaIfModelChanged()
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
        // Explicit: the loadStores callback timing contract depends on this being false.
        privateDesc.shouldAddStoreAsynchronously = false

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
            guard let privateURL = privateDesc.url else {
                fatalError("Private store description has no URL — verify Core Data model 'CashOut' exists")
            }
            let sharedStoreURL = privateURL.deletingLastPathComponent()
                .appendingPathComponent("CashOut-shared.sqlite")

            let sharedDesc = NSPersistentStoreDescription(url: sharedStoreURL)
            if iCloudAvailable {
                // Build the options object fully BEFORE assigning it to the description.
                // Avoids the fragile `desc.options?.databaseScope = ...` optional-chain
                // mutation, which depends on the property returning the same reference on get.
                let sharedOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: "iCloud.com.wagneraz.CashOut"
                )
                sharedOptions.databaseScope = .shared
                sharedDesc.cloudKitContainerOptions = sharedOptions
            } else {
                // Match the private-store iOS 18 guard — explicit nil even though a
                // freshly-constructed description defaults to nil, so a future refactor
                // that hoists construction above the iCloud check can't silently
                // reintroduce the data-loss bug.
                sharedDesc.cloudKitContainerOptions = nil
            }
            sharedDesc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            sharedDesc.setOption(
                true as NSNumber,
                forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
            )
            sharedDesc.shouldMigrateStoreAutomatically = true
            sharedDesc.shouldInferMappingModelAutomatically = true
            sharedDesc.shouldAddStoreAsynchronously = false

            container.persistentStoreDescriptions = [privateDesc, sharedDesc]
        }

        return container
    }

    // MARK: - Store Loading

    /// Calls `loadPersistentStores` and populates `privatePersistentStore`,
    /// `sharedPersistentStore`, and `storeLoadError`.
    ///
    /// Contract: `shouldAddStoreAsynchronously = false` is set on every description, so
    /// the completion handler fires synchronously on the calling thread. Since this
    /// type is `@MainActor` and `init` runs on main, the callback also runs on main —
    /// `MainActor.assumeIsolated` is therefore sound for the mutations below.
    private func loadStores(inMemory: Bool) {
        // Machine-verify the MainActor.assumeIsolated contract below.
        for desc in container.persistentStoreDescriptions {
            precondition(
                desc.shouldAddStoreAsynchronously == false,
                "shouldAddStoreAsynchronously must be false — loadStores relies on synchronous callback"
            )
        }

        let sharedStoreURL: URL? = {
            guard !inMemory, container.persistentStoreDescriptions.count > 1 else { return nil }
            return container.persistentStoreDescriptions[1].url
        }()

        let loadStart = CFAbsoluteTimeGetCurrent()
        container.loadPersistentStores { desc, error in
            MainActor.assumeIsolated {
                let elapsed = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000
                if let error {
                    logger.fault("Store load FAILED in \(elapsed, format: .fixed(precision: 1))ms: \(error.localizedDescription)")
                    Self.logUnderlyingErrors(error)
                    // First-error-wins: preserve the private store's error (loaded first)
                    // rather than letting the shared store's error overwrite it.
                    if self.storeLoadError == nil {
                        self.storeLoadError = error
                    }
                    return
                }
                if inMemory {
                    // Single in-memory store acts as private store for seeding/tests
                    self.privatePersistentStore = self.container.persistentStoreCoordinator.persistentStores.first
                    return
                }
                guard let storeURL = desc.url else { return }
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

    /// Pushes the Core Data model to CloudKit Development schema only when the model's
    /// version identifier changes — avoids a network round-trip on every DEBUG launch.
    private func deploySchemaIfModelChanged() {
        // Deterministic version string — sort + join to survive non-deterministic
        // Set<AnyHashable> ordering and multi-identifier models.
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

    /// Observes `CKAccountChanged` as an async sequence. Call this once from the
    /// root view's `.task {}` — it runs for the lifetime of the task.
    ///
    /// On account change this tears down BOTH store references and posts
    /// `accountDidChange` so consumers can trigger a full state reset. The
    /// container itself cannot be mutated at runtime — consumers should treat
    /// `accountDidChange` as a hint to prompt the user to relaunch.
    func observeAccountChanges() async {
        for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
            if Task.isCancelled { break }
            logger.info("iCloud account changed — clearing store references")
            sharedPersistentStore = nil
            privatePersistentStore = nil
            // Reset error state alongside store nil-outs so downstream gates
            // (purgeOldHistory, deploySchemaIfModelChanged) don't stay blocked
            // on an error from the prior account's session.
            storeLoadError = nil
            NotificationCenter.default.post(name: Self.accountDidChange, object: self)
        }
    }

    // MARK: - History Management

    /// Purges history older than 7 days from the private store. Run from app
    /// startup `.task {}` — not `init` — so the main thread isn't blocked on launch.
    ///
    /// Scoped to the private store only: the shared store's history is managed by
    /// `NSPersistentCloudKitContainer`'s own export-tracking machinery, and
    /// client-side purges there can trigger phantom re-exports.
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
