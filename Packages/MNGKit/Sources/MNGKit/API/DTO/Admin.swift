import Foundation

public struct AdminCloud: Decodable, Equatable, Sendable {
    public let cloud: String
    public let username: String
    public let baseURL: String
    public let root: String
    public let importPath: String
    public let provisioned: Bool
    public let hasSecret: Bool

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cloud = try container.mngValue(.cloud, default: "")
        username = try container.mngValue(.username, default: "")
        baseURL = try container.mngValue(.baseURL, default: "")
        root = try container.mngValue(.root, default: "")
        importPath = try container.mngValue(.importPath, default: "")
        provisioned = try container.mngValue(.provisioned, default: false)
        hasSecret = try container.mngValue(.hasSecret, default: false)
    }

    private enum CodingKeys: String, CodingKey {
        case cloud, username, root, provisioned
        case baseURL = "base_url"
        case importPath = "import_path"
        case hasSecret = "has_secret"
    }
}

public struct AdminUser: Decodable, Equatable, Sendable, Identifiable {
    public let id: Int64
    public let username: String
    public let displayName: String
    public let isAdmin: Bool
    public let active: Bool
    public let createdAt: Int64
    public let lastLoginAt: Int64
    public let icloudAppleID: String
    public let icloudAuthenticated: Bool
    public let total: Int64
    public let bytes: Int64
    public let counts: [String: CloudCounts]
    public let clouds: [AdminCloud]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.mngValue(.id, default: 0)
        username = try container.mngValue(.username, default: "")
        displayName = try container.mngValue(.displayName, default: "")
        isAdmin = try container.mngValue(.isAdmin, default: false)
        active = try container.mngValue(.active, default: false)
        createdAt = try container.mngValue(.createdAt, default: 0)
        lastLoginAt = try container.mngValue(.lastLoginAt, default: 0)
        icloudAppleID = try container.mngValue(.icloudAppleID, default: "")
        icloudAuthenticated = try container.mngValue(.icloudAuthenticated, default: false)
        total = try container.mngValue(.total, default: 0)
        bytes = try container.mngValue(.bytes, default: 0)
        counts = try container.mngValue(.counts, default: [:])
        clouds = try container.mngValue(.clouds, default: [])
    }

    private enum CodingKeys: String, CodingKey {
        case id, username, active, total, bytes, counts, clouds
        case displayName = "display_name"
        case isAdmin = "is_admin"
        case createdAt = "created_at"
        case lastLoginAt = "last_login_at"
        case icloudAppleID = "icloud_apple_id"
        case icloudAuthenticated = "icloud_authenticated"
    }
}

public struct AdminProvisionResult: Decodable, Equatable, Sendable {
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

public struct AdminUsersResponse: Decodable, Equatable, Sendable {
    public let users: [AdminUser]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        users = try container.mngValue(.users, default: [])
    }

    private enum CodingKeys: String, CodingKey {
        case users
    }
}

public struct AdminMutationResponse: Decodable, Equatable, Sendable {
    public let user: AdminUser?
    public let password: String?
    /// The password of the Seafile account, when the cloud was reprovisioned.
    public let cloudPassword: String?
    public let provision: [String: AdminProvisionResult]
    public let clouds: [String: AdminProvisionResult]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        user = try container.decodeIfPresent(AdminUser.self, forKey: .user)
        password = try container.decodeIfPresent(String.self, forKey: .password)
        cloudPassword = try container.decodeIfPresent(String.self, forKey: .cloudPassword)
        provision = try container.mngValue(.provision, default: [:])
        clouds = try container.mngValue(.clouds, default: [:])
    }

    private enum CodingKeys: String, CodingKey {
        case user, password, provision, clouds
        case cloudPassword = "cloud_password"
    }
}

public struct AdminScanResponse: Decodable, Equatable, Sendable {
    public let queued: Bool

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        queued = try container.mngValue(.queued, default: false)
    }

    private enum CodingKeys: String, CodingKey {
        case queued
    }
}

public struct PersonRenameResponse: Decodable, Equatable, Sendable {
    public let updated: Bool

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updated = try container.mngValue(.updated, default: false)
    }

    private enum CodingKeys: String, CodingKey {
        case updated
    }
}
