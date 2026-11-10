/// Lowercase hex encoding and strict decoding, matching the `hex` crate.
public enum Hex {
    private static let alphabet = Array("0123456789abcdef".utf8)

    public static func encode(_ bytes: [UInt8]) -> String {
        var output = [UInt8]()
        output.reserveCapacity(bytes.count * 2)

        for byte in bytes {
            output.append(alphabet[Int(byte >> 4)])
            output.append(alphabet[Int(byte & 0x0F)])
        }

        return String(decoding: output, as: UTF8.self)
    }

    public static func decode(_ value: String) throws -> [UInt8] {
        try decode(value, field: "hex")
    }

    /// Decode a hex string. `field` is used only to build the error case; it
    /// must never contain the value itself.
    public static func decode(_ value: String, field: String) throws -> [UInt8] {
        let bytes = Array(value.utf8)
        guard bytes.count.isMultiple(of: 2) else {
            throw MNGError.invalidHex(field)
        }

        var output = [UInt8]()
        output.reserveCapacity(bytes.count / 2)

        var index = 0
        while index < bytes.count {
            guard let high = nibble(bytes[index]),
                  let low = nibble(bytes[index + 1]) else {
                throw MNGError.invalidHex(field)
            }
            output.append((high << 4) | low)
            index += 2
        }

        return output
    }

    private static func nibble(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57:
            return byte - 48
        case 97...102:
            return byte - 97 + 10
        case 65...70:
            return byte - 65 + 10
        default:
            return nil
        }
    }
}
