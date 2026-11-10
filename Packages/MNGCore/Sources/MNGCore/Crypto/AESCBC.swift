import CommonCrypto
import Foundation

/// AES-256-CBC with PKCS#7 padding, matching the Rust `cbc` crate usage.
///
/// Padding is applied and validated here instead of using
/// `kCCOptionPKCS7Padding`: CommonCrypto's decrypt path can report success
/// without rejecting malformed padding, and this code must fail closed like
/// the Rust reader.
enum AESCBC {
    private static let keyBytes = 32
    private static let blockBytes = 16

    static func encrypt(
        key: SecureBytes,
        iv: SecureBytes,
        plaintext: [UInt8]
    ) throws -> [UInt8] {
        let padding = blockBytes - (plaintext.count % blockBytes)
        var padded = plaintext
        padded.append(contentsOf: repeatElement(UInt8(padding), count: padding))
        defer { Zeroization.wipe(&padded) }

        return try crypt(
            operation: CCOperation(kCCEncrypt),
            key: key,
            iv: iv,
            input: padded
        )
    }

    static func decrypt(
        key: SecureBytes,
        iv: SecureBytes,
        ciphertext: [UInt8]
    ) throws -> [UInt8] {
        guard !ciphertext.isEmpty,
              ciphertext.count.isMultiple(of: blockBytes) else {
            throw MNGError.invalidCiphertext
        }

        var plaintext = try crypt(
            operation: CCOperation(kCCDecrypt),
            key: key,
            iv: iv,
            input: ciphertext
        )
        defer { Zeroization.wipe(&plaintext) }

        // PKCS#7: the final byte is the pad length (1...16) and every padding
        // byte must repeat it. Reject anything else, including a zero pad.
        guard let last = plaintext.last else {
            throw MNGError.invalidCiphertext
        }
        let pad = Int(last)
        guard pad >= 1, pad <= blockBytes, pad <= plaintext.count else {
            throw MNGError.invalidCiphertext
        }
        for offset in 0..<pad where plaintext[plaintext.count - 1 - offset] != last {
            throw MNGError.invalidCiphertext
        }

        return Array(plaintext.dropLast(pad))
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

        var output = [UInt8](repeating: 0, count: input.count)
        var moved = 0

        let status: Int32 = key.withUnsafeBytes { keyBuffer in
            iv.withUnsafeBytes { ivBuffer in
                input.withUnsafeBufferPointer { inputBuffer in
                    output.withUnsafeMutableBufferPointer { outputBuffer in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(0),
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

        guard status == Int32(kCCSuccess), moved == input.count else {
            Zeroization.wipe(&output)
            throw MNGError.invalidCiphertext
        }

        return output
    }
}
