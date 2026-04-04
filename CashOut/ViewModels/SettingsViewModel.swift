import Foundation
import CloudKit
@preconcurrency import CoreData

@MainActor
@Observable
final class SettingsViewModel {
    var isShowingShareSheet = false
    var hasPartner: Bool { cloudSharingService.isShared }
    var partnerDisplayName: String? { cloudSharingService.partnerName }
    var errorMessage: String?

    var activeShare: CKShare?
    var activeContainer: CKContainer?
    private(set) var isInviting = false

    private let cloudSharingService: CloudSharingServiceProtocol
    private let persistenceController: PersistenceController

    init(
        cloudSharingService: CloudSharingServiceProtocol = CloudSharingService(),
        persistenceController: PersistenceController = .shared
    ) {
        self.cloudSharingService = cloudSharingService
        self.persistenceController = persistenceController
    }

    func invitePartner() async {
        guard !isInviting else { return }
        isInviting = true
        errorMessage = nil

        do {
            let request: NSFetchRequest<Category> = Category.fetchRequest()
            if let privateStore = persistenceController.privatePersistentStore {
                request.affectedStores = [privateStore]
            }
            let categories = try persistenceController.container.viewContext.fetch(request)

            guard !categories.isEmpty else {
                errorMessage = "No categories found. Please restart the app."
                isInviting = false
                return
            }

            let (share, container) = try await cloudSharingService.createShare(for: categories)
            activeShare = share
            activeContainer = container
            isShowingShareSheet = true
        } catch {
            guard !Task.isCancelled else { isInviting = false; return }
            errorMessage = error.localizedDescription
            activeShare = nil
            activeContainer = nil
        }
        isInviting = false
    }

    func refreshSharingStatus() async {
        await cloudSharingService.checkSharingStatus()
    }

    func handleShareDismiss(_ share: CKShare?) {
        if let share {
            cloudSharingService.persistUpdatedShare(share)
            Task { await refreshSharingStatus() }
        }
        isShowingShareSheet = false
    }
}
