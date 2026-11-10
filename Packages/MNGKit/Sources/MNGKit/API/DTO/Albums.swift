import Foundation

public struct Album: Decodable, Equatable, Sendable, Identifiable {
    public let key: String
    public let title: String
    public let sub: String
    public let count: Int64
    public let covers: [Item]

    public var id: String { key }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        title = try container.mngValue(.title, default: "")
        sub = try container.mngValue(.sub, default: "")
        count = try container.mngValue(.count, default: 0)
        covers = try container.mngValue(.covers, default: [])
    }

    private enum CodingKeys: String, CodingKey {
        case key, title, sub, count, covers
    }
}

public struct AlbumsResponse: Decodable, Equatable, Sendable {
    public let albums: [Album]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        albums = try container.mngValue(.albums, default: [])
    }

    private enum CodingKeys: String, CodingKey {
        case albums
    }
}

public struct YearBucket: Decodable, Equatable, Sendable, Identifiable {
    public let year: Int
    public let count: Int64
    public let covers: [Item]

    public var id: Int { year }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        year = try container.decode(Int.self, forKey: .year)
        count = try container.mngValue(.count, default: 0)
        covers = try container.mngValue(.covers, default: [])
    }

    private enum CodingKeys: String, CodingKey {
        case year, count, covers
    }
}

public struct YearsResponse: Decodable, Equatable, Sendable {
    public let years: [YearBucket]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        years = try container.mngValue(.years, default: [])
    }

    private enum CodingKeys: String, CodingKey {
        case years
    }
}

public struct MonthBucket: Decodable, Equatable, Sendable, Identifiable {
    public let key: String
    public let year: Int
    public let month: Int
    public let label: String
    public let count: Int64
    public let covers: [Item]

    public var id: String { key }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.mngValue(.key, default: "")
        year = try container.decode(Int.self, forKey: .year)
        month = try container.decode(Int.self, forKey: .month)
        label = try container.mngValue(.label, default: "")
        count = try container.mngValue(.count, default: 0)
        covers = try container.mngValue(.covers, default: [])
    }

    private enum CodingKeys: String, CodingKey {
        case key, year, month, label, count, covers
    }
}

public struct MonthsResponse: Decodable, Equatable, Sendable {
    public let months: [MonthBucket]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        months = try container.mngValue(.months, default: [])
    }

    private enum CodingKeys: String, CodingKey {
        case months
    }
}
