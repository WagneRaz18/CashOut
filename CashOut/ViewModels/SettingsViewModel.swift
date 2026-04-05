import Foundation
import CloudKit
@preconcurrency import CoreData
import os

@MainActor
@Observable
final class SettingsViewModel {
    var isShowingShareSheet = false
    var hasPartner: Bool { cloudSharingService.isShared }
    var partnerDisplayName: String? { cloudSharingService.partnerName }
    var errorMessage: String?
    var categories: [CategoryData] = []

    var activeShare: CKShare?
    var activeContainer: CKContainer?
    private(set) var isInviting = false

    @ObservationIgnored
    private let cloudSharingService: CloudSharingServiceProtocol
    private let persistenceController: PersistenceController
    @ObservationIgnored
    private let categoryRepository: CategoryRepositoryProtocol

    init(
        cloudSharingService: CloudSharingServiceProtocol = CloudSharingService.shared,
        persistenceController: PersistenceController = .shared,
        categoryRepository: CategoryRepositoryProtocol = CategoryRepository()
    ) {
        self.cloudSharingService = cloudSharingService
        self.persistenceController = persistenceController
        self.categoryRepository = categoryRepository
    }

    func invitePartner() async {
        guard !isInviting else { return }
        isInviting = true
        defer { isInviting = false }
        errorMessage = nil

        do {
            let request: NSFetchRequest<Category> = Category.fetchRequest()
            if let privateStore = persistenceController.privatePersistentStore {
                request.affectedStores = [privateStore]
            }
            let categories = try persistenceController.container.viewContext.fetch(request)

            guard !categories.isEmpty else {
                errorMessage = "No categories found. Please restart the app."
                return
            }

            let (share, container) = try await cloudSharingService.createShare(for: categories)
            activeShare = share
            activeContainer = container
            isShowingShareSheet = true
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            activeShare = nil
            activeContainer = nil
        }
    }

    func loadCategories() async {
        do {
            let result = try await categoryRepository.fetchCategories()
            guard !Task.isCancelled else { return }
            categories = result
        } catch {
            guard !Task.isCancelled else { return }
            // Categories are seeded at startup — empty state is infrastructure failure.
            // No errorMessage set — category list in Settings is informational only.
            // The entry screen has its own independent category loading path.
            os_log(.error, "SettingsViewModel: loadCategories failed: %{public}@", error.localizedDescription)
            categories = []
        }
    }

    func refreshSharingStatus() async {
        await cloudSharingService.checkSharingStatus()
    }

    func handleShareDismiss(_ share: CKShare?) {
        if let share {
            cloudSharingService.persistUpdatedShare(share)
        }
        isShowingShareSheet = false
        Task { await refreshSharingStatus() }
    }
}
