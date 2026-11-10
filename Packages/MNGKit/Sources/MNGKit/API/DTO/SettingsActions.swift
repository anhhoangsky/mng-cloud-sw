import Foundation

/// `POST /clouds/test` payload. The server may omit every field when the
/// WebDAV probe failed before producing a result.
public struct CloudTestResponse: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let ms: Int64
    public let message: String

    public init(ok: Bool = false, ms: Int64 = 0, message: String = "") {
        self.ok = ok
        self.ms = ms
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.mngValue(.ok, default: false)
        ms = try container.mngValue(.ms, default: 0)
        message = try container.mngValue(.message, default: "")
    }

    private enum CodingKeys: String, CodingKey {
        case ok, ms, message
    }
}

/// `POST /scans` and `POST /thumbs/retry` acknowledge whether the job was
/// queued or already present in the queue.
public struct QueuedResponse: Decodable, Equatable, Sendable {
    public let queued: Bool

    public init(queued: Bool = false) {
        self.queued = queued
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        queued = try container.mngValue(.queued, default: false)
    }

    private enum CodingKeys: String, CodingKey {
        case queued
    }
}

/// `POST /cache/tmp/clear` payload.
public struct TmpClearResponse: Decodable, Equatable, Sendable {
    public let removed: Int64

    public init(removed: Int64 = 0) {
        self.removed = removed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        removed = try container.mngValue(.removed, default: 0)
    }

    private enum CodingKeys: String, CodingKey {
        case removed
    }
}
