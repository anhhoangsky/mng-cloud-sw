import Foundation

/// A validated `mngd` origin.
///
/// The native app stores a server origin (`https://cloud.example.com`) rather
/// than the PWA path. `mngd` always nests its JSON API under `/api/v1` at the
/// origin, independent of the SPA's `base_path` (`/mng-cloud` or `/app`).
public struct MNGServer: Hashable, Codable, CustomStringConvertible, @unchecked Sendable {
    /// Origin without a trailing slash and without a path.
    public let url: URL

    public init?(string: String) {
        guard case let .success(server) = MNGServer.parse(string) else {
            return nil
        }
        self = server
    }

    private init(validatedURL: URL) {
        self.url = validatedURL
    }

    /// Canonical origin for persistence and display.
    public var origin: String { url.absoluteString }

    /// `https://cloud.example.com/api/v1`.
    public var apiBaseURL: URL {
        url.appendingPathComponent("api", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
    }

    public var description: String { origin }

    /// Normalise user input the way the login screen expects.
    ///
    /// Accepted forms:
    /// - `cloud.example.com` (scheme defaults to HTTPS)
    /// - `https://cloud.example.com/`
    /// - `https://cloud.example.com/mng-cloud/` (path is discarded)
    ///
    /// HTTPS is mandatory for public hosts. Plain HTTP stays available for
    /// local development (`localhost`, `*.local`, loopback/private IPv4).
    public static func parse(_ raw: String) -> Result<MNGServer, MNGServerError> {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .failure(.empty)
        }

        if !text.contains("://") {
            text = "https://" + text
        }

        guard var components = URLComponents(string: text) else {
            return .failure(.invalid)
        }
        guard let scheme = components.scheme?.lowercased() else {
            return .failure(.invalid)
        }
        guard scheme == "http" || scheme == "https" else {
            return .failure(.unsupportedScheme)
        }
        guard let host = components.host, !host.isEmpty else {
            return .failure(.missingHost)
        }
        guard components.user == nil, components.password == nil else {
            return .failure(.credentials)
        }
        guard components.query == nil, components.fragment == nil else {
            return .failure(.invalid)
        }

        let lowerHost = host.lowercased()
        if scheme == "http" && !isLocalHost(lowerHost) {
            return .failure(.insecure)
        }

        // `mngd` serves `/api/v1` from the origin; a pasted SPA path must not
        // become part of the API base.
        components.path = ""
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil

        let urlHost: String
        if lowerHost.contains(":") && !lowerHost.hasPrefix("[") {
            urlHost = "[\(lowerHost)]"
        } else {
            urlHost = lowerHost
        }

        var origin = "\(scheme)://\(urlHost)"
        if let port = components.port,
           !(scheme == "https" && port == 443),
           !(scheme == "http" && port == 80) {
            origin += ":\(port)"
        }

        guard let url = URL(string: origin), url.host != nil else {
            return .failure(.invalid)
        }
        return .success(MNGServer(validatedURL: url))
    }

    /// Percent-encoded API URL. `path` starts with `/v1/...` and may already
    /// contain encoded segments; the query pairs are encoded with JS
    /// `encodeURIComponent` semantics.
    func apiURL(path: String, query: APIQuery) throws -> URL {
        // `mngd` always serves the JSON API under `/api/v1`, regardless of the
        // SPA `base_path`.
        var text = origin + "/api"
        if !path.hasPrefix("/") {
            text += "/"
        }
        text += path
        let encodedQuery = query.encoded
        if !encodedQuery.isEmpty {
            text += "?" + encodedQuery
        }
        guard let url = URL(string: text) else {
            throw APIError.invalid(status: 0)
        }
        return url
    }

    /// Origin-relative URL used by the Seafile one-shot block link relay.
    func originURL(path: String) throws -> URL {
        var text = origin
        if !path.hasPrefix("/") {
            text += "/"
        }
        text += path
        guard let url = URL(string: text) else {
            throw APIError.invalid(status: 0)
        }
        return url
    }

    private static func isLocalHost(_ host: String) -> Bool {
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if bare == "localhost" || bare == "127.0.0.1" || bare == "::1" {
            return true
        }
        if bare.hasSuffix(".local") {
            return true
        }
        return isPrivateIPv4(bare)
    }

    private static func isPrivateIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let octets = parts.map { Int($0) }
        guard octets.allSatisfy({ ($0 ?? -1) >= 0 && ($0 ?? 256) <= 255 }),
              let first = octets[0],
              let second = octets[1] else {
            return false
        }
        switch (first, second) {
        case (10, _), (127, _), (169, 254):
            return true
        case (172, 16...31):
            return true
        case (192, 168):
            return true
        default:
            return false
        }
    }
}

public enum MNGServerError: Error, Equatable, Sendable, LocalizedError {
    case empty
    case invalid
    case unsupportedScheme
    case missingHost
    case credentials
    case insecure

    public var message: String {
        switch self {
        case .empty:
            return APIMessages.serverRequired
        case .invalid:
            return "Địa chỉ máy chủ không hợp lệ."
        case .unsupportedScheme:
            return "Máy chủ phải dùng https."
        case .missingHost:
            return "Địa chỉ máy chủ không có tên miền."
        case .credentials:
            return "Địa chỉ máy chủ không được chứa tên đăng nhập."
        case .insecure:
            return "Máy chủ phải dùng HTTPS. Chỉ máy chủ nội bộ mới được dùng http."
        }
    }

    public var errorDescription: String? { message }
}

/// Query pairs in insertion order, matching the PWA's `ItemQuery::path()`.
struct APIQuery: Sendable {
    private(set) var pairs: [(String, String)] = []

    mutating func add(_ name: String, _ value: String?) {
        guard let value, !value.isEmpty else { return }
        pairs.append((name, value))
    }

    mutating func add(_ name: String, _ value: Int?) {
        guard let value else { return }
        pairs.append((name, String(value)))
    }

    mutating func add(_ name: String, _ value: Bool?) {
        guard let value else { return }
        pairs.append((name, value ? "true" : "false"))
    }

    mutating func add(_ name: String, _ value: Int64?) {
        guard let value else { return }
        pairs.append((name, String(value)))
    }

    var encoded: String {
        pairs.map { "\($0.0)=\(PercentEncoding.encode($0.1))" }
            .joined(separator: "&")
    }
}

enum PercentEncoding {
    private static let allowed = Array(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()".utf8
    )
    private static let hex = Array("0123456789ABCDEF".utf8)

    /// Equivalent to JavaScript `encodeURIComponent`, which the PWA uses for
    /// every dynamic query value and path segment.
    static func encode(_ value: String) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(value.utf8.count)
        for byte in value.utf8 {
            if allowed.contains(byte) {
                bytes.append(byte)
            } else {
                bytes.append(0x25) // '%'
                bytes.append(hex[Int(byte >> 4)])
                bytes.append(hex[Int(byte & 0x0F)])
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
