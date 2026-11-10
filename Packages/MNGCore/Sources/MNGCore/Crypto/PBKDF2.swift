import CommonCrypto
import Foundation

/// PBKDF2-HMAC-SHA256 backed by CommonCrypto.
public enum PBKDF2 {
    /// Derive `length` bytes. The returned buffer is zeroized on release.
    public static func sha256(
        password: [UInt8],
        salt: [UInt8],
        rounds: UInt32,
        length: Int
    ) throws -> SecureBytes {
        guard rounds > 0, length > 0 else {
            throw MNGError.config("invalid PBKDF2 parameters")
        }

        let output = SecureBytes(count: length)

        let status: Int32 = password.withUnsafeBufferPointer { passwordBuffer in
            salt.withUnsafeBufferPointer { saltBuffer in
                output.withUnsafeMutableBytes { outputBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.baseAddress.map {
                            UnsafeRawPointer($0).assumingMemoryBound(to: Int8.self)
                        },
                        password.count,
                        saltBuffer.baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        rounds,
                        outputBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        outputBuffer.count
                    )
                }
            }
        }

        guard status == Int32(kCCSuccess) else {
            output.zeroize()
            throw MNGError.config("PBKDF2 failed with status \(status)")
        }

        return output
    }
}
