import Foundation
import CloudKit
@preconcurrency import CoreData
@testable import CashOut

@MainActor
final class MockCloudSharingService: CloudSharingServiceProtocol {

    // MARK: - Configurable State

    var isShared = false
    var partnerName: String? = nil

    // MARK: - Call Tracking

    var createShareCalled = false
    var checkSharingStatusCalled = false
    var persistUpdatedShareCalled = false
    var lastPersistedShare: CKShare?

    // MARK: - Configurable Results

    var createShareResult: Result<(CKShare, CKContainer), Error> = .failure(
        NSError(domain: "MockCloudSharingService", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "No handler set"])
    )

    // MARK: - Protocol Methods

    func createShare(for objects: [NSManagedObject]) async throws -> (CKShare, CKContainer) {
        createShareCalled = true
        return try createShareResult.get()
    }

    func checkSharingStatus() async {
        checkSharingStatusCalled = true
    }

    func persistUpdatedShare(_ share: CKShare) {
        persistUpdatedShareCalled = true
        lastPersistedShare = share
    }
}
