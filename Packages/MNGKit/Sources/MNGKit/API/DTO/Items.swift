import Foundation

/// Reverse-geocoded place attached to an item.
public struct Place: Decodable, Equatable, Sendable {
    public let road: String
    public let ward: String
    public let district: String
    public let province: String
    public let display: String

    public init(
        road: String = "",
        ward: String = "",
        district: String = "",
        province: String = "",
        display: String = ""
    ) {
        self.road = road
        self.ward = ward
        self.district = district
        self.province = province
        self.display = display
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        road = try container.mngValue(.road, default: "")
        ward = try container.mngValue(.ward, default: "")
        district = try container.mngValue(.district, default: "")
        province = try container.mngValue(.province, default: "")
        display = try container.mngValue(.display, default: "")
    }

    private enum CodingKeys: String, CodingKey {
        case road, ward, district, province, display
    }
}

/// One indexed media item, matching the server's `ItemView`.
public struct Item: Decodable, Equatable, Sendable, Identifiable {
    public let id: Int64
    public let cloud: String
    public let name: String
    public let path: String
    public let parent: String
    /// `"photo"` or `"video"` (JSON key `type`).
    public let mediaType: String
    public let mime: String
    public let size: Int64
    public let etag: String
    public let takenAt: Int64
    public let date: Int64
    public let dateISO: String
    public let year: Int
    public let month: Int
    public let day: Int
    public let width: Int64
    public let height: Int64
    public let duration: Double
    public let live: Bool
    public let liveName: String
    public let favorite: Bool
    public let thumbState: Int
    public let thumb: String
    public let preview: String
    public let media: String
    public let download: String
    public let edit: String
    public let lat: Double
    public let lng: Double
    public let place: Place
    /// Present on `/items/{id}` only.
    public let username: String
    /// Present on `/items/{id}` only.
    public let webdavURL: String

    public var isVideo: Bool { mediaType == "video" }
    public var isPhoto: Bool { mediaType == "photo" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        cloud = try container.mngValue(.cloud, default: "")
        name = try container.mngValue(.name, default: "")
        path = try container.mngValue(.path, default: "")
        parent = try container.mngValue(.parent, default: "")
        mediaType = try container.mngValue(.mediaType, default: "")
        mime = try container.mngValue(.mime, default: "")
        size = try container.mngValue(.size, default: 0)
        etag = try container.mngValue(.etag, default: "")
        takenAt = try container.mngValue(.takenAt, default: 0)
        date = try container.mngValue(.date, default: 0)
        dateISO = try container.mngValue(.dateISO, default: "")
        year = try container.mngValue(.year, default: 0)
        month = try container.mngValue(.month, default: 0)
        day = try container.mngValue(.day, default: 0)
        width = try container.mngValue(.width, default: 0)
        height = try container.mngValue(.height, default: 0)
        duration = try container.mngValue(.duration, default: 0)
        live = try container.mngValue(.live, default: false)
        liveName = try container.mngValue(.liveName, default: "")
        favorite = try container.mngValue(.favorite, default: false)
        thumbState = try container.mngValue(.thumbState, default: 0)
        thumb = try container.mngValue(.thumb, default: "")
        preview = try container.mngValue(.preview, default: "")
        media = try container.mngValue(.media, default: "")
        download = try container.mngValue(.download, default: "")
        edit = try container.mngValue(.edit, default: "")
        lat = try container.mngValue(.lat, default: 0)
        lng = try container.mngValue(.lng, default: 0)
        place = try container.mngValue(.place, default: Place())
        username = try container.mngValue(.username, default: "")
        webdavURL = try container.mngValue(.webdavURL, default: "")
    }

    private enum CodingKeys: String, CodingKey {
        case id, cloud, name, path, parent, mime, size, etag
        case mediaType = "type"
        case takenAt = "taken_at"
        case date
        case dateISO = "date_iso"
        case year, month, day, width, height, duration, live
        case liveName = "live_name"
        case favorite
        case thumbState = "thumb_state"
        case thumb, preview, media, download, edit, lat, lng, place
        case username
        case webdavURL = "webdav_url"
    }
}

/// `GET /items` payload.
public struct ItemsResponse: Decodable, Equatable, Sendable {
    public let cloud: String?
    public let items: [Item]
    public let total: Int64
    public let limit: Int?
    public let offset: Int?
    public let hasMore: Bool

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cloud = try container.decodeIfPresent(String.self, forKey: .cloud)
        items = try container.mngValue(.items, default: [])
        total = try container.mngValue(.total, default: 0)
        limit = try container.decodeIfPresent(Int.self, forKey: .limit)
        offset = try container.decodeIfPresent(Int.self, forKey: .offset)
        hasMore = try container.mngValue(.hasMore, default: false)
    }

    private enum CodingKeys: String, CodingKey {
        case cloud, items, total, limit, offset
        case hasMore = "has_more"
    }
}

/// `GET /items/{id}` payload.
public struct ItemDetail: Decodable, Equatable, Sendable {
    public let item: Item
    public let liveItem: Item?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        item = try container.decode(Item.self, forKey: .item)
        liveItem = try container.decodeIfPresent(Item.self, forKey: .liveItem)
    }

    private enum CodingKeys: String, CodingKey {
        case item
        case liveItem = "live_item"
    }
}

public typealias ItemResponse = ItemDetail

public struct FavoriteResponse: Decodable, Equatable, Sendable {
    public let favorite: Bool

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        favorite = try container.mngValue(.favorite, default: false)
    }

    private enum CodingKeys: String, CodingKey {
        case favorite
    }
}

public struct DeleteResponse: Decodable, Equatable, Sendable {
    public let deleted: Int64

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deleted = try container.mngValue(.deleted, default: 0)
    }

    private enum CodingKeys: String, CodingKey {
        case deleted
    }
}

/// Query parameters for `GET /items`, in the same order as the PWA's
/// `ItemQuery::path()`.
public struct ItemFilters: Equatable, Sendable {
    /// Legacy `/mng-cloud/` page size.
    public static let defaultLimit = 120

    public var cloud: String?
    /// `"photo"`, `"video"`, `"live"` (JSON key `type`).
    public var kind: String?
    /// Fixed album key or a dynamic `person:`, `province:` or `district:` key.
    public var album: String?
    public var year: Int?
    public var month: Int?
    public var favorite: Bool?
    public var q: String?
    public var limit: Int?
    public var offset: Int

    public init(
        cloud: String? = nil,
        kind: String? = nil,
        album: String? = nil,
        year: Int? = nil,
        month: Int? = nil,
        favorite: Bool? = nil,
        q: String? = nil,
        limit: Int? = nil,
        offset: Int = 0
    ) {
        self.cloud = cloud
        self.kind = kind
        self.album = album
        self.year = year
        self.month = month
        self.favorite = favorite
        self.q = q
        self.limit = limit
        self.offset = offset
    }

    /// The server's dynamic album key for a person.
    public mutating func select(person id: Int) {
        album = "person:\(id)"
    }

    /// The server's dynamic album key for a province.
    public mutating func select(province: String) {
        album = "province:\(province)"
    }

    /// The server's dynamic album key for a district (`province|district`).
    public mutating func select(district: String, province: String) {
        album = "district:\(province)|\(district)"
    }

    var query: APIQuery {
        var query = APIQuery()
        query.add("limit", limit ?? Self.defaultLimit)
        query.add("offset", offset)
        query.add("cloud", cloud)
        query.add("type", kind)
        query.add("album", album)
        query.add("year", year)
        query.add("month", month)
        query.add("favorite", favorite)
        let search = q?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        query.add("q", search.isEmpty ? nil : search)
        return query
    }
}
