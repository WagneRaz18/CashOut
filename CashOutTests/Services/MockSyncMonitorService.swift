@testable import CashOut

@MainActor
final class MockSyncMonitorService: SyncMonitorServiceProtocol {
    var syncStatus: SyncStatus = .healthy
    var onSyncStatusChanged: [(@MainActor (SyncStatus) -> Void)] = []
    var startMonitoringCalled = false
    var stopMonitoringCalled = false

    func startMonitoring() {
        startMonitoringCalled = true
    }

    func stopMonitoring() {
        stopMonitoringCalled = true
    }
}
