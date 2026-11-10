import CommonCrypto
import Foundation

/// AES-256-CBC with PKCS#7 padding, matching the Rust `cbc` crate usage.
enum AESCBC {
    private static let keyBytes = 32
    private static let blockBytes = 16

    static func encrypt(
        key: SecureBytes,
        iv: SecureBytes,
        plaintext: [UInt8]
    ) throws -> [UInt8] {
        try crypt(
            operation: CCOperation(kCCEncrypt),
            key: key,
            iv: iv,
            input: plaintext
        )
    }

    static func decrypt(
        key: SecureBytes,
        iv: SecureBytes,
        ciphertext: [UInt8]
    ) throws -> [UInt8] {
        try crypt(
            operation: CCOperation(kCCDecrypt),
            key: key,
            iv: iv,
            input: ciphertext
        )
    }

    private static func crypt(
        operation: CCOperation,
        key: SecureBytes,
        iv: SecureBytes,
        input: [UInt8]
    ) throws -> [UInt8] {
        guard key.count == keyBytes, iv.count == blockBytes else {
            throw MNGError.invalidCiphertext
        }

        // PKCS#7 always writes at least one byte and at most one full block.
        var output = [UInt8](repeating: 0, count: input.count + blockBytes)
        var moved = 0

        let status: Int32 = key.withUnsafeBytes { keyBuffer in
            iv.withUnsafeBytes { ivBuffer in
                input.withUnsafeBufferPointer { inputBuffer in
                    output.withUnsafeMutableBufferPointer { outputBuffer in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuffer.baseAddress,
                            keyBuffer.count,
                            ivBuffer.baseAddress,
                            UnsafeRawBufferPointer(inputBuffer).baseAddress,
                            inputBuffer.count,
                            UnsafeMutableRawBufferPointer(outputBuffer).baseAddress,
                            outputBuffer.count,
                            &moved
                        )
                    }
                }
            }
        }

        guard status == Int32(kCCSuccess), moved >= 0, moved <= output.count else {
            Zeroization.wipe(&output)
            throw MNGError.invalidCiphertext
        }

        let result = Array(output[..<moved])
        Zeroization.wipe(&output)
        return result
    }
}
