import XCTest
@testable import MNGKit

final class ViewerSupportTests: XCTestCase {
    private func item(id: Int64, favorite: Bool = false) throws -> Item {
        let json = """
        {"id":\(id),"name":"IMG_\(id).HEIC","type":"photo","favorite":\(favorite)}
        """
        return try JSONDecoder().decode(Item.self, from: Data(json.utf8))
    }

    private func snapshot(_ ids: [Int64], opening id: Int64) throws -> ViewerCollection {
        let items = try ids.map { try item(id: $0) }
        return try XCTUnwrap(ViewerCollection(items: items, opening: id))
    }

    func testOpeningSelectsTheRequestedItem() throws {
        let viewer = try snapshot([10, 20, 30], opening: 20)
        XCTAssertEqual(viewer.count, 3)
        XCTAssertEqual(viewer.index, 1)
        XCTAssertEqual(viewer.current?.id, 20)
        XCTAssertTrue(viewer.canGoPrevious)
        XCTAssertTrue(viewer.canGoNext)

        let first = try snapshot([10, 20], opening: 10)
        XCTAssertFalse(first.canGoPrevious)
        let last = try snapshot([10, 20], opening: 20)
        XCTAssertFalse(last.canGoNext)

        XCTAssertNil(ViewerCollection(items: try [item(id: 1)], opening: 99))
    }

    func testSelectMovesWithinBounds() throws {
        var viewer = try snapshot([10, 20, 30], opening: 10)
        viewer.select(index: 2)
        XCTAssertEqual(viewer.current?.id, 30)
        viewer.select(index: 9)
        XCTAssertEqual(viewer.current?.id, 30)
        viewer.select(id: 20)
        XCTAssertEqual(viewer.index, 1)
    }

    func testRemovingBeforeCurrentKeepsTheSamePhoto() throws {
        var viewer = try snapshot([10, 20, 30, 40], opening: 30)
        XCTAssertFalse(viewer.remove(ids: [10, 20]))
        XCTAssertEqual(viewer.index, 0)
        XCTAssertEqual(viewer.current?.id, 30)
    }

    func testRemovingCurrentAdvancesThenFallsBack() throws {
        var viewer = try snapshot([10, 20, 30], opening: 20)
        XCTAssertFalse(viewer.remove(ids: [20]))
        XCTAssertEqual(viewer.current?.id, 30)

        var last = try snapshot([10, 20, 30], opening: 30)
        XCTAssertFalse(last.remove(ids: [30]))
        XCTAssertEqual(last.current?.id, 20)

        var middle = try snapshot([10, 20, 30, 40], opening: 20)
        XCTAssertFalse(middle.remove(ids: [20, 30]))
        XCTAssertEqual(middle.current?.id, 40)
    }

    func testRemovingEverythingClosesTheViewer() throws {
        var viewer = try snapshot([10, 20], opening: 10)
        XCTAssertTrue(viewer.remove(ids: [10, 20]))
        XCTAssertTrue(viewer.items.isEmpty)
        XCTAssertEqual(viewer.index, 0)
        XCTAssertNil(viewer.current)
    }

    func testRemovingUnknownIDsIsANoOp() throws {
        var viewer = try snapshot([10, 20], opening: 10)
        XCTAssertFalse(viewer.remove(ids: [99]))
        XCTAssertEqual(viewer.count, 2)
        XCTAssertEqual(viewer.current?.id, 10)
    }

    func testFavoritePatchUpdatesEveryMatchingRow() throws {
        var viewer = try snapshot([10, 20, 30], opening: 10)
        viewer.setFavorite(ids: [10, 30], value: true)
        XCTAssertEqual(viewer.items.map(\.favorite), [true, false, true])
        viewer.setFavorite(ids: [10, 30], value: false)
        XCTAssertEqual(viewer.items.map(\.favorite), [false, false, false])
    }
}
