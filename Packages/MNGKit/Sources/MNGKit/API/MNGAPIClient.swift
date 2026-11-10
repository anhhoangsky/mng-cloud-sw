#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Foundation

/// Typed client for the `mngd` `/api/v1` JSON API.
///
/// The session itself is the server-set `HttpOnly` cookie, persisted by
/// `HTTPCookieStorage`. The CSRF token lives in memory on this actor and is
/// attached to mutating requests.
public actor MNGAPIClient {
    /// Legacy PWA page size (`ui/src/api.rs::PAGE_SIZE`).
    public static let pageSize = ItemFilters.defaultLimit

    public private(set) var server: MNGServer
    public private(set) var csrfToken: String?

    private let session: URLSession
    private let cookieStorage: HTTPCookieStorage
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(
        server: MNGServer,
        session: URLSession? = nil,
        cookieStorage: HTTPCookieStorage = .shared
    ) {
        self.server = server
        self.cookieStorage = cookieStorage
        if let session {
            self.session = session
        } else {
            self.session = URLSession(
                configuration: MNGAPIClient.makeConfiguration(cookieStorage: cookieStorage)
            )
        }
    }

    private static func makeConfiguration(
        cookieStorage: HTTPCookieStorage
    ) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = cookieStorage
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        return configuration
    }

    /// Replace the base origin (used when the user edits the server field).
    public func update(server: MNGServer) {
        self.server = server
    }

    /// Store or clear the in-memory CSRF token.
    public func setCSRF(_ token: String?) {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        csrfToken = trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Auth

    public func me() async throws -> AuthResponse {
        let request = try makeRequest(method: .get, path: "/v1/auth/me")
        let response: AuthResponse = try await perform(request)
        remember(response.csrf)
        return response
    }

    public func login(username: String, password: String) async throws -> AuthResponse {
        let body = try encode(LoginBody(username: username, password: password))
        let request = try makeRequest(
            method: .post,
            path: "/v1/auth/login",
            body: body
        )
        let response: AuthResponse = try await perform(request)
        remember(response.csrf)
        return response
    }

    public func logout() async throws {
        let request = try makeRequest(
            method: .post,
            path: "/v1/auth/logout",
            csrf: true
        )
        let _: OkResponse = try await perform(request)
    }

    /// Clear every cookie for the configured host, matching the PWA's logout
    /// cleanup after the server expires the session cookie.
    public func clearSessionCookies() {
        let host = server.url.host?.lowercased() ?? ""
        guard !host.isEmpty else { return }
        for cookie in cookieStorage.cookies ?? [] {
            let domain = cookie.domain
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if host == domain || host.hasSuffix("." + domain) {
                cookieStorage.deleteCookie(cookie)
            }
        }
    }

    // MARK: - Bootstrap and counters

    public func bootstrap() async throws -> Bootstrap {
        let request = try makeRequest(method: .get, path: "/v1/bootstrap")
        let response: Bootstrap = try await perform(request)
        remember(response.csrf)
        return response
    }

    public func clouds() async throws -> CloudsResponse {
        let request = try makeRequest(method: .get, path: "/v1/clouds")
        return try await perform(request)
    }

    public func counts(cloud: String? = nil) async throws -> CountsResponse {
        var query = APIQuery()
        query.add("cloud", nonEmpty(cloud))
        let request = try makeRequest(method: .get, path: "/v1/counts", query: query)
        return try await perform(request)
    }

    public func stats() async throws -> Stats {
        let request = try makeRequest(method: .get, path: "/v1/stats")
        return try await perform(request)
    }

    // MARK: - Items

    public func items(_ filters: ItemFilters) async throws -> ItemsResponse {
        let request = try makeRequest(
            method: .get,
            path: "/v1/items",
            query: filters.query
        )
        return try await perform(request)
    }

    public func item(id: Int64) async throws -> ItemDetail {
        guard id > 0 else {
            throw APIError(status: 404, code: "not_found", message: "Mục không tồn tại.")
        }
        let request = try makeRequest(method: .get, path: "/v1/items/\(id)")
        return try await perform(request)
    }

    // MARK: - Albums, years and months

    public func albums(cloud: String? = nil) async throws -> AlbumsResponse {
        var query = APIQuery()
        query.add("cloud", nonEmpty(cloud))
        let request = try makeRequest(method: .get, path: "/v1/albums", query: query)
        return try await perform(request)
    }

    public func years(cloud: String? = nil) async throws -> YearsResponse {
        var query = APIQuery()
        query.add("cloud", nonEmpty(cloud))
        let request = try makeRequest(method: .get, path: "/v1/years", query: query)
        return try await perform(request)
    }

    public func months(cloud: String? = nil, year: Int? = nil) async throws -> MonthsResponse {
        var query = APIQuery()
        query.add("cloud", nonEmpty(cloud))
        query.add("year", year)
        let request = try makeRequest(method: .get, path: "/v1/months", query: query)
        return try await perform(request)
    }

    // MARK: - People, places, AI

    public func people() async throws -> PeopleResponse {
        let request = try makeRequest(method: .get, path: "/v1/people")
        return try await perform(request)
    }

    public func places() async throws -> PlacesResponse {
        let request = try makeRequest(method: .get, path: "/v1/places")
        return try await perform(request)
    }

    public func aiStatus() async throws -> AiStatus {
        let request = try makeRequest(method: .get, path: "/v1/ai/status")
        return try await perform(request)
    }

    /// The PWA always scans the whole library, like the legacy
    /// `openDuplicates()` which pins `cloud = 'all'`.
    public func duplicates() async throws -> DuplicatesResponse {
        let request = try makeRequest(method: .get, path: "/v1/duplicates")
        return try await perform(request)
    }

    // MARK: - iCloud importer

    public func icloudStatus() async throws -> IcloudStatus {
        let request = try makeRequest(method: .get, path: "/v1/icloud/status")
        return try await perform(request)
    }

    // MARK: - Native vaults

    public func nativeVaults() async throws -> NativeVaultsResponse {
        let request = try makeRequest(method: .get, path: "/v1/vaults")
        return try await perform(request)
    }

    public func nativeVault(id: Int64) async throws -> NativeVault {
        guard id > 0 else {
            throw APIError(status: 404, code: "not_found", message: "Kho không tồn tại.")
        }
        let request = try makeRequest(method: .get, path: "/v1/vaults/\(id)")
        let response: NativeVaultResponse = try await perform(request)
        return response.vault
    }

    // MARK: - Seafile encrypted libraries

    public func e2eeLibraries() async throws -> E2eeLibrariesResponse {
        let request = try makeRequest(method: .get, path: "/v1/e2ee/libraries")
        return try await perform(request)
    }

    public func e2eeRepo(id: String) async throws -> E2eeRepoResponse {
        let request = try makeRequest(
            method: .get,
            path: "/v1/e2ee/repos/\(PercentEncoding.encode(id))"
        )
        return try await perform(request)
    }

    public func e2eeDir(id: String, path: String) async throws -> E2eeDirResponse {
        var query = APIQuery()
        query.add("p", path)
        let request = try makeRequest(
            method: .get,
            path: "/v1/e2ee/repos/\(PercentEncoding.encode(id))/dir",
            query: query
        )
        return try await perform(request)
    }

    public func e2eeBlocks(id: String, path: String) async throws -> E2eeBlocksResponse {
        var query = APIQuery()
        query.add("p", path)
        let request = try makeRequest(
            method: .get,
            path: "/v1/e2ee/repos/\(PercentEncoding.encode(id))/blocks",
            query: query
        )
        return try await perform(request)
    }

    /// Resolve one ciphertext block URL and reject anything that is not a
    /// same-origin `/seafhttp/` link (ported from the PWA).
    public func e2eeBlockLink(
        repoID: String,
        fileID: String,
        blockID: String,
        path: String
    ) async throws -> String {
        var query = APIQuery()
        query.add("p", path)
        let request = try makeRequest(
            method: .get,
            path: "/v1/e2ee/repos/\(PercentEncoding.encode(repoID))"
                + "/files/\(PercentEncoding.encode(fileID))"
                + "/blocks/\(PercentEncoding.encode(blockID))/link",
            query: query
        )
        let response: E2eeLinkResponse = try await perform(request)
        let url = response.url.trimmingCharacters(in: .whitespacesAndNewlines)
        let pathPart: String
        if let question = url.firstIndex(of: "?") {
            pathPart = String(url[..<question])
        } else {
            pathPart = url
        }
        let hasBadSegment = pathPart
            .split(separator: "/", omittingEmptySubsequences: false)
            .contains { $0 == "." || $0 == ".." }
        let hasControl = url.unicodeScalars.contains { scalar in
            CharacterSet.controlCharacters.contains(scalar) || scalar == "\\"
        }
        guard url.hasPrefix("/seafhttp/"), !hasBadSegment, !hasControl else {
            throw APIError(
                status: 0,
                code: APIError.invalidResponseCode,
                message: "Máy chủ trả về liên kết khối không hợp lệ."
            )
        }
        return url
    }

    /// Download ciphertext from a validated one-shot Seafile link.
    public func e2eeBlockBytes(path: String) async throws -> Data {
        guard path.hasPrefix("/seafhttp/") else {
            throw APIError(
                status: 0,
                code: APIError.invalidResponseCode,
                message: "Máy chủ trả về liên kết khối không hợp lệ."
            )
        }
        var request = URLRequest(url: try server.originURL(path: path))
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.network()
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(
                status: http.statusCode,
                code: "block_fetch",
                message: "Không tải được khối dữ liệu (HTTP \(http.statusCode))."
            )
        }
        return data
    }

    // MARK: - Administration

    public func adminUsers() async throws -> AdminUsersResponse {
        let request = try makeRequest(method: .get, path: "/v1/admin/users")
        return try await perform(request)
    }

    // MARK: - Request plumbing

    private enum Method: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
    }

    private struct LoginBody: Encodable {
        let username: String
        let password: String
    }

    private struct OkResponse: Decodable {
        let ok: Bool

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            ok = try container.mngValue(.ok, default: false)
        }

        private enum CodingKeys: String, CodingKey {
            case ok
        }
    }

    private struct ErrorPayload: Decodable {
        let error: String
        let message: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            error = try container.mngValue(.error, default: "")
            message = try container.mngValue(.message, default: "")
        }

        private enum CodingKeys: String, CodingKey {
            case error, message
        }
    }

    private func remember(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            csrfToken = trimmed
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func makeRequest(
        method: Method,
        path: String,
        query: APIQuery = APIQuery(),
        body: Data? = nil,
        csrf: Bool = false
    ) throws -> URLRequest {
        let url = try server.apiURL(path: path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if csrf, let token = csrfToken {
            request.setValue(token, forHTTPHeaderField: "X-CSRF-Token")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func encode<Body: Encodable>(_ body: Body) throws -> Data {
        do {
            return try encoder.encode(body)
        } catch {
            throw APIError.invalid(status: 0)
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if error != nil {
                    continuation.resume(throwing: APIError.network())
                    return
                }
                guard let data, let response else {
                    continuation.resume(throwing: APIError.network())
                    return
                }
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalid(status: 0)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw apiError(data: data, status: http.statusCode)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.invalid(status: http.statusCode)
        }
    }

    /// Port of `ui/src/api.rs::error_of` plus the fallback strings used by the
    /// shared request helper.
    private func apiError(data: Data, status: Int) -> APIError {
        let payload = try? decoder.decode(ErrorPayload.self, from: data)
        let serverCode = payload?.error.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let serverMessage = payload?.message.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return APIError(
            status: status,
            code: serverCode.isEmpty ? "http_\(status)" : serverCode,
            message: serverMessage.isEmpty ? "Máy chủ trả về lỗi \(status)." : serverMessage
        )
    }
}
