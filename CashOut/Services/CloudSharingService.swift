import Foundation
import CloudKit
@preconcurrency import CoreData
import os

@MainActor
protocol CloudSharingServiceProtocol {
    var isShared: Bool { get }
    var partnerName: String? { get }
    func createShare(for objects: [NSManagedObject]) async throws -> (CKShare, CKContainer)
    func checkSharingStatus() async
    func persistUpdatedShare(_ share: CKShare)
}

@MainActor
@Observable
final class CloudSharingService: CloudSharingServiceProtocol {
    var isShared: Bool = false
    var partnerName: String? = nil
    @ObservationIgnored private var currentShare: CKShare? = nil

    private let persistenceController: PersistenceController

    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    func createShare(for objects: [NSManagedObject]) async throws -> (CKShare, CKContainer) {
        guard !objects.isEmpty else {
            throw NSError(
                domain: "CloudSharingService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot create share with no objects — at least one managed object is required"]
            )
        }

        let (_, share, _) = try await persistenceController.container.share(objects, to: nil)
        currentShare = share
        share[CKShare.SystemFieldKey.title] = "CashOut Household"
        return (share, CKContainer.default())
    }

    func checkSharingStatus() async {
        guard let privateStore = persistenceController.privatePersistentStore else {
            // inMemory/preview mode — solo state
            isShared = false
            partnerName = nil
            currentShare = nil
            return
        }

        do {
            let shares = try persistenceController.container.fetchShares(in: privateStore)
            if let share = shares.first {
                isShared = true
                currentShare = share
                extractPartnerInfo(from: share)
            } else {
                isShared = false
                partnerName = nil
                currentShare = nil
            }
        } catch {
            os_log(.error, "Failed to fetch shares: %{public}@", error.localizedDescription)
            isShared = false
            partnerName = nil
            currentShare = nil
        }
    }

    func persistUpdatedShare(_ share: CKShare) {
        guard let privateStore = persistenceController.privatePersistentStore else { return }
        persistenceController.container.persistUpdatedShare(share, in: privateStore) { _, error in
            if let error {
                os_log(.fault, "Failed to persist updated share: %{public}@", error.localizedDescription)
            }
        }
    }

    // MARK: - Private

    private func extractPartnerInfo(from share: CKShare) {
        let nonOwnerParticipants = share.participants.filter { $0.role != .owner }
        guard let partner = nonOwnerParticipants.first else {
            partnerName = nil
            return
        }

        if let nameComponents = partner.userIdentity.nameComponents {
            partnerName = PersonNameComponentsFormatter.localizedString(
                from: nameComponents,
                style: .default,
                options: []
            )
        } else {
            partnerName = "Partner"
        }
    }
}
