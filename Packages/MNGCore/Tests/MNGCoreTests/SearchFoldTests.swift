import XCTest
@testable import MNGCore

final class SearchFoldTests: XCTestCase {
    func testFoldsVietnameseDiacriticsAndPunctuation() {
        XCTAssertEqual(
            SearchFold.fold("  Ảnh   Đà-Lạt (2024)!!  "),
            "anh da lat 2024"
        )
        XCTAssertEqual(
            SearchFold.fold("Đường Trần Hưng Đạo"),
            "duong tran hung dao"
        )
    }

    func testDropsCombiningMarksAfterDecomposedInput() {
        XCTAssertEqual(SearchFold.fold("a\u{301}n\u{300}"), "an")
    }

    func testKeepsNonLatinLettersAndNumbers() {
        XCTAssertEqual(SearchFold.fold("日本語 123"), "日本語 123")
        XCTAssertEqual(SearchFold.fold("  "), "")
    }

    func testLowercasesSigmaPerScalarLikeRust() {
        // Rust maps every `char` through `char::to_lowercase`, so a final
        // capital sigma becomes σ (not the context-sensitive final ς).
        XCTAssertEqual(SearchFold.fold("ΣΟΦΟΣ"), "σοφοσ")
    }

    func testRawURLDecodeLeavesPlusAndDecodesPercentBytes() {
        XCTAssertEqual(SearchFold.rawurldecode("/a%20b+c.jpg"), "/a b+c.jpg")
        XCTAssertEqual(SearchFold.rawurldecode("/a%2fb"), "/a/b")
        XCTAssertEqual(SearchFold.rawurldecode("/a%zzb"), "/a%zzb")

        let decoded = SearchFold.rawurldecode(
            "/Camera%20Uploads/IMG_0001%20(%C4%91%C3%A3%20ch%E1%BB%89nh%20s%E1%BB%ADa).jpg"
        )
        XCTAssertEqual(
            decoded,
            "/Camera Uploads/IMG_0001 (đã chỉnh sửa).jpg"
        )
    }

    func testRawURLDecodeUsesLossyUTF8() {
        XCTAssertTrue(SearchFold.rawurldecode("/a%FFb").contains("\u{FFFD}"))
    }

    func testCopySearchTextIncludesPlaces() {
        let text = SearchFold.itemSearchText(
            name: "IMG_0001 (đã chỉnh sửa).jpg",
            stem: "IMG_0001 (đã chỉnh sửa)",
            path: "/Camera%20Uploads/IMG_0001%20(%C4%91%C3%A3%20ch%E1%BB%89nh%20s%E1%BB%ADa).jpg",
            places: [
                "Đường Lê Lợi",
                "Phường 1",
                "Quận 3",
                "TP Hồ Chí Minh",
                "Chợ Bến Thành"
            ]
        )

        XCTAssertTrue(text.contains("duong le loi"))
        XCTAssertTrue(text.contains("phuong 1"))
        XCTAssertTrue(text.contains("quan 3"))
        XCTAssertTrue(text.contains("tp ho chi minh"))
        XCTAssertTrue(text.contains("cho ben thanh"))
        XCTAssertTrue(text.contains("da chinh sua"))
    }
}
