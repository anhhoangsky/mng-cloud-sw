import Foundation

public struct Person: Decodable, Equatable, Sendable, Identifiable {
    public let id: Int64
    public var name: String
    public var label: String
    public let faceCount: Int64
    public let itemCount: Int64
    public let coverFaceID: Int64
    public let cover: String
    public let updatedAt: Int64

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        name = try container.mngValue(.name, default: "")
        label = try container.mngValue(.label, default: "")
        faceCount = try container.mngValue(.faceCount, default: 0)
        itemCount = try container.mngValue(.itemCount, default: 0)
        coverFaceID = try container.mngValue(.coverFaceID, default: 0)
        cover = try container.mngValue(.cover, default: "")
        updatedAt = try container.mngValue(.updatedAt, default: 0)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, label, cover, updatedAt = "updated_at"
        case faceCount = "face_count"
        case itemCount = "item_count"
        case coverFaceID = "cover_face_id"
    }
}

public struct PeopleResponse: Decodable, Equatable, Sendable {
    public let people: [Person]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        people = try container.mngValue(.people, default: [])
    }

    private enum CodingKeys: String, CodingKey {
        case people
    }
}

public struct PlaceProvince: Decodable, Equatable, Hashable, Sendable {
    public let province: String
    public let count: Int64
    public let coverID: Int64

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        province = try container.mngValue(.province, default: "")
        count = try container.mngValue(.count, default: 0)
        coverID = try container.mngValue(.coverID, default: 0)
    }

    private enum CodingKeys: String, CodingKey {
        case province, count
        case coverID = "cover_id"
    }
}

public struct PlaceDistrict: Decodable, Equatable, Hashable, Sendable {
    public let province: String
    public let district: String
    public let count: Int64
    public let coverID: Int64

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        province = try container.mngValue(.province, default: "")
        district = try container.mngValue(.district, default: "")
        count = try container.mngValue(.count, default: 0)
        coverID = try container.mngValue(.coverID, default: 0)
    }

    private enum CodingKeys: String, CodingKey {
        case province, district, count
        case coverID = "cover_id"
    }
}

/// `POST /people/{id}/rename` payload lives in `Admin.swift` next to the
/// other admin response shapes.

public struct PlacesResponse: Decodable, Equatable, Sendable {
    public let provinces: [PlaceProvince]
    public let districts: [PlaceDistrict]

    public init(provinces: [PlaceProvince] = [], districts: [PlaceDistrict] = []) {
        self.provinces = provinces
        self.districts = districts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provinces = try container.mngValue(.provinces, default: [])
        districts = try container.mngValue(.districts, default: [])
    }

    private enum CodingKeys: String, CodingKey {
        case provinces, districts
    }
}

public struct AiStats: Decodable, Equatable, Sendable {
    public let total: Int64
    public let facesDone: Int64
    public let facesPending: Int64
    public let facesFailed: Int64
    public let placeDone: Int64
    public let placePending: Int64

    public init(
        total: Int64 = 0,
        facesDone: Int64 = 0,
        facesPending: Int64 = 0,
        facesFailed: Int64 = 0,
        placeDone: Int64 = 0,
        placePending: Int64 = 0
    ) {
        self.total = total
        self.facesDone = facesDone
        self.facesPending = facesPending
        self.facesFailed = facesFailed
        self.placeDone = placeDone
        self.placePending = placePending
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        total = try container.mngValue(.total, default: 0)
        facesDone = try container.mngValue(.facesDone, default: 0)
        facesPending = try container.mngValue(.facesPending, default: 0)
        facesFailed = try container.mngValue(.facesFailed, default: 0)
        placeDone = try container.mngValue(.placeDone, default: 0)
        placePending = try container.mngValue(.placePending, default: 0)
    }

    private enum CodingKeys: String, CodingKey {
        case total
        case facesDone = "faces_done"
        case facesPending = "faces_pending"
        case facesFailed = "faces_failed"
        case placeDone = "place_done"
        case placePending = "place_pending"
    }
}

public struct AiStatus: Decodable, Equatable, Sendable {
    public let stats: AiStats
    public let people: Int64
    public let places: Int64
    public let running: Bool
    public let heartbeat: Int64

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stats = try container.mngValue(.stats, default: AiStats())
        people = try container.mngValue(.people, default: 0)
        places = try container.mngValue(.places, default: 0)
        running = try container.mngValue(.running, default: false)
        heartbeat = try container.mngValue(.heartbeat, default: 0)
    }

    private enum CodingKeys: String, CodingKey {
        case stats, people, places, running, heartbeat
    }
}
