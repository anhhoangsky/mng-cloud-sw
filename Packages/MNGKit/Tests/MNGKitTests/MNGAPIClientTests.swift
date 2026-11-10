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

    func testSettingsActionsSendCSRFAndDecodeResponses() async throws {
        let client = makeClient()
        await client.setCSRF("csrf-settings")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "X-CSRF-Token"),
                "csrf-settings"
            )
            switch request.url?.path ?? "" {
            case "/api/v1/clouds/test":
                let body = try XCTUnwrap(request.capturedBody)
                let object = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: body) as? [String: String]
                )
                XCTAssertEqual(object["cloud"], "seafile")
                return try MockURLProtocol.respondJSON(
                    body: #"{"ok":true,"ms":42,"message":""}"#
                )(request)
            case "/api/v1/scans":
                let body = try XCTUnwrap(request.capturedBody)
                let object = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: body) as? [String: String]
                )
                XCTAssertEqual(object["cloud"], "all")
                return try MockURLProtocol.respondJSON(body: #"{"queued":true}"#)(request)
            case "/api/v1/thumbs/retry":
                return try MockURLProtocol.respondJSON(body: #"{"queued":false}"#)(request)
            case "/api/v1/cache/tmp/clear":
                return try MockURLProtocol.respondJSON(body: #"{"removed":12}"#)(request)
            default:
                XCTFail("unexpected path \(request.url?.path ?? "nil")")
                return try MockURLProtocol.respondJSON(body: #"{}"#)(request)
            }
        }

        let cloud = try await client.testCloud("seafile")
        XCTAssertTrue(cloud.ok)
        XCTAssertEqual(cloud.ms, 42)

        let scan = try await client.scanAll()
        XCTAssertTrue(scan.queued)

        let thumbs = try await client.retryThumbs()
        XCTAssertFalse(thumbs.queued)

        let tmp = try await client.clearTmp()
        XCTAssertEqual(tmp.removed, 12)
        XCTAssertEqual(MockURLProtocol.requests.count, 4)
    }

    func testDuplicatesDecodesFlattenedItemsAndStats() async throws {
        let client = makeClient()
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/duplicates")
            return try MockURLProtocol.respondJSON(body: """
            {
              "groups": [{
                "items": [
                  {"id": 42, "name": "IMG_0042.HEIC", "width": 4032, "height": 3024,
                   "size": 1234, "distance": 3},
                  {"id": 43, "name": "IMG_0043.HEIC", "distance": 7}
                ],
                "similarity": 93,
                "date": 1650000000
              }],
              "stats": {"total": 10, "hashed": 7}
            }
            """)(request)
        }

        let response = try await client.duplicates()
        XCTAssertEqual(response.stats.total, 10)
        XCTAssertEqual(response.stats.hashed, 7)
        let group = try XCTUnwrap(response.groups.first)
        XCTAssertEqual(group.similarity, 93)
        XCTAssertEqual(group.items.count, 2)
        XCTAssertEqual(group.items[0].item.id, 42)
        XCTAssertEqual(group.items[0].distance, 3)
        XCTAssertEqual(group.items[1].item.name, "IMG_0043.HEIC")
    }

    func testSettingsActionErrorKeepsServerReason() {
        let serverError = APIError(
            status: 503,
            code: "queue_unavailable",
            message: "Hàng đợi tác vụ chưa được bật."
        )
        XCTAssertEqual(
            APIMessages.settingsAction(serverError, fallback: "Không xếp hàng được."),
            "Hàng đợi tác vụ chưa được bật."
        )
        let empty = APIError(status: 500, code: "http_500", message: "  ")
        XCTAssertEqual(
            APIMessages.settingsAction(empty, fallback: "Không xếp hàng được."),
            "Không xếp hàng được."
        )
        XCTAssertEqual(
            APIMessages.settingsAction(.network(), fallback: "Không xếp hàng được."),
            "Không kết nối được máy chủ."
        )
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

    func testSaveEditSendsMultipartWithCSRF() async throws {
        let client = makeClient()
        await client.setCSRF("csrf-edit")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/items/42/edit")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "X-CSRF-Token"),
                "csrf-edit"
            )
            let contentType = try XCTUnwrap(
                request.value(forHTTPHeaderField: "Content-Type")
            )
            XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
            let body = String(decoding: try XCTUnwrap(request.capturedBody), as: UTF8.self)
            XCTAssertTrue(body.contains("name=\"file\"; filename=\"edit.jpg\""))
            XCTAssertTrue(body.contains("Content-Type: image/jpeg"))
            XCTAssertTrue(body.contains("name=\"mode\""))
            XCTAssertTrue(body.contains("overwrite"))
            return try MockURLProtocol.respondJSON(
                body: #"{"ok":true,"mode":"overwrite","id":42,"message":"Đã lưu ảnh."}"#
            )(request)
        }

        let response = try await client.saveEdit(
            id: 42,
            data: Data([0x01, 0x02]),
            filename: "edit.jpg",
            mime: "image/jpeg",
            mode: "overwrite"
        )
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.id, 42)
        XCTAssertEqual(response.mode, "overwrite")
    }

    func testVaultRoutesSendCSRFAndDecodeResponses() async throws {
        let client = makeClient()
        await client.setCSRF("csrf-vault")
        let vaultJSON = """
        {
          "id": 7,
          "uid": "00112233445566778899aabbccddeeff",
          "name": "Kho gia đình",
          "kdf": "PBKDF2-SHA256",
          "salt": "c2FsdHNhbHRzYWx0c2FsdA==",
          "iterations": 310000,
          "verifier": "dmVyaWZpZXI=",
          "bytes": 4096,
          "manifest_size": 128,
          "manifest_at": 99,
          "manifest_sha256": "aabb",
          "manifest_ready": true,
          "created_at": 10,
          "updated_at": 20
        }
        """

        MockURLProtocol.handler = { request in
            let method = request.httpMethod ?? "GET"
            switch (method, request.url?.path ?? "") {
            case ("GET", "/api/v1/vaults"):
                return try MockURLProtocol.respondJSON(
                    body: #"{"vaults":[\#(vaultJSON)]}"#
                )(request)
            case ("GET", "/api/v1/vaults/7"):
                return try MockURLProtocol.respondJSON(
                    body: #"{"vault":\#(vaultJSON)}"#
                )(request)
            case ("POST", "/api/v1/vaults"):
                XCTAssertEqual(
                    request.value(forHTTPHeaderField: "X-CSRF-Token"),
                    "csrf-vault"
                )
                let body = try XCTUnwrap(request.capturedBody)
                let object = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: body) as? [String: Any]
                )
                XCTAssertEqual(object["kdf"] as? String, "PBKDF2-SHA256")
                XCTAssertEqual(object["iterations"] as? Int, 310000)
                return try MockURLProtocol.respondJSON(
                    body: #"{"vault":\#(vaultJSON)}"#
                )(request)
            case ("PUT", "/api/v1/vaults/7/manifest"):
                let body = try XCTUnwrap(request.capturedBody)
                let object = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: body) as? [String: Any]
                )
                XCTAssertEqual(object["prev_sha256"] as? String, "aabb")
                XCTAssertEqual(object["bytes"] as? Int, 128)
                return try MockURLProtocol.respondJSON(
                    body: #"{"vault":\#(vaultJSON)}"#
                )(request)
            case ("POST", "/api/v1/vaults/7/blobs/prepare"):
                return try MockURLProtocol.respondJSON(
                    body: #"{"missing":["abc"]}"#
                )(request)
            case ("POST", "/api/v1/vaults/7/files"):
                return try MockURLProtocol.respondJSON(
                    body: #"{"file_id":"0123456789abcdef0123456789abcdef01234567"}"#
                )(request)
            case ("POST", "/api/v1/vaults/7/files/delete"):
                return try MockURLProtocol.respondJSON(body: #"{"ok":true}"#)(request)
            case ("POST", "/api/v1/vaults/7/delete"):
                return try MockURLProtocol.respondJSON(body: #"{"ok":true}"#)(request)
            case ("POST", "/api/v1/vaults/7/rename"):
                return try MockURLProtocol.respondJSON(
                    body: #"{"vault":\#(vaultJSON)}"#
                )(request)
            default:
                XCTFail("unexpected request \(method) \(request.url?.path ?? "nil")")
                return try MockURLProtocol.respondJSON(body: #"{}"#)(request)
            }
        }

        let list = try await client.nativeVaults()
        XCTAssertEqual(list.vaults.count, 1)
        XCTAssertEqual(list.vaults[0].id, 7)
        XCTAssertEqual(list.vaults[0].iterations, 310000)
        XCTAssertTrue(list.vaults[0].manifestReady)
        XCTAssertEqual(list.vaults[0].manifestSHA256, "aabb")

        let single = try await client.nativeVault(id: 7)
        XCTAssertEqual(single.name, "Kho gia đình")

        let created = try await client.createNativeVault(
            uid: "00112233445566778899aabbccddeeff",
            kdf: "PBKDF2-SHA256",
            iterations: 310000,
            salt: "c2FsdHNhbHRzYWx0c2FsdA==",
            verifier: "dmVyaWZpZXI=",
            manifest: "bWFuaWZlc3Q="
        )
        XCTAssertEqual(created.id, 7)

        let updated = try await client.updateNativeManifest(
            id: 7,
            manifest: "bWFuaWZlc3Q=",
            prevSHA256: "aabb",
            bytes: 128
        )
        XCTAssertEqual(updated.manifestSize, 128)

        let missing = try await client.prepareNativeBlocks(id: 7, blocks: ["abc"])
        XCTAssertEqual(missing, ["abc"])

        let fileID = try await client.commitNativeFile(
            id: 7,
            name: "f-1.bin",
            size: 12,
            blocks: ["abc"]
        )
        XCTAssertEqual(fileID, "0123456789abcdef0123456789abcdef01234567")

        try await client.deleteNativeFile(id: 7, name: "f-1.bin")
        try await client.deleteNativeVault(id: 7)
        _ = try await client.renameNativeVault(id: 7, name: "Kho mới")
    }

    func testVaultBinaryRoutesReturnRawBytes() async throws {
        let client = makeClient()
        MockURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/octet-stream"]
                )
            )
            return (response, Data([0x01, 0x02, 0x03]))
        }

        let manifest = try await client.nativeManifestBytes(id: 7)
        XCTAssertEqual(manifest, Data([0x01, 0x02, 0x03]))

        let blob = try await client.nativeBlobBytes(id: 7, blob: "abc")
        XCTAssertEqual(blob, Data([0x01, 0x02, 0x03]))

        let block = try await client.nativeFileBlockBytes(id: 7, fileID: "f", block: "abc")
        XCTAssertEqual(block, Data([0x01, 0x02, 0x03]))
    }

    func testUploadVaultBlockSendsOctetStreamAndRejectsBadID() async throws {
        let client = makeClient()
        await client.setCSRF("csrf-vault")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Content-Type"),
                "application/octet-stream"
            )
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "X-CSRF-Token"),
                "csrf-vault"
            )
            let body = try XCTUnwrap(request.capturedBody)
            XCTAssertEqual(body, Data([0x09, 0x08]))
            return try MockURLProtocol.respondJSON(body: #"{"ok":true}"#)(request)
        }

        let block = "0123456789abcdef0123456789abcdef01234567"
        try await client.uploadNativeBlock(id: 7, block: block, data: Data([0x09, 0x08]))

        do {
            try await client.uploadNativeBlock(id: 7, block: "nope", data: Data())
            XCTFail("expected an invalid block id error")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "invalid_blob")
        }
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
