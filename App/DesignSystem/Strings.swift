import Foundation
import MNGEdit
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
    static let logout = "Đăng xuất"
    static let signingOut = "Đang đăng xuất…"
    static let close = "Đóng"
    static let cancel = "Hủy"

    // Navigation
    static let brandSubtitle = "Thư viện riêng"
    static let navLibrary = "Thư viện"
    static let navAlbums = "Album"
    static let navSearch = "Tìm kiếm"
    static let navVault = "Kho mã hóa"
    static let navVaultTab = "Kho"
    static let navSettings = "Cài đặt"
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
    static let clearFilters = "Bỏ bộ lọc"
    static let select = "Chọn"
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
    static let viewerShare = "Chia sẻ"
    static let viewerSaveToPhotos = "Lưu vào Ảnh"
    static let viewerLiveText = "Live Text"
    static let viewerLiveTextWorking = "Đang nhận dạng chữ…"
    static let viewerLiveTextEmpty = "Không tìm thấy chữ trong ảnh này."
    static let viewerLiveTextFailed = "Không nhận dạng được chữ trong ảnh này."
    static let savedToPhotos = "Đã lưu vào thư viện Ảnh."
    static let saveToPhotosFailed = "Không lưu được vào thư viện Ảnh."

    // Selection and confirmations
    static let deselect = "Bỏ chọn"
    static let preparingZip = "Đang chuẩn bị tập ZIP."
    static let downloadFailed = "Không tải xuống được."
    static let zipFailed = "Không tạo được tập ZIP."

    // Saving into the cloud library
    static let backupToLibrary = "Lưu vào thư viện"
    static let backupTitle = "Đang lưu vào thư viện"
    static let backupDone = "Đã lưu vào thư viện"
    static let backupEmpty = "Không có ảnh nào để lưu."

    static func backupProgress(_ done: Int, _ total: Int) -> String {
        "\(done)/\(total)"
    }

    static func backupSummary(uploaded: Int, skipped: Int, failed: Int) -> String {
        "Đã lưu \(uploaded) mục · \(skipped) mục đã có sẵn · \(failed) mục chưa lưu được."
    }

    // Automatic photo backup
    static let backupSection = "Sao lưu ảnh"
    static let backupAutoTitle = "Sao lưu ảnh tự động"
    static let backupToggleBody = "Ảnh và video mới trên máy được tải lên thư viện ở nền."
    static let backupNote = "Sao lưu chạy trong nền và tiếp tục khi bạn đóng ảnh. Ảnh đã có trong thư viện được bỏ qua."
    static let backupStatus = "Trạng thái"
    static let backupStatusOff = "Đang tắt."
    static let backupStatusPermission = "Cần quyền truy cập thư viện ảnh."
    static let backupStatusScanning = "Đang tìm ảnh mới…"
    static let backupWifiOnly = "Chỉ khi có Wi-Fi"
    static let backupWifiOnlyBody = "Không dùng dữ liệu di động để sao lưu."
    static let backupVideos = "Sao lưu video"
    static let backupVideosBody = "Video mới trên máy cũng được tải lên."
    static let backupRunNow = "Sao lưu ngay"
    static let backupRunNowBody = "Quét thư viện ảnh và tải những gì còn thiếu."

    static func backupPending(_ count: Int) -> String {
        "\(count) mục đang chờ"
    }

    static func backupLastRun(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.day, .month, .year], from: date)
        let day = MNGFormat.itemDate(
            day: parts.day ?? 1,
            month: parts.month ?? 1,
            year: parts.year ?? 0
        )
        return "Lần cuối \(day)"
    }

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
    static let vaultUploadingProgress = "Đang tải lên — {done}/{total} khối"
    static let vaultPreviewTitle = "Xem trước"
    static let vaultPreviewNote = "Đã giải mã trong ứng dụng này"
    static let vaultPreviewUnsupported = "Trình duyệt không xem trước được định dạng này."
    static let vaultDecryptFailed = "Không giải mã được tệp."

    // Image editor
    static let editorTitle = "Chỉnh sửa ảnh"
    static let editorCropTab = "Cắt"
    static let editorAdjustTab = "Chỉnh màu"
    static let editorTuneTab = "Tinh chỉnh"
    static let editorFilterTab = "Bộ lọc"
    static let editorGeometry = "Xoay và lật"
    static let editorRotateLeft = "Trái"
    static let editorRotateRight = "Phải"
    static let editorFlipH = "Ngang"
    static let editorFlipV = "Dọc"
    static let editorAspect = "Tỉ lệ khung"
    static let editorAspectFree = "Tự do"
    static let editorCropHint =
        "Kéo khung hoặc các góc để chọn vùng cắt, sau đó bấm Áp dụng."
    static let editorCropReset = "Đặt lại"
    static let editorCropApply = "Áp dụng vùng cắt"
    static let editorAdjustReset = "Đặt lại thông số"
    static let editorBrightness = "Độ sáng"
    static let editorContrast = "Tương phản"
    static let editorSaturation = "Độ bão hòa"
    static let editorExposure = "Phơi sáng"
    static let editorWarmth = "Độ ấm"
    static let editorTint = "Sắc độ"
    static let editorHighlights = "Vùng sáng"
    static let editorShadows = "Vùng tối"
    static let editorVignette = "Viền mờ"
    static let editorWhites = "Điểm trắng"
    static let editorBlacks = "Điểm đen"
    static let editorVibrance = "Độ sống động"
    static let editorGamma = "Gamma"
    /// The short names of the adjustments, the ones on the chips.
    static let editorBrightnessShort = "Sáng"
    static let editorContrastShort = "Tương phản"
    static let editorSaturationShort = "Bão hòa"
    static let editorExposureShort = "Phơi sáng"
    static let editorWarmthShort = "Ấm"
    static let editorTintShort = "Sắc thái"
    static let editorHighlightsShort = "Vùng sáng"
    static let editorShadowsShort = "Vùng tối"
    static let editorWhitesShort = "Trắng"
    static let editorBlacksShort = "Đen"
    static let editorVibranceShort = "Sống động"
    static let editorGammaShort = "Gamma"
    static let editorVignetteShort = "Mờ góc"
    static let editorFilterOriginal = "Nguyên bản"
    static let editorFilterVivid = "Sống động"
    static let editorFilterWarm = "Ấm"
    static let editorFilterCool = "Lạnh"
    static let editorFilterMono = "Đen trắng"
    static let editorFilterDramatic = "Kịch tính"
    static let editorFilterVintage = "Cổ điển"
    // Filter categories
    static let editorFilterCatAll = "Tất cả"
    static let editorFilterCatRoot = "Chuẩn"
    static let editorFilterCatMeitu = "Meitu"
    static let editorFilterCatXingtu = "Xingtu"
    static let editorFilterCatLr = "Lightroom"
    static let editorFilterCatMono = "Đen trắng"
    // Adjust group captions
    static let editorGroupLight = "Ánh sáng"
    static let editorGroupColor = "Màu"
    static let editorGroupEffect = "Hiệu ứng"
    // Tone tuning
    static let editorTuneTitle = "Tùy chỉnh tone"
    static let editorTuneHint = "Chọn tone, kéo slider để tinh chỉnh rồi Lưu."
    static let editorTuneReset = "Reset tone"
    // Saved filter presets
    static let editorPresetName = "Tên bộ lọc…"
    static let editorPresetSave = "Lưu"
    static let editorPresetSavedTitle = "Bộ lọc đã lưu"
    static let editorPresetSaved = "Đã lưu bộ lọc."
    static let editorPresetExists = "Tên này đã có — chọn tên khác"
    static let editorPresetApplied = "Đã áp dụng bộ lọc."
    static let editorPresetDeleted = "Đã xoá bộ lọc."
    static let editorPresetReset = "Đã tắt bộ lọc."
    static let editorPresetDelete = "Xoá bộ lọc"
    // Text
    static let editorTextTab = "Chữ"
    static let editorTextPlace = "Chạm đặt"
    static let editorTextInput = "Nội dung chữ…"
    static let editorTextTitle = "Kiểu chữ"
    static let editorTextTitleBold = "Chữ đậm"
    static let editorTextCaption = "Chú thích"
    static let editorTextOutlineStyle = "Viền nổi"
    static let editorTextColor = "Màu chữ"
    static let editorTextBold = "Đậm"
    static let editorTextItalic = "Nghiêng"
    static let editorTextOutline = "Viền"
    static let editorTextShadow = "Bóng đổ"
    static let editorTextDuplicate = "Nhân đôi"
    static let editorTextDelete = "Xoá chữ"
    static let editorTextOpacity = "Độ mờ"
    static let editorTextFrame = "Khung chữ"
    static let editorTextEmpty = "Chưa có chữ. Bấm Chạm đặt để bắt đầu."
    static let editorTextHint = "Chạm đúp vào chữ để sửa • Kéo để di chuyển • Chụm 2 ngón để co giãn"
    // AI
    static let editorAITab = "AI"
    static let editorAIModel = "Mô hình"
    static let editorAIModelQuality = "Chất lượng"
    static let editorAIModelBalanced = "Cân bằng"
    static let editorAIModelFast = "Nhanh"
    static let editorAIModelRecommended = "Khuyến nghị"
    static let editorAIBgTitle = "AI tách nền"
    static let editorAIBgRemove = "Xoá phông"
    static let editorAIBgPerson = "Tách người"
    static let editorAIBgBlur = "Mờ phông"
    static let editorAIBgReplace = "Nền trắng"
    static let editorAIRetouchTitle = "AI Retouch"
    static let editorAIRetouchWhiten = "Trắng da"
    static let editorAIRetouchSmooth = "Mịn da"
    static let editorAIRetouchBlemish = "Xóa mụn"
    static let editorAIRetouchTone = "Tông da"
    static let editorAIRetouchHair = "Đổi màu tóc"
    static let editorAISettings = "Tùy chỉnh retouch"
    static let editorAIStrength = "Mức độ"
    static let editorAITone = "Tông"
    static let editorAIHairColor = "Màu tóc"
    static let editorAIHairEspresso = "Nâu đen"
    static let editorAIHairBlack = "Đen"
    static let editorAIHairChestnut = "Hạt dẻ"
    static let editorAIHairCaramel = "Caramel"
    static let editorAIHairAuburn = "Đỏ nâu"
    static let editorAIHint = "AI chạy trên máy, ảnh không rời thiết bị."
    static let editorAIRunning = "Đang chạy AI…"
    static let editorAISegmenting = "Đang tách chủ thể…"
    static let editorAISegmentingPerson = "Đang tách người…"
    static let editorAICompositing = "Đang ghép nền…"
    static let editorAIFace = "Đang tìm khuôn mặt…"
    static let editorAIRetouchRunning = "Đang làm đẹp…"
    static let editorAIApplying = "Đang hoàn thiện…"
    static let editorAICancel = "Hủy AI"
    static let editorAINoSubject = "Không tìm thấy chủ thể để tách nền."
    static let editorAINoFace = "Không tìm thấy khuôn mặt rõ nét."
    static let editorAICancelled = "Đã hủy AI."
    static let editorAIFailed = "Không thể chạy AI."
    static let editorAIDoneCutout = "Đã tách nền. Lịch sử chỉnh sửa đã được đặt lại."
    static let editorAIDoneBackground = "Đã đổi nền. Lịch sử chỉnh sửa đã được đặt lại."
    static let editorAIDoneRetouch = "Đã retouch AI. Lịch sử chỉnh sửa đã được đặt lại."
    static let editorAIReverted = "Đã hoàn tác AI."
    static let editorAIRevert = "Hoàn tác AI"
    static let editorAITransparentNote =
        "Ảnh JPEG không lưu được nền trong suốt — chọn Nền trắng nếu cần."
    // Crop modes
    static let editorCropRatio = "Tỉ lệ"
    static let editorCropRotation = "Xoay"
    static let editorCropFree = "Tự do"
    static let editorCropScreen = "Màn hình"
    static let editorCropPerspectiveVertical = "Trên / dưới"
    static let editorCropPerspectiveHorizontal = "Trái / phải"
    static let editorFilterDefaultLabel = "Mặc định"
    static let editorUndo = "Hoàn tác"
    static let editorRedo = "Làm lại"
    static let editorAuto = "Tự động"
    static let editorAutoTitle = "Tự động tối ưu ảnh"
    static let editorAutoWorking = "Đang phân tích…"
    static let editorHoldOriginal = "Giữ để xem ảnh gốc"
    static let editorExportTitle = "Lưu ảnh"
    static let editorExportSub = "Kết xuất từ file gốc ở độ phân giải đầy đủ."
    static let editorFormat = "Định dạng"
    static let editorQuality = "Chất lượng"
    static let editorExporting = "Đang kết xuất ảnh."
    static let editorSaveMode = "Cách lưu"
    static let editorModeOverwrite = "Ghi đè ảnh gốc"
    static let editorModeCopy = "Lưu thành bản sao"
    static let editorSaveOverwrite = "Lưu đè"
    static let editorSaveCopy = "Lưu bản sao"
    static let editorCancel = "Hủy"
    static let editorSave = "Lưu ảnh"
    static let editorSaved = "Đã lưu ảnh."
    static let editorSavedCopy = "Đã lưu bản sao ảnh."
    static let editorSaveFailed = "Không lưu được ảnh."
    static let editorLoading = "Đang tải ảnh…"
    static let editorUnsupported = "Ảnh này không chỉnh sửa được."
    static let editorEditAction = "Chỉnh sửa"
    static let editorAurumTitle = "Aurum"
    static let editorAurumAction = "Aurum"

    // Administration
    static let adminTitle = "Quản trị người dùng"
    static let adminRowTitle = "Quản trị người dùng"
    static let adminRowBody = "Tạo tài khoản, cấp lại mật khẩu, quản lý dung lượng"
    static let adminCreate = "Tạo"
    static let adminCreateTitle = "Tạo người dùng"
    static let adminUsername = "Tên đăng nhập"
    static let adminDisplayName = "Tên hiển thị"
    static let adminPassword = "Mật khẩu"
    static let adminPasswordPlaceholder = "Ít nhất 8 ký tự"
    static let adminGeneratePassword = "Tạo mật khẩu ngẫu nhiên"
    static let adminProvision = "Tạo tài khoản cloud"
    static let adminProvisionHint =
        "Gọi admin API của máy chủ, sau đó lưu credential trên máy chủ."
    static let adminLoading = "Đang tải danh sách người dùng…"
    static let adminEmpty = "Chưa có người dùng nào."
    static let adminInactive = "Đã khoá"
    static let adminResetPassword = "Cấp lại mật khẩu"
    static let adminReprovision = "Cấp lại mật khẩu cloud"
    static let adminGrantRole = "Cấp quyền quản trị"
    static let adminRevokeRole = "Thu quyền quản trị"
    static let adminLockAccount = "Khoá tài khoản"
    static let adminUnlockAccount = "Mở khoá tài khoản"
    static let adminScan = "Quét lại thư viện"
    static let adminDelete = "Xoá người dùng"
    static let adminDeleteTitle = "Xoá người dùng?"
    static let adminDeleteCloudData = "Xoá luôn dữ liệu cloud"
    static let adminDeleteCloudDataHint =
        "Xoá cả thư viện ảnh trên máy chủ của người dùng."
    static let adminConfirm = "Xác nhận"
    static let adminCreateFailed = "Không tạo được người dùng."
    static let adminActionFailed = "Không thực hiện được thao tác."
    static let adminScanFailed = "Không quét được thư viện."
    static let adminRename = "Đổi tên"
    static let adminRenameTitle = "Đổi tên hiển thị"
    static let adminRenameMessage = "Tên mới hiển thị của tài khoản."
    static let adminSave = "Lưu"
    static let adminCopy = "Sao chép"
    static let adminCloudPassword = "Mật khẩu máy chủ"

    static func adminCreated(_ username: String) -> String {
        "Đã tạo \(username)."
    }

    static func adminPasswordUpdated(_ username: String) -> String {
        "Đã cập nhật mật khẩu cho \(username)."
    }

    static func adminReprovisioned(_ username: String) -> String {
        "Đã cấp lại mật khẩu cloud cho \(username)."
    }

    static func adminGranted(_ username: String) -> String {
        "Đã cấp quyền quản trị cho \(username)."
    }

    static func adminRevoked(_ username: String) -> String {
        "Đã thu quyền quản trị của \(username)."
    }

    static func adminUnlocked(_ username: String) -> String {
        "Đã mở khoá \(username)."
    }

    static func adminLocked(_ username: String) -> String {
        "Đã khoá \(username)."
    }

    static func adminRenamed(_ username: String) -> String {
        "Đã cập nhật \(username)."
    }

    static func adminDeleted(_ username: String) -> String {
        "Đã xoá \(username)."
    }

    static func adminScanQueued(_ username: String) -> String {
        "Đã bắt đầu quét thư viện của \(username)."
    }

    static func adminResetMessage(_ username: String) -> String {
        "Cấp lại mật khẩu cho \(username)."
    }

    static func adminReprovisionMessage(_ username: String) -> String {
        "Cấp lại mật khẩu cho kho của \(username)."
    }

    static func adminDeleteMessage(_ username: String) -> String {
        "Xoá người dùng “\(username)”?"
    }
    static let vaultFileLabel = "Tệp"
    static let vaultImageLabel = "Ảnh"
    static let vaultVideoLabel = "Video"
    static let vaultStale = "Kho đã thay đổi ở phiên khác. Hãy thử lại."
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

    /// Title of one editor filter chip.
    static func editorFilterTitle(_ filter: EditorFilter) -> String {
        switch filter {
        case .original: return "Nguyên bản"
        case .vivid: return "Sống động"
        case .dramatic: return "Kịch tính"
        case .mono: return "Đen trắng"
        case .vintage: return "Cổ điển"
        case .warm: return "Ấm"
        case .cool: return "Lạnh"
        case .meituNatural: return "Tự nhiên"
        case .meituKorea: return "Hàn Quốc"
        case .meituJapan: return "Nhật Bản"
        case .meituSkin: return "Sáng da"
        case .meituPink: return "Hồng đào"
        case .meituWhite: return "Trắng sáng"
        case .xingtuFilm: return "Điện ảnh"
        case .xingtuHK: return "Hồng Kông"
        case .xingtuShowa: return "Chiêu Hoà"
        case .xingtuKama: return "Kamakura"
        case .xingtuNight: return "Ban đêm"
        case .xingtuMorning: return "Buổi sáng"
        case .lrCinema: return "Cinematic"
        case .lrMoody: return "Moody"
        case .lrVibrant: return "Vibrant"
        case .lrPastel: return "Pastel"
        case .lrDesert: return "Sa mạc"
        case .lrStreet: return "Đường phố"
        case .lrFaded: return "Mờ phai"
        case .lrTeal: return "Teal"
        case .monoWarm: return "Đen trắng ấm"
        case .monoCool: return "Đen trắng lạnh"
        }
    }

    /// The one-line hint under the category rail, the web `hint` of the preset.
    static func editorFilterHint(_ filter: EditorFilter) -> String {
        switch filter {
        case .original: return "Không đổi màu"
        case .meituNatural: return "Meitu · Sáng nhẹ, giữ tông da tự nhiên"
        case .meituKorea: return "Meitu · Da hồng sáng, tương phản mềm"
        case .meituJapan: return "Meitu · Trong vắt, đỡ gắt"
        case .meituSkin: return "Meitu · Nâng sáng vùng da, giữ chi tiết"
        case .meituPink: return "Meitu · Hồng ấm, hợp chân dung"
        case .meituWhite: return "Meitu · Sáng tinh khôi, giảm bão hoà nhẹ"
        case .xingtuFilm: return "Xingtu · Teal–orange mềm, hợp đường phố"
        case .xingtuHK: return "Xingtu · Đêm đô thị, xanh lạnh"
        case .xingtuShowa: return "Xingtu · Hoài cổ, phai màu nhẹ"
        case .xingtuKama: return "Xingtu · Bình minh biển, ấm sáng"
        case .xingtuNight: return "Xingtu · Đêm sâu, giữ bóng tối"
        case .xingtuMorning: return "Xingtu · Nắng sớm, ấm và trong"
        case .lrCinema: return "Lightroom · Điện ảnh tương phản mạnh"
        case .lrMoody: return "Lightroom · Ẩm ướt, bóng gắt"
        case .lrVibrant: return "Lightroom · Màu rực, hợp phong cảnh"
        case .lrPastel: return "Lightroom · Nhẹ, trong, chữ chụp đồ"
        case .lrDesert: return "Lightroom · Vàng cát ấm"
        case .lrStreet: return "Lightroom · Grit, hợp street life"
        case .lrFaded: return "Lightroom · Film phai, giảm tương phản"
        case .lrTeal: return "Lightroom · Xanh teal mát"
        case .monoWarm: return "Đen trắng · Ấm hạt"
        case .monoCool: return "Đen trắng · Lạnh, gắt"
        case .vivid, .dramatic, .mono, .vintage, .warm, .cool:
            return "Chuẩn · Cân bằng màu của Aurum"
        }
    }

    /// The label of a filter category chip.
    static func editorFilterCategoryTitle(_ category: EditorFilterCategory) -> String {
        switch category {
        case .root: return editorFilterCatRoot
        case .meitu: return editorFilterCatMeitu
        case .xingtu: return editorFilterCatXingtu
        case .lr: return editorFilterCatLr
        case .mono: return editorFilterCatMono
        }
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
    static let icloudUnsupportedServer = "Máy chủ này chưa cung cấp trình tải iCloud."
    static let icloudUnsupportedHint =
        "Máy chủ chưa bật trình tải iCloud. Quản trị viện cần cấu hình icloudpd trước khi đăng nhập."
    static let icloudUnsupportedAction = "Máy chủ này chưa hỗ trợ thao tác iCloud."
    static let icloudNetworkFailed = "Không kết nối được máy chủ."
    static let icloudCheckFailed = "Không kiểm tra được iCloud."
    static let icloudActionFailed = "Không thực hiện được thao tác iCloud."
    static let icloudServerError = "Máy chủ trả về lỗi %d."
    static let icloudLoginTitle = "Đăng nhập iCloud"
    static let icloudLogin = "Đăng nhập"
    static let icloudPassword = "Mật khẩu"
    static let icloudAppleIDPlaceholder = "apple@example.com"
    static let icloudPasswordPlaceholder = "Mật khẩu Apple ID"
    static let icloudMFA = "Mã 2FA"
    static let icloudMFAHint =
        "Mật khẩu chỉ được dùng để đăng nhập và không được lưu. Nếu tài khoản bật 2FA, bạn sẽ nhập mã ở bước tiếp theo."
    static let icloudMFAPlaceholder = "6 chữ số"
    static let icloudSendMFA = "Gửi mã"
    static let icloudRecent = "Số ảnh gần đây"
    static let icloudDeleteAfter = "Xoá ảnh sau khi nhập"
    static let icloudDeleteAfterHint =
        "Ảnh sẽ bị xoá ngay khi tải xong và thu mục tạm, trước khi nhập xong vào máy chủ."
    static let icloudSaveSettings = "Lưu thiết lập"
    static let icloudStart = "Bắt đầu tải ảnh"
    static let icloudPause = "Tạm dừng"
    static let icloudResume = "Tiếp tục"
    static let icloudCancel = "Huỷ"
    static let icloudLogout = "Đăng xuất iCloud"
    static let icloudLoggedOut = "Đã ngắt kết nối iCloud."
    static let icloudLog = "Nhật ký"
    static let icloudStateQueued = "Đang chờ"
    static let icloudStateRunning = "Đang chạy"
    static let icloudStateAwaitingMFA = "Cần mã 2FA"
    static let icloudStateAwaitingPassword = "Cần mật khẩu"
    static let icloudStatePaused = "Tạm dừng"
    static let icloudStateImporting = "Đang nhập"
    static let icloudStateDone = "Hoàn tất"
    static let icloudStateError = "Lỗi"
    static let icloudStateCancelled = "Đã huỷ"
    static let icloudStateAuthRequired = "Cần đăng nhập"
    static let icloudStateAuthenticated = "Đã kết nối"
    static let icloudStateWaiting = "Chờ"

    static func icloudImported(_ count: Int64) -> String {
        "Đã nhập \(MNGFormat.number(count)) mục"
    }
    static let webdavCopy = "Sao chép"
    static let webdavCopied = "Đã sao chép liên kết WebDAV."
    static let cloudHealthGood = "Kết nối tốt"
    static let cloudHealthBad = "Không phản hồi"
    static let cloudHealthUnknown = "Chưa kiểm tra"

    static func cloudHealth(ms: Int64) -> String {
        "\(cloudHealthGood) · \(max(0, ms)) ms"
    }

}
