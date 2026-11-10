import Foundation

/// Cryptographically secure randomness.
public enum SecureRandom {
    /// Fill an array with bytes from the system CSPRNG.
    ///
    /// `SystemRandomNumberGenerator` is documented to be cryptographically
    /// secure on Apple platforms and is safe to use for AES-GCM nonces.
    public static func bytes(count: Int) -> [UInt8] {
        guard count > 0 else { return [] }

        var generator = SystemRandomNumberGenerator()
        var output = [UInt8]()
        output.reserveCapacity(count)

        for _ in 0..<count {
            output.append(UInt8.random(in: UInt8.min...UInt8.max, using: &generator))
        }

        return output
    }
}
