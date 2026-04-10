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
    @ObservationIgnored
    private var categoryShareTask: Task<Void, Never>?

    var isShowingShareSheet = false

    /// True iff a partner has accepted the invitation. Derived from `SharingState.connected`.
    var hasPartner: Bool {
        if case .connected = cloudSharingService.state { return true }
        return false
    }

    /// True iff the owner has dispatched an invite that is awaiting acceptance.
    /// Explicitly false for `.draft` (sheet open, no invite sent yet) — that was the
    /// source of the original stuck "Invitation Pending" bug.
    var isPendingInvitation: Bool {
        if case .pending = cloudSharingService.state { return true }
        return false
    }

    /// Partner's display name, only meaningful in the connected state.
    var partnerDisplayName: String? {
        if case .connected(let name) = cloudSharingService.state { return name }
        return nil
    }

    var errorMessage: String?
    var categories: [CategoryData] = []
    private(set) var isSavingCategory = false
    var categorySaveError: String?
    private(set) var isDeletingCategory = false
    var categoryDeleteError: String?

    var activeShare: CKShare?
    var activeContainer: CKContainer?
    private(set) var isInviting = false
    private(set) var isCancelling = false
    var isShowingCancelAlert = false

    @ObservationIgnored
    private let cloudSharingService: CloudSharingServiceProtocol
    @ObservationIgnored
    private let persistenceController: PersistenceController
    @ObservationIgnored
    private let categoryRepository: CategoryRepositoryProtocol
    @ObservationIgnored
    private let hapticService: HapticServiceProtocol
    @ObservationIgnored
    private let categoryOrderStore: CategoryOrderStore
    @ObservationIgnored
    private var reorderTask: Task<Void, Never>?

    init(
        cloudSharingService: CloudSharingServiceProtocol = CloudSharingService.shared,
        persistenceController: PersistenceController = .shared,
        categoryRepository: CategoryRepositoryProtocol = CategoryRepository.shared,
        hapticService: HapticServiceProtocol = HapticService.shared,
        categoryOrderStore: CategoryOrderStore = CategoryOrderStore()
    ) {
        self.cloudSharingService = cloudSharingService
        self.persistenceController = persistenceController
        self.categoryRepository = categoryRepository
        self.hapticService = hapticService
        self.categoryOrderStore = categoryOrderStore
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
            let categories = try fetchCategoriesForSharing()
            let (share, container) = try await cloudSharingService.createShare(for: categories)
            guard !Task.isCancelled else { return }
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
            categories = categoryOrderStore.applyUserOrder(to: result)
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
        guard !trimmedName.isEmpty else {
            logger.debug("saveCategory: empty name — skipped")
            return
        }

        // Prevent accidental demotion of default categories
        if let existingID, categories.first(where: { $0.id == existingID })?.isDefault == true {
            logger.warning("saveCategory: attempted to modify default category — blocked")
            return
        }

        guard !isSavingCategory else {
            logger.debug("saveCategory: already saving — skipped")
            return
        }
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

            // Share new custom categories after UI has updated
            if existingID == nil {
                logger.debug("saveCategory: enqueuing share task for new category id=\(id, privacy: .private)")
                let repo = categoryRepository
                categoryShareTask = Task { await repo.shareNewCategoryToHousehold(id: id) }
            }
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
        logger.debug("refreshSharingStatus: done — state=\(String(describing: self.cloudSharingService.state))")
    }

    /// Called by the CloudSharingSheet Coordinator on every dismissal path
    /// (didSaveShare, didStopSharing, failedToSaveShareWithError, and interactive
    /// swipe-dismiss via `presentationControllerDidDismiss`). The Coordinator's own
    /// `fireDismissOnce` guard ensures this runs at most once per sheet presentation;
    /// the ViewModel does not need its own idempotency flag.
    ///
    /// Classification and cleanup of the share lifecycle are entirely delegated to
    /// `CloudSharingService.finalizeShareOutcome`. The ViewModel stays agnostic of
    /// CloudKit mechanics.
    func handleShareDismiss(_ share: CKShare?) {
        logger.info("handleShareDismiss: share=\(share != nil ? "present" : "nil")")
        isShowingShareSheet = false
        activeShare = nil
        activeContainer = nil
        refreshTask?.cancel()
        // Capture the service directly, NOT through `self`. `finalizeShareOutcome`
        // classifies a CloudKit share that was already persisted — skipping it leaves
        // `SharingState` permanently incorrect (the original orphan-share bug vector).
        // A `[weak self]` capture would silently drop the call if the view dismisses
        // before the Task runs. The service is a @MainActor singleton and outlives
        // any individual ViewModel, so capturing it strongly is safe and correct.
        let service = cloudSharingService
        refreshTask = Task {
            await service.finalizeShareOutcome(share)
        }
    }

    func cancelInvitation() async {
        guard !isCancelling else {
            logger.debug("cancelInvitation: already cancelling — skipped")
            return
        }
        logger.info("cancelInvitation: starting share deletion")
        isCancelling = true
        defer { isCancelling = false }
        errorMessage = nil

        do {
            try await cloudSharingService.cancelShare()
            // State cleanup is unconditional — the CloudKit delete already happened
            logger.info("cancelInvitation: share deleted successfully")
            activeShare = nil
            activeContainer = nil
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("cancelInvitation: FAILED — \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func resendInvitation() async {
        logger.info("resendInvitation: re-presenting share sheet with existing share")
        await invitePartner()
    }

    // MARK: - Category Reorder & Delete

    func deleteCategory(id: UUID) async {
        guard !isDeletingCategory else {
            logger.debug("deleteCategory: already deleting — skipped")
            return
        }
        isDeletingCategory = true
        defer { isDeletingCategory = false }
        categoryDeleteError = nil

        logger.info("deleteCategory: id=\(id)")
        do {
            try await categoryRepository.deleteCategory(id: id)
            // Delete is irreversible — state cleanup must be unconditional
            logger.info("deleteCategory: success")
            categoryOrderStore.removeFromOrder(id: id)
            hapticService.trigger(.deleteTap)
            await loadCategories()
        } catch let error as CategoryRepositoryError {
            guard !Task.isCancelled else { return }
            logger.warning("deleteCategory: blocked — \(error.localizedDescription)")
            hapticService.trigger(.error)
            categoryDeleteError = error.localizedDescription
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("deleteCategory: FAILED — \(error.localizedDescription)")
            hapticService.trigger(.error)
            categoryDeleteError = "Failed to delete category. Please try again."
        }
    }

    func moveCategory(from source: IndexSet, to destination: Int) {
        logger.info("moveCategory: from=\(source.map { $0 }) to=\(destination) (\(self.categories.count) categories)")
        categories.move(fromOffsets: source, toOffset: destination)
        categoryOrderStore.persistOrder(categories)

        // Core Data sortOrder update (canonical fallback for partner visibility)
        let orderedIDs = categories.map(\.id)
        let repo = categoryRepository
        if reorderTask != nil {
            logger.debug("moveCategory: cancelling prior reorder task (coalescing)")
        }
        reorderTask?.cancel()
        reorderTask = Task {
            do {
                try await repo.reorderCategories(orderedIDs)
                logger.debug("moveCategory: Core Data reorder complete")
            } catch {
                logger.error("moveCategory: reorder FAILED — \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private

    private func fetchCategoriesForSharing() throws -> [Category] {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "id", ascending: true),
        ]
        if let privateStore = persistenceController.privatePersistentStore {
            request.affectedStores = [privateStore]
        }
        let allCategories = try persistenceController.container.viewContext.fetch(request)

        // Deduplicate defaults — prior seeding failures can leave duplicates.
        // Share only unique records to avoid bloating the shared zone.
        var seenDefaultNames = Set<String>()
        let categories = allCategories.filter { category in
            guard category.isDefault else { return true }
            guard !seenDefaultNames.contains(category.wrappedName) else { return false }
            seenDefaultNames.insert(category.wrappedName)
            return true
        }
        logger.info("fetchCategoriesForSharing: \(categories.count) categories (from \(allCategories.count) raw)")

        guard !categories.isEmpty else {
            logger.error("fetchCategoriesForSharing: no categories found")
            throw NSError(
                domain: "SettingsViewModel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No categories found. Please restart the app."]
            )
        }
        return categories
    }
}
