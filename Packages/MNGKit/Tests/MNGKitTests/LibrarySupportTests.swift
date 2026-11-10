import XCTest
@testable import MNGKit

final class LibrarySupportTests: XCTestCase {
    private func item(
        id: Int64,
        year: Int = 2026,
        month: Int = 11,
        day: Int = 10,
        favorite: Bool = false,
        takenAt: Int64 = 0,
        mediaType: String = "photo"
    ) throws -> Item {
        let json = """
        {"id":\(id),"name":"IMG_\(id).HEIC","type":"\(mediaType)","year":\(year),
         "month":\(month),"day":\(day),"favorite":\(favorite),"taken_at":\(takenAt)}
        """
        return try JSONDecoder().decode(Item.self, from: Data(json.utf8))
    }

    private func itemsResponse(ids: [Int64], total: Int64) throws -> ItemsResponse {
        let list = ids.map { #"{"id":\#($0)}"# }.joined(separator: ",")
        let json = #"{"items":[\#(list)],"total":\#(total),"has_more":false}"#
        return try JSONDecoder().decode(ItemsResponse.self, from: Data(json.utf8))
    }

    // MARK: - Layout and filters

    func testStoredLayoutDefaultsToAll() {
        XCTAssertEqual(LibraryLayout(stored: nil), .all)
        XCTAssertEqual(LibraryLayout(stored: ""), .all)
        XCTAssertEqual(LibraryLayout(stored: "years"), .years)
        XCTAssertEqual(LibraryLayout(stored: "months"), .months)
        XCTAssertEqual(LibraryLayout(stored: "all"), .all)
        XCTAssertEqual(LibraryLayout(stored: "unexpected"), .all)
    }

    func testLayoutChangeClearsDatesButKeepsKind() {
        var state = LibraryFilterState(
            layout: .all,
            kind: .video,
            year: 2024,
            month: 3
        )
        state.selectLayout(.years)
        XCTAssertEqual(state.layout, .years)
        XCTAssertNil(state.year)
        XCTAssertNil(state.month)
        XCTAssertEqual(state.kind, .video)
    }

    func testKindChipReturnsToTimelineAndKeepsDates() {
        var state = LibraryFilterState(
            layout: .months,
            kind: .all,
            year: 2024,
            month: 3
        )
        state.selectKind(.live)
        XCTAssertEqual(state.layout, .all)
        XCTAssertEqual(state.kind, .live)
        XCTAssertEqual(state.year, 2024)
        XCTAssertEqual(state.month, 3)
        XCTAssertTrue(state.isTimeline)
        XCTAssertTrue(state.hasDateFilter)
    }

    func testYearAndMonthDrillDownMatchesPWA() {
        var state = LibraryFilterState(layout: .years)
        state.open(year: 2024)
        XCTAssertEqual(state.layout, .months)
        XCTAssertEqual(state.year, 2024)
        XCTAssertNil(state.month)

        state.open(year: 2024, month: 3)
        XCTAssertEqual(state.layout, .all)
        XCTAssertEqual(state.year, 2024)
        XCTAssertEqual(state.month, 3)

        state.showAllYears()
        XCTAssertNil(state.year)
        XCTAssertNil(state.month)

        state.selectKind(.photo)
        state.clearFilters()
        XCTAssertEqual(state.kind, .all)
        XCTAssertEqual(state.layout, .all)
        XCTAssertNil(state.year)
        XCTAssertNil(state.month)
    }

    func testFilterSummaryAndQueryFields() {
        var state = LibraryFilterState(layout: .all, kind: .all)
        XCTAssertNil(state.summary)

        state.open(year: 2024, month: 3)
        XCTAssertEqual(state.summary, "Tháng 3 2024")

        state.selectKind(.video)
        XCTAssertEqual(state.summary, "Tháng 3 2024 · Video")

        state.showAllYears()
        state.selectLayout(.months)
        state.open(year: 2024)
        XCTAssertEqual(state.summary, "Năm 2024")

        state.clearFilters()
        XCTAssertNil(state.summary)

        let filters = state.itemFilters(cloud: "seafile", offset: 240)
        XCTAssertEqual(filters.cloud, "seafile")
        XCTAssertNil(filters.kind)
        XCTAssertNil(filters.year)
        XCTAssertNil(filters.month)
        XCTAssertEqual(filters.offset, 240)
        XCTAssertEqual(filters.query.value("limit"), "120")
        XCTAssertEqual(filters.query.value("offset"), "240")
    }

    // MARK: - Grouping

    func testGroupingSplitsEveryBoundaryAndPreservesOrder() throws {
        let items = [
            try item(id: 1, year: 2026, month: 11),
            try item(id: 2, year: 2026, month: 11),
            try item(id: 3, year: 2026, month: 10),
            try item(id: 4, year: 0, month: 0),
            try item(id: 5, year: 2025, month: 12),
        ]
        let sections = LibraryGrouping.byMonth(items)
        XCTAssertEqual(sections.map(\.key), ["2026-11", "2026-10", "0-0", "2025-12"])
        XCTAssertEqual(sections.map { $0.items.map(\.id) }, [[1, 2], [3], [4], [5]])
        XCTAssertEqual(
            MNGFormat.monthLabel(year: sections[0].year, month: sections[0].month),
            "Tháng 11 2026"
        )
        XCTAssertEqual(
            MNGFormat.monthLabel(year: sections[2].year, month: sections[2].month),
            "Không rõ ngày"
        )
        XCTAssertTrue(LibraryGrouping.byMonth([]).isEmpty)
    }

    func testFavoritePatchCopiesItem() throws {
        let original = try item(id: 7, favorite: false)
        let patched = original.withFavorite(true)
        XCTAssertFalse(original.favorite)
        XCTAssertTrue(patched.favorite)
        XCTAssertEqual(patched.id, original.id)
        XCTAssertEqual(patched.name, original.name)
    }

    // MARK: - Pages

    func testReplaceAndAppendDeduplicateIds() throws {
        var page = LibraryPage(
            items: [try item(id: 1), try item(id: 2)],
            total: 5
        )
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.count, 2)

        page.append(try itemsResponse(ids: [2, 3], total: 5))
        XCTAssertEqual(page.items.map(\.id), [1, 2, 3])
        XCTAssertTrue(page.hasMore)

        page.append(try itemsResponse(ids: [4, 5], total: 5))
        XCTAssertEqual(page.items.map(\.id), [1, 2, 3, 4, 5])
        XCTAssertFalse(page.hasMore)

        page.replace(with: try itemsResponse(ids: [9], total: 9))
        XCTAssertEqual(page.items.map(\.id), [9])
        XCTAssertEqual(page.total, 9)
        XCTAssertTrue(page.hasMore)
    }

    func testRemoveAndRestoreKeepsOriginalPositions() throws {
        var page = LibraryPage(
            items: [
                try item(id: 1),
                try item(id: 2),
                try item(id: 3),
                try item(id: 4),
            ],
            total: 40
        )

        let removed = page.remove(ids: [2, 4])
        XCTAssertEqual(page.items.map(\.id), [1, 3])
        XCTAssertEqual(page.total, 38)
        XCTAssertEqual(removed.map(\.index), [1, 3])

        page.restore(removed)
        XCTAssertEqual(page.items.map(\.id), [1, 2, 3, 4])
        XCTAssertEqual(page.total, 40)
    }

    func testRestoreIgnoresDuplicatesAndClampsIndex() throws {
        var page = LibraryPage(items: [try item(id: 1)], total: 3)
        page.restore([
            RemovedItem(index: 99, item: try item(id: 2)),
            RemovedItem(index: 0, item: try item(id: 1)),
        ])
        XCTAssertEqual(page.items.map(\.id), [1, 2])
        XCTAssertEqual(page.total, 2)
    }

    func testFavoriteMutation() throws {
        var page = LibraryPage(
            items: [try item(id: 1), try item(id: 2), try item(id: 3)],
            total: 3
        )
        page.setFavorite(ids: [1, 3], value: true)
        XCTAssertEqual(page.items.map(\.favorite), [true, false, true])
        page.setFavorite(id: 2, value: true)
        XCTAssertEqual(page.items.map(\.favorite), [true, true, true])
        page.setFavorite(id: 99, value: true)
        XCTAssertEqual(page.count, 3)
    }
}

private extension APIQuery {
    func value(_ key: String) -> String? {
        pairs.first { $0.0 == key }?.1
    }
}
