import Foundation

/// Error shape returned by the `mngd` client API.
///
/// Mirrors `ui/src/api.rs::ApiError`: `status == 0` means the request never
/// reached the server, `code` is the server's `error` field (or `http_{status}`
/// when the body is not the shared `{error, message}` shape) and `message` is
/// already the Vietnamese sentence the UI should show.
public struct APIError: Error, Equatable, Sendable, LocalizedError {
    public static let networkCode = "network"
    public static let invalidResponseCode = "invalid_response"

    public let status: Int
    public let code: String
    public let message: String

    public init(status: Int, code: String, message: String) {
        self.status = status
        self.code = code
        self.message = message
    }

    /// The request failed before a response arrived (offline, TLS, timeout…).
    public static func network() -> APIError {
        APIError(
            status: 0,
            code: networkCode,
            message: APIMessages.network
        )
    }

    /// A 2xx response whose body was not the expected JSON object.
    public static func invalid(status: Int) -> APIError {
        APIError(
            status: status,
            code: invalidResponseCode,
            message: APIMessages.invalidResponse
        )
    }

    public var isNetwork: Bool { status == 0 }
    public var isUnauthorized: Bool { status == 401 }
    public var isForbidden: Bool { status == 403 }
    public var isUnavailable: Bool { status == 503 }

    /// True when the server explicitly reports a stale/missing CSRF token.
    public var isCSRFFailure: Bool {
        status == 403 && code == "csrf"
    }

    public var errorDescription: String? { message }
}

/// Vietnamese copy shared by the API layer and the session state machine.
/// Values are copied verbatim from `ui/src/components/login.rs` and
/// `ui/src/app.rs`.
public enum APIMessages {
    public static let network = "Không kết nối được máy chủ."
    public static let invalidResponse = "Máy chủ trả về dữ liệu không hợp lệ."
    public static let bootNetwork = "Không kết nối được máy chủ."
    public static let bootUnavailable = "Máy chủ chưa sẵn sàng. Vui lòng thử lại."
    public static let bootFailed = "Không kiểm tra được phiên đăng nhập. Vui lòng thử lại."
    public static let loginNetwork = "Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại."
    public static let loginFallback = "Không đăng nhập được. Vui lòng thử lại."
    public static let usernameRequired = "Nhập tên đăng nhập để tiếp tục."
    public static let passwordRequired = "Nhập mật khẩu để tiếp tục."
    public static let serverRequired = "Nhập địa chỉ máy chủ để tiếp tục."
    public static let logoutNetwork = "Mất kết nối tới máy chủ."
    public static let logoutFailed = "Không đăng xuất được. Vui lòng thử lại."

    // Library error copy, from `item_error()`, `older_error()` and
    // `bootstrap_error()` in `shell.rs`.
    public static let itemListFailed = "Không tải được danh sách ảnh và video."
    public static let olderPageFailed = "Không tải thêm được ảnh cũ."
    public static let bootstrapFailed = "Không tải được thông tin thư viện."

    /// Login card copy.
    public static func login(_ error: APIError) -> String {
        if error.status == 0 {
            return loginNetwork
        }
        let message = error.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? loginFallback : message
    }

    /// Boot screen copy, matching `boot_message()` in the PWA.
    public static func boot(_ error: APIError) -> String {
        switch error.status {
        case 0:
            return bootNetwork
        case 503:
            return bootUnavailable
        default:
            return bootFailed
        }
    }

    /// Logout toast copy, matching `logout_error()` in the PWA shell.
    public static func logout(_ error: APIError) -> String {
        error.status == 0 ? logoutNetwork : logoutFailed
    }

    /// Initial/refresh item page error, matching `item_error()`.
    public static func itemList(_ error: APIError) -> String {
        error.status == 0 ? network : itemListFailed
    }

    /// "Load older" error, matching `older_error()`.
    public static func olderPage(_ error: APIError) -> String {
        error.status == 0 ? network : olderPageFailed
    }

    /// Bootstrap error, matching `bootstrap_error()`.
    public static func bootstrap(_ error: APIError) -> String {
        error.status == 0 ? network : bootstrapFailed
    }

    // MARK: - Bulk action toasts

    /// Single/multi favorite result. Capitalization matches the PWA.
    public static func favoriteChanged(_ value: Bool, count: Int) -> String {
        if count <= 1 {
            return value ? "Đã thêm vào Yêu thích." : "Đã bỏ Yêu thích."
        }
        return value
            ? "Đã thêm yêu thích \(count) mục."
            : "Đã bỏ yêu thích \(count) mục."
    }

    /// Some favorite requests failed after the optimistic update.
    public static func favoritePartial(done: Int, total: Int, failed: Int) -> String {
        "Đã cập nhật \(done)/\(total) mục. \(failed) mục chưa đổi được."
    }

    /// Single/multi delete result.
    public static func deleted(count: Int) -> String {
        count <= 1 ? "Đã xóa khỏi đám mây." : "Đã xóa \(count) mục."
    }

    /// Some delete requests failed; the rows are restored.
    public static func deletePartial(removed: Int, total: Int, failed: Int) -> String {
        "Đã xóa \(removed)/\(total) mục. \(failed) mục chưa xóa được."
    }
}
