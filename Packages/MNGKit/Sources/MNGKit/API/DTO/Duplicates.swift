import Foundation

public struct DuplicateStats: Decodable, Equatable, Sendable {
    public let total: Int64
    public let hashed: Int64

    public init(total: Int64 = 0, hashed: Int64 = 0) {
        self.total = total
        self.hashed = hashed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        total = try container.mngValue(.total, default: 0)
        hashed = try container.mngValue(.hashed, default: 0)
    }

    private enum CodingKeys: String, CodingKey {
        case total, hashed
    }
}

/// The server flattens a full `ItemView` and adds `distance`.
public struct DuplicateItem: Decodable, Equatable, Sendable {
    public let item: Item
    public let distance: Int64

    public init(from decoder: Decoder) throws {
        item = try Item(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        distance = try container.mngValue(.distance, default: 0)
    }

    private enum CodingKeys: String, CodingKey {
        case distance
    }
}

public struct DuplicateGroup: Decodable, Equatable, Sendable {
    public let items: [DuplicateItem]
    public let similarity: Int64
    public let date: Int64

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.mngValue(.items, default: [])
        similarity = try container.mngValue(.similarity, default: 0)
        date = try container.mngValue(.date, default: 0)
    }

    private enum CodingKeys: String, CodingKey {
        case items, similarity, date
    }
}

public struct DuplicatesResponse: Decodable, Equatable, Sendable {
    public let groups: [DuplicateGroup]
    public let stats: DuplicateStats

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groups = try container.mngValue(.groups, default: [])
        stats = try container.mngValue(.stats, default: DuplicateStats())
    }

    private enum CodingKeys: String, CodingKey {
        case groups, stats
    }
}
