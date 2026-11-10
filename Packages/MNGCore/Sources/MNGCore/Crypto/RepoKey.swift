import CryptoKit
import Foundation

/// Seafile encrypted-library engine, ported byte-for-byte from
/// `crates/mng-core/src/crypto/e2ee.rs`.
///
/// The derived content key and IV are held in `SecureBytes`; debug output only
/// reports the salt length.
public struct RepoKey {
    /// Fixed salt used by Seafile encryption version 2.
    public static let fixedSalt: [UInt8] = [
        0xDA, 0x90, 0x45, 0xC3, 0x06, 0xC7, 0xCC, 0x26
    ]

    /// Seafile stores encrypted files in fixed 8 MiB plaintext blocks.
    public static let blockBytes = 8 * 1024 * 1024

    private static let keyBytes = 32
    private static let ivBytes = 16
    private static let saltV3Bytes = 32
    private static let aesBlockBytes = 16
    private static let pbkdf2Rounds: UInt32 = 1_000
    private static let ivRounds: UInt32 = 10

    private let key: SecureBytes
    private let iv: SecureBytes
    private let salt: SecureBytes

    private init(key: SecureBytes, iv: SecureBytes, salt: SecureBytes) {
        self.key = key
        self.iv = iv
        self.salt = salt
    }

    /// Verify the library password and derive the content key/IV.
    ///
    /// `saltHex` is ignored for version 2 and required for version 3.
    public static func unlock(
        encVersion: UInt32,
        repoID: String,
        password: String,
        magicHex: String,
        randomKeyHex: String,
        saltHex: String
    ) throws -> RepoKey {
        guard !repoID.isEmpty, !password.isEmpty else {
            throw MNGError.config("library id and password are required")
        }

        let saltMaterial = try salt(for: encVersion, saltHex: saltHex)
        var saltBytes = saltMaterial.copyBytes()
        defer { Zeroization.wipe(&saltBytes) }

        var passwordBytes = Array(password.utf8)
        defer { Zeroization.wipe(&passwordBytes) }

        let key = try PBKDF2.sha256(
            password: passwordBytes,
            salt: saltBytes,
            rounds: pbkdf2Rounds,
            length: keyBytes
        )

        var magicInput = Array(repoID.utf8)
        magicInput.append(contentsOf: passwordBytes)
        defer { Zeroization.wipe(&magicInput) }

        let computedMagic = try PBKDF2.sha256(
            password: magicInput,
            salt: saltBytes,
            rounds: pbkdf2Rounds,
            length: keyBytes
        )

        let expectedMagic = try Hex.decode(
            magicHex.trimmingCharacters(in: .whitespacesAndNewlines),
            field: "magic"
        )
        var computedMagicBytes = computedMagic.copyBytes()
        defer { Zeroization.wipe(&computedMagicBytes) }
        let magicMatches = expectedMagic.count == keyBytes
            && ConstantTime.equals(computedMagicBytes, expectedMagic)
        guard magicMatches else {
            throw MNGError.wrongPassword
        }

        var keyBytesForIV = key.copyBytes()
        defer { Zeroization.wipe(&keyBytesForIV) }
        let keyIV = try PBKDF2.sha256(
            password: keyBytesForIV,
            salt: saltBytes,
            rounds: ivRounds,
            length: ivBytes
        )

        let encryptedKey = try Hex.decode(
            randomKeyHex.trimmingCharacters(in: .whitespacesAndNewlines),
            field: "random_key"
        )
        guard !encryptedKey.isEmpty,
              encryptedKey.count.isMultiple(of: aesBlockBytes) else {
            throw MNGError.invalidLibraryKey
        }

        var secretBytes: [UInt8]
        do {
            secretBytes = try AESCBC.decrypt(
                key: key,
                iv: keyIV,
                ciphertext: encryptedKey
            )
        } catch {
            throw MNGError.invalidLibraryKey
        }
        guard secretBytes.count == keyBytes else {
            Zeroization.wipe(&secretBytes)
            throw MNGError.invalidLibraryKey
        }
        defer { Zeroization.wipe(&secretBytes) }

        let contentKey = try PBKDF2.sha256(
            password: secretBytes,
            salt: saltBytes,
            rounds: pbkdf2Rounds,
            length: keyBytes
        )

        var contentKeyBytes = contentKey.copyBytes()
        defer { Zeroization.wipe(&contentKeyBytes) }
        let contentIV = try PBKDF2.sha256(
            password: contentKeyBytes,
            salt: saltBytes,
            rounds: ivRounds,
            length: ivBytes
        )

        return RepoKey(key: contentKey, iv: contentIV, salt: saltMaterial)
    }

    /// Encrypt one plaintext block with PKCS#7 padding.
    public func encryptBlock(_ plaintext: [UInt8]) throws -> [UInt8] {
        guard plaintext.count <= Self.blockBytes else {
            throw MNGError.blockTooLarge(plaintext.count)
        }
        return try AESCBC.encrypt(key: key, iv: iv, plaintext: plaintext)
    }

    /// Decrypt one ciphertext block and validate the padding.
    public func decryptBlock(_ ciphertext: [UInt8]) throws -> [UInt8] {
        guard !ciphertext.isEmpty,
              ciphertext.count.isMultiple(of: Self.aesBlockBytes),
              ciphertext.count <= Self.blockBytes + Self.aesBlockBytes else {
            throw MNGError.invalidCiphertext
        }

        let plaintext: [UInt8]
        do {
            plaintext = try AESCBC.decrypt(key: key, iv: iv, ciphertext: ciphertext)
        } catch {
            throw MNGError.invalidCiphertext
        }

        guard plaintext.count <= Self.blockBytes else {
            throw MNGError.invalidCiphertext
        }
        return plaintext
    }

    /// Ciphertext length for a given plaintext length, including padding.
    public static func ciphertextLen(_ plaintextLength: Int) -> Int {
        plaintextLength + aesBlockBytes - (plaintextLength % aesBlockBytes)
    }

    /// SHA-1 of the ciphertext, the block identifier used by Seafile.
    public static func blockID(ciphertext: [UInt8]) -> String {
        let digest = Insecure.SHA1.hash(data: Data(ciphertext))
        return Hex.encode([UInt8](digest))
    }

    // MARK: - Test hooks

    /// Internal only: KAT tests compare the derived key with the Rust vector.
    var contentKeyBytesForTesting: [UInt8] {
        key.copyBytes()
    }

    /// Internal only: KAT tests compare the derived IV with the Rust vector.
    var contentIVBytesForTesting: [UInt8] {
        iv.copyBytes()
    }

    // MARK: - Private

    private static func salt(for version: UInt32, saltHex: String) throws -> SecureBytes {
        switch version {
        case 2:
            return SecureBytes(fixedSalt)
        case 3:
            let decoded = try Hex.decode(
                saltHex.trimmingCharacters(in: .whitespacesAndNewlines),
                field: "salt"
            )
            guard decoded.count == saltV3Bytes else {
                throw MNGError.invalidSalt
            }
            return SecureBytes(decoded)
        default:
            throw MNGError.unsupportedVersion(version)
        }
    }
}

extension RepoKey: CustomDebugStringConvertible {
    public var debugDescription: String {
        "RepoKey(salt_len: \(salt.count))"
    }
}
