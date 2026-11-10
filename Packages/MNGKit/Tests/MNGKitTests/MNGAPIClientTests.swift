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
