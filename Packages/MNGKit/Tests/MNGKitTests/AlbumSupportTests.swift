import XCTest
@testable import MNGKit

final class AlbumSupportTests: XCTestCase {
    // MARK: - Fixtures

    private func item(
        id: Int64,
        name: String = "IMG",
        takenAt: Int64 = 0,
        favorite: Bool = false
    ) throws -> Item {
        let json = """
        {"id":\(id),"name":"\(name)","taken_at":\(takenAt),"favorite":\(favorite)}
        """
        return try JSONDecoder().decode(Item.self, from: Data(json.utf8))
    }

    private func album(key: String, title: String, count: Int64) throws -> Album {
        let json = """
        {"key":"\(key)","title":"\(title)","count":\(count)}
        """
        return try JSONDecoder().decode(Album.self, from: Data(json.utf8))
    }

    private func person(
        id: Int64,
        name: String,
        label: String = "",
        itemCount: Int64
    ) throws -> Person {
        let json = """
        {"id":\(id),"name":"\(name)","label":"\(label)","item_count":\(itemCount)}
        """
        return try JSONDecoder().decode(Person.self, from: Data(json.utf8))
    }

    private func province(_ name: String, count: Int64) throws -> PlaceProvince {
        let json = #"{"province":"\#(name)","count":\#(count)}"#
        return try JSONDecoder().decode(PlaceProvince.self, from: Data(json.utf8))
    }

    private func district(_ name: String, count: Int64) throws -> PlaceDistrict {
        let json = #"{"province":"Việt Nam","district":"\#(name)","count":\#(count)}"#
        return try JSONDecoder().decode(PlaceDistrict.self, from: Data(json.utf8))
    }

    private func aiStatus(
        people: Int64,
        places: Int64,
        facesDone: Int64,
        placeDone: Int64,
        placePending: Int64
    ) throws -> AiStatus {
        let json = """
        {"people":\(people),"places":\(places),"running":true,"stats":{
          "faces_done":\(facesDone),"place_done":\(placeDone),
          "place_pending":\(placePending)}}
        """
        return try JSONDecoder().decode(AiStatus.self, from: Data(json.utf8))
    }

    // MARK: - AlbumFilter

    func testYearAlbumMapsToPlainYearParameter() {
        let filter = AlbumFilter(key: "year:2022", title: "Năm 2022")
        XCTAssertEqual(filter.year, 2022)
        XCTAssertTrue(filter.isYear)
        XCTAssertFalse(filter.isCrossCloud)
        XCTAssertNil(filter.serverAlbum)
        XCTAssertEqual(filter.displayTitle, "Năm 2022")

        let filters = filter.itemFilters(cloud: "seafile", limit: 300)
        XCTAssertEqual(filters.cloud, "seafile")
        XCTAssertEqual(filters.year, 2022)
        XCTAssertNil(filters.album)
        XCTAssertEqual(filters.limit, 300)
        XCTAssertEqual(filters.offset, 0)
    }

    func testFixedAlbumKeepsActiveCloud() {
        let filter = AlbumFilter(key: "videos", title: "Video")
        XCTAssertNil(filter.year)
        XCTAssertEqual(filter.serverAlbum, "videos")
        XCTAssertFalse(filter.isCrossCloud)

        let filters = filter.itemFilters(cloud: "pcloud", offset: 240)
        XCTAssertEqual(filters.cloud, "pcloud")
        XCTAssertEqual(filters.album, "videos")
        XCTAssertNil(filters.year)
        XCTAssertEqual(filters.offset, 240)
    }

    func testDynamicAlbumsOmitCloudAndBadYearsAreIgnored() {
        for key in ["person:12", "province:Hà Nội", "district:Hà Nội|Ba Đình"] {
            let filter = AlbumFilter(key: key, title: "Album")
            XCTAssertTrue(filter.isCrossCloud, key)
            XCTAssertEqual(filter.serverAlbum, key)
            let filters = filter.itemFilters(cloud: "seafile")
            XCTAssertNil(filters.cloud)
            XCTAssertEqual(filters.album, key)
        }

        XCTAssertNil(AlbumFilter(key: "year:0", title: "Năm").year)
        XCTAssertNil(AlbumFilter(key: "year:abc", title: "Năm").year)
        XCTAssertNil(AlbumFilter(key: "year:", title: "Năm").year)
        XCTAssertEqual(AlbumFilter(key: "year:1", title: "Năm").year, 1)
    }

    func testDisplayTitleFallsBackWhenBlank() {
        XCTAssertEqual(AlbumFilter(key: "videos", title: "  ").displayTitle, "Album")
        XCTAssertEqual(AlbumFilter(key: "videos", title: " Video ").displayTitle, "Video")
    }

    // MARK: - Sorting

    func testItemsSortNewestAndOldestWithIdTies() throws {
        let list = [
            try item(id: 1, takenAt: 100),
            try item(id: 2, takenAt: 200),
            try item(id: 3, takenAt: 100),
        ]

        XCTAssertEqual(
            AlbumSorting.items(list, sort: .newest).map(\.id),
            [2, 3, 1]
        )
        XCTAssertEqual(
            AlbumSorting.items(list, sort: .oldest).map(\.id),
            [1, 3, 2]
        )
    }

    func testItemsNameSortIsCaseInsensitiveAndTieBreaksById() throws {
        let list = [
            try item(id: 3, name: "IMG_2"),
            try item(id: 1, name: "img_10"),
            try item(id: 2, name: "IMG_10"),
        ]
        XCTAssertEqual(
            AlbumSorting.items(list, sort: .name).map(\.id),
            [1, 2, 3]
        )
    }

    func testAlbumSortKeepsServerOrderOnCountTies() throws {
        let beta = try album(key: "beta", title: "Beta", count: 5)
        let alpha = try album(key: "alpha", title: "alpha", count: 5)
        let gamma = try album(key: "gamma", title: "Gamma", count: 9)
        let list = [beta, alpha, gamma]

        XCTAssertEqual(
            AlbumSorting.albums(list, sort: .newest).map(\.key),
            ["gamma", "beta", "alpha"]
        )
        XCTAssertEqual(
            AlbumSorting.albums(list, sort: .oldest).map(\.key),
            ["beta", "alpha", "gamma"]
        )
        XCTAssertEqual(
            AlbumSorting.albums(list, sort: .name).map(\.key),
            ["alpha", "beta", "gamma"]
        )
    }

    func testPeopleSortUsesLabelThenNameFallback() throws {
        let named = try person(id: 1, name: "An", itemCount: 2)
        let labelled = try person(id: 2, name: "ignored", label: "Bình", itemCount: 5)
        let blankLabel = try person(id: 3, name: "Zed", label: "   ", itemCount: 5)
        let list = [named, labelled, blankLabel]

        XCTAssertEqual(
            AlbumSorting.people(list, sort: .newest).map(\.id),
            [2, 3, 1]
        )
        XCTAssertEqual(
            AlbumSorting.people(list, sort: .oldest).map(\.id),
            [1, 2, 3]
        )
        XCTAssertEqual(
            AlbumSorting.people(list, sort: .name).map(\.id),
            [1, 2, 3]
        )
    }

    func testPlaceSortingByNameAndCount() throws {
        let provinces = [
            try province("Hà Nội", count: 4),
            try province("Đà Nẵng", count: 9),
            try province("An Giang", count: 4),
        ]
        XCTAssertEqual(
            AlbumSorting.places(provinces, sort: .newest).map(\.province),
            ["Đà Nẵng", "Hà Nội", "An Giang"]
        )
        XCTAssertEqual(
            AlbumSorting.places(provinces, sort: .oldest).map(\.province),
            ["Hà Nội", "An Giang", "Đà Nẵng"]
        )
        XCTAssertEqual(
            AlbumSorting.places(provinces, sort: .name).map(\.province),
            ["An Giang", "Hà Nội", "Đà Nẵng"]
        )

        let districts = [
            try district("Quận 1", count: 3),
            try district("Ba Đình", count: 3),
            try district("Cầu Giấy", count: 8),
        ]
        XCTAssertEqual(
            AlbumSorting.districts(districts, sort: .newest).map(\.district),
            ["Cầu Giấy", "Quận 1", "Ba Đình"]
        )
        XCTAssertEqual(
            AlbumSorting.districts(districts, sort: .name).map(\.district),
            ["Ba Đình", "Cầu Giấy", "Quận 1"]
        )
    }

    // MARK: - Catalog

    func testCollectionsExcludeYearsAndPseudoAlbums() throws {
        let list = [
            try album(key: "year:2022", title: "Năm 2022", count: 12),
            try album(key: "all", title: "Tất cả", count: 99),
            try album(key: "favorites", title: "Yêu thích", count: 7),
            try album(key: "videos", title: "Video", count: 4),
            try album(key: "live", title: "Live Photo", count: 2),
            try album(key: "person:1", title: "Lan", count: 6),
        ]

        XCTAssertEqual(
            AlbumCatalog.collections(list).map(\.key),
            ["videos", "live", "person:1"]
        )
        XCTAssertEqual(AlbumCatalog.years(list).map(\.key), ["year:2022"])
        XCTAssertTrue(AlbumCatalog.isCollection(list[3]))
        XCTAssertFalse(AlbumCatalog.isCollection(list[0]))
        XCTAssertFalse(AlbumCatalog.isCollection(list[1]))
        XCTAssertFalse(AlbumCatalog.isCollection(list[2]))
    }

    func testPersonTitleFallsBackToId() throws {
        let unnamed = try person(id: 5, name: "  ", label: "", itemCount: 1)
        let named = try person(id: 6, name: "Lan", label: "  ", itemCount: 1)
        let labelled = try person(id: 7, name: "x", label: " Mai ", itemCount: 1)

        XCTAssertEqual(AlbumCatalog.personTitle(unnamed), "Người 5")
        XCTAssertEqual(AlbumCatalog.personTitle(named), "Lan")
        XCTAssertEqual(AlbumCatalog.personTitle(labelled), "Mai")
    }

    func testExploreSignatureUsesAiCounters() throws {
        let status = try aiStatus(
            people: 87,
            places: 8,
            facesDone: 10,
            placeDone: 2,
            placePending: 3
        )
        let signature = ExploreSignature(status)
        XCTAssertEqual(signature.description, "87:8:10:2:3")
        XCTAssertEqual(signature, ExploreSignature(status))

        let changed = ExploreSignature(
            try aiStatus(people: 87, places: 8, facesDone: 11, placeDone: 2, placePending: 3)
        )
        XCTAssertNotEqual(signature, changed)
    }

    // MARK: - Favorites reconciliation

    func testFavoritesReconciliationDropsSyncsAndInsertsMissing() throws {
        let stale = try item(id: 1, takenAt: 400, favorite: false)
        let present = try item(id: 3, takenAt: 200, favorite: false)
        let unknown = try item(id: 6, takenAt: 50, favorite: false)
        let removedFavorite = try item(id: 4, takenAt: 300, favorite: true)
        let olderFavorite = try item(id: 2, takenAt: 100, favorite: true)

        let list = [stale, present, unknown]
        let known: [Int64: Item] = [
            stale.id: stale,
            present.id: present.withFavorite(true),
            removedFavorite.id: removedFavorite,
            olderFavorite.id: olderFavorite,
        ]

        let merged = FavoriteReconciliation.apply(list, known: known)
        XCTAssertEqual(merged.map(\.id), [4, 3, 2, 6])
        XCTAssertEqual(merged.map(\.favorite), [true, true, true, false])
    }

    func testFavoritesReconciliationKeepsListOrderWhenNothingIsMissing() throws {
        let first = try item(id: 1, takenAt: 200, favorite: true)
        let second = try item(id: 2, takenAt: 100, favorite: true)
        let merged = FavoriteReconciliation.apply(
            [first, second],
            known: [first.id: first, second.id: second]
        )
        XCTAssertEqual(merged.map(\.id), [1, 2])
    }

    // MARK: - Search

    func testSearchQueryTrimsAndBuildsFavoriteFilter() {
        let query = SearchQuery(text: "  IMG  ", filter: .favorite)
        XCTAssertEqual(query.trimmed, "IMG")
        XCTAssertFalse(query.isEmpty)
        XCTAssertEqual(query.filter.apiValue, "favorite")

        let filters = query.itemFilters(cloud: "seafile")
        XCTAssertEqual(filters.cloud, "seafile")
        XCTAssertEqual(filters.kind, "favorite")
        XCTAssertEqual(filters.q, "IMG")
        XCTAssertEqual(filters.limit, SearchQuery.limit)
        XCTAssertEqual(filters.limit, 300)
        XCTAssertEqual(filters.offset, 0)
        XCTAssertNil(filters.album)
        XCTAssertNil(filters.year)
    }

    func testSearchQueryEmptyAndChips() {
        XCTAssertTrue(SearchQuery(text: "   ", filter: .all).isEmpty)
        XCTAssertNil(SearchFilter.all.apiValue)
        XCTAssertEqual(SearchFilter.photo.apiValue, "photo")
        XCTAssertEqual(SearchFilter.video.apiValue, "video")
        XCTAssertEqual(SearchFilter.live.apiValue, "live")
        XCTAssertEqual(SearchFilter.allCases.count, 5)
        XCTAssertEqual(SearchQuery.debounceMilliseconds, 280)
    }

    func testSearchHintsOpenAlbums() {
        XCTAssertEqual(SearchHint.all.count, 4)
        XCTAssertEqual(
            SearchHint.all.map(\.album.key),
            ["year:2022", "favorites", "videos", "live"]
        )
        XCTAssertEqual(SearchHint.all.map(\.label), [
            "Ảnh năm 2022",
            "Ảnh yêu thích",
            "Tất cả video",
            "Live Photo",
        ])
    }

    func testGridAndSortLabels() {
        XCTAssertEqual(AlbumSort.allCases.map(\.label), ["Mới nhất", "Cũ nhất", "Tên A–Z"])
        XCTAssertEqual(AlbumGrid.allCases.map(\.label), ["Lớn", "Vừa", "Nhỏ"])
        XCTAssertEqual(AlbumGrid.medium.minimumWidth, 140)
        XCTAssertEqual(AlbumGrid.medium.compactMinimumWidth, 108)
        XCTAssertEqual(AlbumGrid.small.spacing, 2)
    }
}
