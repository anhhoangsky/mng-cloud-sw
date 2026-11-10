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

    // Native vault
    static let vaultTitle = "Kho mã hóa"
    static let vaultCreate = "Tạo kho"
    static let vaultRefresh = "Làm mới"
    static let vaultLoading = "Đang tải kho mã hóa…"
    static let vaultLoadFailed = "Không tải được kho mã hóa"
    static let vaultEmptyTitle = "Chưa có kho mã hóa"
    static let vaultEmptyBody = "Tạo kho trên máy chủ, sau đó làm mới danh sách này."
    static let vaultNoteServer =
        "Máy chủ chỉ lưu các khối đã mã hóa AES-256-GCM. Mật khẩu và chìa khóa chỉ tồn tại trong ứng dụng này."
    static let vaultNoteChunks =
        "Nội dung tệp được chia thành khối 4 MiB, mã hóa AES-256-GCM và chỉ giải mã trong ứng dụng này."
    static let vaultNoIndex = "Chưa có chỉ mục"
    static let vaultRootName = "Kho"
    static let vaultUnlock = "Mở khóa"
    static let vaultUnlocking = "Đang mở khóa…"
    static let vaultUnlockBody =
        "Mật khẩu chỉ tạo chìa khóa PBKDF2 trong ứng dụng này; mật khẩu và chìa khóa không được gửi tới máy chủ."
    static let vaultPassword = "Mật khẩu mã hóa"
    static let vaultPasswordPlaceholder = "Nhập mật khẩu của kho"
    static let vaultPasswordMissing = "Hãy nhập mật khẩu mã hóa."
    static let vaultPasswordShort = "Mật khẩu cần ít nhất 8 ký tự."
    static let vaultPasswordMismatch = "Mật khẩu xác nhận không khớp."
    static let vaultWrongPassword = "Mật khẩu không đúng."
    static let vaultDeleteWrongPassword = "Mật khẩu mã hóa không đúng."
    static let vaultUnlockFailed = "Không mở khóa được kho."
    static let vaultInvalidIterations = "Số vòng PBKDF2 không hợp lệ."
    static let vaultInvalidSalt = "Muối mã hóa không hợp lệ."
    static let vaultInvalidVerifier = "Mã xác thực của kho không hợp lệ."
    static let vaultInvalidMetadata = "Siêu dữ liệu kho không hợp lệ."
    static let vaultManifestInvalid = "Chỉ mục mã hóa không hợp lệ hoặc đã bị thay đổi."
    static let vaultNoIndexTitle = "Kho này chưa có chỉ mục mã hóa."
    static let vaultNoIndexBody = "Chủ kho cần tạo chỉ mục trước khi kho có thể mở khóa."
    static let vaultBackToList = "Danh sách kho"
    static let vaultCreateTitle = "Tạo kho mã hóa"
    static let vaultCreateBody =
        "Tên kho, tên tệp và nội dung chỉ được lưu dưới dạng mã hóa trên máy chủ."
    static let vaultName = "Tên kho"
    static let vaultNameMissing = "Hãy nhập tên kho."
    static let vaultNamePlaceholder = "Ví dụ: Kho gia đình"
    static let vaultConfirmPassword = "Nhập lại mật khẩu"
    static let vaultCreating = "Đang tạo kho…"
    static let vaultCreateHint =
        "Mật khẩu không thể khôi phục. Nếu quên, dữ liệu trong kho sẽ không giải mã được."
    static let vaultCreated = "Đã tạo kho mã hóa."
    static let vaultDeleteTitle = "Xóa kho mã hóa?"
    static let vaultDeleting = "Đang xóa…"
    static let vaultDeleteHint =
        "Mật khẩu chỉ kiểm tra chìa khóa trong kho này; mật khẩu và chìa khóa không được gửi tới máy chủ."
    static let vaultFolder = "Thư mục"
    static let vaultUpload = "Tải lên"
    static let vaultLock = "Khóa"
    static let vaultRename = "Đổi tên"
    static let vaultRenameTitle = "Đổi tên kho"
    static let vaultSearchPlaceholder = "Tìm trong kho đã mã hóa…"
    static let vaultSearchEmptyTitle = "Không tìm thấy"
    static let vaultSearchEmptyBody = "Không có mục nào khớp với từ khóa."
    static let vaultEmptyFolderTitle = "Kho đang trống"
    static let vaultEmptyFolderBody = "Kho này chưa có tệp hoặc thư mục con."
    static let vaultCreateFolder = "Tạo thư mục"
    static let vaultFolderName = "Tên thư mục"
    static let vaultFolderPlaceholder = "Tên thư mục mới"
    static let vaultFolderCreating = "Đang tạo…"
    static let vaultFolderInvalid = "Tên thư mục không hợp lệ (tối đa 80 ký tự)."
    static let vaultFolderExists = "Thư mục này đã tồn tại."
    static let vaultFileInvalid = "Tên tệp không hợp lệ."
    static let vaultFileEmpty = "Tệp rỗng chưa được hỗ trợ."
    static let vaultFileTooLarge = "Tệp vượt quá 16 GiB nên chưa thể mã hóa."
    static let vaultFileUnreadable = "Không đọc được tệp."
    static let vaultUploadPhotos = "Chọn ảnh"
    static let vaultUploadFiles = "Chọn tệp"
    static let vaultUploading = "Đang mã hóa"
    static let vaultUploadingProgress = "Đang tải lên — {done}/{total} khối"
    static let vaultPreviewTitle = "Xem trước"
    static let vaultPreviewFile = "Tệp"
    static let vaultPreviewNote = "Đã giải mã trong ứng dụng này"
    static let vaultPreviewUnsupported = "Trình duyệt không xem trước được định dạng này."
    static let vaultPreviewFailed = "Không mở được tệp"
    static let vaultDecryptFailed = "Không giải mã được tệp."
    static let vaultFileLabel = "Tệp"
    static let vaultImageLabel = "Ảnh"
    static let vaultVideoLabel = "Video"
    static let vaultUnlockFailedTitle = "Không mở khóa được kho"
    static let vaultStale = "Kho đã thay đổi ở phiên khác. Hãy thử lại."
    static let vaultLockedNotice = "Kho đã khoá. Nhập mật khẩu để tiếp tục."
    static let vaultDeleted = "Đã xoá kho mã hóa."
    static let vaultFileDeleted = "Đã xoá tệp khỏi chỉ mục."
    static let vaultFolderDeleted = "Đã xoá thư mục khỏi chỉ mục."

    static func vaultMeta(id: Int64, bytes: Int64) -> String {
        "#\(id) • \(MNGFormat.bytes(bytes)) đã mã hóa"
    }

    static func vaultSubtitle(files: Int, bytes: Int64) -> String {
        "\(MNGFormat.number(Int64(files))) tệp • \(MNGFormat.bytes(bytes)) • đã mở khóa"
    }

    static func vaultFolderCount(_ count: Int) -> String {
        "\(MNGFormat.number(Int64(count))) tệp"
    }

    static func vaultFolderPath(_ path: String) -> String {
        "Trong: \(path)"
    }

    static func vaultFolderCreated(_ name: String) -> String {
        "Đã tạo thư mục “\(name)”."
    }

    static func vaultUploaded(_ name: String) -> String {
        "Đã tải lên “\(name)” vào kho mã hóa."
    }

    static func vaultMoved(_ count: Int) -> String {
        "Đã chuyển \(MNGFormat.number(Int64(count))) mục vào kho mã hóa."
    }

    static func vaultMoveWaiting(_ count: Int) -> String {
        "Có \(MNGFormat.number(Int64(count))) mục chờ chuyển vào kho. Mở khoá một kho để tiếp tục."
    }

    static func vaultRenamed(_ name: String) -> String {
        "Đã đổi tên kho thành “\(name)”."
    }

    static func vaultDecrypting(_ done: Int, _ total: Int) -> String {
        "Đang giải mã \(done)/\(total) khối."
    }

    static func vaultDecoded(bytes: Int64) -> String {
        "\(MNGFormat.bytes(bytes)) • \(vaultPreviewNote)"
    }

    static func vaultDeleteBody(_ name: String) -> String {
        "Kho “\(name)” cùng toàn bộ thư viện trên máy chủ của kho sẽ bị xóa vĩnh viễn. Chỉ mục mã hóa, tệp và thư mục bên trong không thể khôi phục."
    }

    static func vaultFileMeta(_ label: String, _ bytes: Int64) -> String {
        "\(label) • \(MNGFormat.bytes(bytes))"
    }

    static func vaultFileMetaPath(_ path: String, _ bytes: Int64) -> String {
        "\(path) • \(MNGFormat.bytes(bytes))"
    }

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
