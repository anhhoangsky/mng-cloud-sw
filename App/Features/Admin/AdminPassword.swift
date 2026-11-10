import Foundation
import Security

/// Local password helper for the administration console.
///
/// The generated password is copied to the pasteboard by the admin, never sent
/// to the server in the clear beyond the create/reset request itself.
enum AdminPassword {
    /// A readable random password (16 characters, no ambiguous symbols).
    static func generate(length: Int = 16) -> String {
        let alphabet = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var output = ""
        var bytes = [UInt8](repeating: 0, count: length)
        let status = bytes.withUnsafeMutableBytes { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, buffer.count, base)
        }
        guard status == errSecSuccess else {
            // Fall back to the system generator when the crypto source fails.
            return String((0..<length).map { _ in alphabet.randomElement() ?? "a" })
        }
        for byte in bytes {
            output.append(alphabet[Int(byte) % alphabet.count])
        }
        return output
    }
}
