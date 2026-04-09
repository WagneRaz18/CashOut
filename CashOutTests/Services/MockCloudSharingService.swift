import Foundation
import CloudKit
@preconcurrency import CoreData
@testable import CashOut

@MainActor
final class MockCloudSharingService: CloudSharingServiceProtocol {

    // MARK: - Configurable State

    var isShared = false
    var isShareOwner = false
    var partnerName: String? = nil

    // MARK: - Call Tracking

    var createShareCalled = false
    var checkSharingStatusCalled = false
    var persistUpdatedShareCalled = false
    var prepareObjectForSharedSaveCalled = false
    var shareObjectsToHouseholdCalled = false
    var resetStateCalled = false
    var cancelShareCalled = false
    var lastPersistedShare: CKShare?

    var cancelShareShouldThrow = false

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

    func prepareObjectForSharedSave(_ object: NSManagedObject) {
        prepareObjectForSharedSaveCalled = true
    }

    func shareObjectsToHouseholdIfNeeded(_ objects: [NSManagedObject]) async throws {
        shareObjectsToHouseholdCalled = true
    }

    func resetState() {
        resetStateCalled = true
        isShared = false
        isShareOwner = false
        partnerName = nil
    }

    func cancelShare() async throws {
        cancelShareCalled = true
        if cancelShareShouldThrow {
            throw NSError(domain: "MockCloudSharingService", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Cancel failed"])
        }
        isShared = false
        isShareOwner = false
        partnerName = nil
    }
}
