# Cài app MNG Cloud lên iPhone (không cần máy Mac)

App `MNG Cloud` là app **SwiftUI native**, nên không chạy được trong Expo/React
Native. Cách test trên iPhone mà **không cần máy Mac** là để GitHub Actions
build một bản `.ipa` đã ký, rồi cài bằng **AltStore** (AltStore tự ký lại
bằng Apple ID của bạn nên `.ipa` chỉ cần hợp lệ là cài được).

> Viết cho **Windows**. Người dùng macOS làm tương tự.

---

## 🔥 Cách nhanh nhất (3 việc, ~15 phút)

Workflow `build-ios` có sẵn đường ký **`apple-id`**: fastlane trên runner tự
tạo chứng thư phát triển, App ID và provisioning profile bằng Apple ID của
bạn. Bạn **không** cần OpenSSL, không cần tạo App ID, không cần tải `.p8`.

### Việc 1 — Đăng ký iPhone trong portal (bắt buộc)

Profile chỉ chứa được thiết bị đã đăng ký.

1. **Lấy UDID** (40 ký tự) trên Windows:
   - **iMazing** (miễn phí, <https://imazing.com>): cắm iPhone bằng cáp USB →
     lần đầu bấm **"Trust This Computer"** trên iPhone → chọn máy →
     **More** → *Device Information* → copy **UDID**.
   - hoặc **Apple Configurator 2** → *View → Device Information* → *UDID*.
2. <https://developer.apple.com/account/resources/devices> → chọn nhóm **iPhone**
   → **+** → *Device Name* tự do · *Platform* **iOS** · *Device Identifier*: dán
   UDID → **Continue** → **Register**.

### Việc 2 — Tạo app-specific password

<https://account.apple.com> → *Sign-in and security* → *App-specific passwords*
→ **+** → đặt tên (`MNG Cloud CI`) → **Create** → copy mã 16 ký tự
(xxxx-xxxx-xxxx-xxxx). Chỉ hiện **một lần**.

### Việc 3 — Thêm 4 secrets vào repo

Repo → **Settings → Secrets and variables → Actions** → **New repository
secret**:

| Tên secret | Giá trị |
| --- | --- |
| `APPLE_ID` | Apple ID của bạn (email) |
| `APPLE_APP_SPECIFIC_PASSWORD` | mã 16 ký tự ở Việc 2 |
| `APPLE_TEAM_ID` | Team ID 10 ký tự — <https://developer.apple.com/account> → bấm tên/email → **Membership Details** |
| `KEYCHAIN_PASSWORD` | chuỗi bất kỳ, ví dụ `mngcloud-keychain-2026` |

### Việc 4 — Chạy workflow → lấy .ipa → AltStore

1. **Actions → build-ios → Run workflow**: branch `main`, configuration
   `Release`, **signing = `apple-id`** → **Run workflow**.
2. Job xanh (~5–15 phút) → cuộn xuống **Artifacts** → **MNGCloud-ipa** → tải
   về (zip) → giải nén ra `MNGCloud.ipa`.
3. **Cài vào iPhone** (xem [§2](#2-cài-ipa-vào-iphone-bằng-altstore)).

> **Nếu fastlane lỗi** (ví dụ Apple ID bật 2FA và app-specific password bị
> từ chối), dùng đường **thủ công** ở [§3](#3-phương-án-thủ-công-nếu-fastlane-lỗi).

---

## 1. Vì sao không dùng được "Access Keys"?

Trang *Access Keys* (App Store Connect API key) **chỉ dành cho account Developer
trả phí 99 USD/năm** → tài khoản miễn phí sẽ thấy *"Access Unavailable"*.
Không sao: tài khoản miễn phí vẫn ký app iOS được, chỉ cần làm thủ công
(chứng thư + provisioning profile) — đường `apple-id` ở trên tự động hoá phần
đó.

## 2. Cài `.ipa` vào iPhone bằng AltStore

### Cách A — cài ngay trên iPhone (tiện nhất)

1. Gửi file `MNGCloud.ipa` sang iPhone: **AirDrop**, **iCloud Drive**, hoặc
   email cho chính mình (đính kèm).
2. Trên iPhone: mở **Files** → vào thư mục chứa file `.ipa` → bấm file →
   nó mở AltStore → **Install** (AltStore sẽ ký lại bằng Apple ID của bạn).
   - Nếu bấm file mà không mở AltStore: vào **AltStore → My Apps → +** → chọn
     file trong Files.
3. Chờ tới khi AltStore báo **Finished**, mở app trên màn hình chính.

### Cách B — cài từ PC

1. Cài **AltStore cho Windows**: <https://altstore.io> → *Download AltStore*.
   (AltStore cần **iTunes**/Apple Mobile Device Support để nhận ra iPhone.)
2. Mở AltStore → tab **My Apps** → **+** → chọn file `.ipa` đã tải → chờ
   **Finished**.

### Lần đầu mở app

1. Mở **MNG Cloud**.
2. Nếu báo chưa tin cậy: **Cài đặt → General → VPN & Device Management** →
   dòng *Developer App* (Apple ID của bạn) → **Trust**.
3. Đăng nhập bằng tài khoản MNG Cloud + URL máy chủ `mngd`
   (ví dụ `https://cloud.example.com`).

### Hạn 7 ngày

- Profile *development* (kể cả account trả phí) hết hạn sau **7 ngày** → app
  mở được nhưng server từ chối phiên.
- **AltStore tự làm mới** profile mỗi 7 ngày nếu iPhone vẫn kết nối cùng
  mạng Wi-Fi và bật *Refresh sideload* trong cài đặt AltStore → thường không
  cần build lại.
- Nếu AltStore không tự làm mới: chạy lại workflow `build-ios` → tải `.ipa` mới
  → cài lại (AltStore sẽ dùng profile cũ hết hạn? → cần *Refresh* trong
  AltStore hoặc xoá app rồi cài lại).

---

## 3. Phương án thủ công (nếu fastlane lỗi)

Làm tay chứng thư + provisioning profile rồi dùng `signing = manual` trong
workflow (cần 6 secrets).

### 3.1 Tạo CSR + khóa riêng (Git Bash trên Windows)

```bash
cd ~/Downloads
openssl req -new -newkey rsa:2048 -nodes \
  -keyout mngcloud-dev.key -out mngcloud-dev.csr \
  -subj "/CN=MNG Cloud Dev/email=you@example.com"
```

### 3.2 Upload CSR lên portal → nhận `.cer`

<https://developer.apple.com/account/resources/certificates> → **+** →
**Apple Development** → *Upload a certificate signing request* → chọn
`mngcloud-dev.csr` → **Continue** → **Register** → **Download** →
`certificate.cer`.

### 3.3 Ghép `.cer` + key thành `.p12`

```bash
cd ~/Downloads
openssl x509 -inform DER -in certificate.cer -out certificate.pem
openssl pkcs12 -export -out certificate.p12 \
  -inkey mngcloud-dev.key -in certificate.pem -password pass:MAT-KHAU
```

### 3.4 Tạo App ID

<https://developer.apple.com/account/resources/identifiers/list> → **App IDs** →
**+** → **App** → iOS → **Explicit** → bundle id `com.mngcloud.app` (khớp
`project.yml`) → Register.

### 3.5 Tạo provisioning profile

<https://developer.apple.com/account/resources/profiles> → **+** → **iOS App
Development** → chọn App ID → chọn iPhone → đặt tên (ví dụ `MNG Cloud Dev`) →
**Generate** → **Download** → `MNG Cloud Dev.mobileprovision`.
**Tên profile** (không phải tên file) dùng cho secret
`PROVISIONING_PROFILE_SPECIFIER`.

### 3.6 Mã hoá base64 (PowerShell)

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\Downloads\certificate.p12"))
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\Downloads\MNG Cloud Dev.mobileprovision"))
```

### 3.7 Secrets cho đường `manual`

| Secret | Giá trị |
| --- | --- |
| `APPLE_TEAM_ID` | Team ID 10 ký tự |
| `BUILD_CERTIFICATE_BASE64` | base64 `certificate.p12` |
| `BUILD_CERTIFICATE_PASSWORD` | mật khẩu đặt ở 3.3 |
| `PROVISIONING_PROFILE_BASE64` | base64 `.mobileprovision` |
| `PROVISIONING_PROFILE_SPECIFIER` | tên profile (3.5) |
| `KEYCHAIN_PASSWORD` | chuỗi bất kỳ |

Rồi chạy workflow với **signing = `manual`**.

---

## 4. Phương án tự động (API key — cần account trả phí)

1. <https://developer.apple.com/account/resources/keys> → *Access Keys* → **+** →
   *Key Access*: **App Manager** → **Register** → tải `AuthKey_XXX.p8`
   (**chỉ tải được 1 lần**).
2. Lấy **Key ID** (10 ký tự sau `AuthKey_`) và **Issuer ID** trên trang Keys.
3. Secrets: `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`,
   `APP_STORE_CONNECT_PRIVATE_KEY` (base64 của `.p8`).
4. Chạy workflow với **signing = `automatic`** → Xcode tự tạo chứng thư +
   profile trên runner.

---

## 5. Xử lý sự cố

| Triệu chứng | Nguyên nhân | Cách sửa |
| --- | --- | --- |
| "Access Unavailable" ở trang Keys | Access Keys cần account **trả phí** | Dùng đường `apple-id` hoặc `manual` |
| "Missing APPLE_ID … secrets" | Thiếu/sai tên secret | Kiểm tra lại 4 secret (đường apple-id) |
| fastlane: "Could not login to Apple" | App-specific password sai, hoặc Apple ID bật 2FA | Tạo lại app-specific password; nếu vẫn lỗi dùng đường `manual` |
| "No profiles for 'com.mngcloud.app'" | Profile không chứa App ID | fastlane tạo App ID tự động; nếu thủ công thì tạo App ID ở 3.4 |
| "Provisioning profile doesn't include device" | Chưa đăng ký UDID | Đăng ký iPhone (Việc 1) rồi chạy lại workflow |
| "Unable to authenticate" khi Sideloadly/AltStore | Sai app-specific password / Apple ID | Tạo lại mật khẩu, đồng bộ iCloud với AltStore |
| "Device not found" | Chưa bấm "Trust This Computer" | Mở khoá máy, chấp nhận Trust, thử lại |
| App mở ra rồi báo lỗi đăng nhập | Profile hết hạn 7 ngày | Bật *Refresh sideload* trong AltStore hoặc cài lại `.ipa` mới |
| Không đăng nhập được dù app mở | Chưa có máy chủ `mngd` hoặc sai URL | Dựng backend từ `mng-cloud-rs`, kiểm tra URL |

---

## 6. Xem giao diện mà không cần cài gì

Workflow `ci` xuất artifact **MNGCloud-simulator** chứa app **chưa ký** cho
simulator. Tải artifact đó, mở bằng Xcode (Window → Devices) để chạy thử UI
trên máy Mac của người khác.

---

## 7. Phụ lục: TestFlight (account trả phí)

1. Tạo app trong **App Store Connect** với bundle id `com.mngcloud.app`.
2. Workflow `release` (tag `v*`) đã sẵn sàng: thêm các secret
   `APPSTORE_KEY_ID`, `APPSTORE_ISSUER_ID`, `APPSTORE_PRIVATE_KEY` và bổ sung
   bước `xcodebuild -exportArchive -destination upload`.
3. Cài từ app **TestFlight** trên iPhone → profile không hết hạn 7 ngày ✓.
