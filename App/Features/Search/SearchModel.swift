import Foundation
import MNGKit
import Observation

/// Search tab state: the 280 ms debounce, the five chips, the 300-result cap
/// and the optimistic favorite/delete reconciliation owned by `shell.rs`.
@MainActor
@Observable
final class SearchModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    let client: MNGAPIClient
    private(set) var cloud: String

    /// Text currently in the field. Submitting copies it to `submitted`.
    private(set) var query = ""
    private(set) var filter: SearchFilter = .all
    private(set) var submitted = ""
    private(set) var page = LibraryPage()
    private(set) var state: LoadState = .idle
    /// True once a search row was optimistically deleted, matching the PWA's
    /// `search_deleted` flag that switches the meta count to the loaded rows.
    private(set) var deleted = false

    var onUnauthorized: (() -> Void)?

    @ObservationIgnored private var requestSeq = 0
    @ObservationIgnored private var debounceSeq = 0
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var deleteSnapshots: [UUID: [RemovedItem]] = [:]

    init(client: MNGAPIClient, cloud: String) {
        self.client = client
        self.cloud = cloud
    }

    // MARK: - Derived state

    var results: [Item] { page.items }
    var total: Int64 { page.total }
    var isEmpty: Bool { page.items.isEmpty }
    var isLoading: Bool { state == .loading }
    var isReady: Bool { state == .ready }
    var showsHints: Bool { submitted.isEmpty }

    var errorMessage: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    /// Hidden until a submitted, successful search exists, and also when every
    /// loaded row was deleted (`deleted && results.isEmpty`).
    var metaText: String? {
        guard !submitted.isEmpty, state == .ready else { return nil }
        guard !(deleted && page.items.isEmpty) else { return nil }
        let count = deleted ? Int64(page.items.count) : page.total
        return Strings.searchMeta(total: count, query: submitted)
    }

    // MARK: - Editing

    /// Every keystroke invalidates the previous debounce and schedules a new
    /// 280 ms query, like the input handler in `shell.rs`.
    func updateQuery(_ text: String) {
        query = text
        debounceSeq &+= 1
        let seq = debounceSeq
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(SearchQuery.debounceMilliseconds) * 1_000_000)
            guard !Task.isCancelled, let self, self.debounceSeq == seq else { return }
            await self.performSearch()
        }
    }

    /// Keyboard "Search" runs immediately.
    func submit() {
        invalidateDebounce()
        Task { [weak self] in
            await self?.performSearch()
        }
    }

    /// Chip changes run immediately, even with an empty field.
    func selectFilter(_ next: SearchFilter) {
        guard next != filter else { return }
        filter = next
        invalidateDebounce()
        Task { [weak self] in
            await self?.performSearch()
        }
    }

    /// Clear button: bump the debounce, empty the field and show the hints.
    func clear() {
        invalidateDebounce()
        query = ""
        Task { [weak self] in
            await self?.performSearch()
        }
    }

    func retry() {
        submit()
    }

    /// A cloud switch reruns only a non-empty query, exactly like the PWA.
    func cloudChanged(to key: String) {
        cloud = key
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        submit()
    }

    private func invalidateDebounce() {
        debounceSeq &+= 1
        debounceTask?.cancel()
        debounceTask = nil
    }

    // MARK: - Network

    private func performSearch() async {
        requestSeq &+= 1
        let seq = requestSeq
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        deleted = false
        submitted = trimmed

        guard !trimmed.isEmpty else {
            page = LibraryPage()
            state = .idle
            return
        }

        state = .loading
        let request = SearchQuery(text: query, filter: filter)
        do {
            let data = try await client.items(
                request.itemFilters(cloud: cloud, limit: SearchQuery.limit)
            )
            guard seq == requestSeq else { return }
            page = LibraryPage(items: data.items, total: data.total)
            state = .ready
        } catch let error as APIError {
            guard seq == requestSeq else { return }
            if error.status == 401 {
                onUnauthorized?()
                return
            }
            page = LibraryPage()
            state = .failed(message(for: error))
        } catch {
            guard seq == requestSeq else { return }
            page = LibraryPage()
            state = .failed(APIMessages.network)
        }
    }

    private func message(for error: APIError) -> String {
        let text = error.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? APIMessages.network : text
    }

    // MARK: - Library mutation observers

    func applyFavorite(ids: Set<Int64>, value: Bool) {
        page.setFavorite(ids: ids, value: value)
    }

    func beginDelete(token: UUID, ids: Set<Int64>, fromSearch: Bool) {
        let removed = page.remove(ids: ids)
        deleteSnapshots[token] = removed
        if fromSearch, !removed.isEmpty {
            deleted = true
        }
    }

    func restoreDelete(token: UUID, ids: Set<Int64>, fromSearch: Bool) {
        guard let snapshot = deleteSnapshots[token] else { return }
        let failed = snapshot.filter { ids.contains($0.item.id) }
        guard !failed.isEmpty else { return }
        page.restore(failed)
        // `search_deleted` is stamped whenever Search is the visible tab, even
        // if this particular delete started elsewhere (shell.rs restore path).
        if fromSearch {
            deleted = true
        }
    }

    func settleDelete(token: UUID) {
        deleteSnapshots[token] = nil
    }
}
