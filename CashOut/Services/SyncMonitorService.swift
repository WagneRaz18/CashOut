@preconcurrency import CoreData
import CloudKit
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "SyncMonitorService")

// MARK: - SyncStatus

enum SyncStatus: Equatable {
    case healthy            // Normal operation, no issues
    case noICloudAccount    // iCloud not signed in
    case syncFailure        // Persistent sync errors detected
}

// MARK: - Protocol

@MainActor
protocol SyncMonitorServiceProtocol: AnyObject {
    var syncStatus: SyncStatus { get }
    var onSyncStatusChanged: [(@MainActor (SyncStatus) -> Void)] { get set }
    func startMonitoring()
}

// MARK: - Implementation

@MainActor
@Observable
final class SyncMonitorService: SyncMonitorServiceProtocol {
    static let shared = SyncMonitorService()

    var syncStatus: SyncStatus = .healthy {
        didSet {
            if oldValue != syncStatus {
                logger.info("Sync status: \(String(describing: oldValue)) → \(String(describing: self.syncStatus))")
                for handler in onSyncStatusChanged { handler(syncStatus) }
            }
        }
    }
    @ObservationIgnored
    var onSyncStatusChanged: [(@MainActor (SyncStatus) -> Void)] = []

    @ObservationIgnored private var consecutiveFailures: Int = 0
    @ObservationIgnored private var lastSuccessDate: Date = .distantPast
    @ObservationIgnored private var isMonitoring = false
    @ObservationIgnored private var initialCheckTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var accountTask: Task<Void, Never>?
    @ObservationIgnored private static let failureThreshold = 3
    @ObservationIgnored private static let failureWindowSeconds: TimeInterval = 300 // 5 min

    init() {}

    func startMonitoring() {
        guard !isMonitoring else {
            logger.debug("startMonitoring: already monitoring — skipped")
            return
        }
        logger.info("startMonitoring: initializing sync monitor")
        isMonitoring = true

        // Cancel previous tasks if any (defensive)
        initialCheckTask?.cancel()
        eventTask?.cancel()
        accountTask?.cancel()

        // Check iCloud account status immediately
        initialCheckTask = Task { await checkICloudAccount() }

        // Monitor CloudKit sync events
        eventTask = Task {
            logger.debug("CloudKit event listener started")
            for await notification in NotificationCenter.default.notifications(
                named: NSPersistentCloudKitContainer.eventChangedNotification
            ) {
                guard !Task.isCancelled else { break }
                guard let event = notification.userInfo?[
                    NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                ] as? NSPersistentCloudKitContainer.Event else { continue }

                // Only process completed events (endDate != nil)
                guard event.endDate != nil else {
                    logger.debug("CloudKit event: in-progress (type=\(event.type.rawValue))")
                    continue
                }

                if event.succeeded {
                    logger.debug("CloudKit event: succeeded (type=\(event.type.rawValue))")
                    consecutiveFailures = 0
                    lastSuccessDate = Date()
                    if syncStatus == .syncFailure {
                        syncStatus = .healthy
                    }
                } else {
                    // Don't promote to .syncFailure while in .noICloudAccount — the root
                    // cause is no account, not sync failure
                    guard syncStatus != .noICloudAccount else { continue }
                    consecutiveFailures += 1
                    let timeSinceSuccess = Date().timeIntervalSince(lastSuccessDate)
                    logger.warning("CloudKit event: FAILED (type=\(event.type.rawValue), error=\(event.error?.localizedDescription ?? "nil"), consecutiveFailures=\(self.consecutiveFailures), secSinceSuccess=\(Int(timeSinceSuccess)))")
                    if consecutiveFailures >= Self.failureThreshold
                        && timeSinceSuccess > Self.failureWindowSeconds {
                        syncStatus = .syncFailure
                    }
                    // Transient errors below threshold: invisible (AC #7)
                }
            }
        }

        // Monitor iCloud account changes
        accountTask = Task {
            logger.debug("iCloud account change listener started")
            for await _ in NotificationCenter.default.notifications(
                named: .CKAccountChanged
            ) {
                guard !Task.isCancelled else { break }
                logger.info("CKAccountChanged notification received")
                await checkICloudAccount()
            }
        }
    }

    // ubiquityIdentityToken is synchronous and consistent with PersistenceController's
    // iCloud availability check. Limitation: does not distinguish .restricted from
    // .available — in parental-control/MDM scenarios, token is non-nil but CloudKit
    // access denied. Acceptable at 2-user personal-use scale.
    private func checkICloudAccount() async {
        let hasToken = FileManager.default.ubiquityIdentityToken != nil
        logger.info("checkICloudAccount: ubiquityIdentityToken=\(hasToken ? "present" : "nil")")
        if !hasToken {
            syncStatus = .noICloudAccount
        } else if syncStatus == .noICloudAccount {
            logger.info("checkICloudAccount: iCloud restored — resetting to healthy")
            syncStatus = .healthy
            consecutiveFailures = 0
            lastSuccessDate = Date()
        }
    }
}
