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

    /// Set or clear one item's favorite flag. Always sent with the CSRF header.
    public func favorite(id: Int64, value: Bool) async throws -> FavoriteResponse {
        guard id > 0 else {
            throw APIError(status: 404, code: "not_found", message: "Mục không tồn tại.")
        }
        let body = try encode(FavoriteBody(value: value))
        let request = try makeRequest(
            method: .post,
            path: "/v1/items/\(id)/favorite",
            body: body,
            csrf: true
        )
        return try await perform(request)
    }

    /// Delete one item. Live Photo companions are handled by the server.
    public func deleteItem(id: Int64) async throws -> DeleteResponse {
        guard id > 0 else {
            throw APIError(status: 404, code: "not_found", message: "Mục không tồn tại.")
        }
        let request = try makeRequest(
            method: .post,
            path: "/v1/items/\(id)/delete",
            csrf: true
        )
        return try await perform(request)
    }

    /// Download an authenticated media path, used by thumbnails and previews.
    public func mediaData(path: String) async throws -> Data {
        guard path.hasPrefix("/"), !path.hasPrefix("//") else {
            throw APIError.invalid(status: 0)
        }
        var request = URLRequest(url: try server.originURL(path: path))
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalid(status: 0)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw apiError(data: data, status: http.statusCode)
        }
        return data
    }

    /// Download one item's media file (photo, video or Live Photo companion)
    /// to a temporary file for the share sheet.
    ///
    /// `suggestedName` is the tile's filename; the server's
    /// `Content-Disposition` is the fallback.
    public func mediaFile(path: String, suggestedName: String) async throws -> DownloadedFile {
        guard path.hasPrefix("/"), !path.hasPrefix("//") else {
            throw APIError.invalid(status: 0)
        }
        var request = URLRequest(url: try server.originURL(path: path))
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        let (location, response) = try await download(request)
        guard let http = response as? HTTPURLResponse else {
            try? FileManager.default.removeItem(at: location)
            throw APIError.invalid(status: 0)
        }
        guard (200..<300).contains(http.statusCode) else {
            let data = (try? Data(contentsOf: location)) ?? Data()
            try? FileManager.default.removeItem(at: location)
            throw apiError(data: data, status: http.statusCode)
        }

        let header = http.value(forHTTPHeaderField: "Content-Disposition")
            .flatMap(Self.filename(fromContentDisposition:))
        let filename = Self.safeFilename(suggestedName)
            ?? header
            ?? "MNG-Cloud"
        return try Self.stageDownload(location, filename: filename)
    }

    /// Stream a ZIP of the selected items to a temporary file.
    ///
    /// `/api/v1/items/zip` validates CSRF from the form body instead of the
    /// header (the PWA uses a native form so the browser can stream to disk).
    /// The limits mirror the server: 100 unique ids and 2 GiB.
    public func archive(ids: [Int64]) async throws -> DownloadedArchive {
        let unique = Array(Set(ids)).sorted()
        guard !unique.isEmpty else {
            throw APIError(
                status: 400,
                code: "no_items",
                message: "Chưa chọn mục nào."
            )
        }
        guard unique.count <= 100 else {
            throw APIError(
                status: 400,
                code: "too_many",
                message: "Tối đa 100 mục mỗi lần."
            )
        }

        let request = try makeArchiveRequest(ids: unique)
        let (location, response) = try await download(request)
        guard let http = response as? HTTPURLResponse else {
            try? FileManager.default.removeItem(at: location)
            throw APIError.invalid(status: 0)
        }
        guard (200..<300).contains(http.statusCode) else {
            let data = (try? Data(contentsOf: location)) ?? Data()
            try? FileManager.default.removeItem(at: location)
            throw apiError(data: data, status: http.statusCode)
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard contentType.lowercased().hasPrefix("application/zip") else {
            try? FileManager.default.removeItem(at: location)
            throw APIError.invalid(status: http.statusCode)
        }
        let filename = http.value(forHTTPHeaderField: "Content-Disposition")
            .flatMap(Self.filename(fromContentDisposition:))
            ?? "MNG-Cloud.zip"
        let named = (filename as NSString).pathExtension.isEmpty
            ? filename + ".zip"
            : filename
        return try Self.stageDownload(location, filename: named)
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

    private struct FavoriteBody: Encodable {
        let value: Bool
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

    /// The ZIP endpoint reads CSRF from the form body, so this request is built
    /// separately from the JSON helper.
    func makeArchiveRequest(ids: [Int64]) throws -> URLRequest {
        var fields = ["csrf=\(PercentEncoding.encode(csrfToken ?? ""))"]
        fields.append(contentsOf: ids.map { "ids=\($0)" })
        var request = URLRequest(url: try server.apiURL(path: "/v1/items/zip", query: APIQuery()))
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("application/zip", forHTTPHeaderField: "Accept")
        request.httpBody = Data(fields.joined(separator: "&").utf8)
        return request
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

    /// Move a completed URLSession download out of its ephemeral location before
    /// the completion handler returns. The final share-friendly name is applied
    /// by `stageDownload` once the response headers are available.
    private func download(_ request: URLRequest) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: request) { location, response, error in
                if error != nil {
                    continuation.resume(throwing: APIError.network())
                    return
                }
                guard let location, let response else {
                    continuation.resume(throwing: APIError.network())
                    return
                }
                let target = FileManager.default.temporaryDirectory
                    .appendingPathComponent("mng-\(UUID().uuidString).download")
                do {
                    try FileManager.default.moveItem(at: location, to: target)
                    continuation.resume(returning: (target, response))
                } catch {
                    continuation.resume(throwing: APIError.invalid(status: 0))
                }
            }
            task.resume()
        }
    }

    /// Move a downloaded temp file into its own share directory. Keeping the
    /// final filename as the last path component lets `UIActivityViewController`
    /// show the real name while every export remains uniquely addressable.
    private static func stageDownload(_ location: URL, filename: String) throws -> DownloadedFile {
        let manager = FileManager.default
        let clean = safeFilename(filename) ?? "MNG-Cloud"
        let directory = manager.temporaryDirectory
            .appendingPathComponent("mng-share", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appendingPathComponent(clean, isDirectory: false)
            try manager.moveItem(at: location, to: target)
            return DownloadedFile(url: target, filename: clean)
        } catch {
            try? manager.removeItem(at: location)
            throw APIError.invalid(status: 0)
        }
    }

    private static func safeFilename(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = (trimmed as NSString).lastPathComponent
        guard !safe.isEmpty, safe != ".", safe != ".." else { return nil }
        return safe
    }

    private static func filename(fromContentDisposition value: String) -> String? {
        guard let range = value.range(of: "filename=", options: .caseInsensitive) else {
            return nil
        }
        var name = String(value[range.upperBound...])
        if name.hasPrefix("\"") {
            name.removeFirst()
            if let end = name.firstIndex(of: "\"") {
                name = String(name[..<end])
            }
        } else if let end = name.firstIndex(of: ";") {
            name = String(name[..<end])
        }
        return safeFilename(name)
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
