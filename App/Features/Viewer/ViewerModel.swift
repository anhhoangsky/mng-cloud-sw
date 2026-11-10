import Foundation
import MNGKit
import Observation

/// Full-screen viewer state: a snapshot of the library, the current position,
/// chrome visibility and the Live Photo mode.
///
/// Tile actions are delegated back to `LibraryModel` so favorite, delete,
/// download and the info sheet keep a single source of truth.
@MainActor
@Observable
final class ViewerModel {
    private(set) var collection: ViewerCollection?
    private(set) var chromeHidden = false
    private(set) var liveMode = false

    var onToggleFavorite: ((Item) -> Void)?
    var onInfo: ((Item) -> Void)?
    var onDownload: ((Item) -> Void)?
    var onDelete: ((Int64) -> Void)?

    var isOpen: Bool { collection != nil }
    var current: Item? { collection?.current }
    var items: [Item] { collection?.items ?? [] }
    var index: Int { collection?.index ?? 0 }
    var canGoPrevious: Bool { collection?.canGoPrevious ?? false }
    var canGoNext: Bool { collection?.canGoNext ?? false }

    func open(items: [Item], id: Int64) {
        guard let next = ViewerCollection(items: items, opening: id) else { return }
        collection = next
        chromeHidden = false
        liveMode = false
    }

    func close() {
        collection = nil
        chromeHidden = false
        liveMode = false
    }

    func select(index: Int) {
        guard var next = collection, next.index != index else { return }
        next.select(index: index)
        collection = next
        liveMode = false
    }

    func goPrevious() {
        guard let collection, collection.canGoPrevious else { return }
        select(index: collection.index - 1)
    }

    func goNext() {
        guard let collection, collection.canGoNext else { return }
        select(index: collection.index + 1)
    }

    func toggleChrome() {
        chromeHidden.toggle()
    }

    /// The LIVE button starts the companion stream exactly once; the still is
    /// the default frame until the person asks for motion.
    func activateLive() {
        guard current?.live == true else { return }
        liveMode = true
    }

    func toggleFavorite() {
        guard let item = current else { return }
        onToggleFavorite?(item)
    }

    func openInfo() {
        guard let item = current else { return }
        onInfo?(item)
    }

    func downloadCurrent() {
        guard let item = current else { return }
        onDownload?(item)
    }

    func deleteCurrent() {
        guard let id = current?.id else { return }
        onDelete?(id)
    }

    func setFavorite(ids: Set<Int64>, value: Bool) {
        guard var next = collection else { return }
        next.setFavorite(ids: ids, value: value)
        collection = next
    }

    /// Optimistically remove deleted rows from the snapshot. Returns the undo
    /// token when at least one visible row changed.
    func remove(ids: Set<Int64>) -> ViewerRemoval? {
        guard let old = collection, !ids.isEmpty else { return nil }
        let affected = Set(old.items.map(\.id)).intersection(ids)
        guard !affected.isEmpty else { return nil }
        var next = old
        let closed = next.remove(ids: affected)
        collection = closed ? nil : next
        liveMode = false
        if closed {
            chromeHidden = false
        }
        return ViewerRemoval(collection: old, ids: affected)
    }

    /// Restore the whole snapshot if any deleted id failed, matching the PWA's
    /// `viewer_backup` rollback.
    func restore(_ removal: ViewerRemoval, failed: Set<Int64>) {
        guard !failed.isDisjoint(with: removal.ids) else { return }
        collection = removal.collection
        liveMode = false
    }
}
