import XCTest
@testable import MNGKit

final class MNGAPIClientTests: XCTestCase {
    private let authJSON = """
    {
      "ok": true,
      "csrf": "csrf-login",
      "expires_at": 1760000000,
      "me": {
        "id": 7,
        "username": "alice",
        "display_name": "Alice Nguyen",
        "is_admin": false,
        "active": true,
        "created_at": 1700000000,
        "last_login_at": 1750000000,
        "icloud_apple_id": "apple@example.com"
      }
    }
    """

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testLoginPostsJSONAndStoresCSRF() async throws {
        let client = makeClient()
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/auth/login")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-CSRF-Token"), nil)
            let body = try XCTUnwrap(request.capturedBody)
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: String]
            )
            XCTAssertEqual(object["username"], "alice")
            XCTAssertEqual(object["password"], "s3cret")
            return try MockURLProtocol.respondJSON(body: self.authJSON)(request)
        }

        let response = try await client.login(username: "alice", password: "s3cret")
        XCTAssertEqual(response.csrf, "csrf-login")
        XCTAssertEqual(response.me.id, 7)
        XCTAssertEqual(response.me.username, "alice")
        XCTAssertEqual(response.me.displayName, "Alice Nguyen")
        XCTAssertEqual(response.me.icloudAppleID, "apple@example.com")
        XCTAssertEqual(response.expiresAt, 1760000000)

        let stored = await client.csrfToken
        XCTAssertEqual(stored, "csrf-login")
    }

    func testMeRefreshesCSRFAndReportsUnauthorized() async throws {
        let client = makeClient()
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/auth/me")
            return try MockURLProtocol.respondJSON(body: self.authJSON)(request)
        }

        let response = try await client.me()
        XCTAssertEqual(response.me.label, "Alice Nguyen")
        let stored = await client.csrfToken
        XCTAssertEqual(stored, "csrf-login")

        MockURLProtocol.handler = MockURLProtocol.respondJSON(
            status: 401,
            body: #"{"error":"auth_required","login":true,"message":"Phiên đăng nhập đã hết hạn."}"#
        )
        do {
            _ = try await client.me()
            XCTFail("expected 401")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 401)
            XCTAssertEqual(error.code, "auth_required")
            XCTAssertEqual(error.message, "Phiên đăng nhập đã hết hạn.")
            XCTAssertTrue(error.isUnauthorized)
        }
    }

    func testLogoutSendsCSRFHeader() async throws {
        let client = makeClient()
        await client.setCSRF("csrf-logout")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/auth/logout")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-CSRF-Token"), "csrf-logout")
            return try MockURLProtocol.respondJSON(body: #"{"ok":true}"#)(request)
        }

        try await client.logout()
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
    }

    func testErrorPayloadUsesServerCodeAndMessage() async throws {
        let client = makeClient()
        MockURLProtocol.handler = MockURLProtocol.respondJSON(
            status: 401,
            body: #"{"error":"bad_credentials","message":"Tên đăng nhập hoặc mật khẩu không đúng."}"#
        )

        do {
            _ = try await client.login(username: "alice", password: "wrong")
            XCTFail("expected an error")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 401)
            XCTAssertEqual(error.code, "bad_credentials")
            XCTAssertEqual(error.message, "Tên đăng nhập hoặc mật khẩu không đúng.")
            XCTAssertEqual(APIMessages.login(error), "Tên đăng nhập hoặc mật khẩu không đúng.")
        }
    }

    func testErrorWithoutPayloadUsesHTTPFallback() async throws {
        let client = makeClient()
        MockURLProtocol.handler = MockURLProtocol.respondJSON(
            status: 500,
            body: #"{"detail":"boom"}"#
        )

        do {
            _ = try await client.me()
            XCTFail("expected an error")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 500)
            XCTAssertEqual(error.code, "http_500")
            XCTAssertEqual(error.message, "Máy chủ trả về lỗi 500.")
        }
    }

    func testMalformedSuccessBodyIsInvalidResponse() async throws {
        let client = makeClient()
        MockURLProtocol.handler = MockURLProtocol.respondJSON(
            body: #"{"ok":true}"#
        )

        do {
            _ = try await client.me()
            XCTFail("expected an error")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 200)
            XCTAssertEqual(error.code, "invalid_response")
            XCTAssertEqual(error.message, "Máy chủ trả về dữ liệu không hợp lệ.")
        }
    }

    func testNetworkFailureMapsToStatusZero() async throws {
        let client = makeClient()
        MockURLProtocol.handler = { _ in
            throw URLError(.timedOut)
        }

        do {
            _ = try await client.me()
            XCTFail("expected an error")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 0)
            XCTAssertEqual(error.code, "network")
            XCTAssertEqual(error.message, "Không kết nối được máy chủ.")
            XCTAssertTrue(error.isNetwork)
        }
    }

    func testItemsUsesPWAQueryOrder() async throws {
        let client = makeClient()
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/items")
            XCTAssertEqual(
                request.url?.query,
                "limit=120&offset=120&cloud=seafile&type=photo&album=person%3A7"
                    + "&year=2022&month=3&favorite=true&q=H%C3%A0%20N%E1%BB%99i"
            )
            return try MockURLProtocol.respondJSON(
                body: #"{"ok":true,"items":[],"total":0,"has_more":false}"#
            )(request)
        }
        var filters = ItemFilters(
            cloud: "seafile",
            kind: "photo",
            album: "person:7",
            year: 2022,
            month: 3,
            favorite: true,
            q: "Hà Nội"
        )
        filters.offset = 120
        let response = try await client.items(filters)
        XCTAssertTrue(response.items.isEmpty)
        XCTAssertFalse(response.hasMore)
    }

    func testDecodesItemPlaceAndLiveFields() async throws {
        let client = makeClient()
        MockURLProtocol.handler = MockURLProtocol.respondJSON(body: """
        {
          "ok": true,
          "items": [{
            "id": 42,
            "cloud": "seafile",
            "name": "IMG_0042.HEIC",
            "type": "photo",
            "mime": "image/heic",
            "size": 1234,
            "taken_at": 1650000000,
            "year": 2022,
            "month": 4,
            "day": 15,
            "width": 4032,
            "height": 3024,
            "live": true,
            "live_name": "IMG_0042.MOV",
            "favorite": true,
            "thumb": "/api/v1/items/42/thumb",
            "lat": 21.0285,
            "lng": 105.8542,
            "place": {
              "road": "Đường Lê Lợi",
              "ward": "Phường 1",
              "district": "Quận 1",
              "province": "Hồ Chí Minh",
              "display": "Đường Lê Lợi, Quận 1"
            }
          }],
          "total": 1,
          "has_more": true
        }
        """)

        let response = try await client.items(ItemFilters())
        let item = try XCTUnwrap(response.items.first)
        XCTAssertEqual(item.id, 42)
        XCTAssertEqual(item.mediaType, "photo")
        XCTAssertTrue(item.isPhoto)
        XCTAssertTrue(item.live)
        XCTAssertEqual(item.liveName, "IMG_0042.MOV")
        XCTAssertEqual(item.place.district, "Quận 1")
        XCTAssertEqual(item.lat, 21.0285, accuracy: 0.0001)
        XCTAssertTrue(response.hasMore)
    }

    func testFavoritePostsValueAndCSRFHeader() async throws {
        let client = makeClient()
        await client.setCSRF("csrf-fav")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/items/42/favorite")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-CSRF-Token"), "csrf-fav")
            let body = try XCTUnwrap(request.capturedBody)
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            XCTAssertEqual(object["value"] as? Bool, true)
            return try MockURLProtocol.respondJSON(body: #"{"ok":true,"favorite":true}"#)(request)
        }

        let response = try await client.favorite(id: 42, value: true)
        XCTAssertTrue(response.favorite)
    }

    func testDeletePostsWithCSRFHeader() async throws {
        let client = makeClient()
        await client.setCSRF("csrf-del")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/items/9/delete")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-CSRF-Token"), "csrf-del")
            return try MockURLProtocol.respondJSON(body: #"{"ok":true,"deleted":1}"#)(request)
        }

        let response = try await client.deleteItem(id: 9)
        XCTAssertEqual(response.deleted, 1)
    }

    func testMediaDataUsesOriginPathAndReturnsBytes() async throws {
        let client = makeClient()
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://api.test/api/v1/items/42/thumb?v=3&size=360"
            )
            return try MockURLProtocol.respondJSON(body: "image-bytes")(request)
        }

        let data = try await client.mediaData(path: "/api/v1/items/42/thumb?v=3&size=360")
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "image-bytes")

        do {
            _ = try await client.mediaData(path: "https://evil.example.com/x")
            XCTFail("expected an invalid path error")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "invalid_response")
        }
    }

    func testArchiveRequestSendsFormCSRFAndSortedIds() async throws {
        let client = makeClient()
        await client.setCSRF("csrf zip/+")
        let request = try await client.makeArchiveRequest(ids: [1, 2, 3])
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.test/api/v1/items/zip")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "application/x-www-form-urlencoded"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/zip")
        let body = String(decoding: try XCTUnwrap(request.capturedBody), as: UTF8.self)
        XCTAssertEqual(body, "csrf=csrf%20zip%2F%2B&ids=1&ids=2&ids=3")
    }

    func testMediaFileStagesDownloadWithSuggestedName() async throws {
        let client = makeClient()
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://api.test/api/v1/items/42/media?live=1"
            )
            return try MockURLProtocol.respondJSON(
                body: "movie-bytes",
                headers: ["Content-Type": "video/quicktime"]
            )(request)
        }

        let file = try await client.mediaFile(
            path: "/api/v1/items/42/media?live=1",
            suggestedName: "../evil.MOV"
        )
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }

        XCTAssertEqual(file.filename, "evil.MOV")
        XCTAssertEqual(file.url.lastPathComponent, "evil.MOV")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path))
        XCTAssertEqual(try Data(contentsOf: file.url), Data("movie-bytes".utf8))
    }

    func testArchiveStreamsDownloadAndUsesContentDispositionName() async throws {
        let client = makeClient()
        await client.setCSRF("csrf zip")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/items/zip")
            let body = String(decoding: try XCTUnwrap(request.capturedBody), as: UTF8.self)
            XCTAssertEqual(body, "csrf=csrf%20zip&ids=1&ids=2")
            let url = try XCTUnwrap(request.url)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Type": "application/zip",
                        "Content-Disposition": "attachment; filename=\"MNG-Cloud-2.zip\"",
                    ]
                )
            )
            return (response, Data([0x50, 0x4B]))
        }

        let archive = try await client.archive(ids: [2, 1, 1])
        defer { try? FileManager.default.removeItem(at: archive.url.deletingLastPathComponent()) }

        XCTAssertEqual(archive.filename, "MNG-Cloud-2.zip")
        XCTAssertEqual(archive.url.lastPathComponent, "MNG-Cloud-2.zip")
        XCTAssertEqual(try Data(contentsOf: archive.url), Data([0x50, 0x4B]))
    }

    func testClearSessionCookiesRemovesHostCookies() async throws {
        let storage = HTTPCookieStorage.shared
        for cookie in storage.cookies ?? [] where cookie.domain.contains("api.test") {
            storage.deleteCookie(cookie)
        }
        let cookie = try XCTUnwrap(
            HTTPCookie(properties: [
                .domain: "api.test",
                .path: "/",
                .name: "mng_session",
                .value: "abc",
                .secure: "TRUE"
            ])
        )
        storage.setCookie(cookie)
        XCTAssertFalse(
            (storage.cookies ?? []).filter { $0.domain.contains("api.test") }.isEmpty
        )

        let client = makeClient(cookieStorage: storage)
        await client.clearSessionCookies()

        XCTAssertTrue(
            (storage.cookies ?? []).filter { $0.domain.contains("api.test") }.isEmpty
        )
    }
}
