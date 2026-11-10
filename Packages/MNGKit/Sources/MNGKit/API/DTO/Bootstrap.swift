import Foundation

public struct CloudCounts: Decodable, Equatable, Sendable {
    public let photo: Int64
    public let video: Int64
    public let bytes: Int64
    public let total: Int64

    public init(photo: Int64 = 0, video: Int64 = 0, bytes: Int64 = 0, total: Int64 = 0) {
        self.photo = photo
        self.video = video
        self.bytes = bytes
        self.total = total
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        photo = try container.mngValue(.photo, default: 0)
        video = try container.mngValue(.video, default: 0)
        bytes = try container.mngValue(.bytes, default: 0)
        total = try container.mngValue(.total, default: 0)
    }

    private enum CodingKeys: String, CodingKey {
        case photo, video, bytes, total
    }
}

/// Last `test_cloud` result, shown on the cloud cards.
public struct CloudHealth: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let ms: Int64
    public let checked: Int64
    public let message: String

    public init(ok: Bool = false, ms: Int64 = 0, checked: Int64 = 0, message: String = "") {
        self.ok = ok
        self.ms = ms
        self.checked = checked
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.mngValue(.ok, default: false)
        ms = try container.mngValue(.ms, default: 0)
        checked = try container.mngValue(.checked, default: 0)
        message = try container.mngValue(.message, default: "")
    }

    private enum CodingKeys: String, CodingKey {
        case ok, ms, checked, message
    }
}

public struct CloudCard: Decodable, Equatable, Sendable {
    public let key: String
    public let label: String
    public let color: String
    public let root: String
    public let username: String
    public let webdav: String
    public let counts: CloudCounts
    public let health: CloudHealth?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        label = try container.mngValue(.label, default: "")
        color = try container.mngValue(.color, default: "")
        root = try container.mngValue(.root, default: "")
        username = try container.mngValue(.username, default: "")
        webdav = try container.mngValue(.webdav, default: "")
        counts = try container.mngValue(.counts, default: CloudCounts())
        // The PWA ignores a malformed individual health object instead of
        // failing the whole bootstrap payload.
        health = try? container.decodeIfPresent(CloudHealth.self, forKey: .health)
    }

    private enum CodingKeys: String, CodingKey {
        case key, label, color, root, username, webdav, counts, health
    }
}

public struct Storage: Decodable, Equatable, Sendable {
    public let free: UInt64

    public init(free: UInt64 = 0) {
        self.free = free
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        free = try container.mngValue(.free, default: 0)
    }

    private enum CodingKeys: String, CodingKey {
        case free
    }
}

/// One cloud's scan progress. The writer shallow-merges fields, so every key
/// can be absent.
public struct ScanStatus: Decodable, Equatable, Sendable {
    public let scanning: Bool
    public let started: Int64
    public let finished: Int64
    public let complete: Bool
    public let message: String
    public let error: String
    public let ok: Bool
    public let files: Int64
    public let dirs: Int64
    public let total: Int64
    public let photos: Int64
    public let videos: Int64
    public let seconds: Int64

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scanning = try container.mngValue(.scanning, default: false)
        started = try container.mngValue(.started, default: 0)
        finished = try container.mngValue(.finished, default: 0)
        complete = try container.mngValue(.complete, default: false)
        message = try container.mngValue(.message, default: "")
        error = try container.mngValue(.error, default: "")
        ok = try container.mngValue(.ok, default: false)
        files = try container.mngValue(.files, default: 0)
        dirs = try container.mngValue(.dirs, default: 0)
        total = try container.mngValue(.total, default: 0)
        photos = try container.mngValue(.photos, default: 0)
        videos = try container.mngValue(.videos, default: 0)
        seconds = try container.mngValue(.seconds, default: 0)
    }

    private enum CodingKeys: String, CodingKey {
        case scanning, started, finished, complete, message, error, ok
        case files, dirs, total, photos, videos, seconds
    }
}

/// First-render payload of `GET /bootstrap`.
public struct Bootstrap: Decodable, Equatable, Sendable {
    public let me: Me
    public let csrf: String
    public let clouds: [CloudCard]
    public let counts: [String: CloudCounts]
    public let total: Int64
    public let activeCloud: String?
    public let storage: Storage
    public let scan: [String: ScanStatus]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        me = try container.decode(Me.self, forKey: .me)
        csrf = try container.mngValue(.csrf, default: "")
        clouds = try container.mngValue(.clouds, default: [])
        counts = try container.mngValue(.counts, default: [:])
        total = try container.mngValue(.total, default: 0)
        activeCloud = try container.decodeIfPresent(String.self, forKey: .activeCloud)
        storage = try container.mngValue(.storage, default: Storage())
        scan = try container.mngValue(.scan, default: [:])
    }

    private enum CodingKeys: String, CodingKey {
        case me, csrf, clouds, counts, total, storage, scan
        case activeCloud = "active_cloud"
    }
}

/// Payload of `GET /clouds`.
public struct CloudsResponse: Decodable, Equatable, Sendable {
    public let clouds: [CloudCard]
    public let counts: [String: CloudCounts]
    public let total: Int64
    public let activeCloud: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clouds = try container.mngValue(.clouds, default: [])
        counts = try container.mngValue(.counts, default: [:])
        total = try container.mngValue(.total, default: 0)
        activeCloud = try container.decodeIfPresent(String.self, forKey: .activeCloud)
    }

    private enum CodingKeys: String, CodingKey {
        case clouds, counts, total
        case activeCloud = "active_cloud"
    }
}

/// Payload of `GET /counts`.
public struct CountsResponse: Decodable, Equatable, Sendable {
    public let cloud: String?
    public let counts: [String: CloudCounts]
    public let total: Int64
    public let bytes: Int64

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cloud = try container.decodeIfPresent(String.self, forKey: .cloud)
        counts = try container.mngValue(.counts, default: [:])
        total = try container.mngValue(.total, default: 0)
        bytes = try container.mngValue(.bytes, default: 0)
    }

    private enum CodingKeys: String, CodingKey {
        case cloud, counts, total, bytes
    }
}

/// One legacy thumbnail-state row (`n`, not `count`).
public struct ThumbStateCount: Decodable, Equatable, Sendable {
    public let thumbState: Int
    public let n: Int64

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        thumbState = try container.mngValue(.thumbState, default: 0)
        n = try container.mngValue(.n, default: 0)
    }

    private enum CodingKeys: String, CodingKey {
        case thumbState = "thumb_state"
        case n
    }
}

/// Payload of `GET /stats`.
public struct Stats: Decodable, Equatable, Sendable {
    public let counts: [String: CloudCounts]
    public let scan: [String: ScanStatus]
    public let thumbs: [ThumbStateCount]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        counts = try container.mngValue(.counts, default: [:])
        scan = try container.mngValue(.scan, default: [:])
        thumbs = try container.mngValue(.thumbs, default: [])
    }

    private enum CodingKeys: String, CodingKey {
        case counts, scan, thumbs
    }
}
