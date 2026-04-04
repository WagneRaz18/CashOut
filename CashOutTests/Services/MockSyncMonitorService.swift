@testable import CashOut

@MainActor
final class MockSyncMonitorService: SyncMonitorServiceProtocol {
    var syncStatus: SyncStatus = .healthy
    var onSyncStatusChanged: [(@MainActor (SyncStatus) -> Void)] = []
    var startMonitoringCalled = false

    func startMonitoring() {
        startMonitoringCalled = true
    }
}
