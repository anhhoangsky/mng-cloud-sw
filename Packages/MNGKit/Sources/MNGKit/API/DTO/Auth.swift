import Foundation

/// Public identity returned by `/auth/login` and `/auth/me`.
public struct Me: Decodable, Equatable, Sendable {
    public let id: Int64
    public let username: String
    public let displayName: String?
    public let isAdmin: Bool
    public let icloudAppleID: String
    public let active: Bool
    public let createdAt: Int64
    public let lastLoginAt: Int64

    private enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case isAdmin = "is_admin"
        case icloudAppleID = "icloud_apple_id"
        case active
        case createdAt = "created_at"
        case lastLoginAt = "last_login_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        isAdmin = try container.mngValue(.isAdmin, default: false)
        icloudAppleID = try container.mngValue(.icloudAppleID, default: "")
        active = try container.mngValue(.active, default: true)
        createdAt = try container.mngValue(.createdAt, default: 0)
        lastLoginAt = try container.mngValue(.lastLoginAt, default: 0)
    }

    /// Human label used by the shell: `display_name` when set, else username.
    public var label: String {
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? username : name
    }
}

/// `/auth/login` and `/auth/me` payload.
public struct AuthResponse: Decodable, Equatable, Sendable {
    public let csrf: String
    public let expiresAt: Int64
    public let me: Me

    private enum CodingKeys: String, CodingKey {
        case csrf
        case expiresAt = "expires_at"
        case me
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        csrf = try container.mngValue(.csrf, default: "")
        expiresAt = try container.mngValue(.expiresAt, default: 0)
        me = try container.decode(Me.self, forKey: .me)
    }
}

/// In-memory session. The real session token is the HttpOnly cookie; only the
/// CSRF token and identity are kept by the app.
public struct Session: Equatable, Sendable {
    public let csrf: String
    public let me: Me

    public init(csrf: String, me: Me) {
        self.csrf = csrf
        self.me = me
    }

    public init(_ response: AuthResponse) {
        self.init(csrf: response.csrf, me: response.me)
    }
}
