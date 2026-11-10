import CryptoKit
import Foundation

/// Lowercase SHA-1 hex, the Seafile block identifier.
///
/// The vault stores every ciphertext chunk under the SHA-1 of its bytes, so
/// the client has to compute the same digest as the server.
public enum SHA1 {
    public static func hex(_ bytes: [UInt8]) -> String {
        let digest = Insecure.SHA1.hash(data: Data(bytes))
        return Hex.encode([UInt8](digest))
    }
}
