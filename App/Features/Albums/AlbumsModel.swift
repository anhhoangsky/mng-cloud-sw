import Foundation
import MNGKit
import Observation

/// Albums tab state: seven independently collapsible sections, the AI
/// signature poll, person renaming and the favorite/delete reconciliation the
/// PWA shell keeps in `shell.rs`.
@MainActor
@Observable
final class AlbumsModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    let client: MNGAPIClient
    private(set) var cloud: String

    private(set) var albums: [Album] = []
    private(set) var albumsState: LoadState = .idle
    private(set) var recent: [Item] = []
    private(set) var recentState: LoadState = .idle
    private(set) var favorites: [Item] = []
    private(set) var favoritesState: LoadState = .idle

    private(set) var people: [Person] = []
    private(set) var places = PlacesResponse()
    private(set) var ai: AiStatus?
    private(set) var exploreState: LoadState = .idle
    private(set) var exploreLoaded = false

    // Section preferences survive tab switches for this session.
    var recentOpen = true
    var recentSort: AlbumSort = .newest
    var recentGrid: AlbumGrid = .medium

    var favoritesOpen = true
    var favoritesSort: AlbumSort = .newest
    var favoritesGrid: AlbumGrid = .medium

    var collectionsOpen = true
    var collectionsSort: AlbumSort = .name
    var collectionsGrid: AlbumGrid = .medium

    var yearsOpen = true
    var yearsSort: AlbumSort = .newest
    var yearsGrid: AlbumGrid = .medium

    var peopleOpen = true
    var peopleSort: AlbumSort = .newest
    var peopleGrid: AlbumGrid = .medium

    var placesOpen = true
    var placesSort: AlbumSort = .newest
    var placesGrid: AlbumGrid = .medium

    var districtsOpen = true
    var districtsSort: AlbumSort = .newest
    var districtsGrid: AlbumGrid = .medium

    /// Person rename sheet. Renaming is optimistic; a failure restores both
    /// `name` and `label` from this snapshot.
    private(set) var personToEdit: Person?
    var personName = ""
    private(set) var personSaving = false

    var onUnauthorized: (() -> Void)?
    var onToast: ((String) -> Void)?
    /// Library page + Search results, used to seed the favorites section with
    /// rows that the server snapshot does not know about yet.
    var knownItems: () -> [Item] = { [] }

    @ObservationIgnored private var albumsSeq = 0
    @ObservationIgnored private var recentSeq = 0
    @ObservationIgnored private var favoritesSeq = 0
    @ObservationIgnored private var exploreSeq = 0
    @ObservationIgnored private var exploreSignature: ExploreSignature?
    @ObservationIgnored private var deleteSnapshots: [UUID: DeleteSnapshot] = [:]

    init(client: MNGAPIClient, cloud: String) {
        self.client = client
        self.cloud = cloud
    }

    // MARK: - Derived sections

    var collections: [Album] {
        AlbumSorting.albums(AlbumCatalog.collections(albums), sort: collectionsSort)
    }

    var years: [Album] {
        AlbumSorting.albums(AlbumCatalog.years(albums), sort: yearsSort)
    }

    var sortedPeople: [Person] {
        AlbumSorting.people(people, sort: peopleSort)
    }

    var sortedPlaces: [PlaceProvince] {
        AlbumSorting.places(places.provinces, sort: placesSort)
    }

    var sortedDistricts: [PlaceDistrict] {
        AlbumSorting.districts(places.districts, sort: districtsSort)
    }

    var shouldPollExplore: Bool {
        ai?.running == true
    }

    var exploreError: String? {
        guard !exploreLoaded else { return nil }
        if case .failed(let message) = exploreState { return message }
        return nil
    }

    var albumsError: String? {
        guard albums.isEmpty else { return nil }
        if case .failed(let message) = albumsState { return message }
        return nil
    }

    // MARK: - Loading

    /// Called whenever Albums becomes visible. Collections/recent/favorites
    /// load only once (`Idle`); the AI/people/places signature always refreshes.
    func loadIfNeeded() async {
        async let albumsLoad: Void = loadAlbumsIfNeeded()
        async let recentLoad: Void = loadRecentIfNeeded()
        async let favoritesLoad: Void = loadFavoritesIfNeeded()
        async let exploreLoad: Void = loadExplore(force: false)
        _ = await (albumsLoad, recentLoad, favoritesLoad, exploreLoad)
    }

    /// Cloud switch invalidates every section, like `switch_cloud()`.
    func reloadAll() async {
        async let albumsLoad: Void = loadAlbums()
        async let recentLoad: Void = loadRecent()
        async let favoritesLoad: Void = loadFavorites()
        async let exploreLoad: Void = loadExplore(force: false)
        _ = await (albumsLoad, recentLoad, favoritesLoad, exploreLoad)
    }

    /// Cloud switch invalidates every section even when Albums is not visible.
    /// In-flight requests are invalidated and the next `loadIfNeeded()` fetches
    /// the new library instead of leaving stale cards behind.
    func updateCloud(_ key: String) {
        guard key != cloud else { return }
        cloud = key
        albumsSeq &+= 1
        recentSeq &+= 1
        favoritesSeq &+= 1
        exploreSeq &+= 1
        albums = []
        albumsState = .idle
        recent = []
        recentState = .idle
        favorites = []
        favoritesState = .idle
        people = []
        places = PlacesResponse()
        ai = nil
        exploreState = .idle
        exploreLoaded = false
        exploreSignature = nil
        deleteSnapshots.removeAll()
    }

    private func loadAlbumsIfNeeded() async {
        guard albumsState == .idle else { return }
        await loadAlbums()
    }

    private func loadRecentIfNeeded() async {
        guard recentState == .idle else { return }
        await loadRecent()
    }

    private func loadFavoritesIfNeeded() async {
        guard favoritesState == .idle else { return }
        await loadFavorites()
    }

    func retryAlbums() async {
        await loadAlbums()
    }

    func retryRecent() async {
        await loadRecent()
    }

    func retryFavorites() async {
        await loadFavorites()
    }

    func retryExplore() async {
        await loadExplore(force: true)
    }

    private func loadAlbums() async {
        albumsSeq &+= 1
        let seq = albumsSeq
        albumsState = .loading
        do {
            let data = try await client.albums(cloud: cloud)
            guard seq == albumsSeq else { return }
            albums = data.albums
            albumsState = .ready
        } catch let error as APIError {
            guard seq == albumsSeq else { return }
            if handleUnauthorized(error) { return }
            albumsState = .failed(APIMessages.album(error))
        } catch {
            guard seq == albumsSeq else { return }
            albumsState = .failed(APIMessages.network)
        }
    }

    private func loadRecent() async {
        recentSeq &+= 1
        let seq = recentSeq
        recentState = .loading
        do {
            let data = try await client.items(
                ItemFilters(cloud: cloud, limit: 36, offset: 0)
            )
            guard seq == recentSeq else { return }
            recent = data.items
            recentState = .ready
        } catch let error as APIError {
            guard seq == recentSeq else { return }
            if handleUnauthorized(error) { return }
            recentState = .failed(APIMessages.album(error))
        } catch {
            guard seq == recentSeq else { return }
            recentState = .failed(APIMessages.network)
        }
    }

    private func loadFavorites() async {
        favoritesSeq &+= 1
        let seq = favoritesSeq
        favoritesState = .loading
        do {
            let data = try await client.items(
                ItemFilters(cloud: cloud, favorite: true, limit: 36, offset: 0)
            )
            guard seq == favoritesSeq else { return }
            var known: [Int64: Item] = [:]
            for item in knownItems() {
                known[item.id] = item
            }
            // Recent wins over Library/Search on duplicate ids, matching the
            // PWA's chain order.
            for item in recent {
                known[item.id] = item
            }
            favorites = FavoriteReconciliation.apply(data.items, known: known)
            favoritesState = .ready
        } catch let error as APIError {
            guard seq == favoritesSeq else { return }
            if handleUnauthorized(error) { return }
            favoritesState = .failed(APIMessages.album(error))
        } catch {
            guard seq == favoritesSeq else { return }
            favoritesState = .failed(APIMessages.network)
        }
    }

    /// One AI status request, then people/places only when the five counters
    /// changed (or a rename forced a reload).
    private func loadExplore(force: Bool) async {
        exploreSeq &+= 1
        let seq = exploreSeq
        if !exploreLoaded, exploreState != .loading {
            exploreState = .loading
        }

        let status: AiStatus
        do {
            status = try await client.aiStatus()
        } catch let error as APIError {
            guard seq == exploreSeq else { return }
            if handleUnauthorized(error) { return }
            if !exploreLoaded {
                exploreState = .failed(message(for: error))
            }
            return
        } catch {
            guard seq == exploreSeq else { return }
            if !exploreLoaded {
                exploreState = .failed(APIMessages.network)
            }
            return
        }

        guard seq == exploreSeq else { return }
        let signature = ExploreSignature(status)
        let needsReload = force
            || !exploreLoaded
            || exploreSignature != signature
        // The poll runs every twenty seconds while the worker is busy. Only
        // publish a real change, so an identical snapshot does not rebuild
        // the whole album page for nothing.
        if ai != status {
            ai = status
        }

        guard needsReload else {
            if exploreState != .ready {
                exploreState = .ready
            }
            return
        }

        async let peopleResult = fetchPeople()
        async let placesResult = fetchPlaces()
        let (peopleResponse, placesResponse) = await (peopleResult, placesResult)
        guard seq == exploreSeq else { return }

        switch peopleResponse {
        case .failure(let error):
            if handleUnauthorized(error) { return }
            if !exploreLoaded {
                exploreState = .failed(message(for: error))
            }
            return
        case .success:
            break
        }
        switch placesResponse {
        case .failure(let error):
            if handleUnauthorized(error) { return }
            if !exploreLoaded {
                exploreState = .failed(message(for: error))
            }
            return
        case .success:
            break
        }

        guard case .success(let peopleData) = peopleResponse,
              case .success(let placesData) = placesResponse
        else { return }
        people = peopleData.people
        places = placesData
        exploreSignature = signature
        exploreLoaded = true
        exploreState = .ready
    }

    private func fetchPeople() async -> Result<PeopleResponse, APIError> {
        do {
            return .success(try await client.people())
        } catch let error as APIError {
            return .failure(error)
        } catch {
            return .failure(APIError.network())
        }
    }

    private func fetchPlaces() async -> Result<PlacesResponse, APIError> {
        do {
            return .success(try await client.places())
        } catch let error as APIError {
            return .failure(error)
        } catch {
            return .failure(APIError.network())
        }
    }

    /// Runs only while the Albums tab is visible and the worker is running.
    /// The view starts this as a task keyed on `shouldPollExplore`; leaving the
    /// tab or pausing the worker cancels it.
    func pollExplore() async {
        while !Task.isCancelled {
            guard shouldPollExplore else { return }
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled, shouldPollExplore else { return }
            await loadExplore(force: false)
        }
    }

    private func handleUnauthorized(_ error: APIError) -> Bool {
        guard error.status == 401 else { return false }
        onUnauthorized?()
        return true
    }

    private func message(for error: APIError) -> String {
        let text = error.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? APIMessages.network : text
    }

    // MARK: - Album filters

    func album(for person: Person) -> AlbumFilter {
        AlbumFilter(
            key: "person:\(person.id)",
            title: AlbumCatalog.personTitle(person)
        )
    }

    func album(for province: PlaceProvince) -> AlbumFilter {
        AlbumFilter(
            key: "province:\(province.province)",
            title: province.province
        )
    }

    func album(for district: PlaceDistrict) -> AlbumFilter {
        AlbumFilter(
            key: "district:\(district.province)|\(district.district)",
            title: district.district
        )
    }

    func album(for album: Album) -> AlbumFilter {
        AlbumFilter(key: album.key, title: album.title)
    }

    // MARK: - Library mutation observers

    func applyFavorite(ids: Set<Int64>, value: Bool, known: [Int64: Item]) {
        guard !ids.isEmpty else { return }
        for index in recent.indices where ids.contains(recent[index].id) {
            recent[index].favorite = value
        }

        var snapshots = known.filter { ids.contains($0.key) }
        for item in recent where ids.contains(item.id) {
            snapshots[item.id] = item
        }
        // A row can be favorited straight from the open viewer while the
        // favorites section is the only place holding it.
        for item in favorites where ids.contains(item.id) {
            var copy = item
            copy.favorite = value
            snapshots[item.id] = copy
        }
        favorites = FavoriteReconciliation.apply(favorites, known: snapshots)
    }

    func beginDelete(token: UUID, ids: Set<Int64>) {
        guard !ids.isEmpty else { return }
        let snapshot = DeleteSnapshot(
            recent: Self.remove(ids: ids, from: &recent),
            favorites: Self.remove(ids: ids, from: &favorites)
        )
        deleteSnapshots[token] = snapshot
    }

    func restoreDelete(token: UUID, ids: Set<Int64>) {
        guard let snapshot = deleteSnapshots[token] else { return }
        Self.restore(snapshot.recent, ids: ids, into: &recent)
        Self.restore(snapshot.favorites, ids: ids, into: &favorites)
    }

    func settleDelete(token: UUID) {
        deleteSnapshots[token] = nil
    }

    private struct DeleteSnapshot {
        let recent: [RemovedItem]
        let favorites: [RemovedItem]
    }

    private static func remove(ids: Set<Int64>, from list: inout [Item]) -> [RemovedItem] {
        var removed: [RemovedItem] = []
        var kept: [Item] = []
        kept.reserveCapacity(list.count)
        for (index, item) in list.enumerated() {
            if ids.contains(item.id) {
                removed.append(RemovedItem(index: index, item: item))
            } else {
                kept.append(item)
            }
        }
        list = kept
        return removed
    }

    private static func restore(
        _ removed: [RemovedItem],
        ids: Set<Int64>,
        into list: inout [Item]
    ) {
        let failed = removed
            .filter { ids.contains($0.item.id) }
            .sorted { $0.index < $1.index }
        guard !failed.isEmpty else { return }
        var present = Set(list.map(\.id))
        for entry in failed where present.insert(entry.item.id).inserted {
            list.insert(entry.item, at: min(max(0, entry.index), list.count))
        }
    }

    // MARK: - Person rename

    func beginEditPerson(_ person: Person) {
        personName = person.name
        personSaving = false
        personToEdit = person
    }

    func cancelPersonEdit() {
        personToEdit = nil
    }

    /// Optimistic rename: the card updates immediately, the sheet closes, and
    /// a failure restores the previous name/label.
    func savePerson() {
        guard !personSaving, let person = personToEdit else { return }
        let id = person.id
        let name = personName.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = people.first { $0.id == id }.map { ($0.name, $0.label) }

        for index in people.indices where people[index].id == id {
            people[index].name = name
            people[index].label = name.isEmpty ? "Người \(id)" : name
        }
        personSaving = true
        personToEdit = nil
        onToast?(name.isEmpty ? Strings.personNameCleared : Strings.personNameSaved)

        Task { [weak self] in
            await self?.finishRename(id: id, name: name, previous: previous)
        }
    }

    private func finishRename(
        id: Int64,
        name: String,
        previous: (String, String)?
    ) async {
        do {
            _ = try await client.renamePerson(id: id, name: name)
            personSaving = false
            await loadExplore(force: true)
        } catch let error as APIError {
            personSaving = false
            if handleUnauthorized(error) { return }
            restorePerson(id: id, previous: previous)
            onToast?(message(for: error))
        } catch {
            personSaving = false
            restorePerson(id: id, previous: previous)
            onToast?(APIMessages.network)
        }
    }

    private func restorePerson(id: Int64, previous: (String, String)?) {
        guard let previous else { return }
        for index in people.indices where people[index].id == id {
            people[index].name = previous.0
            people[index].label = previous.1
        }
    }
}
