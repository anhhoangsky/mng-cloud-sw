import XCTest
@testable import MNGKit

final class MNGFormatTests: XCTestCase {
    func testNumberUsesDotThousands() {
        XCTAssertEqual(MNGFormat.number(0), "0")
        XCTAssertEqual(MNGFormat.number(7), "7")
        XCTAssertEqual(MNGFormat.number(999), "999")
        XCTAssertEqual(MNGFormat.number(1_000), "1.000")
        XCTAssertEqual(MNGFormat.number(1_966), "1.966")
        XCTAssertEqual(MNGFormat.number(1_234_567), "1.234.567")
        XCTAssertEqual(MNGFormat.number(-5), "0")
        XCTAssertEqual(MNGFormat.count(1_966), "1.966 mục")
        XCTAssertEqual(MNGFormat.count(1), "1 mục")
    }

    func testBytesMatchPWAUnits() {
        XCTAssertEqual(MNGFormat.bytes(0), "0 B")
        XCTAssertEqual(MNGFormat.bytes(512), "512 B")
        XCTAssertEqual(MNGFormat.bytes(1_023), "1023 B")
        XCTAssertEqual(MNGFormat.bytes(1_024), "1.0 KB")
        XCTAssertEqual(MNGFormat.bytes(1_536), "1.5 KB")
        XCTAssertEqual(MNGFormat.bytes(1_048_576), "1.0 MB")
        XCTAssertEqual(MNGFormat.bytes(5_368_709_120), "5.0 GB")
        XCTAssertEqual(MNGFormat.bytes(-1), "0 B")
    }

    func testDurationRoundsAndPads() {
        XCTAssertEqual(MNGFormat.duration(0), "0:00")
        XCTAssertEqual(MNGFormat.duration(-3), "0:00")
        XCTAssertEqual(MNGFormat.duration(9.6), "0:10")
        XCTAssertEqual(MNGFormat.duration(59.4), "0:59")
        XCTAssertEqual(MNGFormat.duration(65), "1:05")
        XCTAssertEqual(MNGFormat.duration(3_600), "1:00:00")
        XCTAssertEqual(MNGFormat.duration(3_661), "1:01:01")
    }

    func testCoordinateUsesFiveDecimalsAndHemispheres() {
        XCTAssertEqual(
            MNGFormat.coordinate(latitude: 16.05441, longitude: 108.20217),
            "16.05441° N, 108.20217° E"
        )
        XCTAssertEqual(
            MNGFormat.coordinate(latitude: -33.8688, longitude: -151.2093),
            "33.86880° S, 151.20930° W"
        )
    }

    func testDatesAndLabels() {
        XCTAssertEqual(
            MNGFormat.itemDate(day: 5, month: 11, year: 2026),
            "5 tháng 11, 2026"
        )
        XCTAssertEqual(MNGFormat.itemDate(day: 5, month: 0, year: 2026), "5 tháng 1, 2026")
        XCTAssertEqual(MNGFormat.itemDate(day: 5, month: 11, year: 0), "Không rõ ngày")
        XCTAssertEqual(MNGFormat.monthLabel(year: 2026, month: 11), "Tháng 11 2026")
        XCTAssertEqual(MNGFormat.monthLabel(year: 0, month: 0), "Không rõ ngày")
        XCTAssertNil(MNGFormat.resolution(width: 0, height: 100))
        XCTAssertEqual(MNGFormat.resolution(width: 1920, height: 1080), "1920 × 1080")
    }

    func testTodayUsesLocalCalendar() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 7 * 3600))
        let date = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 9))
        )
        XCTAssertEqual(MNGFormat.today(date, calendar: calendar), "5 tháng 11, 2026")
    }

    func testTimeRendersUTC() {
        XCTAssertEqual(MNGFormat.time(takenAt: 0), "")
        XCTAssertEqual(MNGFormat.time(takenAt: -10), "")
        XCTAssertEqual(MNGFormat.time(takenAt: 1_650_000_000), "05:20")
        XCTAssertEqual(MNGFormat.time(takenAt: 1_650_000_060), "05:21")
    }

    private func viewerItem(
        mediaType: String = "photo",
        width: Int64 = 0,
        height: Int64 = 0,
        size: Int64 = 0,
        duration: Double = 0,
        takenAt: Int64 = 0
    ) throws -> Item {
        let json = """
        {"id":1,"name":"IMG_0001.HEIC","type":"\(mediaType)","width":\(width),
         "height":\(height),"size":\(size),"duration":\(duration),
         "taken_at":\(takenAt),"day":5,"month":11,"year":2026}
        """
        return try JSONDecoder().decode(Item.self, from: Data(json.utf8))
    }

    func testViewerTitleMatchesPWA() throws {
        XCTAssertEqual(
            MNGFormat.viewerTitle(try viewerItem(
                mediaType: "video",
                size: 1_048_576,
                duration: 65
            )),
            "1:05 · 1.0 MB"
        )
        XCTAssertEqual(
            MNGFormat.viewerTitle(try viewerItem(
                width: 1920,
                height: 1080,
                size: 1_536
            )),
            "1920 × 1080 · 1.5 KB"
        )
        XCTAssertEqual(
            MNGFormat.viewerTitle(try viewerItem(size: 0)),
            "0 B"
        )
    }

    func testViewerSubtitleAlwaysKeepsThreeFields() throws {
        XCTAssertEqual(
            MNGFormat.viewerSubtitle(
                try viewerItem(takenAt: 1_650_000_000),
                cloud: "Seafile"
            ),
            "Seafile · 5 tháng 11, 2026 · 05:20"
        )
        XCTAssertEqual(
            MNGFormat.viewerSubtitle(try viewerItem(), cloud: "Seafile"),
            "Seafile · 5 tháng 11, 2026 · "
        )
    }

    func testLibraryErrorCopyMatchesPWA() {
        XCTAssertEqual(APIMessages.itemList(.network()), "Không kết nối được máy chủ.")
        XCTAssertEqual(
            APIMessages.itemList(APIError(status: 500, code: "x", message: "x")),
            "Không tải được danh sách ảnh và video."
        )
        XCTAssertEqual(
            APIMessages.olderPage(APIError(status: 500, code: "x", message: "x")),
            "Không tải thêm được ảnh cũ."
        )
        XCTAssertEqual(
            APIMessages.bootstrap(APIError(status: 500, code: "x", message: "x")),
            "Không tải được thông tin thư viện."
        )
    }

    func testBulkActionCopyMatchesPWA() {
        XCTAssertEqual(APIMessages.favoriteChanged(true, count: 1), "Đã thêm vào Yêu thích.")
        XCTAssertEqual(APIMessages.favoriteChanged(false, count: 1), "Đã bỏ Yêu thích.")
        XCTAssertEqual(APIMessages.favoriteChanged(true, count: 3), "Đã thêm yêu thích 3 mục.")
        XCTAssertEqual(APIMessages.favoriteChanged(false, count: 3), "Đã bỏ yêu thích 3 mục.")
        XCTAssertEqual(
            APIMessages.favoritePartial(done: 2, total: 4, failed: 2),
            "Đã cập nhật 2/4 mục. 2 mục chưa đổi được."
        )
        XCTAssertEqual(APIMessages.deleted(count: 1), "Đã xóa khỏi đám mây.")
        XCTAssertEqual(APIMessages.deleted(count: 4), "Đã xóa 4 mục.")
        XCTAssertEqual(
            APIMessages.deletePartial(removed: 3, total: 4, failed: 1),
            "Đã xóa 3/4 mục. 1 mục chưa xóa được."
        )
    }
}
