import Foundation
import CloudKit
@preconcurrency import CoreData
import os

@MainActor
@Observable
final class SettingsViewModel {
    @ObservationIgnored
    private var refreshTask: Task<Void, Never>?

    var isShowingShareSheet = false
    var hasPartner: Bool { cloudSharingService.isShared }
    var partnerDisplayName: String? { cloudSharingService.partnerName }
    var errorMessage: String?
    var categories: [CategoryData] = []
    private(set) var isSavingCategory = false
    var categorySaveError: String?

    var activeShare: CKShare?
    var activeContainer: CKContainer?
    private(set) var isInviting = false

    @ObservationIgnored
    private let cloudSharingService: CloudSharingServiceProtocol
    @ObservationIgnored
    private let persistenceController: PersistenceController
    @ObservationIgnored
    private let categoryRepository: CategoryRepositoryProtocol
    @ObservationIgnored
    private let hapticService: HapticServiceProtocol

    init(
        cloudSharingService: CloudSharingServiceProtocol = CloudSharingService.shared,
        persistenceController: PersistenceController = .shared,
        categoryRepository: CategoryRepositoryProtocol = CategoryRepository(),
        hapticService: HapticServiceProtocol = HapticService()
    ) {
        self.cloudSharingService = cloudSharingService
        self.persistenceController = persistenceController
        self.categoryRepository = categoryRepository
        self.hapticService = hapticService
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

    func saveCategory(name: String, iconName: String, colorName: String, existingID: UUID?) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        // Prevent accidental demotion of default categories
        if let existingID, categories.first(where: { $0.id == existingID })?.isDefault == true {
            return
        }

        guard !isSavingCategory else { return }
        isSavingCategory = true
        defer { isSavingCategory = false }
        categorySaveError = nil

        let id = existingID ?? UUID()
        let sortOrder: Int16 = existingID != nil
            ? (categories.first { $0.id == existingID }?.sortOrder ?? Int16(categories.count))
            : Int16(categories.count)

        let data = CategoryData(
            id: id,
            name: trimmedName,
            iconName: iconName,
            colorName: colorName,
            isDefault: false,
            sortOrder: sortOrder
        )

        do {
            try await categoryRepository.saveCategory(data)
            guard !Task.isCancelled else { return }
            hapticService.trigger(.saveTap)
            await loadCategories()
        } catch {
            guard !Task.isCancelled else { return }
            hapticService.trigger(.error)
            categorySaveError = "Failed to save category. Please try again."
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
        refreshTask?.cancel()
        refreshTask = Task { await refreshSharingStatus() }
    }
}
