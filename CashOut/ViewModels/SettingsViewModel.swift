import Foundation
import CloudKit
@preconcurrency import CoreData
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "SettingsViewModel")

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
        logger.debug("SettingsViewModel.init")
    }

    func invitePartner() async {
        guard !isInviting else {
            logger.debug("invitePartner: already inviting — skipped")
            return
        }
        logger.info("invitePartner: starting share creation flow")
        isInviting = true
        defer { isInviting = false }
        errorMessage = nil

        do {
            let request: NSFetchRequest<Category> = Category.fetchRequest()
            if let privateStore = persistenceController.privatePersistentStore {
                request.affectedStores = [privateStore]
            }
            let categories = try persistenceController.container.viewContext.fetch(request)
            logger.info("invitePartner: found \(categories.count) categories to share")

            guard !categories.isEmpty else {
                logger.error("invitePartner: no categories found — cannot create share")
                errorMessage = "No categories found. Please restart the app."
                return
            }

            let (share, container) = try await cloudSharingService.createShare(for: categories)
            logger.info("invitePartner: share created successfully")
            activeShare = share
            activeContainer = container
            isShowingShareSheet = true
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("invitePartner: FAILED — \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            activeShare = nil
            activeContainer = nil
        }
    }

    func loadCategories() async {
        logger.debug("loadCategories: fetching")
        do {
            let result = try await categoryRepository.fetchCategories()
            guard !Task.isCancelled else { return }
            logger.info("loadCategories: loaded \(result.count) categories")
            categories = result
        } catch {
            guard !Task.isCancelled else { return }
            // Categories are seeded at startup — empty state is infrastructure failure.
            // No errorMessage set — category list in Settings is informational only.
            // The entry screen has its own independent category loading path.
            logger.error("loadCategories: FAILED — \(error.localizedDescription)")
            categories = []
        }
    }

    func saveCategory(name: String, iconName: String, colorName: String, existingID: UUID?) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        // Prevent accidental demotion of default categories
        if let existingID, categories.first(where: { $0.id == existingID })?.isDefault == true {
            logger.warning("saveCategory: attempted to modify default category — blocked")
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

        logger.info("saveCategory: \(existingID != nil ? "updating" : "creating") '\(trimmedName)' id=\(id)")

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
            logger.info("saveCategory: success")
            hapticService.trigger(.saveTap)
            await loadCategories()
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("saveCategory: FAILED — \(error.localizedDescription)")
            hapticService.trigger(.error)
            categorySaveError = "Failed to save category. Please try again."
        }
    }

    func refreshSharingStatus() async {
        logger.debug("refreshSharingStatus: checking")
        await cloudSharingService.checkSharingStatus()
        logger.debug("refreshSharingStatus: done — isShared=\(self.cloudSharingService.isShared)")
    }

    func handleShareDismiss(_ share: CKShare?) {
        logger.info("handleShareDismiss: share=\(share != nil ? "present" : "nil")")
        if let share {
            cloudSharingService.persistUpdatedShare(share)
        }
        isShowingShareSheet = false
        refreshTask?.cancel()
        refreshTask = Task { await refreshSharingStatus() }
    }
}
