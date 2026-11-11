# Cài app native lên iPhone (không cần máy Mac)

App `MNG Cloud` là app **SwiftUI native**, nên không chạy được trên Expo/React
Native. Cách test trên iPhone mà không cần máy Mac là để GitHub Actions build
một bản `.ipa` đã ký, rồi cài bằng Sideloadly/AltStore.

## 1. Chuẩn bị tài khoản Apple (miễn phí)

1. Tạo tài khoản tại <https://developer.apple.com> (tài khoản Apple ID miễn phí
   là đủ, không cần trả 99 USD/năm).
2. Vào **Account Holder** (hoặc **Membership**) để lấy **Team ID** (10 ký tự).
3. Vào **Keys → Access Keys → +** để tạo một **App Store Connect API Key**:
   - quyền **App Manager** (hoặc Admin),
   - tải file `AuthKey_XXXXXXXXXX.p8`.
4. Vào **Devices → +** để đăng ký iPhone của bạn:
   - cần **UDID** của máy (xem mục bên dưới),
   - đặt tên bất kỳ, ví dụ `iPhone cua toi`.

### Lấy UDID của iPhone khi không có máy Mac

- **iMazing** (Windows) → chọn thiết bị → `More > Device Information` → *UDID*.
- Hoặc dùng **Apple Configurator 2** (macOS/Windows) → *Device Information*.
- Hoặc lấy UDID từ `pymobiledevice3`: `python -m pymobiledevice3 lockdown list`.

## 2. Thêm secrets cho repo

Vào **Settings → Secrets and variables → Actions → New repository secret**, tạo
4 biến sau:

| Tên secret | Giá trị |
| --- | --- |
| `APPLE_TEAM_ID` | Team ID 10 ký tự |
| `APP_STORE_CONNECT_KEY_ID` | phần `XXXXXXXXXX` của tên file `.p8` |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID (UUID) hiển thị cùng lúc tạo key |
| `APP_STORE_CONNECT_PRIVATE_KEY` | nội dung file `.p8` mã hóa **base64** |

Mã hóa base64 (PowerShell):

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXXXXXXXX.p8"))
```

## 3. Chạy workflow build

- **Actions → build-ios → Run workflow** → chọn `Release` → **Run**.
- Workflow dùng runner macOS của GitHub: XcodeGen sinh project, Xcode tự tạo
  chứng thư ký phát triển và provisioning profile (nhờ `-allowProvisioningUpdates`
  và API key), rồi xuất `.ipa`.
- Xong, tải artifact **MNGCloud-ipa** (giữ 30 ngày).

## 4. Cài lên iPhone

Trên **Windows**:

1. Tải [Sideloadly](https://sideloadly.io) (miễn phí) — hoặc AltStore.
2. Kéo file `.ipa` vào Sideloadly, nhập **Apple ID** của bạn + *app-specific
   password* (tạo tại <https://account.apple.com> → *Sign-in and security* →
   *App-specific passwords*), bấm **Start**.
3. Trên iPhone: **Cài đặt → Chung → VPN & Quản lý thiết bị** → *Trust* tài
   khoản của bạn → mở app.

Trên **macOS**: dùng **Apple Configurator** hoặc kéo `.ipa` vào **Finder** với
iPhone đã đăng nhập.

### Hạn dùng

Profile phát triển của tài khoản miễn phí hết hạn sau **7 ngày**. Hết hạn thì
app không mở được nữa — chạy lại workflow `build-ios` để có bản `.ipa` mới
(cùng Apple ID) rồi cài lại. Nếu bạn có account trả phí, đổi sang TestFlight
(bộ hồ sơ `release.yml` sẵn sàng cho việc đó).

## 5. Thử nhanh trong Simulator (không cần ký)

Workflow `ci` xuất artifact `MNGCloud-simulator` chứa app chưa ký cho
simulator. Mở bằng Xcode (Window → Devices) để chạy thử UI mà không cần
iPhone.

## Lưu ý về máy chủ

App cần một máy chủ `mngd` đã chạy (URL của box của bạn) và tài khoản MNG
Cloud để đăng nhập. Nếu chưa có, hãy dựng backend từ `mng-cloud-rs` trước —
app iOS là client thuần của API `/api/v1` đó.
