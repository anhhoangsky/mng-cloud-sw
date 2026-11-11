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

    // MARK: - Settings actions

    /// Probe one cloud's WebDAV endpoint from the server.
    public func testCloud(_ key: String) async throws -> CloudTestResponse {
        let body = try encode(TestCloudBody(cloud: key))
        let request = try makeRequest(
            method: .post,
            path: "/v1/clouds/test",
            body: body,
            csrf: true
        )
        return try await perform(request)
    }

    /// Queue a full library scan (`cloud = "all"`), matching `scan_all`.
    public func scanAll() async throws -> QueuedResponse {
        let body = try encode(ScanBody(cloud: "all"))
        let request = try makeRequest(
            method: .post,
            path: "/v1/scans",
            body: body,
            csrf: true
        )
        return try await perform(request)
    }

    /// Queue a retry for items whose thumbnail state is failed.
    public func retryThumbs() async throws -> QueuedResponse {
        let request = try makeRequest(
            method: .post,
            path: "/v1/thumbs/retry",
            csrf: true
        )
        return try await perform(request)
    }

    /// Ask the server to delete its temporary downloads/cache.
    public func clearTmp() async throws -> TmpClearResponse {
        let request = try makeRequest(
            method: .post,
            path: "/v1/cache/tmp/clear",
            csrf: true
        )
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

    // MARK: - Media uploads

    /// `POST /api/v1/media/match`: exact `(taken_at, size)` dedupe pre-check.
    ///
    /// Returns `true` when the library already carries the same photo, so the
    /// caller can skip the transfer.
    public func mediaMatch(takenAt: Int64, size: Int64) async throws -> Bool {
        guard takenAt > 0, size > 0 else { return false }
        let body = try encode(MediaMatchBody(takenAt: takenAt, size: size))
        let request = try makeRequest(
            method: .post,
            path: "/v1/media/match",
            body: body,
            csrf: true
        )
        let response: MediaMatchResponse = try await perform(request)
        return response.matched
    }

    /// `POST /api/v1/media/upload`: one photo or video per request.
    ///
    /// The body is a multipart form with a single `file` part. The multipart
    /// envelope is written to a scratch file and the file itself is streamed
    /// from disk, so a large video never lands in memory as a whole.
    ///
    /// The server stores the file in the owner's library and indexes it. A
    /// `matched` answer means an identical object was already there and no
    /// transfer happened.
    public func mediaUpload(
        name: String,
        fileURL: URL,
        mime: String
    ) async throws -> MediaUploadResponse {
        let boundary = "----MNGUpload\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let body = try Self.multipartBody(
            boundary: boundary,
            name: name,
            fileURL: fileURL,
            mime: mime
        )
        defer { try? FileManager.default.removeItem(at: body) }

        var request = try makeRequest(method: .post, path: "/v1/media/upload", csrf: true)
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        let (payload, response) = try await upload(request, fromFile: body)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalid(status: 0)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw apiError(data: payload, status: http.statusCode)
        }
        do {
            return try decoder.decode(MediaUploadResponse.self, from: payload)
        } catch {
            throw APIError.invalid(status: http.statusCode)
        }
    }

    /// Build the request of a media upload without sending it.
    ///
    /// A background `URLSession` has to carry everything the server needs with
    /// the request: the system replays it long after the app was suspended,
    /// so the session cookie and the CSRF token travel in the headers instead
    /// of a cookie jar that is not there yet.
    ///
    /// The multipart envelope is written to a scratch file, because a
    /// background upload can only be sent from a file.
    public func mediaUploadRequest(
        name: String,
        fileURL: URL,
        mime: String
    ) async throws -> MediaUploadRequest {
        let boundary = "----MNGUpload\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let body = try multipartBody(
            boundary: boundary,
            name: name,
            fileURL: fileURL,
            mime: mime
        )
        var request = try makeRequest(method: .post, path: "/v1/media/upload", csrf: true)
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        if let cookie = sessionCookie(), let fields = HTTPCookie.requestHeaderFields(with: [cookie]),
           let header = fields["Cookie"] {
            request.setValue(header, forHTTPHeaderField: "Cookie")
        }
        return MediaUploadRequest(request: request, bodyFile: body)
    }

    /// The session cookie of the signed-in user.
    private func sessionCookie() -> HTTPCookie? {
        let url = server.url
        return cookieStorage.cookies(for: url)?.first {
            $0.name == "mng_session"
        }
    }

    /// Write the multipart envelope and the file into one scratch file.
    ///
    /// The scratch file lives in Application Support, not in the temporary
    /// directory: a background upload may only read it minutes later, and the
    /// system is free to purge the temporary directory while the app is not
    /// running. The caller removes it once the transfer is done.
    private func multipartBody(
        boundary: String,
        name: String,
        fileURL: URL,
        mime: String
    ) throws -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("mng-upload-body", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let target = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("multipart")
        _ = FileManager.default.createFile(atPath: target.path, contents: nil)
        guard let output = try? FileHandle(forWritingTo: target) else {
            throw APIError.invalid(status: 0)
        }
        defer { try? output.close() }

        let filename = safeFilename(name) ?? "upload"
        let header = "--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
            + "Content-Type: \(mime)\r\n\r\n"
        try output.write(contentsOf: Data(header.utf8))

        guard let input = try? FileHandle(forReadingFrom: fileURL) else {
            throw APIError.invalid(status: 0)
        }
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }

        try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
        return target
    }

    /// Upload an edited image back to the item as `multipart/form-data`.
    ///
    /// `mode` is `overwrite` (replace the original) or `copy` (keep the
    /// original and store the edit next to it).
    public func saveEdit(
        id: Int64,
        data: Data,
        filename: String,
        mime: String,
        mode: String
    ) async throws -> EditResponse {
        guard id > 0 else {
            throw APIError(status: 404, code: "not_found", message: "Ảnh không tồn tại.")
        }
        let boundary = "----MNGEdit\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let safeName = filename.replacingOccurrences(of: "\"", with: "")
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(
            Data(
                "Content-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\n"
                    .utf8
            )
        )
        body.append(Data("Content-Type: \(mime)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"mode\"\r\n\r\n".utf8))
        body.append(Data("\(mode)\r\n".utf8))
        body.append(Data("--\(boundary)--\r\n".utf8))

        var request = try makeRequest(
            method: .post,
            path: "/v1/items/\(id)/edit",
            csrf: true
        )
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body
        let response: EditResponse = try await perform(request)
        return response
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

    /// Rename or clear one face cluster. The PWA sends an empty name to
    /// restore the generated `Người {id}` label.
    public func renamePerson(id: Int64, name: String) async throws -> PersonRenameResponse {
        guard id > 0 else {
            throw APIError(status: 404, code: "not_found", message: "Người không tồn tại.")
        }
        let body = try encode(RenamePersonBody(name: name))
        let request = try makeRequest(
            method: .post,
            path: "/v1/people/\(id)/rename",
            body: body,
            csrf: true
        )
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

    /// Start the Apple ID login. The server answers with the auth job.
    public func icloudLogin(
        appleID: String,
        password: String
    ) async throws -> IcloudJobResponse {
        let body = try encode(
            IcloudLoginBody(appleID: appleID, password: password)
        )
        let request = try makeRequest(
            method: .post,
            path: "/v1/icloud/login",
            body: body,
            csrf: true
        )
        return try await perform(request)
    }

    /// Answer the two-factor prompt.
    public func icloudMFA(code: String) async throws -> IcloudMessageResponse {
        let body = try encode(IcloudMFABody(code: code))
        let request = try makeRequest(
            method: .post,
            path: "/v1/icloud/mfa",
            body: body,
            csrf: true
        )
        return try await perform(request)
    }

    /// Queue the import job.
    public func icloudStart(
        recent: Int64,
        deleteAfter: Bool
    ) async throws -> IcloudJobResponse {
        let body = try encode(
            IcloudStartBody(recent: recent, deleteAfter: deleteAfter)
        )
        let request = try makeRequest(
            method: .post,
            path: "/v1/icloud/start",
            body: body,
            csrf: true
        )
        return try await perform(request)
    }

    /// Store the importer settings (Apple ID, recent limit, delete-after).
    public func icloudSave(
        appleID: String,
        recent: Int64,
        deleteAfter: Bool
    ) async throws -> IcloudSaveResponse {
        let body = try encode(
            IcloudSaveBody(
                appleID: appleID,
                recent: recent,
                deleteAfter: deleteAfter
            )
        )
        let request = try makeRequest(
            method: .post,
            path: "/v1/icloud/save",
            body: body,
            csrf: true
        )
        return try await perform(request)
    }

    /// Pause, resume or cancel a running job.
    public func icloudControl(
        command: String,
        jobID: String
    ) async throws -> IcloudJobResponse {
        let body = try encode(IcloudControlBody(command: command, jobID: jobID))
        let request = try makeRequest(
            method: .post,
            path: "/v1/icloud/control",
            body: body,
            csrf: true
        )
        return try await perform(request)
    }

    /// Forget the stored Apple ID session on the server.
    public func icloudLogout() async throws -> IcloudLogoutResponse {
        let request = try makeRequest(
            method: .post,
            path: "/v1/icloud/logout",
            csrf: true
        )
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

    /// Create one native vault. Only the public KDF parameters, the encrypted
    /// verifier and the encrypted manifest leave the device.
    public func createNativeVault(
        uid: String,
        kdf: String,
        iterations: Int64,
        salt: String,
        verifier: String,
        manifest: String
    ) async throws -> NativeVault {
        let body = try encode(
            CreateVaultBody(
                uid: uid,
                kdf: kdf,
                iterations: iterations,
                salt: salt,
                verifier: verifier,
                manifest: manifest
            )
        )
        let request = try makeRequest(
            method: .post,
            path: "/v1/vaults",
            body: body,
            csrf: true
        )
        let response: NativeVaultResponse = try await perform(request)
        return response.vault
    }

    /// Compare-and-swap the encrypted manifest. A `409 {"error":"stale"}` means
    /// another session wrote first; the caller refetches and retries once.
    public func updateNativeManifest(
        id: Int64,
        manifest: String,
        prevSHA256: String,
        bytes: Int64
    ) async throws -> NativeVault {
        let body = try encode(
            UpdateManifestBody(
                manifest: manifest,
                prevSHA256: prevSHA256,
                bytes: bytes
            )
        )
        let request = try makeRequest(
            method: .put,
            path: "/v1/vaults/\(id)/manifest",
            body: body,
            csrf: true
        )
        let response: NativeVaultResponse = try await perform(request)
        return response.vault
    }

    /// Ask the server which of the given blocks it still has to receive.
    public func prepareNativeBlocks(id: Int64, blocks: [String]) async throws -> [String] {
        let body = try encode(PrepareBlocksBody(blocks: blocks))
        let request = try makeRequest(
            method: .post,
            path: "/v1/vaults/\(id)/blobs/prepare",
            body: body,
            csrf: true
        )
        let response: NativePrepareResponse = try await perform(request)
        return response.missing
    }

    /// Commit one opaque blob file after every block was uploaded.
    public func commitNativeFile(
        id: Int64,
        name: String,
        size: Int64,
        blocks: [String]
    ) async throws -> String {
        let body = try encode(
            CommitFileBody(name: name, size: size, blocks: blocks)
        )
        let request = try makeRequest(
            method: .post,
            path: "/v1/vaults/\(id)/files",
            body: body,
            csrf: true
        )
        let response: NativeCommitResponse = try await perform(request)
        return response.fileID
    }

    /// Remove one committed file from the vault's blob library.
    public func deleteNativeFile(id: Int64, name: String) async throws {
        let body = try encode(DeleteFileBody(name: name))
        let request = try makeRequest(
            method: .post,
            path: "/v1/vaults/\(id)/files/delete",
            body: body,
            csrf: true
        )
        let _: OkResponse = try await perform(request)
    }

    /// Delete one owner vault, including its ciphertext blobs.
    public func deleteNativeVault(id: Int64) async throws {
        let request = try makeRequest(
            method: .post,
            path: "/v1/vaults/\(id)/delete",
            csrf: true
        )
        let _: OkResponse = try await perform(request)
    }

    /// Rename one vault. The server stores the new name in the clear, exactly
    /// like the PWA.
    public func renameNativeVault(id: Int64, name: String) async throws -> NativeVault {
        let body = try encode(RenameVaultBody(name: name))
        let request = try makeRequest(
            method: .post,
            path: "/v1/vaults/\(id)/rename",
            body: body,
            csrf: true
        )
        let response: NativeVaultResponse = try await perform(request)
        return response.vault
    }

    /// Upload one encrypted block. The body is the raw `iv || ciphertext || tag`.
    public func uploadNativeBlock(id: Int64, block: String, data: Data) async throws {
        guard Self.isBlockID(block) else {
            throw APIError(
                status: 0,
                code: "invalid_blob",
                message: "Mã khối dữ liệu không hợp lệ."
            )
        }
        var request = try makeRequest(
            method: .put,
            path: "/v1/vaults/\(id)/blobs/\(block)",
            csrf: true
        )
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.httpBody = data
        let (payload, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.network()
        }
        guard (200..<300).contains(http.statusCode) else {
            throw apiError(data: payload, status: http.statusCode)
        }
    }

    /// Download the encrypted manifest (`iv || ciphertext || tag`).
    public func nativeManifestBytes(id: Int64) async throws -> Data {
        let request = try makeRequest(
            method: .get,
            path: "/v1/vaults/\(id)/manifest"
        )
        return try await performBinary(request)
    }

    /// Download one encrypted blob by its SHA-1 block id.
    public func nativeBlobBytes(id: Int64, blob: String) async throws -> Data {
        let request = try makeRequest(
            method: .get,
            path: "/v1/vaults/\(id)/blobs/\(blob)"
        )
        return try await performBinary(request)
    }

    /// Download one ciphertext block of a committed vault file.
    public func nativeFileBlockBytes(
        id: Int64,
        fileID: String,
        block: String
    ) async throws -> Data {
        let request = try makeRequest(
            method: .get,
            path: "/v1/vaults/\(id)/files/\(fileID)/blocks/\(block)"
        )
        return try await performBinary(request)
    }

    /// 40 lowercase hex characters, the Seafile block and file id shape.
    private static func isBlockID(_ value: String) -> Bool {
        value.count == 40 && value.allSatisfy { character in
            character.isHexDigit && !character.isUppercase
        }
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

    public func adminUser(id: Int64) async throws -> AdminUser {
        guard id > 0 else {
            throw APIError(status: 404, code: "not_found", message: "Người dùng không tồn tại.")
        }
        let request = try makeRequest(method: .get, path: "/v1/admin/users/\(id)")
        let response: AdminMutationResponse = try await perform(request)
        guard let user = response.user else {
            throw APIError.invalid(status: 0)
        }
        return user
    }

    /// Create a user and optionally provision the cloud accounts.
    public func createAdminUser(
        username: String,
        displayName: String,
        password: String,
        provision: Bool
    ) async throws -> AdminMutationResponse {
        let body = try encode(
            CreateAdminUserBody(
                username: username,
                displayName: displayName,
                password: password,
                provision: provision
            )
        )
        let request = try makeRequest(
            method: .post,
            path: "/v1/admin/users",
            body: body,
            csrf: true
        )
        return try await perform(request)
    }

    /// Reset a user's MNG Cloud password.
    public func resetAdminUserPassword(
        id: Int64,
        password: String
    ) async throws -> AdminMutationResponse {
        let body = try encode(AdminPasswordBody(id: id, password: password))
        let request = try makeRequest(
            method: .post,
            path: "/v1/admin/users/\(id)/password",
            body: body,
            csrf: true
        )
        return try await perform(request)
    }

    /// Re-provision the cloud accounts of a user with a new password.
    public func reprovisionAdminUser(
        id: Int64,
        password: String
    ) async throws -> AdminMutationResponse {
        let body = try encode(AdminPasswordBody(id: id, password: password))
        let request = try makeRequest(
            method: .post,
            path: "/v1/admin/users/\(id)/reprovision",
            body: body,
            csrf: true
        )
        return try await perform(request)
    }

    /// Update the display name, the active flag or the admin flag.
    public func updateAdminUser(
        id: Int64,
        displayName: String?,
        active: Bool?,
        isAdmin: Bool?
    ) async throws -> AdminMutationResponse {
        let body = try encode(
            UpdateAdminUserBody(
                id: id,
                displayName: displayName,
                active: active,
                isAdmin: isAdmin
            )
        )
        let request = try makeRequest(
            method: .post,
            path: "/v1/admin/users/\(id)/update",
            body: body,
            csrf: true
        )
        return try await perform(request)
    }

    /// Delete a user, optionally with the cloud data.
    public func deleteAdminUser(
        id: Int64,
        deleteCloudData: Bool
    ) async throws -> AdminMutationResponse {
        let body = try encode(
            DeleteAdminUserBody(id: id, deleteCloudData: deleteCloudData)
        )
        let request = try makeRequest(
            method: .post,
            path: "/v1/admin/users/\(id)/delete",
            body: body,
            csrf: true
        )
        return try await perform(request)
    }

    /// Queue a scan for one user's library.
    public func scanAdminUser(id: Int64) async throws -> AdminScanResponse {
        let body = try encode(AdminScanBody(id: id))
        let request = try makeRequest(
            method: .post,
            path: "/v1/admin/users/\(id)/scan",
            body: body,
            csrf: true
        )
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

    /// Body of `POST /api/v1/media/match`.
    private struct MediaMatchBody: Encodable {
        let takenAt: Int64
        let size: Int64

        enum CodingKeys: String, CodingKey {
            case takenAt = "taken_at"
            case size
        }
    }

    private struct RenamePersonBody: Encodable {
        let name: String
    }

    private struct TestCloudBody: Encodable {
        let cloud: String
    }

    private struct ScanBody: Encodable {
        let cloud: String
    }

    private struct CreateVaultBody: Encodable {
        let uid: String
        let kdf: String
        let iterations: Int64
        let salt: String
        let verifier: String
        let manifest: String
    }

    private struct UpdateManifestBody: Encodable {
        let manifest: String
        let prevSHA256: String
        let bytes: Int64

        enum CodingKeys: String, CodingKey {
            case manifest
            case prevSHA256 = "prev_sha256"
            case bytes
        }
    }

    private struct PrepareBlocksBody: Encodable {
        let blocks: [String]
    }

    private struct CommitFileBody: Encodable {
        let name: String
        let size: Int64
        let blocks: [String]
    }

    private struct DeleteFileBody: Encodable {
        let name: String
    }

    private struct RenameVaultBody: Encodable {
        let name: String
    }

    private struct CreateAdminUserBody: Encodable {
        let username: String
        let displayName: String
        let password: String
        let provision: Bool

        enum CodingKeys: String, CodingKey {
            case username, password, provision
            case displayName = "display_name"
        }
    }

    private struct AdminPasswordBody: Encodable {
        let id: Int64
        let password: String
    }

    private struct UpdateAdminUserBody: Encodable {
        let id: Int64
        let displayName: String?
        let active: Bool?
        let isAdmin: Bool?

        enum CodingKeys: String, CodingKey {
            case id, active
            case displayName = "display_name"
            case isAdmin = "is_admin"
        }
    }

    private struct DeleteAdminUserBody: Encodable {
        let id: Int64
        let deleteCloudData: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case deleteCloudData = "delete_cloud_data"
        }
    }

    private struct AdminScanBody: Encodable {
        let id: Int64
    }

    private struct IcloudLoginBody: Encodable {
        let appleID: String
        let password: String

        enum CodingKeys: String, CodingKey {
            case appleID = "apple_id"
            case password
        }
    }

    private struct IcloudMFABody: Encodable {
        let code: String
    }

    private struct IcloudStartBody: Encodable {
        let recent: Int64
        let deleteAfter: Bool

        enum CodingKeys: String, CodingKey {
            case recent
            case deleteAfter = "delete_after"
        }
    }

    private struct IcloudSaveBody: Encodable {
        let appleID: String
        let recent: Int64
        let deleteAfter: Bool

        enum CodingKeys: String, CodingKey {
            case recent
            case appleID = "apple_id"
            case deleteAfter = "delete_after"
        }
    }

    private struct IcloudControlBody: Encodable {
        let command: String
        let jobID: String

        enum CodingKeys: String, CodingKey {
            case command
            case jobID = "job_id"
        }
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

    /// Send a request whose body lives in a file. The body is streamed from
    /// disk, so an upload never has to be buffered in memory.
    private func upload(
        _ request: URLRequest,
        fromFile url: URL
    ) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.uploadTask(with: request, fromFile: url) { data, response, error in
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

    /// Binary routes answer with the raw bytes; the vault relays ciphertext
    /// blobs that are never JSON.
    private func performBinary(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalid(status: 0)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw apiError(data: data, status: http.statusCode)
        }
        return data
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
