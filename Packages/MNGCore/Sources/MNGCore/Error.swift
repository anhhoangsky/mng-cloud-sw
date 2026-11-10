import Foundation

/// Errors mirrored from `crates/mng-core/src/error.rs`.
///
/// The cases are stable because callers match on them to produce the exact
/// Vietnamese copy used by the web client.
public enum MNGError: Error, Equatable, Sendable {
    /// Unsupported Seafile encryption version.
    case unsupportedVersion(UInt32)

    /// A hex field could not be decoded. The associated value is the field
    /// name (`"magic"`, `"random_key"`, `"salt"`), never the value itself.
    case invalidHex(String)

    /// The library or vault password is wrong.
    case wrongPassword

    /// The encrypted library key is malformed.
    case invalidLibraryKey

    /// The ciphertext is empty, misaligned or fails its padding check.
    case invalidCiphertext

    /// Native vault data is malformed. The associated value is the field name.
    case invalidVault(String)

    /// A plaintext block exceeds the 8 MiB Seafile limit.
    case blockTooLarge(Int)

    /// Encryption version 3 requires a 32-byte salt.
    case invalidSalt

    /// A KDF or configuration parameter is invalid.
    case config(String)
}

extension MNGError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "unsupported Seafile encryption version: \(version)"
        case .invalidHex(let field):
            return "invalid hex value for \(field)"
        case .wrongPassword:
            return "wrong library password"
        case .invalidLibraryKey:
            return "the encrypted library key is invalid"
        case .invalidCiphertext:
            return "the ciphertext is invalid"
        case .invalidVault(let field):
            return "the native vault data is invalid: \(field)"
        case .blockTooLarge(let bytes):
            return "a block exceeds the 8 MiB limit: \(bytes) bytes"
        case .invalidSalt:
            return "encryption version 3 requires a 32-byte salt"
        case .config(let message):
            return "configuration error: \(message)"
        }
    }
}
