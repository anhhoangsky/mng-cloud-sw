/// Constant-time comparison helpers.
public enum ConstantTime {
    /// Equal-length byte comparison without early exit.
    public static func equals(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        // Lengths are public metadata, so an early return here does not leak
        // secret content.
        guard lhs.count == rhs.count else { return false }

        var difference: UInt8 = 0
        for index in 0..<lhs.count {
            difference |= lhs[index] ^ rhs[index]
        }
        return difference == 0
    }

    /// UTF-8 comparison, used for the vault verifier plaintext.
    public static func equals(_ lhs: String, _ rhs: String) -> Bool {
        equals(Array(lhs.utf8), Array(rhs.utf8))
    }
}
