#if canImport(Darwin)
import Darwin
#endif

/// Best-effort zeroization helper. `memset_s` is not elided by the optimizer;
/// the fallback exists only for non-Apple toolchains.
enum Zeroization {
    static func wipe(_ base: UnsafeMutableRawPointer?, count: Int) {
        guard let base, count > 0 else { return }
        #if canImport(Darwin)
        _ = memset_s(base, count, 0, count)
        #else
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        for index in 0..<count {
            bytes[index] = 0
        }
        #endif
    }

    static func wipe(_ buffer: UnsafeMutableRawBufferPointer) {
        wipe(buffer.baseAddress, count: buffer.count)
    }

    static func wipe(_ bytes: inout [UInt8]) {
        bytes.withUnsafeMutableBufferPointer { buffer in
            wipe(UnsafeMutableRawBufferPointer(buffer))
        }
    }
}

/// Raw key material that is wiped when the last reference is released.
///
/// The wrapper deliberately does not conform to `Codable`, `CustomString-
/// Convertible` or `Equatable`, so accidental logging or archiving of key
/// material is harder. Callers that need bytes receive a copy via
/// `copyBytes()` and are responsible for wiping it.
public final class SecureBytes {
    private var storage: [UInt8]

    public init(count: Int) {
        precondition(count >= 0, "SecureBytes count must not be negative")
        storage = [UInt8](repeating: 0, count: count)
    }

    public init(_ bytes: [UInt8]) {
        storage = bytes
    }

    public var count: Int {
        storage.count
    }

    /// Copy the bytes out of the protected buffer. The caller owns the copy.
    public func copyBytes() -> [UInt8] {
        storage
    }

    public func withUnsafeBytes<Result>(
        _ body: (UnsafeRawBufferPointer) throws -> Result
    ) rethrows -> Result {
        try storage.withUnsafeBufferPointer { buffer in
            try body(UnsafeRawBufferPointer(buffer))
        }
    }

    public func withUnsafeMutableBytes<Result>(
        _ body: (UnsafeMutableRawBufferPointer) throws -> Result
    ) rethrows -> Result {
        try storage.withUnsafeMutableBufferPointer { buffer in
            try body(UnsafeMutableRawBufferPointer(buffer))
        }
    }

    /// Overwrite the buffer in place. Safe to call more than once.
    public func zeroize() {
        storage.withUnsafeMutableBufferPointer { buffer in
            Zeroization.wipe(UnsafeMutableRawBufferPointer(buffer))
        }
    }

    deinit {
        zeroize()
    }
}
