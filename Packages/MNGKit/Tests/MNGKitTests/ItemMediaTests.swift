import XCTest
@testable import MNGKit

final class ItemMediaTests: XCTestCase {
    private func item(_ json: String) throws -> Item {
        try JSONDecoder().decode(Item.self, from: Data(json.utf8))
    }

    func testThumbnailPathMatchesPWAQueryRule() throws {
        let withServerPath = try item("""
        {"id":42,"thumb":"/api/v1/items/42/thumb?v=3"}
        """)
        XCTAssertEqual(
            withServerPath.thumbnailPath(size: 360),
            "/api/v1/items/42/thumb?v=3&size=360"
        )

        let withoutPath = try item(#"{"id":7}"#)
        XCTAssertEqual(
            withoutPath.thumbnailPath(size: 160),
            "/api/v1/items/7/thumb?v=3&size=160"
        )
        XCTAssertEqual(
            withoutPath.thumbnailPath(size: 0),
            "/api/v1/items/7/thumb?v=3&size=1"
        )
    }

    func testPreviewMediaAndDownloadFallbacks() throws {
        let bare = try item(#"{"id":9}"#)
        XCTAssertEqual(bare.previewPath, "/api/v1/items/9/preview?v=3")
        XCTAssertEqual(bare.mediaPath(), "/api/v1/items/9/media")
        XCTAssertEqual(bare.downloadPath, "/api/v1/items/9/media?download=1")

        let full = try item("""
        {
          "id": 9,
          "preview": "/api/v1/items/9/preview?token=a",
          "media": "/api/v1/items/9/media?token=b",
          "download": "/api/v1/items/9/media?token=c&download=1"
        }
        """)
        XCTAssertEqual(full.previewPath, "/api/v1/items/9/preview?token=a")
        XCTAssertEqual(full.mediaPath(), "/api/v1/items/9/media?token=b")
        XCTAssertEqual(
            full.mediaPath(live: true),
            "/api/v1/items/9/media?token=b&live=1"
        )
        XCTAssertEqual(
            full.downloadPath,
            "/api/v1/items/9/media?token=c&download=1"
        )
    }

    func testMissingThumbnailsFallBackToPreviewAndOriginal() throws {
        let photo = try item(#"{"id":9,"media_type":"photo"}"#)
        XCTAssertEqual(
            photo.thumbnailFallbackPaths,
            [
                "/api/v1/items/9/preview?v=3",
                "/api/v1/items/9/media",
            ]
        )

        let video = try item(#"{"id":10,"media_type":"video"}"#)
        XCTAssertTrue(video.thumbnailFallbackPaths.isEmpty)
    }

    func testMediaURLStaysOnOrigin() throws {
        let server = try XCTUnwrap(MNGServer(string: "https://cloud.example.com/mng-cloud/"))
        XCTAssertEqual(
            server.mediaURL("/api/v1/items/1/thumb?v=3&size=360")?.absoluteString,
            "https://cloud.example.com/api/v1/items/1/thumb?v=3&size=360"
        )
        XCTAssertNil(server.mediaURL("https://evil.example.com/x"))
        XCTAssertNil(server.mediaURL("//evil.example.com/x"))
        XCTAssertNil(server.mediaURL("api/v1/items/1/thumb"))
    }
}
