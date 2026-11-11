import Foundation

/// `POST /api/v1/media/match` response.
///
/// `matched` is true when the index already carries a photo with the same
/// `(taken_at, size)`, so the client can skip the transfer.
public struct MediaMatchResponse: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let matched: Bool
    public let id: Int64?
    public let path: String?

    public init(
        ok: Bool = true,
        matched: Bool,
        id: Int64? = nil,
        path: String? = nil
    ) {
        self.ok = ok
        self.matched = matched
        self.id = id
        self.path = path
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.mngValue(.ok, default: true)
        matched = try container.mngValue(.matched, default: false)
        id = try container.decodeIfPresent(Int64.self, forKey: .id)
        path = try container.decodeIfPresent(String.self, forKey: .path)
    }

    private enum CodingKeys: String, CodingKey {
        case ok, matched, id, path
    }
}

/// `POST /api/v1/media/upload` response.
///
/// `matched` is true when the server found an identical object (same name,
/// same size) already at the target path and skipped the transfer.
public struct MediaUploadResponse: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let matched: Bool
    public let id: Int64?
    public let path: String?

    public init(
        ok: Bool = true,
        matched: Bool,
        id: Int64? = nil,
        path: String? = nil
    ) {
        self.ok = ok
        self.matched = matched
        self.id = id
        self.path = path
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.mngValue(.ok, default: true)
        matched = try container.mngValue(.matched, default: false)
        id = try container.decodeIfPresent(Int64.self, forKey: .id)
        path = try container.decodeIfPresent(String.self, forKey: .path)
    }

    private enum CodingKeys: String, CodingKey {
        case ok, matched, id, path
    }
}
