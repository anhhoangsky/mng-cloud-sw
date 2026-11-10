import XCTest
import MNGCore
import MNGKit

final class SmokeTests: XCTestCase {
    func testPackagesLink() {
        XCTAssertFalse(MNGCoreInfo.version.isEmpty)
        XCTAssertFalse(MNGKitInfo.version.isEmpty)
    }
}
