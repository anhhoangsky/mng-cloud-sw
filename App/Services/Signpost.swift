import Foundation
import os

/// `os_signpost` helpers so the device profiling in Xcode shows where the
/// time goes (network, image decode, editor render).
enum Signpost {
    private static let api = OSSignposter(
        subsystem: "com.mngcloud.app",
        category: "network"
    )
    private static let decode = OSSignposter(
        subsystem: "com.mngcloud.app",
        category: "decode"
    )
    private static let render = OSSignposter(
        subsystem: "com.mngcloud.app",
        category: "render"
    )

    /// Measure one synchronous block of work.
    static func measure<T>(
        _ signposter: OSSignposter,
        _ name: StaticString,
        _ body: () throws -> T
    ) rethrows -> T {
        let sign = signposter.beginInterval(name)
        defer { signposter.endInterval(name, sign) }
        return try body()
    }

    static func api<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        try measure(api, name, body)
    }

    static func decode<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        try measure(decode, name, body)
    }

    static func render<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        try measure(render, name, body)
    }
}
