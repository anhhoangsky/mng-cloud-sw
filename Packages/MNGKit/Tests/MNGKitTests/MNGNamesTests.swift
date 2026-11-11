import XCTest
@testable import MNGKit

/// The file name date rules have to match the Rust worker byte for byte: the
/// app uses them for the upload dedupe pre-check, and the worker uses them
/// when it indexes the file afterwards.
///
/// The expectations are the ones `crates/mng-core/src/names.rs` asserts.
final class MNGNamesTests: XCTestCase {
    /// 2022-09-10 18:38:59 as a UTC epoch that carries the wall-clock time.
    private let sample = Int64(1_662_835_139)

    func testFilenameDatesMatchTheLegacyPatterns() {
        for name in [
            "IMG_20220910_183859_3C16.jpg",
            "VID_20220910_183859.mp4",
            "Screenshot_2022-09-10-18-38-59.png",
            "Screen_2022-09-10-18-38-59.png",
            "2022-09-10 18:38:59.jpg",
            "22-09-10 18-38-59 0001.jpg",
            "20220910_183859.jpg",
            "PXL_2022.09.10_18.38.59.jpg",
            "IMG_20220910%5F183859.jpg",
        ] {
            XCTAssertEqual(MNGNames.takenAt(from: name), sample, name)
        }
    }

    func testInvalidFilenameDatesFallBackToTheModificationTime() {
        for name in [
            "IMG_20211310_183859.jpg",
            "IMG_20220230_183859.jpg",
            "IMG_20220910_243859.jpg",
            "IMG_20220910_186059.jpg",
            "IMG_20220910_183860.jpg",
            "IMG_19890910_183859.jpg",
            "IMG_20380910_183859.jpg",
            "99-01-02 03-04-05.jpg",
        ] {
            XCTAssertEqual(MNGNames.takenAt(from: name, mtime: 99), 99, name)
        }
        XCTAssertEqual(MNGNames.takenAt(from: "holiday.jpg"), 0)
    }

    func testCompactDatesRequireDigitBoundaries() {
        XCTAssertEqual(MNGNames.takenAt(from: "x20220910_183859.jpg"), sample)
        XCTAssertEqual(
            MNGNames.takenAt(from: "120220910_1838590.jpg", mtime: 5),
            5
        )
        XCTAssertEqual(
            MNGNames.takenAt(from: "20220910_1838599.jpg", mtime: 5),
            5
        )
    }

    func testAnInvalidCompactDateDoesNotLetALaterNumberWin() {
        XCTAssertEqual(
            MNGNames.takenAt(from: "20211310_183859_20220910_183859.jpg", mtime: 5),
            5
        )
    }

    func testLeapDaysAreValidOnlyInLeapYears() {
        XCTAssertNotEqual(MNGNames.takenAt(from: "IMG_20240229_120000.jpg"), 0)
        XCTAssertEqual(
            MNGNames.takenAt(from: "IMG_20230229_120000.jpg", mtime: 7),
            7
        )
    }

    func testStemDropsOnlyTheExtension() {
        XCTAssertEqual(MNGNames.stem(of: "IMG_0001.HEIC"), "IMG_0001")
        XCTAssertEqual(MNGNames.stem(of: "IMG_0001"), "IMG_0001")
        XCTAssertEqual(MNGNames.stem(of: "my.photo.name.jpg"), "my.photo.name")
    }
}
