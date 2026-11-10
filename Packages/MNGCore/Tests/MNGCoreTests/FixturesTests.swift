import XCTest
@testable import MNGCore

/// Phase 0 only checks that the crypto vectors survived the copy. Phase 1
/// replaces these with the full known-answer tests.
final class FixturesTests: XCTestCase {
    func testE2EEVectorsLoad() throws {
        let json = try loadJSON("e2ee_kat")
        XCTAssertEqual(json["password"] as? String, "correct horse battery staple")
        XCTAssertEqual(json["block_id"] as? String, "b1a472759dc8cc5b2fad8fbc6a5a2c554237d2b3")
        XCTAssertEqual(json["empty_block_id"] as? String, "409c6fd68df4284330f38dbdc2b0166185e0e2d8")
    }

    func testVaultVectorsLoad() throws {
        let json = try loadJSON("vault_kat")
        XCTAssertEqual(json["iterations"] as? Int, 310_000)
        XCTAssertEqual(json["uid"] as? String, "0123456789abcdef0123456789abcdef")
        XCTAssertEqual(json["password"] as? String, "Mật khẩu kho thử nghiệm")
    }

    private func loadJSON(_ name: String) throws -> [String: Any] {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "missing fixture \(name).json"
        )
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
