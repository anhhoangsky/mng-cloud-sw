import XCTest
@testable import MNGKit

final class MNGKitInfoTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertFalse(MNGKitInfo.version.isEmpty)
    }
}
