#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Foundation
import XCTest
@testable import MNGKit

/// Deterministic URLProtocol used by the MNGKit tests. No real network traffic
/// ever leaves the test process.
final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var requests: [URLRequest] = []
    static var lastRequest: URLRequest? { requests.last }

    static func reset() {
        handler = nil
        requests = []
    }

    static func respondJSON(
        status: Int = 200,
        body: String,
        headers: [String: String]? = nil
    ) -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { request in
            let url = try XCTUnwrap(request.url)
            var allHeaders = ["Content-Type": "application/json"]
            headers?.forEach { allHeaders[$0.key] = $0.value }
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: url,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: allHeaders
                )
            )
            return (response, Data(body.utf8))
        }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpShouldSetCookies = true
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.requests.append(request)
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func testServer(_ raw: String = "https://api.test") -> MNGServer {
    guard let server = MNGServer(string: raw) else {
        preconditionFailure("test server must be valid: \(raw)")
    }
    return server
}

func makeClient(
    server raw: String = "https://api.test",
    cookieStorage: HTTPCookieStorage = .shared
) -> MNGAPIClient {
    MNGAPIClient(
        server: testServer(raw),
        session: MockURLProtocol.makeSession(),
        cookieStorage: cookieStorage
    )
}
