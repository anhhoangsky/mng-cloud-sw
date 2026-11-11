# Cài app MNG Cloud lên iPhone (không cần máy Mac)

App `MNG Cloud` là app **SwiftUI native**, nên không chạy được trong Expo/React
Native. Cách test trên iPhone mà **không cần máy Mac** là để GitHub Actions
build một bản `.ipa` đã ký, rồi cài bằng Sideloadly.

Hướng dẫn này dùng **tài khoản Apple Developer miễn phí** (không cần trả 99
USD/năm). Nếu bạn có account trả phí, xem [phần 12](#12-phương-án-tự-động-với-api-key).

> Viết cho **Windows**. Người dùng macOS làm tương tự, chỉ khác ở chỗ mã
> hoá base64 và tạo CSR (trên macOS: `openssl` có sẵn trong Terminal).

---

## 0. Tóm tắt

| # | Việc | Ở đâu |
| --- | --- | --- |
| 1 | Tạo tài khoản Apple Developer miễn phí, lấy **Team ID** | developer.apple.com |
| 2 | Lấy **UDID** và **đăng ký thiết bị** | iMazing + developer.apple.com |
| 3 | Tạo **App ID** `com.mngcloud.app` | developer.apple.com → Identifiers |
| 4 | Tạo **chứng thư phát triển** (CSR → .cer → .p12) | OpenSSL + developer.apple.com |
| 5 | Tạo **provisioning profile** và tải `.mobileprovision` | developer.apple.com → Profiles |
| 6 | Thêm 6 **secrets** vào repo GitHub | Repo → Settings → Secrets |
| 7 | Chạy workflow **build-ios** → tải `.ipa` | GitHub Actions |
| 8 | Cài lên iPhone bằng **Sideloadly** | Windows |

---

## 1. Tài khoản Apple Developer miễn phí + Team ID

### 1.1 Đăng ký

1. Mở <https://developer.apple.com/account/register> → đăng nhập Apple ID.
2. Điền thông tin, chọn quyền **Individual** → **Continue** → đồng ý điều khoản.
3. Bật 2FA cho tài khoản này nếu Apple yêu cầu.

### 1.2 Lấy Team ID

1. Vào <https://developer.apple.com/account> → bấm **tên/email** góc trên phải →
   **Membership Details** (hoặc menu **Membership**).
2. Mục **Team Information** → copy **Team ID** (10 ký tự, ví dụ `A1B2C3D4E5`).
   → lưu lại, đây là secret `APPLE_TEAM_ID`.

> Với account *Individual*, Team ID **không phải** Apple ID của bạn.

### 1.3 Mở "Certificates, Identifiers & Profiles"

Đây là nơi làm mọi thứ cho tài khoản miễn phí:

<https://developer.apple.com/account/resources/identifiers/list>

> **Lỗi "Access Unavailable"?** Trang *Access Keys* (API key của App Store
> Connect) **chỉ dành cho account trả phí** — đó là lý do bạn không mở được.
> Tài khoản miễn phí dùng **chứng thư + provisioning profile thủ công** như
> hướng dẫn dưới đây.

---

## 2. UDID + đăng ký thiết bị

### 2.1 Lấy UDID (trên Windows)

**UDID** là mã 40 ký tự của iPhone (ví dụ `00008110-001A2B3C4D5E6F70`). Không lấy
được trong Cài đặt của iPhone — phải qua máy tính.

**Cách 1 — iMazing (khuyên dùng, miễn phí)**

1. Tải <https://imazing.com> → *Download for Windows* → cài đặt → mở.
2. **Cắm iPhone bằng cáp USB**.
3. Lần đầu, iPhone hiện *"Trust This Computer?"* → **Trust** → nhập mật khẩu.
   (Bỏ bước này thì iMazing không thấy máy.)
4. Chọn thiết bị ở thanh trái → bấm **More** → mục *Device Information* →
   copy dòng **UDID**.

**Cách 2 — Apple Configurator 2**: <https://support.apple.com/en-us/HT204154>
→ cắm iPhone → **View → Device Information** → *Unique Device Identifier (UDID)*.

**Cách 3 — 3uTools**: tab *设备信息* → cột **UDID**.

### 2.2 Đăng ký thiết bị

1. Vào <https://developer.apple.com/account/resources/devices>.
2. Chọn nhóm **iPhone** (hoặc iPad) ở cột trái → bấm **+**.
3. *Device Name*: tự do (ví dụ `iPhone cua toi`) · *Platform*: **iOS** ·
   *Device Identifier*: dán UDID → **Continue** → **Register**.

(Tối đa 100 thiết bị/nền tảng/năm.)

---

## 3. Tạo App ID

1. <https://developer.apple.com/account/resources/identifiers/list> → mục
   **Identifiers** → tab **App IDs** → **+**.
2. Chọn **App** → **Description**: `MNG Cloud` → **Platform**: **iOS** →
   **Continue**.
3. Chọn **Explicit** → *Bundle ID*: `com.mngcloud.app` (phải **khớp chính xác**
   với `project.yml`) → **Continue** → **Register** → **Done**.

Không cần bật capability nào (app không dùng Push/iCloud…).

---

## 4. Tạo chứng thư phát triển (.p12)

Apple không tải khóa riêng cho bạn — bạn tự tạo **CSR** rồi upload lên
portal, Apple cấp chứng thư `.cer`, rồi bạn ghép `.cer` + khóa riêng thành
`.p12`.

### 4.1 Tạo CSR + khóa riêng (OpenSSL)

Mở **Git Bash** trên Windows (đã có sẵn nếu bạn dùng git; nếu chưa thì tải
<https://git-scm.com>), rồi:

```bash
cd ~/Downloads
openssl req -new -newkey rsa:2048 -nodes \
  -keyout mngcloud-dev.key \
  -out mngcloud-dev.csr \
  -subj "/CN=MNG Cloud Dev/email=you@example.com"
```

Sinh ra 2 file: `mngcloud-dev.key` (khóa riêng — **giữ kỹ, không được commit**)
và `mngcloud-dev.csr` (để upload).

### 4.2 Upload CSR lên portal → nhận `.cer`

1. <https://developer.apple.com/account/resources/certificates> → **+**.
2. Chọn **Apple Development** → *Certificate Type* → **Continue**.
3. Chọn **Upload a certificate signing request** → upload file
   `mngcloud-dev.csr` → **Continue** → **Register**.
4. Bấm **Download** → file **`certificate.cer`** ✓.

### 4.3 Ghép `.cer` + key thành `.p12` (Git Bash)

```bash
cd ~/Downloads
openssl x509 -inform DER -in certificate.cer -out certificate.pem
openssl pkcs12 -export -out certificate.p12 \
  -inkey mngcloud-dev.key -in certificate.pem \
  -password pass:CHON-MAT-KHAU-CUA-BAN
```

`CHON-MAT-KHAU-CUA-BAN` chính là mật khẩu của file `.p12` — nhớ nó, sẽ dùng
làm secret.

### 4.4 Mã hoá base64 (PowerShell)

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\Downloads\certificate.p12"))
```

→ chuỗi này là secret `BUILD_CERTIFICATE_BASE64`.
→ mật khẩu ở bước 4.3 là secret `BUILD_CERTIFICATE_PASSWORD`.

---

## 5. Tạo provisioning profile

1. <https://developer.apple.com/account/resources/profiles> → **+**.
2. Chọn **iOS App Development** → **Continue**.
3. *App ID* → chọn `MNG Cloud` (vừa tạo ở bước 3) → **Continue**.
4. *Devices* → chọn iPhone đã đăng ký ở bước 2 → **Continue**.
5. *Name*: ví dụ `MNG Cloud Dev` → **Generate** → **Download** → file
   **`MNG Cloud Dev.mobileprovision`** ✓.
   ⚠️ **Tên của profile** (không phải tên file) là giá trị secret
   `PROVISIONING_PROFILE_SPECIFIER` — ví dụ `MNG Cloud Dev`.
6. Mã hoá base64 (PowerShell):

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\Downloads\MNG Cloud Dev.mobileprovision"))
```

→ secret `PROVISIONING_PROFILE_BASE64`.

---

## 6. Thêm secrets vào repo GitHub

Repo → **Settings → Secrets and variables → Actions** → **New repository
secret**. Tạo 6 secret:

| Tên secret | Giá trị |
| --- | --- |
| `APPLE_TEAM_ID` | Team ID 10 ký tự (bước 1.2) |
| `BUILD_CERTIFICATE_BASE64` | base64 của `certificate.p12` (bước 4.4) |
| `BUILD_CERTIFICATE_PASSWORD` | mật khẩu bạn đặt ở bước 4.3 |
| `PROVISIONING_PROFILE_BASE64` | base64 của `.mobileprovision` (bước 5.6) |
| `PROVISIONING_PROFILE_SPECIFIER` | **tên** của profile, ví dụ `MNG Cloud Dev` (bước 5.5) |
| `KEYCHAIN_PASSWORD` | chuỗi bất kỳ, ví dụ `openssl rand -base64 24` |

> Tất cả secret này đều **chỉ dùng trong CI**, không đụng tới app.

---

## 7. Chạy workflow build

1. Tab **Actions** → workflow **build-ios** → **Run workflow**.
2. Chọn branch `main`, configuration `Release`, **signing = `manual`** →
   **Run workflow**.
3. Các bước trong log:
   *Select Xcode* → *Install XcodeGen* → *Generate the project* → *Import the
   development certificate and the profile* → *Archive (manual signing)* →
   *Export the IPA* → *Upload the IPA*.
4. Xong (job xanh) → cuộn xuống mục **Artifacts** → **MNGCloud-ipa** → tải về
   (zip) → giải nén ra file `.ipa`.

---

## 8. Cài `.ipa` lên iPhone bằng Sideloadly

1. Tải Sideloadly: <https://sideloadly.io> → chọn Windows → cài đặt.
   (Lần đầu Sideloadly cần **iTunes**/**Apple Mobile Device Support** để nhận ra
   iPhone — hãy đồng ý khi nó báo.)
2. Kéo file `.ipa` vào cửa sổ Sideloadly → nhập:
   - **Apple ID**: Apple ID của bạn,
   - **Password**: *app-specific password* (bước 9).
3. Bấm **Start** → chờ tới **DONE**.
4. Nếu Sideloadly yêu cầu, cắm iPhone vào PC và bấm **Trust** trên iPhone.

### 8.1 Tạo app-specific password (bước 9 nói ở trên)

<https://account.apple.com> → *Sign-in and security* → *App-specific
passwords* → **+** → đặt tên (ví dụ `Sideloadly`) → **Create** → copy mã 16 ký
tự (chỉ hiện **một lần**).

> Với account **Individual**, Sideloadly có thể báo lỗi *"This Apple ID is not
> supported"* khi dùng app-specific password cho *sideload* — khi đó dùng
> **AltStore** trên máy tính (AltStore cài app từ .ipa qua "Sideload" →
> *Install IPA*) hoặc đăng nhập bằng ứng dụng **Apple Configurator**.

---

## 9. Mở app lần đầt

1. Mở **MNG Cloud**.
2. Nếu báo chưa tin cậy: **Cài đặt → General → VPN & Device Management** →
   chọn dòng *Developer App* (Apple ID của bạn) → **Trust**.
3. Đăng nhập bằng tài khoản MNG Cloud + URL máy chủ `mngd`
   (ví dụ `https://cloud.example.com`).

---

## 10. Hạn 7 ngày

- Profile **development** (kể cả account trả phí) chỉ hợp lệ **7 ngày**.
- Hết hạn: app mở được nhưng server từ chối phiên → lỗi đăng nhập.
- Cách sửa: chạy lại workflow **build-ios** (profile mới) rồi Sideloadly lại
  file `.ipa`.
- Sideloadly có thể **tự làm mới** profile mỗi 7 ngày nếu iPhone vẫn ở cùng
  mạng Wi-Fi và bật *Refresh sideload*.

---

## 11. Xử lý sự cố

| Triệu chứng | Nguyên nhân | Cách sửa |
| --- | --- | --- |
| "Missing BUILD_CERTIFICATE_BASE64…" | Thiếu/sai tên secret | Kiểm tra lại 6 secret ở bước 6 |
| "No profiles for 'com.mngcloud.app'" | Profile không chứa App ID đúng | Tạo lại profile, chọn đúng App ID `com.mngcloud.app` (bước 5) |
| "Provisioning profile doesn't include device" | Chưa đăng ký UDID hoặc chọn sai máy | Đăng ký lại (bước 2), tạo lại profile (bước 5) |
| "The certificate is not valid" khi archive | `.p12` sai mật khẩu hoặc `.cer` không khớp `.key` | Làm lại bước 4.3–4.4, kiểm tra mật khẩu |
| "Unable to authenticate" khi Sideloadly | Sai app-specific password / Apple ID | Tạo lại app-specific password (bước 8.1) |
| "Device not found" trong Sideloadly | Chưa bấm "Trust This Computer" | Mở khoá máy, chấp nhận Trust, thử lại |
| App đã cài mở ra rồi báo lỗi đăng nhập | Profile hết hạn 7 ngày | Chạy lại workflow + Sideloadly lại |
| Không đăng nhập được dù app mở | Chưa có máy chủ `mngd` hoặc sai URL | Dựng backend từ `mng-cloud-rs`, kiểm tra URL |
| Trang *Access Keys* báo "Access Unavailable" | Access Keys cần account **trả phí** | Dùng đường thủ công ở trên (bước 3–5) |

---

## 12. Phương án tự động (với API key, cần account trả phí)

Nếu bạn có membership trả phí (99 USD/năm):

1. Tạo **App Store Connect API Key** ở
   <https://developer.apple.com/account/resources/keys> → mục *Access Keys* →
   **+** → *Key Access*: **App Manager** → **Register** → tải `AuthKey_XXX.p8`
   (**chỉ tải được 1 lần**).
2. Lấy **Key ID** (10 ký tự sau `AuthKey_`) và **Issuer ID** trên trang Keys.
3. Thêm secrets: `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`,
   `APP_STORE_CONNECT_PRIVATE_KEY` (base64 của `.p8`).
4. Chạy workflow **build-ios** với **signing = `automatic`** → Xcode tự tạo
   chứng thư + profile trên runner.

---

## 13. Xem giao diện mà không cần cài gì

Workflow `ci` xuất artifact **MNGCloud-simulator** chứa app **chưa ký** cho
simulator. Tải artifact đó, mở bằng Xcode (Window → Devices) để chạy thử UI
trên máy Mac của người khác.

---

## 14. Phụ lục: TestFlight (account trả phí)

1. Tạo app trong **App Store Connect** với bundle id `com.mngcloud.app`.
2. Workflow `release` (tag `v*`) đã sẵn sàng: thêm các secret
   `APPSTORE_KEY_ID`, `APPSTORE_ISSUER_ID`, `APPSTORE_PRIVATE_KEY` và bổ sung
   bước `xcodebuild -exportArchive -destination upload`.
3. Cài từ app **TestFlight** trên iPhone → profile không hết hạn 7 ngày ✓.
