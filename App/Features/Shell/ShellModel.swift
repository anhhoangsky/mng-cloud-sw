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

    var tab: ShellTab = .library
    var toast: String?
    var shareFile: DownloadedFile?
    var isCloudPickerPresented = false

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

        library.cloudLabel = { [weak self] cloud in
            self?.cloudLabel(for: cloud) ?? (cloud.isEmpty ? Strings.cloud.lowercased() : cloud)
        }
        library.onEvent = { [weak self] event in
            self?.handle(event)
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
        await library.setCloud(fallback)
    }

    func switchCloud(_ key: String) async {
        guard let cloud = clouds.first(where: { $0.key == key }) else { return }
        defaults.set(key, forKey: Self.activeCloudKey)
        let changed = key != activeCloud
        activeCloud = key
        isCloudPickerPresented = false

        let label = cloud.label.trimmingCharacters(in: .whitespacesAndNewlines)
        notify("\(Strings.viewingCloud) \(label.isEmpty ? "thư viện" : label).")
        guard changed else { return }
        await library.setCloud(key)
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
        tab = next
    }

    var title: String {
        tab == .library ? Strings.navLibrary : tab.label
    }

    var subtitle: String {
        guard tab == .library else { return tab.subtitle }
        let card = activeCloudCard
        let count = card?.counts.total ?? bootstrap?.total ?? library.page.total
        let video = card?.counts.video
            ?? Int64(library.page.items.filter(\.isVideo).count)
        return "\(MNGFormat.today()) · \(MNGFormat.number(count)) mục · \(MNGFormat.number(video)) video"
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
            Task { [weak self] in
                guard let self else { return }
                await store.expireSession()
                ThumbCache.shared.clear()
            }
        case .share(let file):
            if let old = shareFile, old.url != file.url {
                try? FileManager.default.removeItem(at: old.url.deletingLastPathComponent())
            }
            shareFile = file
        }
    }
}
