import Foundation

/// One album drill-down: the server key plus the title shown in the header.
///
/// Fixed keys (`favorites`, `videos`, `live`, screenshots…) are sent as
/// `/items?album=…`. `year:YYYY` is the one legacy key that maps to the plain
/// `year` query parameter. People, provinces and districts are pinned to
/// `cloud = nil` so a face/place album spans every connected library, exactly
/// like `item_cloud_filter()` in `shell.rs`.
public struct AlbumFilter: Equatable, Sendable, Identifiable {
    public let key: String
    public let title: String

    public init(key: String, title: String) {
        self.key = key
        self.title = title
    }

    public var id: String { key }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Album" : trimmed
    }

    /// Parsed `year:YYYY` value, or `nil` for every other key.
    public var year: Int? {
        guard key.hasPrefix("year:") else { return nil }
        let value = key.dropFirst("year:".count)
        guard let year = Int(value), (1...9999).contains(year) else { return nil }
        return year
    }

    public var isYear: Bool { key.hasPrefix("year:") }

    /// `person:`, `province:` and `district:` albums ignore the active cloud.
    public var isCrossCloud: Bool {
        key.hasPrefix("person:")
            || key.hasPrefix("province:")
            || key.hasPrefix("district:")
    }

    /// Value for `/items?album=`; `year:YYYY` uses `year` instead.
    public var serverAlbum: String? {
        key.hasPrefix("year:") ? nil : key
    }

    public func itemFilters(cloud: String?, offset: Int = 0, limit: Int? = nil) -> ItemFilters {
        ItemFilters(
            cloud: isCrossCloud ? nil : cloud,
            album: serverAlbum,
            year: year,
            limit: limit,
            offset: offset
        )
    }
}

/// Albums section order. People and places interpret `newest` as "most items".
public enum AlbumSort: String, CaseIterable, Sendable {
    case newest
    case oldest
    case name

    public var label: String {
        switch self {
        case .newest: "Mới nhất"
        case .oldest: "Cũ nhất"
        case .name: "Tên A–Z"
        }
    }
}

/// Per-section density, matching the PWA's `Lớn / Vừa / Nhỏ` options.
public enum AlbumGrid: String, CaseIterable, Sendable {
    case large
    case medium
    case small

    public var label: String {
        switch self {
        case .large: "Lớn"
        case .medium: "Vừa"
        case .small: "Nhỏ"
        }
    }

    /// Minimum tile width from `app.css` (`220/140/92px`).
    public var minimumWidth: Int {
        switch self {
        case .large: 220
        case .medium: 140
        case .small: 92
        }
    }

    /// Narrower minimum on phones so two, three and four columns all fit.
    public var compactMinimumWidth: Int {
        switch self {
        case .large: 164
        case .medium: 108
        case .small: 76
        }
    }

    public var spacing: CGFloat {
        switch self {
        case .large: 8
        case .medium: 4
        case .small: 2
        }
    }
}

/// Sorting rules copied from `sort_albums`, `sort_people`, `sort_places`,
/// `sort_districts` and `sorted_album_items`.
///
/// Rust's `sort_by_key` is stable; the helpers below preserve the server's
/// order on ties instead of relying on Swift's unstable `sort`.
public enum AlbumSorting {
    public static func items(_ items: [Item], sort: AlbumSort) -> [Item] {
        switch sort {
        case .newest:
            return stable(items) { left, right in
                left.takenAt > right.takenAt
                    || (left.takenAt == right.takenAt && left.id > right.id)
            }
        case .oldest:
            return stable(items) { left, right in
                left.takenAt < right.takenAt
                    || (left.takenAt == right.takenAt && left.id < right.id)
            }
        case .name:
            return stable(items) { left, right in
                let byName = left.name.lowercased()
                let other = right.name.lowercased()
                if byName != other {
                    return byName < other
                }
                return left.id < right.id
            }
        }
    }

    public static func albums(_ albums: [Album], sort: AlbumSort) -> [Album] {
        switch sort {
        case .newest:
            return stable(albums) { $0.count > $1.count }
        case .oldest:
            return stable(albums) { $0.count < $1.count }
        case .name:
            return stable(albums) {
                $0.title.lowercased() < $1.title.lowercased()
            }
        }
    }

    public static func people(_ people: [Person], sort: AlbumSort) -> [Person] {
        switch sort {
        case .newest:
            return stable(people) { $0.itemCount > $1.itemCount }
        case .oldest:
            return stable(people) { $0.itemCount < $1.itemCount }
        case .name:
            return stable(people) {
                personName($0).lowercased() < personName($1).lowercased()
            }
        }
    }

    public static func places(_ places: [PlaceProvince], sort: AlbumSort) -> [PlaceProvince] {
        switch sort {
        case .newest:
            return stable(places) { $0.count > $1.count }
        case .oldest:
            return stable(places) { $0.count < $1.count }
        case .name:
            return stable(places) {
                $0.province.lowercased() < $1.province.lowercased()
            }
        }
    }

    public static func districts(_ places: [PlaceDistrict], sort: AlbumSort) -> [PlaceDistrict] {
        switch sort {
        case .newest:
            return stable(places) { $0.count > $1.count }
        case .oldest:
            return stable(places) { $0.count < $1.count }
        case .name:
            return stable(places) {
                $0.district.lowercased() < $1.district.lowercased()
            }
        }
    }

    public static func personName(_ person: Person) -> String {
        person.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? person.name
            : person.label
    }

    private static func stable<Element>(
        _ list: [Element],
        by ordered: (Element, Element) -> Bool
    ) -> [Element] {
        list.enumerated()
            .sorted { left, right in
                if ordered(left.element, right.element) { return true }
                if ordered(right.element, left.element) { return false }
                return left.offset < right.offset
            }
            .map(\.element)
    }
}

/// Album buckets shown on the Albums tab.
public enum AlbumCatalog {
    /// `is_collection_album()` excludes years, the "all" pseudo-album and the
    /// favorites pseudo-album.
    public static func isCollection(_ album: Album) -> Bool {
        !album.key.hasPrefix("year:")
            && album.key != "all"
            && album.key != "favorites"
    }

    public static func collections(_ albums: [Album]) -> [Album] {
        albums.filter(isCollection)
    }

    public static func years(_ albums: [Album]) -> [Album] {
        albums.filter { $0.key.hasPrefix("year:") }
    }

    /// `Người {id}` is the PWA fallback for an unnamed face.
    public static func personTitle(_ person: Person) -> String {
        let name = AlbumSorting.personName(person)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Người \(person.id)" : name
    }
}

/// The five AI counters that force a reload of people/places.
public struct ExploreSignature: Equatable, Sendable, CustomStringConvertible {
    public let people: Int64
    public let places: Int64
    public let facesDone: Int64
    public let placeDone: Int64
    public let placePending: Int64

    public init(_ status: AiStatus) {
        people = status.people
        places = status.places
        facesDone = status.stats.facesDone
        placeDone = status.stats.placeDone
        placePending = status.stats.placePending
    }

    public var description: String {
        "\(people):\(places):\(facesDone):\(placeDone):\(placePending)"
    }
}

/// Merge a server favorites page with every locally known item.
///
/// The favorites snapshot can lag a favorite by up to 15 seconds, so flags are
/// synced from the local copies, rows known to be unfavorited are dropped and
/// locally favorited rows missing from the response are inserted in
/// newest-first order (ported from `reconcile_favorites`).
public enum FavoriteReconciliation {
    public static func apply(_ list: [Item], known: [Int64: Item]) -> [Item] {
        var merged = list.filter { item in
            known[item.id]?.favorite ?? true
        }
        for index in merged.indices {
            if let item = known[merged[index].id] {
                merged[index].favorite = item.favorite
            }
        }

        let present = Set(merged.map(\.id))
        let missing = known.values
            .filter { $0.favorite && !present.contains($0.id) }
            .sorted {
                $0.takenAt > $1.takenAt
                    || ($0.takenAt == $1.takenAt && $0.id > $1.id)
            }
        for item in missing {
            let position = merged.firstIndex {
                $0.takenAt < item.takenAt
                    || ($0.takenAt == item.takenAt && $0.id < item.id)
            } ?? merged.endIndex
            merged.insert(item, at: position)
        }
        return merged
    }
}

/// Search chips. `favorite` is search-only and is sent as `type=favorite`, the
/// same (slightly odd) query the PWA builds from `SearchFilter::api_value()`.
public enum SearchFilter: String, CaseIterable, Sendable {
    case all
    case photo
    case video
    case live
    case favorite

    public var label: String {
        switch self {
        case .all: "Tất cả"
        case .photo: "Ảnh"
        case .video: "Video"
        case .live: "Live"
        case .favorite: "Yêu thích"
        }
    }

    public var apiValue: String? {
        switch self {
        case .all: nil
        case .photo: "photo"
        case .video: "video"
        case .live: "live"
        case .favorite: "favorite"
        }
    }
}

/// One submitted search. The PWA caps results at 300 and never pages.
public struct SearchQuery: Equatable, Sendable {
    public static let limit = 300
    public static let debounceMilliseconds = 280

    public let text: String
    public let filter: SearchFilter

    public init(text: String, filter: SearchFilter) {
        self.text = text
        self.filter = filter
    }

    public var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isEmpty: Bool { trimmed.isEmpty }

    public func itemFilters(cloud: String?, offset: Int = 0, limit: Int? = nil) -> ItemFilters {
        ItemFilters(
            cloud: cloud,
            kind: filter.apiValue,
            q: trimmed,
            limit: limit ?? Self.limit,
            offset: offset
        )
    }
}

/// Static rows in the empty Search view. Each opens an album in the library.
public struct SearchHint: Equatable, Sendable, Identifiable {
    public let album: AlbumFilter
    public let label: String
    public let icon: String

    public var id: String { album.key }

    public init(album: AlbumFilter, label: String, icon: String) {
        self.album = album
        self.label = label
        self.icon = icon
    }

    public static let all: [SearchHint] = [
        SearchHint(
            album: AlbumFilter(key: "year:2022", title: "Năm 2022"),
            label: "Ảnh năm 2022",
            icon: "photo.on.rectangle"
        ),
        SearchHint(
            album: AlbumFilter(key: "favorites", title: "Yêu thích"),
            label: "Ảnh yêu thích",
            icon: "heart"
        ),
        SearchHint(
            album: AlbumFilter(key: "videos", title: "Video"),
            label: "Tất cả video",
            icon: "video"
        ),
        SearchHint(
            album: AlbumFilter(key: "live", title: "Live Photo"),
            label: "Live Photo",
            icon: "livephoto"
        ),
    ]
}
