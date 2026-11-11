# Cài app MNG Cloud lên iPhone (không cần máy Mac)

App `MNG Cloud` là app **SwiftUI native**, nên không chạy được trên Expo/React
Native. Cách test trên iPhone mà **không cần máy Mac** là để GitHub Actions
build một bản `.ipa` đã ký, rồi bạn cài bằng Sideloadly.

> Toàn bộ hướng dẫn viết cho **Windows**. Người dùng macOS làm tương tự, chỉ
> khác ở chỗ mã hoá base64 (dùng `base64 -i file.p8 | tr -d '\n'`).

---

## 0. Tóm tắt 5 bước

| # | Việc | Ở đâu |
| --- | --- | --- |
| 1 | Tạo tài khoản Apple Developer miễn phí, lấy **Team ID** | developer.apple.com |
| 2 | Tạo **App Store Connect API Key**, tải file `.p8` | developer.apple.com → Keys |
| 3 | Lấy **UDID** của iPhone và **đăng ký thiết bị** | developer.apple.com → Devices |
| 4 | Thêm 4 **secrets** vào repo GitHub | Repo → Settings → Secrets |
| 5 | Chạy workflow **build-ios**, tải `.ipa`, cài bằng **Sideloadly** | GitHub Actions → Sideloadly |

---

## 1. Tài khoản Apple Developer (miễn phí)

### 1.1 Đăng ký

1. Mở <https://developer.apple.com/account/register> và đăng nhập bằng Apple ID
   của bạn (Apple ID thường, không cần trả phí).
2. Điền thông tin cá nhân, chọn quyền **Individual** (cá nhân), đồng ý điều
   khoản → bấm **Continue**.
3. Nếu Apple yêu cầu xác minh 2FA cho tài khoản này → bật 2FA (bắt buộc từ
   2024).

### 1.2 Lấy Team ID

1. Vào <https://developer.apple.com/account> → đăng nhập.
2. Trên thanh trên cùng bên phải, bấm **tên/email của bạn** → chọn
   **Membership Details** (hoặc vào tab **Membership** ở menu bên trái).
3. Ở mục **Team Information** sẽ thấy:
   - **Team ID**: chuỗi **10 ký tự** (ví dụ `A1B2C3D4E5`) ← **đây là giá trị
     cần đưa vào secret `APPLE_TEAM_ID`**.
   - Team Name (tên hiển thị của bạn).
4. Copy Team ID lại, sang bước 2.

> **Lưu ý:** với tài khoản *Individual*, Team ID **không phải** là Apple ID
> của bạn và cũng không phải mã `XXXXXXXXXX` trong tên file `.p8`.

---

## 2. Tạo API key (Access Keys)

Đây là "chìa khoá" để GitHub Actions được phép ký app thay bạn. Bạn **không**
cần nhập mật khẩu Apple ID ở đâu trong CI.

### 2.1 Mở trang Keys

1. Vào <https://developer.apple.com/account/resources/keys> (đăng nhập sẵn).
2. Cuộn xuống mục **Access Keys** (không phải "Certificates, Identifiers &
   Profiles" bên trên).

### 2.2 Tạo key

1. Bấm nút **+** cạnh "Access Keys".
2. Điền:
   - **Key Name**: gõ tên gợi ý, ví dụ `MNG Cloud CI` (tên này chỉ để bạn nhận
     biết, không ảnh hưởng gì).
   - **Key Access**: chọn **App Manager** (hoặc **Admin** nếu bạn muốn quyền
     rộng hơn). **Không** chọn "Developer Only" cho workflow này.
3. Bấm **Continue** → màn hình **Register** → bấm **Register**.

### 2.3 Tải file `.p8` (CHỈ TẢI ĐƯỢC MỘT LẦN)

1. Sau khi bấm Register, Apple hiện trang **Download the key now** với nút
   **Download** (một số bản UI ghi là "Download Your Key").
2. Bấm **Download** → file tải về có tên dạng **`AuthKey_XXXXXXXXXX.p8`**
   (10 ký tự `XXXXXXXXXX` là **Key ID**).
3. **Giữ file .p8 cất riêng** — Apple không cho tải lại lần thứ hai. Đừng
   commit file này vào git.

### 2.4 Ghi lại 2 mã còn lại

Ngay trên trang **Keys** (mục Access Keys) bạn sẽ thấy một bảng:

| Cột | Ý nghĩa | Dùng cho |
| --- | --- | --- |
| **Key ID** | 10 ký tự, cũng là phần sau `AuthKey_` trong tên file | secret `APP_STORE_CONNECT_KEY_ID` |
| **Issuer ID** | 1 UUID dài | secret `APP_STORE_CONNECT_ISSUER_ID` |

Bấm vào tên key để mở chi tiết sẽ hiện đủ cả hai.

---

## 3. Lấy UDID của iPhone (chạy trên Windows)

**UDID** là mã 40 ký tự của thiết bị, ví dụ
`00008110-001A2B3C4D5E6F70` (dạng `00008103-...` với iPhone, `00008030-...`
với iPad). Bạn **không** lấy được UDID trong Cài đặt của iPhone — phải dùng
máy tính.

### 3.1 Cách 1 — iMazing (khuyên dùng, miễn phí)

1. Tải iMazing cho Windows: <https://imazing.com> → **Download for Windows**.
2. Cài đặt, mở iMazing.
3. Cắm iPhone vào PC bằng **cáp USB** (không phải sạc không dây).
4. Lần đầu, **trên iPhone** sẽ hiện thông báo *"Trust This Computer?"* →
   bấm **Trust** → nhập mật khẩu iPhone. (Không làm bước này thì iMazing
   không thấy máy.)
5. Trong iMazing, chọn thiết bị ở thanh bên trái → bấm **More** (hoặc icon
   "i" / **Device Information**) → tìm dòng **UDID** → bấm **Copy**.

### 3.2 Cách 2 — Apple Configurator 2

1. Tải tại <https://support.apple.com/en-us/HT204154> (mục *Apple Configurator
   2 for Windows*).
2. Cài đặt → cắm iPhone → chọn thiết bị → menu **View → Device Information** →
   copy **Unique Device Identifier (UDID)**.

### 3.3 Cách 3 — 3uTools (nhanh, tiếng Trung)

Cài 3uTools → cắm iPhone → tab "Device Info" (设备信息) → copy **UDID**.

### 3.4 Mẹo

- Nếu iMazing hiện "Recovery Mode" hoặc không nhận: thử đổi cáp/cổng, hoặc
  bấm **Trust** lại trên iPhone (Cài đặt → General → Reset → Reset Location &
  Privacy sẽ hiện lại hộp thoại Trust).
- Bạn chỉ cần **1 UDID** cho 1 iPhone. Nhiều máy thì đăng ký từng máy.

---

## 4. Đăng ký thiết bị trong portal

Không có UDID thì Xcode không tạo được provisioning profile.

1. Vào <https://developer.apple.com/account/resources/devices>.
2. Chọn đúng nhóm thiết bị (iPhone / iPad) ở cột trái.
3. Bấm **+**:
   - **Device Name**: ví dụ `iPhone cua toi` (tên tự do, dùng để nhận biết).
   - **Platform**: chọn **iOS**.
   - **Device Identifier**: dán **UDID** đã copy ở bước 3.
4. Bấm **Continue** → **Register**.

Bạn có tối đa 100 thiết bị cho mỗi nền tảng mỗi năm ✓ (đủ dùng).

---

## 5. Tạo app-specific password (dùng cho Sideloadly)

Tài khoản miễn phí không cho Sideloadly dùng mật khẩu Apple ID thường, nên
cần một mật khẩu riêng.

1. Vào <https://account.apple.com> → đăng nhập.
2. **Sign-in and security** → **App-specific passwords** → **+**.
3. Đặt tên (ví dụ `Sideloadly`) → **Create** → copy mã 16 ký tự (xxxx-xxxx-
   xxxx-xxxx).
4. Mật khẩu này chỉ hiện **một lần** — lưu lại ngay.

---

## 6. Thêm secrets vào repo GitHub

1. Vào repo `anhhoangsky/mng-cloud-sw` → **Settings** → **Secrets and
   variables** → **Actions** → **New repository secret**.
2. Tạo 4 secret:

| Tên secret | Giá trị lấy từ |
| --- | --- |
| `APPLE_TEAM_ID` | Team ID 10 ký tự (bước 1.2) |
| `APP_STORE_CONNECT_KEY_ID` | Key ID 10 ký tự (bước 2.4) |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID UUID (bước 2.4) |
| `APP_STORE_CONNECT_PRIVATE_KEY` | nội dung file `.p8` **mã hoá base64** |

### 6.1 Mã hoá base64 file `.p8` trên Windows (PowerShell)

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\Downloads\AuthKey_XXXXXXXXXX.p8"))
```

Lệnh in ra một chuỗi dài khoảng 100–200 ký tự → copy nguyên chuỗi đó vào
ô `APP_STORE_CONNECT_PRIVATE_KEY`.

> Đừng dán nội dung `.p8` gốc (không base64): workflow giải mã base64, nếu
> dán sai sẽ báo lỗi "Missing … secrets" hoặc ký thất bại.

---

## 7. Chạy workflow build

1. Vào tab **Actions** của repo → chọn workflow **build-ios** bên trái.
2. Bấm **Run workflow** → chọn branch `main`, configuration `Release` →
   **Run workflow**.
3. Theo dõi tiến trình (~5–15 phút). Các bước chính:
   - *Select Xcode* → *Install XcodeGen* → *Generate the project* →
     *Import the App Store Connect key* → *Archive (automatic signing)* →
     *Export the IPA* → *Upload the IPA*.
   - Bước **Archive** sẽ tự tạo chứng thư "Apple Development" và profile
     mới (nhờ `-allowProvisioningUpdates`).
4. Xong job sẽ báo **green**. Ở trang run, cuộn xuống mục **Artifacts** →
   bấm **MNGCloud-ipa** → file `.ipa` được tải về (zip).

> Nếu bước *Import the App Store Connect key* báo thiếu secret → kiểm tra lại
> tên secret có đúng không (phải viết đúng, phân biệt hoa thường).

---

## 8. Cài `.ipa` lên iPhone bằng Sideloadly

1. Tải Sideloadly: <https://sideloadly.io> → chọn Windows → cài đặt.
   (Lần chạy đầu Sideloadly sẽ cần bạn cài **iTunes** hoặc **Apple Mobile
   Device Support** để nhận ra iPhone — hãy đồng ý khi nó báo.)
2. Mở Sideloadly → kéo file `.ipa` vừa tải vào cửa sổ → nhập:
   - **Apple ID**: Apple ID của bạn,
   - **Password**: app-specific password ở bước 5.
3. Bấm **Start** → chờ đợi ("SIDELOADING..." rồi "DONE").
4. Cắm iPhone vào PC (nếu Sideloadly yêu cầu), mở khoá máy và bấm **Trust**
   nếu có thông báo.

### 8.1 Cài trực tiếp từ iPhone (không cần PC)

Thay vì tải `.ipa` qua PC, bạn có thể lưu artifact lên điện thoại rồi mở
bằng Sideloadly trên iPhone — nhưng cách trên ổn định hơn.

---

## 9. Mở app lần đầt trên iPhone

1. Mở app **MNG Cloud**.
2. Nếu hiện *"Untrusted Developer"* hoặc app không mở được:
   **Cài đặt → General → VPN & Device Management** → chọn dòng
   *Developer App* (Apple ID của bạn) → **Trust**.
3. Đăng nhập bằng tài khoản MNG Cloud của bạn và URL máy chủ `mngd`
   (ví dụ `https://cloud.example.com`).

---

## 10. Hạn 7 ngày

- Profile **development** của tài khoản miễn phí chỉ hợp lệ **7 ngày**.
- Hết hạn: app vẫn mở được nhưng server từ chối session → bạn thấy lỗi
  đăng nhập. Cách sửa: chạy lại workflow **build-ios** (Xcode sinh profile
  mới) rồi Sideloadly lại file `.ipa`.
- Sideloadly có thể **tự làm mới** profile mỗi 7 ngày nếu iPhone vẫn kết
  nối với cùng mạng Wi-Fi và bật "Refresh sideload" trong cài đặt.

---

## 11. Xử lý sự cố

| Triệu chứng | Nguyên nhân | Cách sửa |
| --- | --- | --- |
| "Missing APPLE_TEAM_ID … secrets" | Thiếu/ sai tên secret | Kiểm tra lại 4 secret ở bước 6 |
| "No profiles for 'com.mngcloud.app'" | Xcode không tạo được profile | Kiểm tra API key có quyền App Manager/Admin và thiết bị đã được đăng ký (bước 4) |
| "Provisioning profile doesn't include device" | Thiết bị chưa đăng ký hoặc sai UDID | Đăng ký lại UDID (bước 4) rồi chạy lại workflow |
| "Unable to authenticate" khi Sideloadly | Sai app-specific password hoặc Apple ID | Tạo lại app-specific password (bước 5) |
| "Device not found" trong Sideloadly | Chưa bấm "Trust This Computer" trên iPhone | Mở khoá máy, chấp nhận Trust, thử lại |
| App đã cài mở ra rồi báo lỗi đăng nhập | Profile hết hạn 7 ngày | Chạy lại workflow + Sideloadly lại |
| Không đăng nhập được dù app mở | Chưa có máy chủ `mngd` hoặc sai URL | Dựng backend từ `mng-cloud-rs`, kiểm tra URL |

---

## 12. Phương án thay thế: TestFlight

Nếu bạn có tài khoản Apple Developer trả phí (99 USD/năm):

1. Tạo **App Store Connect** app (record) với bundle id `com.mngcloud.app`.
2. Dùng workflow `release` (tag `v*`) để upload, hoặc bổ sung bước
   `xcodebuild -exportArchive -destination upload` với
   `APPSTORE_KEY_ID` / `APPSTORE_ISSUER_ID` / `APPSTORE_PRIVATE_KEY`.
3. Cài app từ app TestFlight trên iPhone → profile **TestFlight** không hết hạn
   sau 7 ngày ✓.

---

## 13. Xem giao diện mà không cần cài gì

Workflow `ci` xuất artifact **MNGCloud-simulator** chứa app **chưa ký** cho
simulator. Tải artifact đó, mở bằng Xcode (Window → Devices) để chạy thử UI
trên máy Mac của người khác hoặc trên máy ảo hoá.

Lưu ý: simulator không đăng nhập được vào máy chủ thật trừ khi bạn trỏ
app về box của mình qua `Settings` (URL máy chủ) — và cookie phiên trên
simulator là của máy đó.
