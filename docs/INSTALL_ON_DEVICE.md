# Cài app MNG Cloud lên iPhone bằng AltStore (không cần máy Mac, **không cần Team ID**)

App `MNG Cloud` là app **SwiftUI native**, nên không chạy được trong Expo/React
Native. Cách test trên iPhone mà không cần máy Mac:

```
GitHub Actions            máy của bạn                    iPhone
─────────────            ──────────────                  ──────
build .ipa chưa ký  ──▶  AltStore / AltServer  ──▶  AltStore ký lại bằng
                          (AltStore Classic)              Apple ID cá nhân → cài app
```

* **GitHub Actions** chỉ build + đóng gói: `Payload/MNGCloud.app` trong một
  file `.ipa` **chưa ký**, không đụng tới Apple ID nào.
* **AltStore trên máy của bạn** ký lại bằng **Apple ID miễn phí** (Personal
  Team) rồi cài vào iPhone.

---

## 1. Build unsigned IPA (GitHub Actions)

1. Vào repo → tab **Actions** → workflow **build-ios** → **Run workflow**.
2. Chọn branch `main`, configuration `Release` → **Run workflow**.
3. Job làm 5 việc (xem log):
   | Bước | Việc |
   | --- | --- |
   | Generate the project | `xcodegen generate` từ `project.yml` |
   | Check the Personal Team capabilities | in báo cáo capability của app, **fail rõ ràng** nếu app cần capability mà tài khoản miễn phí không cấp được |
   | Build the unsigned device app | `xcodebuild … CODE_SIGNING_ALLOWED=NO` cho `generic/platform=iOS` (binary arm64 cho máy thật) |
   | Package the unsigned IPA | `scripts/make-unsigned-ipa.sh` → đóng gói + kiểm tra lại bundle |
   | Upload the IPA | artifact **`MNGCloud-AltStore-IPA`** (giữ 30 ngày) |
4. Xong job (xanh) → cuộn xuống **Artifacts** → bấm **MNGCloud-AltStore-IPA** →
   tải về (zip) → giải nén ra `MNGCloud.ipa`.

### Báo cáo trong log

`make-unsigned-ipa.sh` in ra để bạn biết IPA có đúng không:

```
== IPA report ==
Bundle id:       com.mngcloud.app
Display name:    MNG Cloud
Version:         1.0.0 (1)
Minimum iOS:     17.0
Executable:      MNGCloud
Architectures:   arm64
Binary:          Mach-O 64-bit executable arm64
Signature:       none (AltStore signs it with the personal Apple ID)
Frameworks:      none (Swift package libraries are linked statically)
App extensions:  none
Watch apps:      none
Packaged:        build/altstore/MNGCloud.ipa (2.1M)
Payload layout:
  Payload
  Payload/MNGCloud.app
  ...
```

Nếu bundle sai, executable thiếu, kiến trúc không phải arm64 hoặc framework nhúng
bị hỏng, script **dừng với lỗi rõ ràng** chứ không tạo ra IPA hỏng.

---

## 2. Cài bằng AltStore Classic

Bạn đã cài AltStore rồi, nên chỉ còn một trong hai cách sau:

### Cách A — từ máy tính (AltStore trên Windows)

1. Mở **AltStore** → tab **My Apps** → bấm **+** → chọn `MNGCloud.ipa` →
   chờ **Finished**.
2. Nếu AltStore báo chưa có iPhone: cắm iPhone bằng cáp USB và bấm **Trust
   This Computer** trên iPhone.

### Cách B — cài trực tiếp trên iPhone

1. Gửi `MNGCloud.ipa` sang iPhone: **AirDrop**, **iCloud Drive**, hoặc email cho
   chính mình.
2. Trên iPhone: mở **Files** → bấm file `.ipa` → nó mở **AltStore** →
   **Install** → chờ **Finished**.

### Lần đầu mở app

1. Mở **MNG Cloud**.
2. Nếu báo chưa tin cậy: **Cài đặt → General → VPN & Device Management** →
   dòng *Developer App* (Apple ID của bạn) → **Trust**.
3. Đăng nhập bằng tài khoản MNG Cloud + URL máy chủ `mngd`
   (ví dụ `https://cloud.example.com`).

---

## 3. Giới hạn của Apple ID miễn phí (Personal Team)

Đây là các giới hạn **của Apple**, không phải của app. Đã đối chiếu với app:

| Giới hạn | Ảnh hưởng tới MNG Cloud |
| --- | --- |
| Profile *development* hết hạn sau **7 ngày** | App mở được nhưng phiên đăng nhập (cookie máy chủ) có thể bị từ chối. **AltStore tự làm mới** profile mỗi 7 ngày nếu iPhone vẫn ở cùng mạng Wi-Fi và bật *Refresh sideload*. Nếu không, cài lại `.ipa` (workflow cho artifact mới). |
| Số **App ID** đăng ký được trong 7 ngày (AltStore ghi "10 apps / 7 days" cho account miễn phí) | Mỗi lần AltStore cài app mới dùng một App ID. Xoá app trên máy rồi cài lại vẫn tốn một App ID. |
| Số **thiết bị** (100/loại/năm) | Chỉ cần đăng ký iPhone của bạn — AltStore tự làm. |
| **Không có Push Notifications** | App **không** dùng push (không có `aps-environment`) → không ảnh hưởng. |
| **Không có iCloud/CloudKit** | Tính năng "iCloud" trong app là **trình nhập chạy trên máy chủ `mngd`**, không dùng CloudKit của Apple → không ảnh hưởng. |
| **Không có App Groups** | App không dùng App Group → không ảnh hưởng. |
| **Không có Keychain Sharing** | App không dùng nhóm keychain dùng chung (chỉ `HTTPCookieStorage` + `UserDefaults` của riêng app) → không ảnh hưởng. |
| **Không có Associated Domains** | App không dùng → không ảnh hưởng. |
| AltStore có thể **đổi bundle id** thành `com.mngcloud.app.<random>` | `UserDefaults`/keychain của app bị tách theo bundle id → nếu AltStore đổi id, chỉ cần **đăng nhập lại**. Dữ liệu trên máy chủ không bị ảnh hưởng. |
| Không có **background fetch** | App không khai báo `UIBackgroundModes` → không ảnh hưởng (app chỉ chạy khi mở). |

### Nếu sau này app cần một capability

Workflow `build-ios` chạy `scripts/check-personal-team-entitlements.sh` trước khi
build. Script **không tự ý xoá** capability (xoá là đổi chức năng app) mà sẽ
**dừng build** với thông báo rõ ràng, ví dụ:

```
== Personal Team capability report ==
Entitlements files: 1
  - App/App.entitlements
    UNSUPPORTED by a free Personal Team: aps-environment
RESULT: the app requests entitlements that a free Personal Team cannot
        grant. Remove the capability from the app (it is a functional
        change) or build with a paid team. Nothing was stripped here.
```

Khi đó bạn có 2 lựa chọn: bỏ capability khỏi app, hoặc dùng đường ký trả phí.

---

## 4. Nếu muốn IPA đã ký sẵn (account trả phí)

Workflow riêng **`build-ios-signed`**:
- `signing = automatic` → dùng App Store Connect API key (Xcode tự tạo chứng thư
  và profile trên runner).
- `signing = manual` → bạn tự upload `.p12` + `.mobileprovision` qua secrets.

Hai workflow tách biệt hoàn toàn: `build-ios` **không dùng secret nào**.

---

## 5. Xử lý sự cố

| Triệu chứng | Nguyên nhân | Cách sửa |
| --- | --- | --- |
| AltStore báo "Invalid Signature" / không cài được | File `.ipa` bị hỏng hoặc tải về chưa giải nén | Tải lại artifact, giải nén `.ipa`, cài lại |
| AltStore báo "The app could not be installed" vì hết App ID | Đã dùng hết số App ID 7 ngày | Chờ hết 7 ngày hoặc dùng đường ký trả phí |
| App mở ra rồi báo lỗi đăng nhập | Profile hết hạn / cookie phiên cũ | Bật *Refresh sideload* trong AltStore, hoặc cài lại `.ipa` và đăng nhập lại |
| "Device not found" | Chưa bấm **Trust This Computer** | Mở khoá iPhone, chấp nhận Trust, thử lại |
| Không đăng nhập được dù app mở | Chưa có máy chủ `mngd` hoặc sai URL | Dựng backend từ `mng-cloud-rs`, kiểm tra URL |
| Workflow báo "the app requests entitlements…" | App cần capability mà account miễn phí không cấp | Xem mục 3, hoặc dùng `build-ios-signed` |
| Workflow báo "Missing …" | Sai tên input của workflow | Chạy lại với `configuration=Release`, `artifact_name=MNGCloud-AltStore-IPA` |

---

## 6. Xem giao diện mà không cần cài gì

Workflow `ci` xuất artifact **MNGCloud-simulator** chứa app **chưa ký** cho
simulator. Tải artifact đó, mở bằng Xcode (Window → Devices) để chạy thử UI
trên máy Mac của người khác.
