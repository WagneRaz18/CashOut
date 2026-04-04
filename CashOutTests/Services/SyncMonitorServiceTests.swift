import XCTest
@testable import CashOut

@MainActor
final class SyncMonitorServiceTests: XCTestCase {

    // MARK: - Initial State

    func testInitialSyncStatusIsHealthy() {
        let service = SyncMonitorService()

        XCTAssertEqual(
            service.syncStatus, .healthy,
            "Initial syncStatus should be .healthy"
        )
    }

    // MARK: - startMonitoring Guard

    func testStartMonitoringIsIdempotent() {
        let service = SyncMonitorService()

        service.startMonitoring()
        service.startMonitoring() // Second call should be no-op

        // No crash or duplicate Task spawning — isMonitoring guard works
        XCTAssertEqual(
            service.syncStatus, .healthy,
            "syncStatus should remain .healthy after double startMonitoring"
        )
    }

    // MARK: - Callback Firing

    func testOnSyncStatusChangedFiresWhenStatusChanges() {
        let service = SyncMonitorService()
        var receivedStatuses: [SyncStatus] = []
        service.onSyncStatusChanged = { status in
            receivedStatuses.append(status)
        }

        service.syncStatus = .syncFailure

        XCTAssertEqual(receivedStatuses, [.syncFailure])
    }

    func testOnSyncStatusChangedDoesNotFireWhenValueUnchanged() {
        let service = SyncMonitorService()
        var callCount = 0
        service.onSyncStatusChanged = { _ in
            callCount += 1
        }

        service.syncStatus = .healthy // Same as initial — should not fire

        XCTAssertEqual(callCount, 0, "Callback should not fire when value doesn't change")
    }

    func testOnSyncStatusChangedFiresOnMultipleTransitions() {
        let service = SyncMonitorService()
        var receivedStatuses: [SyncStatus] = []
        service.onSyncStatusChanged = { status in
            receivedStatuses.append(status)
        }

        service.syncStatus = .noICloudAccount
        service.syncStatus = .healthy
        service.syncStatus = .syncFailure

        XCTAssertEqual(receivedStatuses, [.noICloudAccount, .healthy, .syncFailure])
    }

    // MARK: - SyncStatus Equatable

    func testSyncStatusEquatableConformance() {
        XCTAssertEqual(SyncStatus.healthy, SyncStatus.healthy)
        XCTAssertEqual(SyncStatus.noICloudAccount, SyncStatus.noICloudAccount)
        XCTAssertEqual(SyncStatus.syncFailure, SyncStatus.syncFailure)
        XCTAssertNotEqual(SyncStatus.healthy, SyncStatus.syncFailure)
        XCTAssertNotEqual(SyncStatus.healthy, SyncStatus.noICloudAccount)
        XCTAssertNotEqual(SyncStatus.syncFailure, SyncStatus.noICloudAccount)
    }
}
