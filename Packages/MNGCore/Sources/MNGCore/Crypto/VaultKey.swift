import Foundation

/// Password-derived AES-256-GCM key for one unlocked native vault
/// (`mng-vault/v1`), ported from `crates/mng-core/src/crypto/vault.rs`.
public struct VaultKey {
    /// Prefix shared by every additional-authenticated-data string.
    public static let version = "mng-vault/v1"

    /// Iteration count used by the legacy browser implementation.
    public static let iterations: Int64 = 310_000

    /// Native files are split into 4 MiB plaintext chunks.
    public static let chunkBytes = 4 * 1024 * 1024

    /// AES-GCM nonce length; stored as the first 12 bytes of every blob.
    public static let nonceBytes = 12

    private static let keyBytes = 32
    private static let tagBytes = 16
    private static let saltMinBytes = 16
    private static let saltMaxBytes = 64
    private static let maxIterations: Int64 = 2_000_000

    private let key: SecureBytes

    private init(key: SecureBytes) {
        self.key = key
    }

    /// Derive the vault key from a password and its stored base64 salt.
    ///
    /// The password is normalized to NFKC first, matching the legacy browser
    /// implementation and the Rust `unicode-normalization` call.
    public static func unlock(
        uid: String,
        password: String,
        saltBase64: String,
        iterations: Int64
    ) throws -> VaultKey {
        let uidBytes = Array(uid.utf8)
        guard uidBytes.count == 32, uidBytes.allSatisfy({ Self.isASCIIHex($0) }) else {
            throw MNGError.invalidVault("uid")
        }
        guard !password.isEmpty else {
            throw MNGError.invalidVault("password")
        }
        guard iterations >= 1, iterations <= maxIterations else {
            throw MNGError.invalidVault("iterations")
        }

        let salt = try decodeBase64(
            saltBase64,
            field: "salt",
            min: saltMinBytes,
            max: saltMaxBytes
        )
        var saltBytes = salt.copyBytes()
        defer { Zeroization.wipe(&saltBytes) }

        let normalized = password.precomposedStringWithCompatibilityMapping
        var passwordBytes = Array(normalized.utf8)
        defer { Zeroization.wipe(&passwordBytes) }

        let key = try PBKDF2.sha256(
            password: passwordBytes,
            salt: saltBytes,
            rounds: UInt32(iterations),
            length: keyBytes
        )

        return VaultKey(key: key)
    }

    /// Verify the stored verifier ciphertext. A wrong password or a tampered
    /// verifier both fail closed with `wrongPassword`.
    public func verify(uid: String, verifierBase64: String) throws {
        let verifier = try Self.decodeBase64(
            verifierBase64,
            field: "verifier",
            min: 16,
            max: 4096
        )

        let plaintext: SecureBytes
        do {
            plaintext = try decrypt(
                aad: Self.verifierAAD(uid: uid),
                data: verifier.copyBytes()
            )
        } catch {
            throw MNGError.wrongPassword
        }

        var actual = plaintext.copyBytes()
        defer { Zeroization.wipe(&actual) }
        guard ConstantTime.equals(actual, Array(Self.verifierText(uid: uid).utf8)) else {
            throw MNGError.wrongPassword
        }
    }

    /// Encrypt one blob with a caller-supplied nonce.
    ///
    /// Output layout: `nonce (12 bytes) || ciphertext || tag (16 bytes)`.
    /// Callers must use a fresh random nonce for every encryption under the
    /// same key.
    public func encrypt(
        aad: String,
        nonce: [UInt8],
        plaintext: [UInt8]
    ) throws -> [UInt8] {
        guard nonce.count == Self.nonceBytes else {
            throw MNGError.invalidVault("nonce")
        }
        return try AESGCM.seal(key: key, nonce: nonce, aad: aad, plaintext: plaintext)
    }

    /// Encrypt the manifest after binding it to this vault's uid.
    public func encryptManifest(
        uid: String,
        nonce: [UInt8],
        manifest: VaultManifest
    ) throws -> [UInt8] {
        guard manifest.uid == uid else {
            throw MNGError.invalidVault("manifest uid")
        }

        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(manifest)
        } catch {
            throw MNGError.invalidVault("manifest")
        }
        var plaintext = encoded
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }

        return try encrypt(
            aad: Self.manifestAAD(uid: uid),
            nonce: nonce,
            plaintext: [UInt8](plaintext)
        )
    }

    /// Decrypt one blob. The input layout is `nonce || ciphertext || tag`.
    public func decrypt(aad: String, data: [UInt8]) throws -> SecureBytes {
        // 12-byte nonce + at least one plaintext byte + 16-byte tag.
        guard data.count >= Self.nonceBytes + Self.tagBytes + 1 else {
            throw MNGError.invalidVault("ciphertext")
        }
        return try AESGCM.open(key: key, aad: aad, blob: data)
    }

    /// Decrypt and parse the manifest, checking that it belongs to `uid`.
    public func decryptManifest(uid: String, data: [UInt8]) throws -> VaultManifest {
        var plaintext = try decrypt(aad: Self.manifestAAD(uid: uid), data: data).copyBytes()
        defer { Zeroization.wipe(&plaintext) }

        var encoded = Data(plaintext)
        defer { encoded.resetBytes(in: 0..<encoded.count) }

        let manifest: VaultManifest
        do {
            manifest = try JSONDecoder().decode(VaultManifest.self, from: encoded)
        } catch {
            throw MNGError.invalidVault("manifest")
        }

        guard manifest.uid == uid else {
            throw MNGError.invalidVault("manifest uid")
        }
        return manifest
    }

    // MARK: - Chunk and thumbnail helpers

    public func encryptChunk(
        uid: String,
        fileID: String,
        index: Int,
        total: Int,
        nonce: [UInt8],
        plaintext: [UInt8]
    ) throws -> [UInt8] {
        try encrypt(
            aad: Self.chunkAAD(uid: uid, fileID: fileID, index: index, total: total),
            nonce: nonce,
            plaintext: plaintext
        )
    }

    public func decryptChunk(
        uid: String,
        fileID: String,
        index: Int,
        total: Int,
        data: [UInt8]
    ) throws -> SecureBytes {
        try decrypt(
            aad: Self.chunkAAD(uid: uid, fileID: fileID, index: index, total: total),
            data: data
        )
    }

    public func encryptThumb(
        uid: String,
        fileID: String,
        nonce: [UInt8],
        plaintext: [UInt8]
    ) throws -> [UInt8] {
        try encrypt(
            aad: Self.thumbAAD(uid: uid, fileID: fileID),
            nonce: nonce,
            plaintext: plaintext
        )
    }

    public func decryptThumb(
        uid: String,
        fileID: String,
        data: [UInt8]
    ) throws -> SecureBytes {
        try decrypt(
            aad: Self.thumbAAD(uid: uid, fileID: fileID),
            data: data
        )
    }

    // MARK: - AAD and format helpers

    public static func manifestAAD(uid: String) -> String {
        "\(version)/\(uid)/manifest"
    }

    public static func verifierAAD(uid: String) -> String {
        "\(version)/\(uid)/verifier"
    }

    public static func chunkAAD(uid: String, fileID: String, index: Int, total: Int) -> String {
        "\(version)/\(uid)/file/\(fileID)/chunk/\(index)/\(total)"
    }

    public static func thumbAAD(uid: String, fileID: String) -> String {
        "\(version)/\(uid)/file/\(fileID)/thumb"
    }

    public static func verifierText(uid: String) -> String {
        "mng-vault-verifier/v1/\(uid)"
    }

    /// Fresh random nonce for a new AES-GCM blob.
    public static func randomNonce() -> [UInt8] {
        SecureRandom.bytes(count: nonceBytes)
    }

    // MARK: - Private

    private static func decodeBase64(
        _ value: String,
        field: String,
        min: Int,
        max: Int
    ) throws -> SecureBytes {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: trimmed, options: []) else {
            throw MNGError.invalidVault(field)
        }
        guard data.count >= min, data.count <= max else {
            throw MNGError.invalidVault(field)
        }
        return SecureBytes([UInt8](data))
    }

    private static func isASCIIHex(_ byte: UInt8) -> Bool {
        switch byte {
        case 48...57, 65...70, 97...102:
            return true
        default:
            return false
        }
    }
}

extension VaultKey: CustomDebugStringConvertible {
    public var debugDescription: String {
        "VaultKey()"
    }
}
