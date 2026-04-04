@preconcurrency import CoreData
import CloudKit
import os

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
    var onSyncStatusChanged: (@MainActor (SyncStatus) -> Void)? { get set }
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
                onSyncStatusChanged?(syncStatus)
            }
        }
    }
    var onSyncStatusChanged: (@MainActor (SyncStatus) -> Void)?

    @ObservationIgnored private var consecutiveFailures: Int = 0
    @ObservationIgnored private var lastSuccessDate: Date = Date()
    @ObservationIgnored private var isMonitoring = false
    @ObservationIgnored private var initialCheckTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var accountTask: Task<Void, Never>?
    @ObservationIgnored private static let failureThreshold = 3
    @ObservationIgnored private static let failureWindowSeconds: TimeInterval = 300 // 5 min

    init() {}

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Cancel previous tasks if any (defensive)
        initialCheckTask?.cancel()
        eventTask?.cancel()
        accountTask?.cancel()

        // Check iCloud account status immediately
        initialCheckTask = Task { await checkICloudAccount() }

        // Monitor CloudKit sync events
        eventTask = Task {
            for await notification in NotificationCenter.default.notifications(
                named: NSPersistentCloudKitContainer.eventChangedNotification
            ) {
                guard !Task.isCancelled else { break }
                guard let event = notification.userInfo?[
                    NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                ] as? NSPersistentCloudKitContainer.Event else { continue }

                // Only process completed events (endDate != nil)
                guard event.endDate != nil else { continue }

                if event.succeeded {
                    consecutiveFailures = 0
                    lastSuccessDate = Date()
                    if syncStatus == .syncFailure {
                        syncStatus = .healthy
                    }
                } else {
                    consecutiveFailures += 1
                    let timeSinceSuccess = Date().timeIntervalSince(lastSuccessDate)
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
            for await _ in NotificationCenter.default.notifications(
                named: .CKAccountChanged
            ) {
                guard !Task.isCancelled else { break }
                await checkICloudAccount()
            }
        }
    }

    // ubiquityIdentityToken is synchronous and consistent with PersistenceController's
    // iCloud availability check. Limitation: does not distinguish .restricted from
    // .available — in parental-control/MDM scenarios, token is non-nil but CloudKit
    // access denied. Acceptable at 2-user personal-use scale.
    private func checkICloudAccount() async {
        if FileManager.default.ubiquityIdentityToken == nil {
            syncStatus = .noICloudAccount
        } else if syncStatus == .noICloudAccount {
            syncStatus = .healthy
            consecutiveFailures = 0
            lastSuccessDate = Date()
        }
    }
}
