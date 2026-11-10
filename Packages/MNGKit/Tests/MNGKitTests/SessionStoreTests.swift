import XCTest
@testable import MNGKit

@MainActor
final class SessionStoreTests: XCTestCase {
    private let authJSON = """
    {
      "ok": true,
      "csrf": "csrf-session",
      "expires_at": 1760000000,
      "me": {
        "id": 7,
        "username": "alice",
        "display_name": "Alice Nguyen",
        "is_admin": false,
        "active": true,
        "icloud_apple_id": ""
      }
    }
    """

    nonisolated override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    nonisolated override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "MNGKitTests.SessionStore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeStore(defaults: UserDefaults) -> SessionStore {
        SessionStore(defaults: defaults) { server in
            MNGAPIClient(
                server: server,
                session: MockURLProtocol.makeSession()
            )
        }
    }

    func testFirstLaunchWithoutServerShowsLogin() async throws {
        let store = makeStore(defaults: try makeDefaults())
        await store.start()
        XCTAssertEqual(store.phase, .login)
        XCTAssertNil(store.session)
        XCTAssertNil(store.bootError)
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }

    func testStoredServerMeSuccessBecomesReady() async throws {
        let defaults = try makeDefaults()
        defaults.set("https://api.test", forKey: SessionStore.serverKey)
        let store = makeStore(defaults: defaults)
        MockURLProtocol.handler = MockURLProtocol.respondJSON(body: authJSON)

        await store.start()

        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.session?.csrf, "csrf-session")
        XCTAssertEqual(store.session?.me.username, "alice")
        XCTAssertEqual(store.serverText, "https://api.test")
    }

    func testMeUnauthorizedFallsBackToLogin() async throws {
        let defaults = try makeDefaults()
        defaults.set("https://api.test", forKey: SessionStore.serverKey)
        let store = makeStore(defaults: defaults)
        MockURLProtocol.handler = MockURLProtocol.respondJSON(
            status: 401,
            body: #"{"error":"auth_required","message":"Phiên đăng nhập đã hết hạn."}"#
        )

        await store.start()

        XCTAssertEqual(store.phase, .login)
        XCTAssertNil(store.session)
        XCTAssertNil(store.bootError)
    }

    func testMeFailureKeepsBootErrorAndRetryRecovers() async throws {
        let defaults = try makeDefaults()
        defaults.set("https://api.test", forKey: SessionStore.serverKey)
        let store = makeStore(defaults: defaults)
        MockURLProtocol.handler = MockURLProtocol.respondJSON(
            status: 500,
            body: #"{"error":"internal"}"#
        )

        await store.start()
        XCTAssertEqual(store.phase, .checking)
        XCTAssertEqual(
            store.bootError,
            "Không kiểm tra được phiên đăng nhập. Vui lòng thử lại."
        )

        MockURLProtocol.handler = MockURLProtocol.respondJSON(body: authJSON)
        await store.retry()
        XCTAssertEqual(store.phase, .ready)
        XCTAssertNil(store.bootError)
        XCTAssertEqual(store.session?.me.id, 7)
    }

    func testBootNetworkCopyMatchesPWA() async throws {
        let defaults = try makeDefaults()
        defaults.set("https://api.test", forKey: SessionStore.serverKey)
        let store = makeStore(defaults: defaults)
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }

        await store.start()
        XCTAssertEqual(store.phase, .checking)
        XCTAssertEqual(store.bootError, "Không kết nối được máy chủ.")
    }

    func testLoginValidatesServerThenCredentials() async throws {
        let store = makeStore(defaults: try makeDefaults())
        await store.start()
        XCTAssertEqual(store.phase, .login)

        await store.login()
        XCTAssertEqual(store.loginError, "Nhập địa chỉ máy chủ để tiếp tục.")
        XCTAssertEqual(store.loginErrorField, .server)

        store.serverText = "https://api.test"
        await store.login()
        XCTAssertEqual(store.loginError, "Nhập tên đăng nhập để tiếp tục.")
        XCTAssertEqual(store.loginErrorField, .username)

        store.username = "alice"
        await store.login()
        XCTAssertEqual(store.loginError, "Nhập mật khẩu để tiếp tục.")
        XCTAssertEqual(store.loginErrorField, .password)

        store.password = "secret"
        store.serverText = "ftp://api.test"
        await store.login()
        XCTAssertEqual(store.loginError, "Máy chủ phải dùng https.")
        XCTAssertEqual(store.loginErrorField, .server)
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }

    func testLoginSuccessPersistsNormalizedServerAndUsername() async throws {
        let defaults = try makeDefaults()
        let store = makeStore(defaults: defaults)
        await store.start()
        store.serverText = "api.test/mng-cloud/"
        store.username = "  alice  "
        store.password = "s3cret"
        MockURLProtocol.handler = MockURLProtocol.respondJSON(body: authJSON)

        await store.login()

        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.session?.me.username, "alice")
        XCTAssertEqual(store.password, "")
        XCTAssertFalse(store.isLoggingIn)
        XCTAssertEqual(store.serverText, "https://api.test")
        XCTAssertEqual(
            defaults.string(forKey: SessionStore.serverKey),
            "https://api.test"
        )
        XCTAssertEqual(defaults.string(forKey: SessionStore.usernameKey), "alice")
    }

    func testLoginRejectedUsesServerMessage() async throws {
        let defaults = try makeDefaults()
        let store = makeStore(defaults: defaults)
        await store.start()
        store.serverText = "https://api.test"
        store.username = "alice"
        store.password = "wrong"
        MockURLProtocol.handler = MockURLProtocol.respondJSON(
            status: 401,
            body: #"{"error":"bad_credentials","message":"Tên đăng nhập hoặc mật khẩu không đúng."}"#
        )

        await store.login()

        XCTAssertEqual(store.phase, .login)
        XCTAssertNil(store.session)
        XCTAssertEqual(
            store.loginError,
            "Tên đăng nhập hoặc mật khẩu không đúng."
        )
        XCTAssertFalse(store.isLoggingIn)
        XCTAssertNil(defaults.string(forKey: SessionStore.serverKey))
    }

    func testLoginNetworkFailureUsesLoginCopy() async throws {
        let store = makeStore(defaults: try makeDefaults())
        await store.start()
        store.serverText = "https://api.test"
        store.username = "alice"
        store.password = "secret"
        MockURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }

        await store.login()
        XCTAssertEqual(
            store.loginError,
            "Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại."
        )
    }

    func testLogoutSendsCSRFAndClearsSession() async throws {
        let defaults = try makeDefaults()
        defaults.set("https://api.test", forKey: SessionStore.serverKey)
        let store = makeStore(defaults: defaults)
        MockURLProtocol.handler = MockURLProtocol.respondJSON(body: authJSON)
        await store.start()
        XCTAssertEqual(store.phase, .ready)

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/auth/logout")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-CSRF-Token"), "csrf-session")
            return try MockURLProtocol.respondJSON(body: #"{"ok":true}"#)(request)
        }

        await store.logout()

        XCTAssertEqual(store.phase, .login)
        XCTAssertNil(store.session)
        XCTAssertFalse(store.isLoggingOut)
        XCTAssertEqual(defaults.string(forKey: SessionStore.usernameKey) ?? "alice", "alice")
    }

    func testLogoutFailureKeepsSessionAndShowsToastCopy() async throws {
        let defaults = try makeDefaults()
        defaults.set("https://api.test", forKey: SessionStore.serverKey)
        let store = makeStore(defaults: defaults)
        MockURLProtocol.handler = MockURLProtocol.respondJSON(body: authJSON)
        await store.start()

        MockURLProtocol.handler = MockURLProtocol.respondJSON(
            status: 500,
            body: #"{"error":"internal"}"#
        )
        await store.logout()

        XCTAssertEqual(store.phase, .ready)
        XCTAssertNotNil(store.session)
        XCTAssertEqual(store.logoutError, "Không đăng xuất được. Vui lòng thử lại.")
        XCTAssertFalse(store.isLoggingOut)

        store.clearLogoutError()
        XCTAssertNil(store.logoutError)
    }
}
