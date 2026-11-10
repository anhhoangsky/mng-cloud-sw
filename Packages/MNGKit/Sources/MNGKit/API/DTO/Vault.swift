import Foundation

/// One native `mng-vault/v1` library. The server stores only public KDF
/// parameters and ciphertext; passwords and derived keys never leave the app.
public struct NativeVault: Decodable, Equatable, Sendable, Identifiable {
    public let id: Int64
    public let uid: String
    public let name: String
    public let kdf: String
    public let salt: String
    public let iterations: Int64
    public let verifier: String
    public let bytes: Int64
    public let manifestSize: Int64
    public let manifestAt: Int64
    public let manifestSHA256: String
    public let manifestReady: Bool
    public let createdAt: Int64
    public let updatedAt: Int64

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.mngValue(.id, default: 0)
        uid = try container.mngValue(.uid, default: "")
        name = try container.mngValue(.name, default: "")
        kdf = try container.mngValue(.kdf, default: "")
        salt = try container.mngValue(.salt, default: "")
        iterations = try container.mngValue(.iterations, default: 0)
        verifier = try container.mngValue(.verifier, default: "")
        bytes = try container.mngValue(.bytes, default: 0)
        manifestSize = try container.mngValue(.manifestSize, default: 0)
        manifestAt = try container.mngValue(.manifestAt, default: 0)
        manifestSHA256 = try container.mngValue(.manifestSHA256, default: "")
        manifestReady = try container.mngValue(.manifestReady, default: false)
        createdAt = try container.mngValue(.createdAt, default: 0)
        updatedAt = try container.mngValue(.updatedAt, default: 0)
    }

    private enum CodingKeys: String, CodingKey {
        case id, uid, name, kdf, salt, iterations, verifier, bytes
        case manifestSize = "manifest_size"
        case manifestAt = "manifest_at"
        case manifestSHA256 = "manifest_sha256"
        case manifestReady = "manifest_ready"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Plan name for the vault metadata DTO.
public typealias VaultMeta = NativeVault

public struct NativeVaultsResponse: Decodable, Equatable, Sendable {
    public let vaults: [NativeVault]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vaults = try container.mngValue(.vaults, default: [])
    }

    private enum CodingKeys: String, CodingKey {
        case vaults
    }
}

public struct NativeVaultResponse: Decodable, Equatable, Sendable {
    public let vault: NativeVault

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vault = try container.decode(NativeVault.self, forKey: .vault)
    }

    private enum CodingKeys: String, CodingKey {
        case vault
    }
}
