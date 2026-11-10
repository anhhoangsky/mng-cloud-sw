import Foundation

enum TestFixtureError: Error {
    case missing(String)
}

struct E2EEFixture: Decodable {
    struct V3: Decodable {
        let magicHex: String
        let randomKeyHex: String
        let contentKeyHex: String
        let contentIVHex: String
        let cipherHex: String
        let blockID: String

        enum CodingKeys: String, CodingKey {
            case magicHex = "magic_hex"
            case randomKeyHex = "random_key_hex"
            case contentKeyHex = "content_key_hex"
            case contentIVHex = "content_iv_hex"
            case cipherHex = "cipher_hex"
            case blockID = "block_id"
        }
    }

    let password: String
    let repoID: String
    let magicHex: String
    let randomKeyHex: String
    let saltV3Hex: String
    let contentKeyHex: String
    let contentIVHex: String
    let plainHex: String
    let cipherHex: String
    let blockID: String
    let emptyCipherHex: String
    let emptyBlockID: String
    let v3: V3

    enum CodingKeys: String, CodingKey {
        case password
        case repoID = "repo_id"
        case magicHex = "magic_hex"
        case randomKeyHex = "random_key_hex"
        case saltV3Hex = "salt_v3_hex"
        case contentKeyHex = "content_key_hex"
        case contentIVHex = "content_iv_hex"
        case plainHex = "plain_hex"
        case cipherHex = "cipher_hex"
        case blockID = "block_id"
        case emptyCipherHex = "empty_cipher_hex"
        case emptyBlockID = "empty_block_id"
        case v3
    }
}

struct VaultFixture: Decodable {
    let uid: String
    let password: String
    let saltBase64: String
    let iterations: Int64
    let verifierBase64: String
    let manifestBase64: String
    let manifestJSON: String
    let chunkAAD: String
    let chunkPlain: String
    let chunkBase64: String
    let thumbAAD: String
    let thumbPlain: String
    let thumbBase64: String

    enum CodingKeys: String, CodingKey {
        case uid
        case password
        case saltBase64 = "salt_b64"
        case iterations
        case verifierBase64 = "verifier_b64"
        case manifestBase64 = "manifest_b64"
        case manifestJSON = "manifest_json"
        case chunkAAD = "chunk_aad"
        case chunkPlain = "chunk_plain"
        case chunkBase64 = "chunk_b64"
        case thumbAAD = "thumb_aad"
        case thumbPlain = "thumb_plain"
        case thumbBase64 = "thumb_b64"
    }
}

enum TestFixtures {
    static func e2ee() throws -> E2EEFixture {
        try load("e2ee_kat")
    }

    static func vault() throws -> VaultFixture {
        try load("vault_kat")
    }

    private static func load<T: Decodable>(_ name: String) throws -> T {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures"
        ) else {
            throw TestFixtureError.missing("\(name).json")
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
