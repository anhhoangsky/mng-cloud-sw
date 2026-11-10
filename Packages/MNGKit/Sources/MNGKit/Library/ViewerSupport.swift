import Foundation

/// Snapshot list backing the full-screen viewer.
///
/// The PWA keeps a separate `viewer_items` vector so deletes and paging in the
/// library cannot reorder the open viewer. This type ports the same rules:
/// opening selects the item, deletion removes rows and advances to the nearest
/// neighbour, and removing the last row closes the viewer.
public struct ViewerCollection: Equatable, Sendable {
    public private(set) var items: [Item]
    public private(set) var index: Int

    /// Fails when the id is not in the snapshot, matching `open_viewer()`.
    public init?(items: [Item], opening id: Int64) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        self.items = items
        self.index = index
    }

    public init(items: [Item], index: Int) {
        self.items = items
        self.index = items.indices.contains(index) ? index : 0
    }

    public var current: Item? {
        items.indices.contains(index) ? items[index] : nil
    }

    public var count: Int { items.count }

    public var canGoPrevious: Bool { index > 0 }

    public var canGoNext: Bool { index + 1 < items.count }

    public mutating func select(index next: Int) {
        guard items.indices.contains(next) else { return }
        index = next
    }

    public mutating func select(id: Int64) {
        guard let next = items.firstIndex(where: { $0.id == id }) else { return }
        index = next
    }

    /// Remove deleted rows. Returns `true` when the snapshot became empty and
    /// the viewer must close.
    @discardableResult
    public mutating func remove(ids: Set<Int64>) -> Bool {
        guard !ids.isEmpty, !items.isEmpty, current != nil else { return false }
        let oldItems = items
        let oldIndex = index
        let currentID = oldItems[oldIndex].id
        let next = oldItems.filter { !ids.contains($0.id) }
        guard next.count != oldItems.count else { return false }
        guard !next.isEmpty else {
            items = []
            index = 0
            return true
        }

        let removedBefore = oldItems[..<oldIndex]
            .filter { ids.contains($0.id) }
            .count
        let wasCurrent = ids.contains(currentID)
        var nextIndex = oldIndex - removedBefore
        if wasCurrent {
            nextIndex = min(nextIndex, next.count - 1)
        } else if nextIndex >= next.count {
            nextIndex = next.count - 1
        }
        items = next
        index = max(0, nextIndex)
        return false
    }

    public mutating func setFavorite(ids: Set<Int64>, value: Bool) {
        guard !ids.isEmpty else { return }
        for position in items.indices where ids.contains(items[position].id) {
            items[position].favorite = value
        }
    }
}

/// Everything needed to undo an optimistic viewer deletion. The PWA restores
/// the whole snapshot (list, index and open state) if any deleted id fails.
public struct ViewerRemoval: Equatable, Sendable {
    public let collection: ViewerCollection
    public let ids: Set<Int64>

    public init(collection: ViewerCollection, ids: Set<Int64>) {
        self.collection = collection
        self.ids = ids
    }
}
