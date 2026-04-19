@preconcurrency import CoreData
import Foundation

@MainActor
protocol PublicSyncServiceProtocol: AnyObject {
    func registerSubscriptions() async
    func removeSubscriptions() async
    func upsert(expense: Expense)
    func upsert(category: Category)
    func handleRemoteNotification(userInfo: [AnyHashable: Any]) async
    func fetchChanges() async
    func backfillAllLocalRecords() async
    func resetFetchCursor()
}
