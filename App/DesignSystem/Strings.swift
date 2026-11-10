import Foundation

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
    static let accountSection = "Tài khoản"
    static let serverSection = "Máy chủ"
    static let storageSection = "Dung lượng"
    static let versionSection = "Phiên bản"
    static let displayName = "Tên hiển thị"
    static let username = "Tên đăng nhập"
    static let serverAddress = "Địa chỉ máy chủ"
    static let activeCloudLabel = "Đám mây đang dùng"
    static let appVersion = "MNG Cloud"
    static let freeSpace = "trống"
    static let settingsNote = "Thông tin đăng nhập được lưu trên máy chủ, không lưu trong trình duyệt."
    static let serverOpen = "Mở máy chủ"
    static let serverOpenBody = "Quản lý thư viện, chia sẻ và tệp gốc"
    static let cacheSection = "Bộ nhớ đệm"
    static let clearThumbnails = "Xóa bộ nhớ đệm ảnh thu nhỏ"
    static let thumbnailsCleared = "Đã xóa bộ nhớ đệm ảnh thu nhỏ."
    static let buildLabel = "Bản dựng"
    static let storageFree = "Dung lượng trống"

    // Placeholders
    static let albumsSubtitle = "Ảnh gần đây, yêu thích, khuôn mặt và địa điểm"
    static let searchSubtitle = "Theo tên tệp, album hoặc loại"
    static let vaultSubtitle = "Mã hóa đầu cuối, chìa khóa chỉ ở thiết bị"
    static let comingSoon = "Tính năng đang được xây dựng."
    static let comingSoonHint = "Phần này sẽ có ở giai đoạn tiếp theo."

    // Errors (server parity)
    static let networkError = "Không kết nối được máy chủ."
    static let serverNotReady = "Máy chủ chưa sẵn sàng. Vui lòng thử lại."
    static let invalidResponse = "Máy chủ trả về dữ liệu không hợp lệ."
    static let unsupported = "Chưa hỗ trợ trên máy chủ này"
    static let unavailable = "Không khả dụng"
}
