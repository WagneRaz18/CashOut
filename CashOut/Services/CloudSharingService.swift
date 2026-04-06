import Foundation
import CloudKit
@preconcurrency import CoreData
import os

@MainActor
protocol CloudSharingServiceProtocol {
    var isShared: Bool { get }
    var isShareOwner: Bool { get }
    var partnerName: String? { get }
    func createShare(for objects: [NSManagedObject]) async throws -> (CKShare, CKContainer)
    func checkSharingStatus() async
    func persistUpdatedShare(_ share: CKShare)
    func prepareObjectForSharedSave(_ object: NSManagedObject)
    func shareObjectsToHouseholdIfNeeded(_ objects: [NSManagedObject]) async throws
}

@MainActor
@Observable
final class CloudSharingService: CloudSharingServiceProtocol {
    static let shared = CloudSharingService()

    var isShared: Bool = false
    var partnerName: String? = nil

    var isShareOwner: Bool {
        guard let share = currentShare else { return false }
        return share.currentUserParticipant?.role == .owner
    }

    @ObservationIgnored private var currentShare: CKShare? = nil

    private let persistenceController: PersistenceController
    private static let containerIdentifier = "iCloud.com.wagneraz.CashOut"

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

        guard FileManager.default.ubiquityIdentityToken != nil else {
            throw NSError(
                domain: "CloudSharingService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Sign in to iCloud in Settings to invite a partner."]
            )
        }

        // Re-validate cached share before reuse (may have been revoked)
        if let existingShare = currentShare {
            let validationStore = isShareOwner
                ? persistenceController.privatePersistentStore
                : persistenceController.sharedPersistentStore
            if let store = validationStore {
                do {
                    let freshShares = try persistenceController.container.fetchShares(in: store)
                    if freshShares.contains(where: { $0.recordID == existingShare.recordID }) {
                        return (existingShare, CKContainer(identifier: Self.containerIdentifier))
                    }
                    // Share not found in store — revoked or deleted, create new
                    currentShare = nil
                } catch {
                    // Transient error (network, etc.) — keep cached share to avoid duplicate creation
                    os_log(.error, "fetchShares failed during share validation: %{public}@", error.localizedDescription)
                    return (existingShare, CKContainer(identifier: Self.containerIdentifier))
                }
            }
        }

        let (_, share, _) = try await persistenceController.container.share(objects, to: nil)
        currentShare = share
        share[CKShare.SystemFieldKey.title] = "CashOut Household"
        return (share, CKContainer(identifier: Self.containerIdentifier))
    }

    func checkSharingStatus() async {
        // 1. Check owner's private store for shares
        if let privateStore = persistenceController.privatePersistentStore {
            do {
                let privateShares = try persistenceController.container.fetchShares(in: privateStore)
                if let share = privateShares.first {
                    isShared = true
                    currentShare = share
                    extractPartnerInfo(from: share)
                    return
                }
            } catch {
                os_log(.error, "Failed to fetch shares from private store: %{public}@", error.localizedDescription)
            }
        }

        // 2. Check shared store for shares (partner perspective)
        if let sharedStore = persistenceController.sharedPersistentStore {
            do {
                let sharedShares = try persistenceController.container.fetchShares(in: sharedStore)
                if let share = sharedShares.first {
                    isShared = true
                    currentShare = share
                    extractPartnerInfo(from: share)
                    return
                }
            } catch {
                os_log(.error, "Failed to fetch shares from shared store: %{public}@", error.localizedDescription)
            }
        }

        // 3. No shares found — solo mode (only reset if both stores are loaded)
        guard persistenceController.privatePersistentStore != nil ||
              persistenceController.sharedPersistentStore != nil else {
            // Store references nil (e.g., mid-account-change) — don't reset sharing state
            return
        }
        isShared = false
        partnerName = nil
        currentShare = nil
    }

    func persistUpdatedShare(_ share: CKShare) {
        // Route to the correct store based on role
        let targetStore: NSPersistentStore?
        if isShareOwner {
            targetStore = persistenceController.privatePersistentStore
        } else {
            targetStore = persistenceController.sharedPersistentStore
        }
        guard let store = targetStore else { return }
        persistenceController.container.persistUpdatedShare(share, in: store) { _, error in
            if let error {
                os_log(.fault, "Failed to persist updated share: %{public}@", error.localizedDescription)
            }
        }
    }

    func prepareObjectForSharedSave(_ object: NSManagedObject) {
        guard isShared, !isShareOwner else { return }
        guard object.managedObjectContext != nil else {
            os_log(.error, "prepareObjectForSharedSave called with nil managedObjectContext")
            return
        }
        // Participant: assign to shared store so save goes to shared zone
        guard let sharedStore = persistenceController.sharedPersistentStore else { return }
        object.managedObjectContext?.assign(object, to: sharedStore)
    }

    func shareObjectsToHouseholdIfNeeded(_ objects: [NSManagedObject]) async throws {
        guard isShared, isShareOwner, let share = currentShare else { return }
        guard !objects.isEmpty else { return }
        // Guard: iCloud must be available
        guard FileManager.default.ubiquityIdentityToken != nil else {
            os_log(.error, "iCloud unavailable — expense saved locally but not shared to household zone")
            return
        }
        do {
            _ = try await persistenceController.container.share(objects, to: share)
        } catch {
            os_log(.error, "Failed to share expense to household zone: %{public}@", error.localizedDescription)
        }
    }

    // MARK: - Private

    private func extractPartnerInfo(from share: CKShare) {
        // Filter out the CURRENT user to find the OTHER person
        guard let currentUserRecordID = share.currentUserParticipant?.userIdentity.userRecordID else {
            // Can't identify current user — can't determine who the partner is
            partnerName = nil
            return
        }
        let otherParticipants = share.participants.filter { participant in
            participant.userIdentity.userRecordID != currentUserRecordID
        }

        // Accept only participants with .accepted status
        if let partner = otherParticipants.first(where: { $0.acceptanceStatus == .accepted }) {
            if let nameComponents = partner.userIdentity.nameComponents {
                partnerName = PersonNameComponentsFormatter.localizedString(
                    from: nameComponents, style: .short, options: []
                )
            } else {
                partnerName = "Partner"
            }
        } else {
            partnerName = nil
        }
    }
}
