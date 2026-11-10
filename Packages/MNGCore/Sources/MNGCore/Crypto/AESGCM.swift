import CryptoKit
import Foundation

/// AES-256-GCM backed by CryptoKit.
///
/// Blobs use the same layout as the Rust implementation:
/// `nonce (12 bytes) || ciphertext || tag (16 bytes)`, which is exactly
/// CryptoKit's `SealedBox.combined` representation.
enum AESGCM {
    static let keyBytes = 32
    static let nonceBytes = 12

    static func seal(
        key: SecureBytes,
        nonce: [UInt8],
        aad: String,
        plaintext: [UInt8]
    ) throws -> [UInt8] {
        guard key.count == keyBytes else {
            throw MNGError.invalidVault("key")
        }
        guard nonce.count == nonceBytes else {
            throw MNGError.invalidVault("nonce")
        }

        do {
            let symmetricKey = SymmetricKey(data: Data(key.copyBytes()))
            let gcmNonce = try AES.GCM.Nonce(data: Data(nonce))
            let sealed = try AES.GCM.seal(
                Data(plaintext),
                using: symmetricKey,
                nonce: gcmNonce,
                authenticating: Data(aad.utf8)
            )
            guard let combined = sealed.combined else {
                throw MNGError.invalidVault("encrypt")
            }
            return [UInt8](combined)
        } catch let error as MNGError {
            throw error
        } catch {
            throw MNGError.invalidVault("encrypt")
        }
    }

    static func open(
        key: SecureBytes,
        aad: String,
        blob: [UInt8]
    ) throws -> SecureBytes {
        guard key.count == keyBytes else {
            throw MNGError.invalidVault("key")
        }

        do {
            let symmetricKey = SymmetricKey(data: Data(key.copyBytes()))
            let sealed = try AES.GCM.SealedBox(combined: Data(blob))
            let plaintext = try AES.GCM.open(
                sealed,
                using: symmetricKey,
                authenticating: Data(aad.utf8)
            )
            return SecureBytes([UInt8](plaintext))
        } catch {
            throw MNGError.invalidVault("ciphertext")
        }
    }
}
