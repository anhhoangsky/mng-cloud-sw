import Foundation

/// One Seafile library exposed by `/e2ee/libraries`.
public struct E2eeLibrary: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let encrypted: Bool
    public let encVersion: Int64
    public let size: Int64
    public let mtime: Int64
    public let permission: String

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.mngValue(.id, default: "")
        name = try container.mngValue(.name, default: "")
        encrypted = try container.mngValue(.encrypted, default: false)
        encVersion = try container.mngValue(.encVersion, default: 0)
        size = try container.mngValue(.size, default: 0)
        mtime = try container.mngValue(.mtime, default: 0)
        permission = try container.mngValue(.permission, default: "")
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, encrypted, size, mtime, permission
        case encVersion = "enc_version"
    }
}

public struct E2eeLibrariesResponse: Decodable, Equatable, Sendable {
    public let libraries: [E2eeLibrary]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        libraries = try container.mngValue(.libraries, default: [])
    }

    private enum CodingKeys: String, CodingKey {
        case libraries
    }
}

/// One encrypted repository and the public unlock material.
public struct E2eeRepo: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let encrypted: Bool
    public let encVersion: Int64
    public let salt: String
    public let magic: String
    public let randomKey: String
    public let size: Int64
    public let mtime: Int64
    public let permission: String

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.mngValue(.id, default: "")
        name = try container.mngValue(.name, default: "")
        encrypted = try container.mngValue(.encrypted, default: false)
        encVersion = try container.mngValue(.encVersion, default: 0)
        salt = try container.mngValue(.salt, default: "")
        magic = try container.mngValue(.magic, default: "")
        randomKey = try container.mngValue(.randomKey, default: "")
        size = try container.mngValue(.size, default: 0)
        mtime = try container.mngValue(.mtime, default: 0)
        permission = try container.mngValue(.permission, default: "")
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, encrypted, salt, magic, size, mtime, permission
        case encVersion = "enc_version"
        case randomKey = "random_key"
    }
}

public struct E2eeRepoResponse: Decodable, Equatable, Sendable {
    public let repo: E2eeRepo

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        repo = try container.decode(E2eeRepo.self, forKey: .repo)
    }

    private enum CodingKeys: String, CodingKey {
        case repo
    }
}

public struct E2eeEntry: Decodable, Equatable, Sendable {
    public let kind: String
    public let name: String
    public let id: String
    public let size: Int64
    public let mtime: Int64
    public let permission: String

    public var isDirectory: Bool { kind == "dir" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.mngValue(.kind, default: "")
        name = try container.mngValue(.name, default: "")
        id = try container.mngValue(.id, default: "")
        size = try container.mngValue(.size, default: 0)
        mtime = try container.mngValue(.mtime, default: 0)
        permission = try container.mngValue(.permission, default: "")
    }

    private enum CodingKeys: String, CodingKey {
        case kind = "type"
        case name, id, size, mtime, permission
    }
}

public struct E2eeDirResponse: Decodable, Equatable, Sendable {
    public let path: String
    public let entries: [E2eeEntry]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.mngValue(.path, default: "")
        entries = try container.mngValue(.entries, default: [])
    }

    private enum CodingKeys: String, CodingKey {
        case path, entries
    }
}

public struct E2eeBlocksResponse: Decodable, Equatable, Sendable {
    public let path: String
    public let fileID: String
    public let blocks: [String]
    public let encrypted: Bool
    public let encVersion: Int64

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.mngValue(.path, default: "")
        fileID = try container.mngValue(.fileID, default: "")
        blocks = try container.mngValue(.blocks, default: [])
        encrypted = try container.mngValue(.encrypted, default: false)
        encVersion = try container.mngValue(.encVersion, default: 0)
    }

    private enum CodingKeys: String, CodingKey {
        case path, blocks, encrypted
        case fileID = "file_id"
        case encVersion = "enc_version"
    }
}

public struct E2eeLinkResponse: Decodable, Equatable, Sendable {
    public let url: String

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.mngValue(.url, default: "")
    }

    private enum CodingKeys: String, CodingKey {
        case url
    }
}
