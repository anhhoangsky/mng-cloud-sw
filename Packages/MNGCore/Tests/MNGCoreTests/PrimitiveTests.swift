import XCTest
@testable import MNGCore

final class PrimitiveTests: XCTestCase {
    func testHexRoundTrip() throws {
        let bytes: [UInt8] = [0x00, 0x01, 0x0F, 0x10, 0xA5, 0xFF]
        XCTAssertEqual(Hex.encode(bytes), "00010f10a5ff")
        XCTAssertEqual(try Hex.decode("00010f10a5ff"), bytes)
        XCTAssertEqual(try Hex.decode("A5FF"), [0xA5, 0xFF])
        XCTAssertEqual(try Hex.decode(""), [])
    }

    func testHexRejectsOddAndInvalidInput() {
        XCTAssertThrowsError(try Hex.decode("abc")) { error in
            XCTAssertEqual(error as? MNGError, .invalidHex("hex"))
        }
        XCTAssertThrowsError(try Hex.decode("zz")) { error in
            XCTAssertEqual(error as? MNGError, .invalidHex("hex"))
        }
        XCTAssertThrowsError(try Hex.decode("g0", field: "magic")) { error in
            XCTAssertEqual(error as? MNGError, .invalidHex("magic"))
        }
    }

    func testConstantTimeComparison() {
        XCTAssertTrue(ConstantTime.equals([1, 2, 3], [1, 2, 3]))
        XCTAssertFalse(ConstantTime.equals([1, 2, 3], [1, 2, 4]))
        XCTAssertFalse(ConstantTime.equals([1, 2, 3], [1, 2]))
        XCTAssertTrue(ConstantTime.equals("", ""))
        XCTAssertTrue(ConstantTime.equals("xin chào", "xin chào"))
        XCTAssertFalse(ConstantTime.equals("xin chào", "xin chao"))
    }

    func testSecureRandomProducesRequestedLength() {
        XCTAssertEqual(SecureRandom.bytes(count: 0), [])
        XCTAssertEqual(SecureRandom.bytes(count: 32).count, 32)
        XCTAssertNotEqual(SecureRandom.bytes(count: 32), SecureRandom.bytes(count: 32))
    }

    func testSecureBytesZeroizes() {
        let bytes = SecureBytes([1, 2, 3])
        XCTAssertEqual(bytes.copyBytes(), [1, 2, 3])
        bytes.zeroize()
        XCTAssertEqual(bytes.copyBytes(), [0, 0, 0])
        XCTAssertEqual(bytes.count, 3)
    }
}
