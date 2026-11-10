import XCTest
@testable import MNGKit

final class ItemFiltersTests: XCTestCase {
    func testQueryOrderAndEncodingMatchPWA() {
        var filters = ItemFilters(
            cloud: "seafile",
            kind: "photo",
            album: "person:7",
            year: 2022,
            month: 3,
            favorite: true,
            q: "  Hà Nội  "
        )
        filters.offset = 120
        XCTAssertEqual(
            filters.query.encoded,
            "limit=120&offset=120&cloud=seafile&type=photo&album=person%3A7"
                + "&year=2022&month=3&favorite=true&q=H%C3%A0%20N%E1%BB%99i"
        )
    }

    func testEmptyAndWhitespaceFiltersAreOmitted() {
        let filters = ItemFilters(cloud: "", kind: "", album: "", q: "   ")
        XCTAssertEqual(filters.query.encoded, "limit=120&offset=0")
    }

    func testFavoriteFalseIsSent() {
        let filters = ItemFilters(favorite: false)
        XCTAssertEqual(filters.query.encoded, "limit=120&offset=0&favorite=false")
    }

    func testDynamicAlbumSelectorsMatchServerKeys() {
        var filters = ItemFilters()
        filters.select(person: 12)
        XCTAssertEqual(filters.album, "person:12")
        filters.select(province: "Hà Nội")
        XCTAssertEqual(filters.album, "province:Hà Nội")
        filters.select(district: "Ba Đình", province: "Hà Nội")
        XCTAssertEqual(filters.album, "district:Hà Nội|Ba Đình")
    }

    func testCustomLimitIsNotClampedLocally() {
        let filters = ItemFilters(limit: 999)
        XCTAssertTrue(filters.query.encoded.hasPrefix("limit=999&offset=0"))
    }
}
