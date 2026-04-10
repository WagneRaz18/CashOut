import Foundation
import CloudKit
@preconcurrency import CoreData
@testable import CashOut

@MainActor
final class MockCloudSharingService: CloudSharingServiceProtocol {

    // MARK: - Configurable State

    var state: SharingState = .solo
    var isShareOwner = false

    // MARK: - Call Tracking

    var createShareCalled = false
    var checkSharingStatusCalled = false
    var persistUpdatedShareCalled = false
    var prepareObjectForSharedSaveCalled = false
    var shareObjectsToHouseholdCalled = false
    var resetStateCalled = false
    var cancelShareCalled = false
    var finalizeShareOutcomeCalled = false
    var lastPersistedShare: CKShare?
    var lastFinalizedShare: CKShare?

    var cancelShareShouldThrow = false

    // MARK: - Configurable Results

    var createShareResult: Result<(CKShare, CKContainer), Error> = .failure(
        NSError(domain: "MockCloudSharingService", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "No handler set"])
    )

    /// Optional state the mock transitions to when `finalizeShareOutcome` is called.
    /// Tests set this to verify VM behavior when the service reports an outcome.
    var finalizeShareOutcomeResultState: SharingState?

    // MARK: - Protocol Methods

    func createShare(for objects: [NSManagedObject]) async throws -> (CKShare, CKContainer) {
        createShareCalled = true
        let result = try createShareResult.get()
        state = .draft
        return result
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
        state = .solo
        isShareOwner = false
    }

    func cancelShare() async throws {
        cancelShareCalled = true
        if cancelShareShouldThrow {
            throw NSError(domain: "MockCloudSharingService", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Cancel failed"])
        }
        state = .solo
        isShareOwner = false
    }

    func finalizeShareOutcome(_ updatedShare: CKShare?) async {
        finalizeShareOutcomeCalled = true
        lastFinalizedShare = updatedShare
        if let resultState = finalizeShareOutcomeResultState {
            state = resultState
        }
    }
}
