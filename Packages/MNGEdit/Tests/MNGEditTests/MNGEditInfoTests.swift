import XCTest
@testable import MNGEdit

final class MNGEditInfoTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertFalse(MNGEditInfo.version.isEmpty)
    }
}
