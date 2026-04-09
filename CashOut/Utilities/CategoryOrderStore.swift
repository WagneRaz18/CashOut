import Foundation

/// Per-user category display order stored in UserDefaults.
/// Not synced via CloudKit — each user has their own order.
struct CategoryOrderStore {
    private static let key = "categoryDisplayOrder"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Sort fetched categories by the user's saved order.
    /// New categories (from partner sync) are appended at the end.
    /// Stale UUIDs (deleted categories) are pruned from the saved order.
    func applyUserOrder(to fetched: [CategoryData]) -> [CategoryData] {
        guard let savedOrder = defaults.stringArray(forKey: Self.key) else {
            return fetched
        }
        let indexMap = Dictionary(savedOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let maxIndex = savedOrder.count

        let sorted = fetched.sorted { a, b in
            let aIndex = indexMap[a.id.uuidString] ?? (maxIndex + Int(a.sortOrder))
            let bIndex = indexMap[b.id.uuidString] ?? (maxIndex + Int(b.sortOrder))
            return aIndex < bIndex
        }

        // Prune stale UUIDs
        let liveIDs = Set(fetched.map { $0.id.uuidString })
        let pruned = savedOrder.filter { liveIDs.contains($0) }
        if pruned.count != savedOrder.count {
            defaults.set(pruned, forKey: Self.key)
        }

        return sorted
    }

    /// Persist the current display order.
    func persistOrder(_ categories: [CategoryData]) {
        let order = categories.map { $0.id.uuidString }
        defaults.set(order, forKey: Self.key)
    }

    /// Remove a deleted category from the saved order.
    func removeFromOrder(id: UUID) {
        var order = defaults.stringArray(forKey: Self.key) ?? []
        order.removeAll { $0 == id.uuidString }
        defaults.set(order, forKey: Self.key)
    }
}
