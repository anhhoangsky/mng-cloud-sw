import Foundation

/// AI strings that live with the engine code. Keeping them here means the
/// native model work does not touch the shared string table used by the
/// backup and library screens.
extension Strings {
    static let editorAIModelMaximum = "Tối đa"

    // Model store errors
    static let editorAIModelNotInstalled = "Mô hình chưa được tải."
    static let editorAIDownloadFailed =
        "Không tải được mô hình. Kiểm tra kết nối và thử lại."
    static let editorAIModelChecksum =
        "Tệp mô hình không khớp mã kiểm tra. Đã chặn cài đặt."
    static let editorAIModelWrongSize =
        "Tệp mô hình tải về không đúng dung lượng."
    static let editorAIModelUnpack = "Không giải nén được mô hình."
    static let editorAIModelIncompatible =
        "Mô hình không tương thích với phiên bản ứng dụng."
    static let editorAIModelCompile = "Không biên dịch được mô hình cho thiết bị."
    static let editorAIModelCorrupt = "Mô hình đã cài bị hỏng. Hãy tải lại."

    static func editorAIModelDisk(required: Int, available: Int) -> String {
        "Cần khoảng \(required) MB trống, chỉ còn \(available) MB."
    }

    // Download sheet
    static func editorAIModelDownloadBody(
        name: String,
        megabytes: Int
    ) -> String {
        "\(name) giúp viền tóc và vùng trong suốt chính xác hơn. "
            + "Dung lượng tải khoảng \(megabytes) MB, chỉ tải một lần."
    }
    static func editorAIModelDownloadLicense(_ license: String) -> String {
        "Giấy phép \(license) · Mô hình chạy hoàn toàn trên máy."
    }
    static let editorAIModelDownloadAction = "Tải mô hình"
    static let editorAIModelDownloadLater = "Để sau"
    static let editorAIModelDownloading = "Đang tải mô hình…"
    static let editorAIModelInstalling = "Đang cài mô hình…"
    static func editorAIModelReady(_ name: String) -> String {
        "Đã cài \(name). Lần tách nền sau sẽ dùng mô hình này."
    }
    static let editorAIModelDownloadCancelled = "Đã hủy tải mô hình."
    static let editorAIModelNeedsWiFi = "Cần Wi-Fi để tải mô hình này."
    static let editorAIDetecting = "Đang nhận diện chủ thể…"
}
