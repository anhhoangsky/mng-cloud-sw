import Foundation
import MNGKit
import Observation

enum LibraryEvent {
    case toast(String)
    case unauthorized
    case share(DownloadedFile)
}

/// Where the mobile Back button returns after an album drill-down, matching
/// the PWA's `album_return` signal.
enum AlbumReturn: String, Equatable, Sendable {
    case albums
    case search
}

struct DeletePrompt: Identifiable {
    let id = UUID()
    let ids: [Int64]
    let title: String
    let message: String
    let confirmLabel: String
}

/// Library screen state: grouping, paging, selection and tile actions.
///
/// The model owns every optimistic update so the grid and the info sheet always
/// agree with the PWA's rollback rules.
@MainActor
@Observable
final class LibraryModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    enum OlderState: Equatable {
        case idle
        case loading
        case failed(String)
    }

    let client: MNGAPIClient
    private(set) var cloud: String
    private(set) var filters: LibraryFilterState

    private(set) var page = LibraryPage()
    /// Bumped every time a reload finishes replacing the page. The grid uses
    /// it to ignore the scroll clamp of a shorter page as a gesture.
    private(set) var revision = 0
    private(set) var years: [YearBucket] = []
    private(set) var months: [MonthBucket] = []
    private(set) var loadState: LoadState = .idle
    private(set) var olderState: OlderState = .idle
    private(set) var olderExhausted = false

    private(set) var selectionMode = false
    private(set) var selection: Set<Int64> = []
    private(set) var pendingDelete: DeletePrompt?

    /// Non-nil while the Library tab is showing an album drill-down. The
    /// timeline keeps rendering the normal page/grid, but selection, paging
    /// and the Library toolbar are disabled.
    private(set) var activeAlbum: AlbumFilter?
    private(set) var albumReturn: AlbumReturn = .albums

    private(set) var infoItem: Item?
    private(set) var isLoadingInfo = false
    private(set) var isDownloading = false

    /// The date of the photo at the top of the visible timeline. The compact
    /// header shows it instead of the item count once the library is scrolled,
    /// like iOS Photos.
    private(set) var timelineTopDate: String?

    /// Snapshot list used by the full-screen viewer. It is independent of
    /// `page`, so paging or filtering can never reorder an open viewer.
    let viewer = ViewerModel()

    /// Filled by `ShellModel` so the library does not depend on bootstrap.
    var cloudLabel: (String) -> String = { $0.isEmpty ? "đám mây" : $0 }
    var onEvent: ((LibraryEvent) -> Void)?

    /// Favorite patches fan out to Search and Albums. The map carries full
    /// snapshots for the changed ids so the favorites section can be seeded.
    var onFavoritePatched: ((Set<Int64>, Bool, [Int64: Item]) -> Void)?

    /// Tokenized delete callbacks: Search and Albums snapshot only the rows
    /// they own, and a later rollback restores exactly those rows.
    var onDeleteRemoved: ((UUID, Set<Int64>) -> Void)?
    var onDeleteRestored: ((UUID, Set<Int64>) -> Void)?
    var onDeleteSettled: ((UUID) -> Void)?

    /// The info sheet is presented by the root shell so it also works from
    /// Search and Albums result tiles.
    var onPresentInfo: (() -> Void)?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var requestSeq = 0

    init(
        client: MNGAPIClient,
        cloud: String,
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.cloud = cloud
        self.defaults = defaults
        let stored = defaults.string(forKey: LibraryLayout.storageKey)
        filters = LibraryFilterState(layout: LibraryLayout(stored: stored))

        viewer.onToggleFavorite = { [weak self] item in
            self?.toggleFavorite(item)
        }
        viewer.onInfo = { [weak self] item in
            self?.openInfo(item)
        }
        viewer.onDownload = { [weak self] item in
            self?.download(item)
        }
        viewer.onShare = { [weak self] item in
            // The share sheet needs a real file on disk, so the original is
            // fetched first and handed to `UIActivityViewController`.
            self?.download(item)
        }
        viewer.onDelete = { [weak self] item in
            self?.requestDelete(items: [item])
        }
    }

    // MARK: - Loading

    func start() async {
        guard loadState == .idle else { return }
        await reload()
    }

    func reload() async {
        requestSeq &+= 1
        let seq = requestSeq
        olderState = .idle
        olderExhausted = false
        loadState = .loading
        defer {
            if seq == requestSeq {
                revision &+= 1
            }
        }

        switch filters.layout {
        case .all:
            await loadTimeline(seq: seq)
        case .years:
            await loadYears(seq: seq)
        case .months:
            await loadMonths(seq: seq)
        }
    }

    func retry() async {
        await reload()
    }

    /// Warm the thumbnails of the rows that are about to scroll into view.
    private func prefetchThumbnails() {
        let upcoming = page.items.suffix(8).map { $0.thumbnailPath(size: 360) }
        ThumbCache.shared.prefetch(paths: upcoming, client: client)
    }

    private func loadTimeline(seq: Int) async {        do {
            let response = try await client.items(
                requestFilters(offset: 0)
            )
            guard seq == requestSeq else { return }
            page.replace(with: response)
            loadState = .ready
            prefetchThumbnails()
        } catch let error as APIError {
            guard seq == requestSeq else { return }
            if error.status == 401 {
                onEvent?(.unauthorized)
                return
            }
            loadState = .failed(APIMessages.itemList(error))
        } catch {
            guard seq == requestSeq else { return }
            loadState = .failed(APIMessages.itemList(.network()))
        }
    }

    private func loadYears(seq: Int) async {
        do {
            let response = try await client.years(cloud: cloud)
            guard seq == requestSeq else { return }
            years = response.years
            loadState = .ready
        } catch let error as APIError {
            guard seq == requestSeq else { return }
            if error.status == 401 {
                onEvent?(.unauthorized)
                return
            }
            loadState = .failed(APIMessages.itemList(error))
        } catch {
            guard seq == requestSeq else { return }
            loadState = .failed(APIMessages.itemList(.network()))
        }
    }

    private func loadMonths(seq: Int) async {
        do {
            let response = try await client.months(
                cloud: cloud,
                year: filters.year
            )
            guard seq == requestSeq else { return }
            months = response.months
            loadState = .ready
        } catch let error as APIError {
            guard seq == requestSeq else { return }
            if error.status == 401 {
                onEvent?(.unauthorized)
                return
            }
            loadState = .failed(APIMessages.itemList(error))
        } catch {
            guard seq == requestSeq else { return }
            loadState = .failed(APIMessages.itemList(.network()))
        }
    }

    func loadOlderIfNeeded() async {
        guard activeAlbum == nil,
              filters.isTimeline,
              page.hasMore,
              !olderExhausted,
              olderState != .loading,
              loadState == .ready
        else { return }
        await loadOlder()
    }

    func loadOlder() async {
        guard activeAlbum == nil, filters.isTimeline, page.hasMore, olderState != .loading else { return }
        let seq = requestSeq
        olderState = .loading
        do {
            let response = try await client.items(
                requestFilters(offset: page.count)
            )
            guard seq == requestSeq else { return }
            if response.items.isEmpty {
                olderExhausted = true
            }
            page.append(response)
            olderState = .idle
        } catch let error as APIError {
            guard seq == requestSeq else { return }
            olderState = .idle
            if error.status == 401 {
                onEvent?(.unauthorized)
                return
            }
            // The web has no loading footer: a failed page is a toast and
            // the scroll trigger may ask again.
            onEvent?(.toast(APIMessages.olderPage(error)))
        } catch {
            guard seq == requestSeq else { return }
            olderState = .idle
            onEvent?(.toast(APIMessages.olderPage(.network())))
        }
    }

    // MARK: - Filters

    var isAlbumOpen: Bool { activeAlbum != nil }

    /// Enter an album drill-down. State changes are synchronous so the shell
    /// can switch tabs without a frame of stale timeline content; the caller
    /// follows with `reload()`.
    func beginAlbum(_ album: AlbumFilter, returnTo: AlbumReturn) {
        exitSelection()
        activeAlbum = album
        albumReturn = returnTo
        // `openAlbum()` clears the kind chip: an album opened while "Video"
        // was selected would otherwise silently show no photos.
        filters.kind = .all
        filters.year = album.year
        filters.month = nil
        filters.layout = .all
        page = LibraryPage()
        years = []
        months = []
        olderState = .idle
        olderExhausted = false
        loadState = .loading
    }

    /// Leave the album without networking. Returns the tab that should become
    /// active; the caller reloads the library grid afterwards.
    @discardableResult
    func closeAlbum() -> AlbumReturn? {
        guard activeAlbum != nil else { return nil }
        let target = albumReturn
        exitSelection()
        activeAlbum = nil
        filters.showAllYears()
        filters.layout = .all
        page = LibraryPage()
        months = []
        return target
    }

    /// The album filter wins over the timeline filters and pins people/place
    /// albums to every cloud, like `item_cloud_filter()`.
    private func requestFilters(offset: Int, limit: Int? = nil) -> ItemFilters {
        if let activeAlbum {
            return activeAlbum.itemFilters(cloud: cloud, offset: offset, limit: limit)
        }
        return filters.itemFilters(cloud: cloud, offset: offset, limit: limit)
    }

    func selectLayout(_ layout: LibraryLayout) async {
        exitSelection()
        activeAlbum = nil
        filters.selectLayout(layout)
        defaults.set(layout.rawValue, forKey: LibraryLayout.storageKey)
        page = LibraryPage()
        years = []
        months = []
        await reload()
    }

    func selectKind(_ kind: ItemKindFilter) async {
        exitSelection()
        filters.selectKind(kind)
        // Keep the old grid on screen until the new page arrives, so the
        // scroll offset stays where the person left it, like the web's
        // `keep_scroll` reload.
        years = []
        months = []
        await reload()
    }

    func open(year: Int) async {
        exitSelection()
        activeAlbum = nil
        filters.open(year: year)
        page = LibraryPage()
        months = []
        await reload()
    }

    func open(year: Int, month: Int) async {
        exitSelection()
        activeAlbum = nil
        filters.open(year: year, month: month)
        page = LibraryPage()
        await reload()
    }

    func showAllYears() async {
        exitSelection()
        filters.showAllYears()
        months = []
        await reload()
    }

    func clearFilters() async {
        exitSelection()
        activeAlbum = nil
        filters.clearFilters()
        // Same `keep_scroll` behaviour as the kind chips: the old page stays
        // until the new one is ready.
        await reload()
    }

    func setCloud(_ key: String) async {
        guard key != cloud else { return }
        exitSelection()
        cloud = key
        page = LibraryPage()
        years = []
        months = []
        await reload()
    }

    /// Mobile header back button: any year/month drill-down returns to the
    /// years grid, matching `go_back()`.
    func goBack() async {
        guard filters.hasDateFilter else { return }
        exitSelection()
        filters.showAllYears()
        filters.selectLayout(.years)
        page = LibraryPage()
        months = []
        await reload()
    }

    // MARK: - Selection

    var canSelect: Bool {
        activeAlbum == nil
            && filters.isTimeline
            && !filters.hasDateFilter
            && !page.items.isEmpty
    }

    var selectedItems: [Item] {
        page.items.filter { selection.contains($0.id) }
    }

    func isSelected(_ id: Int64) -> Bool {
        selection.contains(id)
    }

    func enterSelection() {
        guard filters.isTimeline else { return }
        selectionMode = true
        selection = []
    }

    func exitSelection() {
        selectionMode = false
        selection = []
    }

    func toggleSelection(_ id: Int64) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    /// Replace the whole selection in one step, used by the marquee drag.
    /// The empty set is valid: the person can start a drag on an empty
    /// selection and the X must stay available until they leave.
    func replaceSelection(_ ids: Set<Int64>) {
        guard selectionMode else { return }
        if selection != ids {
            selection = ids
        }
    }

    func favoriteSelection() {
        let selected = selectedItems
        guard let first = selected.min(by: { $0.id < $1.id }) else { return }
        let value = !first.favorite
        let ids = selected.map(\.id)
        exitSelection()
        setFavorite(ids: ids, value: value)
    }

    func downloadSelection() {
        let ids = selectedItems.map(\.id)
        guard !ids.isEmpty else { return }
        exitSelection()
        downloadArchive(ids: ids)
    }

    func deleteSelection() {
        requestDelete(ids: selectedItems.map(\.id))
    }

    // MARK: - Viewer

    /// Open the shared viewer with the current timeline page as its snapshot.
    /// The tile must be part of the page; a detail snapshot falls back to a
    /// single-item viewer instead of dropping the tap.
    func openViewer(_ item: Item) {
        guard !selectionMode else { return }
        let list = page.items.contains(where: { $0.id == item.id })
            ? page.items
            : [item]
        viewer.open(items: list, id: item.id)
    }

    /// Albums photo grids already sorted their list; seed the viewer with that
    /// exact order so previous/next stay inside the section the person opened.
    func openViewer(items: [Item], id: Int64) {
        guard !selectionMode else { return }
        viewer.open(items: items, id: id)
    }

    // MARK: - Favorite

    func toggleFavorite(_ item: Item) {
        setFavorite(ids: [item.id], value: !item.favorite)
    }

    func setFavorite(ids: [Int64], value: Bool) {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return }
        applyFavorite(ids: Set(unique), value: value)
        Task { [weak self] in
            await self?.performFavorite(ids: unique, value: value)
        }
    }

    private func applyFavorite(ids: Set<Int64>, value: Bool) {
        page.setFavorite(ids: ids, value: value)
        viewer.setFavorite(ids: ids, value: value)
        if let item = infoItem, ids.contains(item.id) {
            infoItem = item.withFavorite(value)
        }
        // Snapshot the changed rows after the flip; the favorites section uses
        // these full items to insert a row that its first snapshot missed.
        var known: [Int64: Item] = [:]
        for item in page.items where ids.contains(item.id) {
            known[item.id] = item
        }
        for item in viewer.items where ids.contains(item.id) {
            known[item.id] = item
        }
        if let infoItem, ids.contains(infoItem.id) {
            known[infoItem.id] = infoItem
        }
        onFavoritePatched?(ids, value, known)
    }

    private func performFavorite(ids: [Int64], value: Bool) async {
        var done = 0
        var failed: [Int64] = []

        for chunk in ids.chunked(into: 4) {
            let results = await favoriteChunk(chunk, value: value)
            for (id, result) in results {
                switch result {
                case .success(let response):
                    done += 1
                    if response.favorite != value {
                        applyFavorite(ids: [id], value: response.favorite)
                    }
                case .failure(let error):
                    if error.status == 401 {
                        onEvent?(.unauthorized)
                        return
                    }
                    failed.append(id)
                }
            }
        }

        if failed.isEmpty {
            onEvent?(.toast(APIMessages.favoriteChanged(value, count: ids.count)))
        } else {
            applyFavorite(ids: Set(failed), value: !value)
            onEvent?(.toast(
                APIMessages.favoritePartial(
                    done: done,
                    total: ids.count,
                    failed: failed.count
                )
            ))
        }
    }

    private func favoriteChunk(
        _ ids: [Int64],
        value: Bool
    ) async -> [(Int64, Result<FavoriteResponse, APIError>)] {
        await withTaskGroup(
            of: (Int64, Result<FavoriteResponse, APIError>).self
        ) { group in
            for id in ids {
                group.addTask { [client] in
                    do {
                        return (id, .success(try await client.favorite(id: id, value: value)))
                    } catch let error as APIError {
                        return (id, .failure(error))
                    } catch {
                        return (id, .failure(.network()))
                    }
                }
            }
            var results: [(Int64, Result<FavoriteResponse, APIError>)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    // MARK: - Delete

    func requestDelete(items: [Item]) {
        var source: [Int64: Item] = [:]
        for item in items {
            source[item.id] = item
        }
        requestDelete(ids: items.map(\.id), source: source)
    }

    func requestDelete(ids: [Int64]) {
        requestDelete(ids: ids, source: [:])
    }

    /// `source` carries rows that are not part of the library page or viewer
    /// (Search results and the Albums photo sections).
    private func requestDelete(ids: [Int64], source: [Int64: Item]) {
        let unique = Array(Set(ids)).sorted()
        guard let firstID = unique.first else { return }
        let first = source[firstID]
            ?? page.item(id: firstID)
            ?? viewer.items.first(where: { $0.id == firstID })
        let label = cloudLabel(first?.cloud ?? cloud)

        let prompt: DeletePrompt
        if unique.count == 1 {
            let body = first?.live == true
                ? Strings.deleteLiveBody
                : Strings.deleteBody
            let name = first?.name ?? ""
            prompt = DeletePrompt(
                ids: unique,
                title: Strings.deleteTitle(cloud: label),
                message: name.isEmpty ? body : "\(name)\n\(body)",
                confirmLabel: Strings.delete
            )
        } else {
            prompt = DeletePrompt(
                ids: unique,
                title: Strings.deleteManyTitle(unique.count),
                message: "\(Strings.deleteManySub)\n\(Strings.deleteManyBody)",
                confirmLabel: Strings.deleteManyConfirm(unique.count)
            )
        }
        pendingDelete = prompt
    }

    func cancelDelete() {
        pendingDelete = nil
    }

    func confirmDelete() {
        guard let prompt = pendingDelete else { return }
        pendingDelete = nil
        exitSelection()
        let token = UUID()
        let ids = Set(prompt.ids)
        let removed = page.remove(ids: ids)
        let viewerRemoval = viewer.remove(ids: ids)
        onDeleteRemoved?(token, ids)
        Task { [weak self] in
            await self?.performDelete(
                token: token,
                ids: prompt.ids,
                removed: removed,
                viewerRemoval: viewerRemoval
            )
        }
    }

    func deleteFromInfo(_ item: Item) {
        dismissInfo()
        // Let the sheet finish dismissing before the root shell presents the
        // confirmation alert underneath it.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 320_000_000)
            self?.requestDelete(items: [item])
        }
    }

    private func performDelete(
        token: UUID,
        ids: [Int64],
        removed: [RemovedItem],
        viewerRemoval: ViewerRemoval?
    ) async {
        var removedCount = 0
        var failed: [Int64] = []

        for chunk in ids.chunked(into: 4) {
            let results = await deleteChunk(chunk)
            for (id, result) in results {
                switch result {
                case .success:
                    removedCount += 1
                case .failure(let error):
                    if error.status == 401 {
                        onDeleteSettled?(token)
                        onEvent?(.unauthorized)
                        return
                    }
                    failed.append(id)
                }
            }
        }

        if failed.isEmpty {
            onEvent?(.toast(APIMessages.deleted(count: ids.count)))
        } else {
            let failedSet = Set(failed)
            page.restore(removed.filter { failedSet.contains($0.item.id) })
            if let viewerRemoval {
                viewer.restore(viewerRemoval, failed: failedSet)
            }
            onDeleteRestored?(token, failedSet)
            onEvent?(.toast(
                APIMessages.deletePartial(
                    removed: removedCount,
                    total: ids.count,
                    failed: failed.count
                )
            ))
        }
        onDeleteSettled?(token)
    }

    private func deleteChunk(
        _ ids: [Int64]
    ) async -> [(Int64, Result<DeleteResponse, APIError>)] {
        await withTaskGroup(
            of: (Int64, Result<DeleteResponse, APIError>).self
        ) { group in
            for id in ids {
                group.addTask { [client] in
                    do {
                        return (id, .success(try await client.deleteItem(id: id)))
                    } catch let error as APIError {
                        return (id, .failure(error))
                    } catch {
                        return (id, .failure(.network()))
                    }
                }
            }
            var results: [(Int64, Result<DeleteResponse, APIError>)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    // MARK: - Downloads

    func download(_ item: Item) {
        guard !isDownloading else { return }
        isDownloading = true
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let filename = name.isEmpty ? "MNG-Cloud" : name
        Task { [weak self] in
            guard let self else { return }
            defer { self.isDownloading = false }
            do {
                let file = try await self.client.mediaFile(
                    path: item.downloadPath,
                    suggestedName: filename
                )
                self.onEvent?(.share(file))
            } catch let error as APIError {
                if error.status == 401 {
                    self.onEvent?(.unauthorized)
                } else {
                    self.onEvent?(.toast(
                        error.message.isEmpty ? Strings.downloadFailed : error.message
                    ))
                }
            } catch {
                self.onEvent?(.toast(Strings.downloadFailed))
            }
        }
    }

    /// Stream a ZIP of the selected items to a temporary file.
    func downloadArchive(ids: [Int64]) {
        guard !ids.isEmpty, !isDownloading else { return }
        isDownloading = true
        onEvent?(.toast(Strings.preparingZip))
        Task { [weak self] in
            guard let self else { return }
            defer { self.isDownloading = false }
            do {
                let archive = try await self.client.archive(ids: ids)
                self.onEvent?(.share(archive))
            } catch let error as APIError {
                if error.status == 401 {
                    self.onEvent?(.unauthorized)
                } else {
                    self.onEvent?(.toast(
                        error.message.isEmpty ? Strings.zipFailed : error.message
                    ))
                }
            } catch {
                self.onEvent?(.toast(Strings.zipFailed))
            }
        }
    }

    // MARK: - Info

    /// Publish the date the compact header shows while the timeline is
    /// scrolled. `nil` restores the item count.
    func setTimelineTopDate(_ date: String?) {
        if timelineTopDate != date {
            timelineTopDate = date
        }
    }

    /// The date of one timeline item, used by the header when the grid is
    /// scrolled.
    func timelineDate(for id: Int64) -> String? {
        guard let item = page.items.first(where: { $0.id == id }) else { return nil }
        return MNGFormat.itemDate(item)
    }

    func openInfo(_ item: Item) {
        infoItem = item
        isLoadingInfo = true
        onPresentInfo?()
        Task { [weak self] in
            guard let self else { return }
            do {
                let detail = try await self.client.item(id: item.id)
                guard self.infoItem?.id == item.id else { return }
                self.infoItem = detail.item
                self.isLoadingInfo = false
            } catch let error as APIError {
                guard self.infoItem?.id == item.id else { return }
                self.isLoadingInfo = false
                if error.status == 401 {
                    self.onEvent?(.unauthorized)
                } else {
                    self.onEvent?(.toast(
                        error.message.isEmpty ? APIMessages.itemListFailed : error.message
                    ))
                }
            } catch {
                guard self.infoItem?.id == item.id else { return }
                self.isLoadingInfo = false
                self.onEvent?(.toast(APIMessages.itemList(.network())))
            }
        }
    }

    func dismissInfo() {
        infoItem = nil
        isLoadingInfo = false
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
