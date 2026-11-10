import XCTest
@testable import MNGKit

final class MNGServerTests: XCTestCase {
    func testBareHostDefaultsToHTTPS() throws {
        let server = try MNGServer.parse("cloud.example.com").get()
        XCTAssertEqual(server.origin, "https://cloud.example.com")
    }

    func testTrailingSlashAndPWAPathAreDiscarded() throws {
        let server = try MNGServer.parse("https://Cloud.Example.com/mng-cloud/").get()
        XCTAssertEqual(server.origin, "https://cloud.example.com")
    }

    func testNonDefaultPortIsKept() throws {
        let server = try MNGServer.parse("https://cloud.example.com:8443/").get()
        XCTAssertEqual(server.origin, "https://cloud.example.com:8443")
    }

    func testDefaultPortIsElided() throws {
        let server = try MNGServer.parse("https://cloud.example.com:443").get()
        XCTAssertEqual(server.origin, "https://cloud.example.com")
    }

    func testHTTPIsAllowedOnLocalDevelopmentHosts() throws {
        for raw in [
            "http://localhost:8080",
            "http://127.0.0.1:8080",
            "http://192.168.1.20:8080",
            "http://box.local",
            "http://[::1]:8080"
        ] {
            let server = try MNGServer.parse(raw).get()
            XCTAssertEqual(server.origin, raw, "should keep \(raw)")
        }
    }

    func testPublicHTTPIsRejected() {
        let result = MNGServer.parse("http://cloud.example.com")
        guard case .failure(let error) = result else {
            return XCTFail("public HTTP must be rejected")
        }
        XCTAssertEqual(error, .insecure)
        XCTAssertFalse(error.message.isEmpty)
    }

    func testEmptyAndMalformedInputsAreRejected() {
        XCTAssertEqual(MNGServer.parse("   ").failureValue, .empty)
        XCTAssertEqual(MNGServer.parse("ftp://cloud.example.com").failureValue, .unsupportedScheme)
        XCTAssertEqual(MNGServer.parse("https://").failureValue, .missingHost)
        XCTAssertEqual(
            MNGServer.parse("https://user:pass@cloud.example.com").failureValue,
            .credentials
        )
        XCTAssertEqual(
            MNGServer.parse("https://cloud.example.com?x=1").failureValue,
            .invalid
        )
    }

    func testAPIURLUsesOriginRootAndEncodesQuery() throws {
        let server = try MNGServer.parse("https://cloud.example.com/mng-cloud/").get()
        var query = APIQuery()
        query.add("q", "Hà Nội & more/đ")
        query.add("limit", 120)
        let url = try server.apiURL(path: "/v1/items", query: query)
        XCTAssertEqual(
            url.absoluteString,
            "https://cloud.example.com/api/v1/items?q=H%C3%A0%20N%E1%BB%99i%20%26%20more%2F%C4%91&limit=120"
        )
    }

    func testPercentEncodingMatchesEncodeURIComponent() {
        XCTAssertEqual(PercentEncoding.encode("a b&c/đ"), "a%20b%26c%2F%C4%91")
        XCTAssertEqual(PercentEncoding.encode("!*'()~-_.AZ09"), "!*'()~-_.AZ09")
        XCTAssertEqual(PercentEncoding.encode("%+?#"), "%25%2B%3F%23")
        XCTAssertEqual(PercentEncoding.encode("😀"), "%F0%9F%98%80")
    }
}

private extension Result {
    var failureValue: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
