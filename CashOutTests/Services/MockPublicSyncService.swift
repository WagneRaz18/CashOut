@preconcurrency import CoreData
import Foundation
@testable import CashOut

@MainActor
final class MockPublicSyncService: PublicSyncServiceProtocol {
    // Call tracking
    var registerSubscriptionsCallCount = 0
    var removeSubscriptionsCallCount = 0
    var upsertExpenseCallCount = 0
    var upsertCategoryCallCount = 0
    var handleRemoteNotificationCallCount = 0
    var fetchChangesCallCount = 0
    var backfillCallCount = 0
    var resetFetchCursorCallCount = 0
    var lastRemoteNotificationUserInfo: [AnyHashable: Any]?

    func registerSubscriptions() async {
        registerSubscriptionsCallCount += 1
    }

    func removeSubscriptions() async {
        removeSubscriptionsCallCount += 1
    }

    func upsert(expense: CashOut.Expense) {
        upsertExpenseCallCount += 1
    }

    func upsert(category: CashOut.Category) {
        upsertCategoryCallCount += 1
    }

    func handleRemoteNotification(userInfo: [AnyHashable: Any]) async {
        handleRemoteNotificationCallCount += 1
        lastRemoteNotificationUserInfo = userInfo
    }

    func fetchChanges() async {
        fetchChangesCallCount += 1
    }

    func backfillAllLocalRecords() async {
        backfillCallCount += 1
    }

    func resetFetchCursor() {
        resetFetchCursorCallCount += 1
    }
}
