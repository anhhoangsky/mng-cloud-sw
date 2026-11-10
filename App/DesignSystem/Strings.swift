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

    // Navigation
    static let navLibrary = "Thư viện"
    static let navAlbums = "Album"
    static let navVault = "Kho mã hóa"
    static let navSettings = "Cài đặt"
    static let navAdmin = "Quản trị"

    // Library
    static let filterAll = "Tất cả"
    static let filterPhotos = "Ảnh"
    static let filterVideos = "Video"
    static let filterLive = "Live"
    static let filterFavorites = "Yêu thích"
    static let select = "Chọn"
    static let cancel = "Hủy"
    static let save = "Lưu"

    // Errors (server parity)
    static let networkError = "Không kết nối được máy chủ."
    static let serverNotReady = "Máy chủ chưa sẵn sàng. Vui lòng thử lại."
    static let invalidResponse = "Máy chủ trả về dữ liệu không hợp lệ."
    static let unsupported = "Chưa hỗ trợ trên máy chủ này"
    static let unavailable = "Không khả dụng"
}
