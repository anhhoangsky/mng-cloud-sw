import Foundation
import MNGKit

/// Vietnamese copy, ported 1:1 from `ui/` and the PWA shell. Every user-facing
/// string lives here so parity reviews can diff one file.
enum Strings {
    static let appName = "MNG Cloud"

    // Boot / login
    static let bootLoading = "Đang mở thư viện…"
    static let bootRetry = "Thử lại"
    static let loginSubtitle = "Thư viện ảnh riêng của bạn"
    static let loginServer = "Máy chủ"
    static let loginServerPlaceholder = "https://cloud.example.com"
    static let loginUsername = "Tên đăng nhập"
    static let loginUsernamePlaceholder = "Tên đăng nhập"
    static let loginPassword = "Mật khẩu"
    static let loginPasswordPlaceholder = "Nhập mật khẩu"
    static let loginSubmit = "Mở thư viện"
    static let loginOpening = "Đang mở…"
    static let loginFootServer = "Kết nối trực tiếp với máy chủ của bạn."
    static let loginFootPrivacy = "Không có dữ liệu nào được gửi tới bên thứ ba."
    static let sessionReady = "Đã đăng nhập"
    static let sessionReadyHint = "Phiên đăng nhập đã sẵn sàng. Thư viện sẽ được mở ở bước tiếp theo."
    static let logout = "Đăng xuất"
    static let signingOut = "Đang đăng xuất…"
    static let close = "Đóng"
    static let cancel = "Hủy"
    static let save = "Lưu"

    // Navigation
    static let brandSubtitle = "Thư viện riêng"
    static let navLibrary = "Thư viện"
    static let navAlbums = "Album"
    static let navSearch = "Tìm kiếm"
    static let navVault = "Kho mã hóa"
    static let navVaultTab = "Kho"
    static let navSettings = "Cài đặt"
    static let navAdmin = "Quản trị"
    static let navMain = "Điều hướng chính"
    static let back = "Quay lại"

    // Library toolbar and layouts
    static let layoutYears = "Năm"
    static let layoutMonths = "Tháng"
    static let layoutAll = "Tất cả"
    static let layoutLabel = "Kiểu xem thư viện"
    static let filterAll = "Tất cả"
    static let filterPhotos = "Ảnh"
    static let filterVideos = "Video"
    static let filterLive = "Live"
    static let filterFavorites = "Yêu thích"
    static let filtersLabel = "Bộ lọc"
    static let clearFilters = "Bỏ bộ lọc"
    static let select = "Chọn"
    static let selectPhotos = "Chọn ảnh"
    static let allYears = "Tất cả các năm"
    static let kindPhoto = "Ảnh"
    static let kindVideo = "Video"
    static let shortUnknownDate = "không rõ ngày"

    // Library states
    static let errorTitle = "Không tải được thư viện"
    static let retry = "Thử lại"
    static let loadOlder = "Đang tải thêm…"
    static let emptyItemsTitle = "Chưa có mục nào"
    static let emptyItemsBody = "Quét thư viện để bắt đầu."
    static let emptyFilteredTitle = "Không có mục phù hợp"
    static let emptyFilteredBody = "Thử bỏ bớt bộ lọc hoặc quét lại thư viện."
    static let emptyYearsTitle = "Thư viện đang trống"
    static let emptyYearsBody = "Quét máy chủ để lập chỉ mục ảnh và video."
    static let emptyMonthsTitle = "Không có ảnh trong năm này"
    static let emptyMonthsBody = "Chọn một năm khác hoặc chuyển sang Tất cả."

    // Tile menu and info sheet
    static let favorite = "Yêu thích"
    static let unfavorite = "Bỏ yêu thích"
    static let download = "Tải xuống"
    static let info = "Thông tin"
    static let moveToVault = "Chuyển vào kho mã hóa"
    static let delete = "Xóa"
    static let itemName = "Tên"
    static let itemDate = "Ngày"
    static let itemLocation = "Vị trí"
    static let itemKind = "Loại"
    static let itemSize = "Kích thước"
    static let itemResolution = "Độ phân giải"
    static let itemDuration = "Thời lượng"
    static let itemCloud = "Đám mây"
    static let itemFolder = "Thư mục"
    static let itemAccount = "Tài khoản"
    static let itemWebDAV = "WebDAV"
    static let copyWebDAV = "Sao chép liên kết WebDAV"
    static let copiedWebDAV = "Đã sao chép liên kết WebDAV."
    static let copyFailed = "Không thể sao chép liên kết."
    static let livePhoto = "Live Photo"
    static let videoLivePhoto = "Video · Live Photo"

    // Viewer
    static let viewerPrevious = "Ảnh trước"
    static let viewerNext = "Ảnh sau"
    static let viewerStrip = "Danh sách ảnh"
    static let liveBadge = "LIVE"
    static let viewerPlay = "Phát"

    // Selection and confirmations
    static let selectionLabel = "Đã chọn"
    static let deselect = "Bỏ chọn"
    static let preparingZip = "Đang chuẩn bị tập ZIP."
    static let downloadFailed = "Không tải xuống được."
    static let zipFailed = "Không tạo được tập ZIP."
    static let unknownDate = "Không rõ ngày"

    static func selectedCount(_ count: Int) -> String {
        "\(count) đã chọn"
    }

    static func itemCount(_ count: Int) -> String {
        "\(count) mục"
    }

    static func deleteTitle(cloud: String) -> String {
        "Xóa khỏi \(cloud)?"
    }

    /// Info-sheet delete button; unlike the confirmation title it has no `?`.
    static func deleteFrom(cloud: String) -> String {
        "Xóa khỏi \(cloud)"
    }

    static let deleteBody = "Tệp sẽ bị xóa khỏi đám mây. Thao tác này không thể hoàn tác từ MNG Cloud."
    static let deleteLiveBody = "Ảnh và phần video Live Photo sẽ bị xóa khỏi đám mây. Thao tác này không thể hoàn tác từ MNG Cloud."

    static func deleteManyTitle(_ count: Int) -> String {
        "Xóa \(count) mục?"
    }

    static let deleteManySub = "Các tệp sẽ bị xóa khỏi đám mây đang chọn."
    static let deleteManyBody = "Thao tác này không thể hoàn tác từ MNG Cloud. Ảnh Live Photo sẽ xóa cả phần video đi kèm."

    static func deleteManyConfirm(_ count: Int) -> String {
        "Xóa \(count) mục"
    }

    // Cloud picker
    static let switchCloud = "Chuyển đám mây"
    static let cloud = "Đám mây"
    static let serverFallback = "Máy chủ"
    static let webdavAccount = "WebDAV"
    static let connecting = "Đang kết nối…"
    static let viewingCloud = "Đang xem"

    // Settings
    static let settingsSubtitle = "Kết nối, bộ nhớ đệm và tài khoản"
    static let connectionsSection = "Kết nối"
    static let librarySection = "Thư viện"
    static let toolsSection = "Công cụ"
    static let aboutSection = "Giới thiệu"
    static let accountSection = "Tài khoản"
    static let freeSpace = "trống"
    static let settingsConnectionsNote =
        "Nhấn vào một đám mây để kiểm tra WebDAV. Thông tin đăng nhập được lưu trên máy chủ, không lưu trong trình duyệt."
    static let settingsAboutBody = "Giao diện thư viện ảnh lấy cảm hứng từ iOS Photos."
    static let serverOpen = "Mở máy chủ"
    static let serverOpenBody = "Quản lý thư viện, chia sẻ và tệp gốc"
    static let storageFree = "Dung lượng trống"
    static let storageServerBody = "Ổ chứa trên máy chủ"
    static let roleAdmin = "Quản trị viên"
    static let roleMember = "Thành viên"
    static let accountLogoutBody = "Kết thúc phiên trên thiết bị này"

    // Settings actions
    static let vaultRowBody = "Mã hóa đầu cuối · chìa khóa chỉ nằm trong trình duyệt"
    static let scanRowTitle = "Quét lại thư viện"
    static let scanRowBody = "Lập chỉ mục ảnh mới từ cả hai đám mây"
    static let scanBusyBody = "Đang xếp hàng quét…"
    static let scanQueued = "Đã xếp hàng quét thư viện."
    static let scanAlreadyQueued = "Lần quét này đã có trong hàng đợi."
    static let scanFailed = "Không xếp hàng quét được thư viện."
    static let thumbsRowTitle = "Tạo lại ảnh thu nhỏ lỗi"
    static let thumbsBusyBody = "Đang xếp hàng tạo lại…"
    static let thumbsQueued = "Đã xếp hàng tạo lại ảnh thu nhỏ."
    static let thumbsAlreadyQueued = "Lần tạo lại này đã có trong hàng đợi."
    static let thumbsFailed = "Không xếp hàng tạo lại ảnh thu nhỏ được."
    static let tmpRowTitle = "Xóa tệp tạm"
    static let tmpRowBody = "Giải phóng bộ nhớ đệm tải xuống"
    static let tmpBusyBody = "Đang dọn tệp tạm…"
    static let tmpEmpty = "Không có tệp tạm nào để xóa."
    static let tmpFailed = "Không xóa được tệp tạm."
    static let testCloudFailed = "Không kiểm tra được kết nối."
    static let cloudTestGood = "Kết nối tốt."
    static let cloudTesting = "Đang kiểm tra…"
    static let duplicatesRowTitle = "Ảnh trùng lặp"
    static let duplicatesRowBody = "Perceptual Hash · tìm ảnh gần giống nhau"

    static let thumbsRowBody = "mục · thử lại mục lỗi"

    static func thumbsRowSub(_ total: Int64) -> String {
        "\(MNGFormat.number(total)) \(thumbsRowBody)"
    }

    static func tmpCleared(_ count: Int64) -> String {
        "Đã xóa \(MNGFormat.number(count)) tệp tạm."
    }

    // Duplicates
    static let duplicatesTitle = "Ảnh trùng lặp"
    static let duplicatesSubtitle =
        "Perceptual Hash · ảnh gần giống nhau trong thư viện"
    static let duplicatesLoadingTitle = "Đang đọc thư viện."
    static let duplicatesLoadingBody =
        "Perceptual Hash sẽ được tính cho các ảnh chưa có dấu vết."
    static let duplicatesErrorTitle = "Không tìm được ảnh trùng lặp"
    static let duplicatesEmptyTitle = "Không có ảnh trùng lặp"
    static let duplicatesEmptyBody =
        "Mọi ảnh đã phân tích đều khác nhau ở ngưỡng hiện tại."
    static let duplicatesAnalyzedSuffix = " ảnh đã phân tích trên cả hai đám mây · "
    static let duplicatesGroupSuffix = " nhóm gần giống nhau"
    static let duplicatesPendingHashes = " · một số ảnh còn chờ tạo thumbnail"

    static func duplicateGroupTitle(_ index: Int) -> String {
        "Nhóm \(index)"
    }

    static func duplicateGroupMeta(count: Int, similarity: Int64) -> String {
        "\(count) ảnh · giống \(max(0, similarity))%"
    }

    static func duplicateMore(_ count: Int) -> String {
        "Xem thêm \(MNGFormat.number(Int64(count))) nhóm"
    }

    // Placeholders
    static let albumsSubtitle = "Ảnh gần đây, yêu thích, khuôn mặt và địa điểm"
    static let searchSubtitle = "Theo tên tệp, album hoặc loại"
    static let vaultSubtitle = "Mã hóa đầu cuối, chìa khóa chỉ ở thiết bị"
    static let comingSoon = "Tính năng đang được xây dựng."
    static let comingSoonHint = "Phần này sẽ có ở giai đoạn tiếp theo."

    // Albums
    static let albumFallback = "Album"
    static let albumSelected = "Bộ sưu tập đã chọn"
    static let albumRecent = "Ảnh gần đây"
    static let albumFavorites = "Ảnh yêu thích"
    static let albumCollections = "Bộ sưu tập"
    static let albumYears = "Năm"
    static let albumPeople = "Mọi người"
    static let albumPlaces = "Địa điểm"
    static let albumDistricts = "Quận, huyện"
    static let albumEmptyTitle = "Album này chưa có ảnh"
    static let albumRecentEmpty = "Chưa có ảnh"
    static let albumRecentEmptyBody = "Quét thư viện để bắt đầu."
    static let albumFavoritesEmpty = "Chưa có ảnh yêu thích"
    static let albumFavoritesEmptyBody = "Nhấn giữ một ảnh và chọn Yêu thích để thêm vào đây."
    static let albumCollectionsEmpty =
        "Chưa có bộ sưu tập. Ảnh video, Live Photo và ảnh chụp màn hình sẽ xuất hiện ở đây."
    static let albumYearsEmpty = "Chưa có năm nào được lập chỉ mục."
    static let albumPeopleEmpty =
        "Chưa nhận diện được người nào. AI sẽ tự cập nhật khi tìm thấy khuôn mặt rõ nét."
    static let albumPlacesEmpty = "Chưa có địa điểm. Ảnh có GPS sẽ được nhận diện tỉnh thành."
    static let albumDistrictsEmpty = "Chưa có quận huyện nào được nhận diện."
    static let albumShowAll = "Xem tất cả"
    static let albumShowLess = "Thu gọn"
    static let albumSortLabel = "Sắp xếp"
    static let albumGridLabel = "Kiểu lưới"
    static let albumUnknownProvince = "Không rõ tỉnh"
    static let albumErrorTitle = "Không tải được album"
    static let aiConnectingTitle = "Đang kết nối AI."
    static let aiConnectingBody = "Sắp xếp khuôn mặt và địa điểm trong thư viện."
    static let aiDoneTitle = "AI đã phân tích xong"
    static let aiRunningTitle = "AI đang phân tích nền"
    static let aiPausedTitle = "AI đang tạm dừng"

    static func albumItemSub(_ count: Int64, sub: String) -> String {
        let trimmed = sub.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? "\(MNGFormat.number(count)) mục"
            : "\(MNGFormat.number(count)) mục · \(trimmed)"
    }

    static func albumYearSub(_ count: Int64) -> String {
        "\(MNGFormat.number(count)) mục"
    }

    static func albumPhotoCount(_ count: Int64) -> String {
        "\(MNGFormat.number(count)) ảnh"
    }

    static func albumPlaceSub(province: String, count: Int64) -> String {
        let name = province.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = name.isEmpty ? albumUnknownProvince : name
        return "\(label) · \(MNGFormat.number(count)) ảnh"
    }

    static func aiDoneBody(_ count: Int64) -> String {
        "\(MNGFormat.number(count)) ảnh đã được nhận diện khuôn mặt và địa chỉ."
    }

    static func aiPendingBody(faces: Int64, places: Int64) -> String {
        "\(MNGFormat.number(faces)) ảnh chờ nhận diện · \(MNGFormat.number(places)) ảnh chờ định vị"
    }

    static func personRenameSub(itemCount: Int64, faceCount: Int64) -> String {
        "\(MNGFormat.number(itemCount)) ảnh · \(MNGFormat.number(faceCount)) khuôn mặt"
    }

    // Person rename
    static let personRenameTitle = "Đổi tên người"
    static let personNameLabel = "Tên"
    static let personNamePlaceholder = "Ví dụ: Mẹ, Hà, Minh…"
    static let personNameSave = "Lưu tên"
    static let personNameCleared = "Đã bỏ tên."
    static let personNameSaved = "Đã lưu tên."

    // Search
    static let searchPlaceholder = "Tìm ảnh, video…"
    static let searchFieldLabel = "Tìm ảnh và video"
    static let searchClear = "Xóa tìm kiếm"
    static let searchFiltersLabel = "Lọc kết quả"
    static let searchErrorTitle = "Lỗi tìm kiếm"
    static let searchEmptyTitle = "Không tìm thấy"
    static let searchEmptyBody = "Thử tên tệp khác hoặc chọn bộ lọc khác."

    static func searchMeta(total: Int64, query: String) -> String {
        "\(MNGFormat.number(total)) kết quả cho \"\(query)\""
    }

    // Connections
    static let connectionsTitle = "Thư viện đám mây"
    static let connectionsSubtitle = "Thư viện trên máy chủ được kết nối tự động bằng WebDAV."
    static let connectionsNote =
        "MNG Cloud đọc trực tiếp từ máy chủ bằng tài khoản ứng dụng lưu trên máy chủ. Không cần đăng nhập lại dịch vụ này."
    static let icloudSection = "iCloud"
    static let icloudPhotos = "iCloud Photos"
    static let icloudNote =
        "iCloud dùng API không chính thức. Ảnh sẽ được tải về máy chủ rồi nhập vào máy chủ."
    static let icloudStatusLabel = "Trạng thái"
    static let icloudAppleID = "Apple ID"
    static let icloudUnknown = "Chưa kết nối · dùng API không chính thức"
    static let icloudNotConfigured = "Máy chủ chưa cấu hình trình tải iCloud"
    static let icloudConnected = "Đã kết nối · sẵn sàng tải ảnh"
    static let icloudDisconnected = "Chưa kết nối · đăng nhập Apple ID"
    static let icloudUnsupported = "Máy chủ chưa hỗ trợ trình tải iCloud"
    static let icloudUnavailable = "Không kiểm tra được iCloud"
    static let icloudStatusUnknown = "Thiết lập"
    static let icloudStatusNotConfigured = "Chưa cấu hình"
    static let icloudStatusConnected = "Đã kết nối"
    static let icloudStatusUnsupported = "Chưa hỗ trợ"
    static let icloudStatusUnavailable = "Không khả dụng"
    static let icloudDeferred = "Trình nhập iCloud đầy đủ sẽ có ở giai đoạn sau."
    static let webdavCopy = "Sao chép"
    static let webdavCopied = "Đã sao chép liên kết WebDAV."
    static let webdavCopyFailed = "Không thể sao chép liên kết."
    static let cloudHealthGood = "Kết nối tốt"
    static let cloudHealthBad = "Không phản hồi"
    static let cloudHealthUnknown = "Chưa kiểm tra"

    static func cloudHealth(ms: Int64) -> String {
        "\(cloudHealthGood) · \(max(0, ms)) ms"
    }

    // Errors (server parity)
    static let networkError = "Không kết nối được máy chủ."
    static let serverNotReady = "Máy chủ chưa sẵn sàng. Vui lòng thử lại."
    static let invalidResponse = "Máy chủ trả về dữ liệu không hợp lệ."
    static let unsupported = "Chưa hỗ trợ trên máy chủ này"
    static let unavailable = "Không khả dụng"
}
