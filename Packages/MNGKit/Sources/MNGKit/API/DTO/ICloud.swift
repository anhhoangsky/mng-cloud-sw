import Foundation

/// One importer job. The server relays the Python worker's status document.
public struct IcloudJob: Decodable, Equatable, Sendable {
    public let id: String
    public let jobType: String
    public let state: String
    public let message: String
    public let progress: Double
    public let pid: Int64
    public let log: String
    public let started: Int64
    public let updated: Int64
    public let error: String
    public let username: String
    public let recent: Int64
    public let deleteAfter: Bool
    public let imported: Int64

    public var isActive: Bool {
        switch state {
        case "queued", "running", "awaiting_mfa", "awaiting_password", "paused", "importing":
            return true
        default:
            return false
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.mngValue(.id, default: "")
        jobType = try container.mngValue(.jobType, default: "")
        state = try container.mngValue(.state, default: "")
        message = try container.mngValue(.message, default: "")
        progress = try container.mngValue(.progress, default: 0)
        pid = try container.mngValue(.pid, default: 0)
        log = try container.mngValue(.log, default: "")
        started = try container.mngValue(.started, default: 0)
        updated = try container.mngValue(.updated, default: 0)
        error = try container.mngValue(.error, default: "")
        username = try container.mngValue(.username, default: "")
        recent = try container.mngValue(.recent, default: 0)
        deleteAfter = try container.mngValue(.deleteAfter, default: false)
        imported = try container.mngValue(.imported, default: 0)
    }

    private enum CodingKeys: String, CodingKey {
        case id, state, message, progress, pid, log, started, updated, error
        case username, recent, imported
        case jobType = "type"
        case deleteAfter = "delete_after"
    }
}

public struct IcloudSettings: Decodable, Equatable, Sendable {
    public let recent: Int64
    public let deleteAfter: Bool
    public let importPath: String

    public init(recent: Int64 = 0, deleteAfter: Bool = false, importPath: String = "") {
        self.recent = recent
        self.deleteAfter = deleteAfter
        self.importPath = importPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recent = try container.mngValue(.recent, default: 0)
        deleteAfter = try container.mngValue(.deleteAfter, default: false)
        importPath = try container.mngValue(.importPath, default: "")
    }

    private enum CodingKeys: String, CodingKey {
        case recent
        case deleteAfter = "delete_after"
        case importPath = "import_path"
    }
}

public struct IcloudStatus: Decodable, Equatable, Sendable {
    /// False when the server has no iCloud runner configured.
    public let configured: Bool
    public let authenticated: Bool
    public let appleID: String
    public let authJob: IcloudJob?
    public let downloadJob: IcloudJob?
    public let activeJob: IcloudJob?
    public let settings: IcloudSettings

    /// Legacy precedence: active job, then download, then auth.
    public var job: IcloudJob? {
        activeJob ?? downloadJob ?? authJob
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        configured = try container.mngValue(.configured, default: false)
        authenticated = try container.mngValue(.authenticated, default: false)
        appleID = try container.mngValue(.appleID, default: "")
        authJob = try container.decodeIfPresent(IcloudJob.self, forKey: .authJob)
        downloadJob = try container.decodeIfPresent(IcloudJob.self, forKey: .downloadJob)
        activeJob = try container.decodeIfPresent(IcloudJob.self, forKey: .activeJob)
        settings = try container.mngValue(.settings, default: IcloudSettings())
    }

    private enum CodingKeys: String, CodingKey {
        case configured, authenticated, settings
        case appleID = "apple_id"
        case authJob = "auth_job"
        case downloadJob = "download_job"
        case activeJob = "active_job"
    }
}

public struct IcloudJobResponse: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let job: IcloudJob?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.mngValue(.ok, default: false)
        job = try container.decodeIfPresent(IcloudJob.self, forKey: .job)
    }

    private enum CodingKeys: String, CodingKey {
        case ok, job
    }
}

public struct IcloudMessageResponse: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let message: String

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.mngValue(.ok, default: false)
        message = try container.mngValue(.message, default: "")
    }

    private enum CodingKeys: String, CodingKey {
        case ok, message
    }
}

public struct IcloudSaveResponse: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let settings: IcloudSettings

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.mngValue(.ok, default: false)
        settings = try container.mngValue(.settings, default: IcloudSettings())
    }

    private enum CodingKeys: String, CodingKey {
        case ok, settings
    }
}

public struct IcloudLogoutResponse: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let removed: Int64

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.mngValue(.ok, default: false)
        removed = try container.mngValue(.removed, default: 0)
    }

    private enum CodingKeys: String, CodingKey {
        case ok, removed
    }
}
