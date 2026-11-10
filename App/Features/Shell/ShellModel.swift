import MNGKit
import Observation
import SwiftUI

/// The five destinations of the PWA shell. The compact tab bar shows four and
/// reaches Search through its own button, exactly like `shell.rs`.
enum ShellTab: String, CaseIterable, Identifiable {
    case library
    case albums
    case search
    case vault
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .library: Strings.navLibrary
        case .albums: Strings.navAlbums
        case .search: Strings.navSearch
        case .vault: Strings.navVault
        case .settings: Strings.navSettings
        }
    }

    var tabLabel: String {
        self == .vault ? Strings.navVaultTab : label
    }

    var icon: String {
        switch self {
        case .library: "photo.on.rectangle.angled"
        case .albums: "rectangle.stack"
        case .search: "magnifyingglass"
        case .vault: "lock"
        case .settings: "gearshape"
        }
    }

    var subtitle: String {
        switch self {
        case .library: ""
        case .albums: Strings.albumsSubtitle
        case .search: Strings.searchSubtitle
        case .vault: Strings.vaultSubtitle
        case .settings: Strings.settingsSubtitle
        }
    }

    static let tabBarTabs: [ShellTab] = [.library, .albums, .vault, .settings]
    static let sidebarTabs: [ShellTab] = [.library, .albums, .search, .vault, .settings]
}

/// One root modal at a time. Opening iCloud from Connections switches this
/// route instead of stacking a second sheet; info and person rename are owned
/// here so they also work from Search and Albums.
enum ShellSheet: String, Identifiable {
    case connections
    case icloud
    case info
    case person

    var id: String { rawValue }
}

/// Shell state shared by both layouts: active tab, cloud, bootstrap counters,
/// toast and the library model.
@MainActor
@Observable
final class ShellModel {
    static let activeCloudKey = "mng.activeCloud"
    static let defaultCloud = "seafile"

    let store: SessionStore
    let client: MNGAPIClient
    let server: MNGServer
    let library: LibraryModel
    let search: SearchModel
    let albums: AlbumsModel
    let icloud: ICloudModel

    var tab: ShellTab = .library
    var toast: String?
    var shareFile: DownloadedFile?
    var activeSheet: ShellSheet?

    private(set) var bootstrap: Bootstrap?
    private(set) var activeCloud: String
    private(set) var isLoggingOut = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var started = false
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init(store: SessionStore, defaults: UserDefaults = .standard) {
        guard let client = store.apiClient, let server = store.server else {
            preconditionFailure("ShellModel requires a ready session")
        }
        self.store = store
        self.client = client
        self.server = server
        self.defaults = defaults

        let stored = defaults
            .string(forKey: Self.activeCloudKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (stored?.isEmpty == false ? stored : nil) ?? Self.defaultCloud
        activeCloud = key
        library = LibraryModel(client: client, cloud: key)
        search = SearchModel(client: client, cloud: key)
        albums = AlbumsModel(client: client, cloud: key)
        icloud = ICloudModel(client: client)

        library.cloudLabel = { [weak self] cloud in
            self?.cloudLabel(for: cloud) ?? (cloud.isEmpty ? Strings.cloud.lowercased() : cloud)
        }
        library.onEvent = { [weak self] event in
            self?.handle(event)
        }

        // Favorite/delete fan-out. The library owns the network mutation; the
        // other tabs only reconcile their own snapshots.
        library.onFavoritePatched = { [weak self] ids, value, known in
            guard let self else { return }
            search.applyFavorite(ids: ids, value: value)
            var snapshots = known
            for item in search.results where ids.contains(item.id) {
                snapshots[item.id] = item
            }
            albums.applyFavorite(ids: ids, value: value, known: snapshots)
        }
        library.onDeleteRemoved = { [weak self] token, ids in
            guard let self else { return }
            search.beginDelete(token: token, ids: ids, fromSearch: tab == .search)
            albums.beginDelete(token: token, ids: ids)
        }
        library.onDeleteRestored = { [weak self] token, ids in
            guard let self else { return }
            search.restoreDelete(token: token, ids: ids, fromSearch: tab == .search)
            albums.restoreDelete(token: token, ids: ids)
        }
        library.onDeleteSettled = { [weak self] token in
            self?.search.settleDelete(token: token)
            self?.albums.settleDelete(token: token)
        }

        search.onUnauthorized = { [weak self] in
            self?.expireSession()
        }
        albums.onUnauthorized = { [weak self] in
            self?.expireSession()
        }
        icloud.onUnauthorized = { [weak self] in
            self?.expireSession()
        }
        albums.onToast = { [weak self] message in
            self?.notify(message)
        }
        albums.knownItems = { [weak self] in
            guard let self else { return [] }
            return library.page.items + search.results
        }
        library.onPresentInfo = { [weak self] in
            self?.activeSheet = .info
        }
    }

    // MARK: - Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        // Bootstrap and the first item page are independent. Both run on the
        // main actor, so they interleave at their awaits instead of blocking
        // each other.
        let bootstrapTask = Task { @MainActor [weak self] in
            await self?.refreshBootstrap()
        }
        await library.start()
        await bootstrapTask.value
    }

    func refreshBootstrap() async {
        do {
            let data = try await client.bootstrap()
            bootstrap = data
            await repairActiveCloud(with: data)
        } catch let error as APIError {
            if await store.handle(error) { return }
            notify(APIMessages.bootstrap(error))
        } catch {
            notify(APIMessages.bootstrap(.network()))
        }
    }

    /// If `mng.activeCloud` names a library the server no longer returns, use
    /// the server's active cloud or its first card, like the PWA effect.
    private func repairActiveCloud(with data: Bootstrap) async {
        guard !data.clouds.contains(where: { $0.key == activeCloud }) else { return }
        let fallback = data.activeCloud
            .flatMap { key in
                data.clouds.contains(where: { $0.key == key }) ? key : nil
            }
            ?? data.clouds.first?.key
            ?? Self.defaultCloud
        guard fallback != activeCloud else { return }
        activeCloud = fallback
        defaults.set(fallback, forKey: Self.activeCloudKey)
        albums.updateCloud(fallback)
        search.cloudChanged(to: fallback)
        await library.setCloud(fallback)
        if tab == .albums {
            await albums.reloadAll()
        }
    }

    func switchCloud(_ key: String) async {
        guard let cloud = clouds.first(where: { $0.key == key }) else { return }
        defaults.set(key, forKey: Self.activeCloudKey)
        let changed = key != activeCloud
        activeCloud = key
        activeSheet = nil

        let label = cloud.label.trimmingCharacters(in: .whitespacesAndNewlines)
        notify("\(Strings.viewingCloud) \(label.isEmpty ? "thư viện" : label).")
        guard changed else { return }
        // Keep every tab pointed at the selected library. Albums drops its
        // loaded sections so the next visit reloads; Search reruns a non-empty
        // query in the background.
        albums.updateCloud(key)
        search.cloudChanged(to: key)
        await library.setCloud(key)
        if tab == .albums {
            await albums.reloadAll()
        }
    }

    func logout() async {
        guard !isLoggingOut else { return }
        isLoggingOut = true
        await store.logout()
        isLoggingOut = false
        if let error = store.logoutError {
            store.clearLogoutError()
            notify(error)
        }
        ThumbCache.shared.clear()
        PreviewCache.shared.clear()
    }

    func clearThumbnails() {
        ThumbCache.shared.clear()
    }

    // MARK: - Presentation

    func notify(_ message: String) {
        toastTask?.cancel()
        withAnimation(Tokens.Motion.fade) {
            toast = message
        }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled, let self else { return }
            withAnimation(Tokens.Motion.fade) {
                self.toast = nil
            }
        }
    }

    func dismissShare() {
        if let file = shareFile {
            try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent())
        }
        shareFile = nil
    }

    // MARK: - Derived copy

    var clouds: [CloudCard] { bootstrap?.clouds ?? [] }

    var activeCloudCard: CloudCard? {
        clouds.first { $0.key == activeCloud }
    }

    var activeCloudLabel: String {
        let label = activeCloudCard?.label.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return label.isEmpty ? Strings.serverFallback : label
    }

    var activeCloudTotal: Int64 {
        activeCloudCard?.counts.total ?? bootstrap?.total ?? library.page.total
    }

    var cloudSubtitleText: String {
        guard let card = activeCloudCard else { return Strings.connecting }
        return cloudSubtitle(for: card)
    }

    func selectTab(_ next: ShellTab) {
        if next != .library {
            library.exitSelection()
        }
        // Switching away from an album (or tapping Library) leaves the
        // drill-down, clears its filters/layout and refreshes the grid.
        if library.isAlbumOpen {
            library.closeAlbum()
            Task { [weak self] in
                await self?.library.reload()
            }
        }
        tab = next
        if next == .albums {
            Task { [weak self] in
                await self?.albums.loadIfNeeded()
            }
        }
    }

    /// Tab highlight while an album is open points at the place it was opened
    /// from (`album_return`), not at Library.
    func isTabActive(_ target: ShellTab) -> Bool {
        if library.isAlbumOpen {
            return target == (library.albumReturn == .search ? .search : .albums)
        }
        return tab == target
    }

    /// Open an album drill-down inside the Library tab. Search opens a hint
    /// album with Search as the back target.
    func openAlbum(_ album: AlbumFilter) {
        let returnTo: AlbumReturn = tab == .search ? .search : .albums
        library.beginAlbum(album, returnTo: returnTo)
        tab = .library
        Task { [weak self] in
            await self?.library.reload()
        }
    }

    var canGoBack: Bool {
        library.isAlbumOpen
            || (tab == .library && library.filters.hasDateFilter)
    }

    func goBack() async {
        if library.isAlbumOpen {
            let target = library.closeAlbum()
            tab = target == .search ? .search : .albums
            await library.reload()
            return
        }
        await library.goBack()
    }

    var title: String {
        if library.isAlbumOpen, let album = library.activeAlbum {
            return album.displayTitle
        }
        return tab == .library ? Strings.navLibrary : tab.label
    }

    var subtitle: String {
        if library.isAlbumOpen {
            return Strings.albumSelected
        }
        guard tab == .library else { return tab.subtitle }
        let card = activeCloudCard
        let count = card?.counts.total ?? bootstrap?.total ?? library.page.total
        let video = card?.counts.video
            ?? Int64(library.page.items.filter(\.isVideo).count)
        return "\(MNGFormat.today()) · \(MNGFormat.number(count)) mục · \(MNGFormat.number(video)) video"
    }

    // MARK: - Modals

    func presentConnections() {
        activeSheet = .connections
    }

    func presentICloud() {
        activeSheet = .icloud
    }

    func presentPersonEdit(_ person: Person) {
        albums.beginEditPerson(person)
        activeSheet = .person
    }

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var sidebarFoot: String {
        let username = store.session?.me.username ?? ""
        return "\(username) · MNG Cloud \(appVersion)"
    }

    var storageFreeText: String? {
        guard let free = bootstrap?.storage.free, free > 0 else { return nil }
        return "\(MNGFormat.bytes(Int64(clamping: free))) \(Strings.freeSpace)"
    }

    func cloudLabel(for key: String) -> String {
        guard !key.isEmpty else { return "đám mây" }
        if let cloud = clouds.first(where: { $0.key == key }) {
            let label = cloud.label.trimmingCharacters(in: .whitespacesAndNewlines)
            return label.isEmpty ? cloud.key : label
        }
        return key
    }

    func cloudSubtitle(for cloud: CloudCard) -> String {
        cloud.username.isEmpty
            ? Strings.connecting
            : "WebDAV · \(cloud.username)"
    }

    // MARK: - Events

    private func handle(_ event: LibraryEvent) {
        switch event {
        case .toast(let message):
            notify(message)
        case .unauthorized:
            expireSession()
        case .share(let file):
            if let old = shareFile, old.url != file.url {
                try? FileManager.default.removeItem(at: old.url.deletingLastPathComponent())
            }
            shareFile = file
        }
    }

    /// 401 from any tab ends the session exactly once; the session state
    /// machine owns the retry/login transition.
    func expireSession() {
        Task { [weak self] in
            guard let self else { return }
            await store.expireSession()
            ThumbCache.shared.clear()
            PreviewCache.shared.clear()
        }
    }
}
