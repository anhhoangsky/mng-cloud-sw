# MNG Cloud iOS — Kế hoạch chuyển toàn bộ app sang Swift/SwiftUI

- **Dự án nguồn:** `D:\rk3229\mng-cloud-rs` (Leptos CSR/WASM PWA + Rust core)
- **Dự án đích:** `D:\rk3229\mng-cloud-sw` (iOS/iPadOS, SwiftUI thuần)
- **Công cụ:** XcodeGen (sinh `.xcodeproj` từ YAML) + GitHub Actions (macOS runner)
- **Ngày lập:** 2026-11-10
- **Phiên bản tài liệu:** 1.0

---

## 1. Mục tiêu

Xây dựng app iOS/iPadOS **MNG Cloud** bằng Swift/SwiftUI, có hành vi và giao diện
**càng giống càng tốt** với shell native hiện tại (`ui/` — Leptos 0.8 CSR/WASM,
bản triển khai `0.3.1` + các slice trong cây làm việc), đồng thời giữ nguyên
toàn bộ backend `mngd`/Seafile. App mới là **client thuần**: mọi dữ liệu, xác
thực, phân quyền, E2EE và lịch sử vẫn nằm ở server như hiện tại.

Kết quả bàn giao:

1. Repo `mng-cloud-sw` tự build được **không cần máy Mac cục bộ** — GitHub
   Actions là "compiler".
2. `project.yml` (XcodeGen) là nguồn duy nhất mô tả project; không commit
   `xcodeproj` (tránh conflict).
3. App SwiftUI đạt parity theo từng phase, có KAT crypto trùng khớp 100% với
   Rust, có CI chặn regression.
4. Quy trình phát hành: simulator artifact → bản ad-hoc/TestFlight ký bằng
   secrets → (tuỳ chọn) App Store.

---

## 2. Phạm vi: chuyển gì, giữ gì

### 2.1 Giữ nguyên trên server (KHÔNG chuyển sang Swift)

| Thành phần | Vai trò |
| --- | --- |
| `crates/mngd` | HTTP API `/api/v1/*`, auth cookie, RBAC, media stream, vault relay |
| `crates/mng-writer` | Ghi SQLite có allowlist qua socket nội bộ |
| `crates/mng-worker` | Scan WebDAV, pHash, thumbnail, preview |
| `crates/mng-auth`, `crates/mng-db` | Xác thực, mô hình dữ liệu |
| `crates/mng-sign` | Ký release offline (P-256) |
| `seaf-server` + Seahub + MariaDB/Redis | Lưu trữ upstream, không đổi |
| `extension/`, `ops/`, `tools/`, `web/sw.js`, `ui/sw.js` | Trust anchor của web; iOS thay bằng chữ ký app/TestFlight |

### 2.2 Chuyển sang Swift/SwiftUI

| Nguồn | Nội dung | Đích |
| --- | --- | --- |
| `ui/` (Leptos) | Toàn bộ giao diện: login, shell, thư viện, viewer, album, search, vault, settings, admin, iCloud, connections, duplicates | App SwiftUI |
| `crates/mng-wasm` | `E2eeSession` + `EditSession` (biên WASM) | API Swift tương đương |
| `crates/mng-core/src/crypto/e2ee.rs` | Seafile E2EE v2/v3 (PBKDF2 + AES-256-CBC + SHA-1 block id) | `MNGCore/Crypto/RepoKey.swift` |
| `crates/mng-core/src/crypto/vault.rs` | `mng-vault/v1` (PBKDF2 310k + AES-256-GCM + AAD + manifest) | `MNGCore/Crypto/Vault*.swift` |
| `crates/mng-core/src/search.rs` | `fold()` + `rawurldecode()` | `MNGCore/SearchFold.swift` |
| `crates/mng-edit/src/lib.rs` | Rotate/flip/crop, adjustments, filter, encode | `MNGEdit/Editor.swift` (Core Image) |
| `ui/assets/app.css` | Design tokens, dark/light, glass, motion | `App/DesignSystem/*` |
| `ui/assets/sprite.svg`, `icon-*.png` | Icon, logo, app icon | Asset catalog + SF Symbols |
| `ui/src/api.rs` | Typed client + DTO | `MNGKit/*` |

### 2.3 Không cần port

- Service worker, Trusted Types, CSP, extension, `mng-sign` verification phía
  client: iOS dùng chữ ký app (Apple) thay cho chuỗi ký web.
- `localStorage` → `UserDefaults`; Blob URL → file tạm bảo vệ; Web Animations →
  SwiftUI animation/`matchedGeometryEffect`.
- Hover/right-click → long-press/context menu; phím tắt web → hardware keyboard
  (chỉ iPad, tuỳ chọn).

---

## 3. Kiến trúc mục tiêu

```
┌────────────────────────── iPhone / iPad ──────────────────────────┐
│  App target: MNGCloud (SwiftUI)                                    │
│   ├── Features/  Login · Shell · Library · Viewer · Albums         │
│   │              Search · Vault · Settings · Admin · Icloud        │
│   ├── DesignSystem/ (tokens từ app.css, components dùng chung)     │
│   └── Services/  SessionStore · ThumbCache · MediaLoader           │
│                                                                    │
│  Local Swift packages:                                             │
│   ├── MNGKit  — URLSession client, DTO Codable, CSRF, multipart    │
│   ├── MNGCore — RepoKey, VaultKey, VaultManifest, SearchFold       │
│   └── MNGEdit — Core Image editor (crop/adjust/filter/encode)      │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ HTTPS + cookie phiên HttpOnly
                               │ X-CSRF-Token trên POST/PUT/DELETE
                               ▼
                     nginx → mngd /api/v1/*  (giữ nguyên)
                               ├── seaf-server / Seahub (upstream)
                               └── mng-writer / mng-worker (nội bộ)
```

**Nguyên tắc:**

- Không thêm dependency bên thứ ba (0 SPM remote) — chỉ Apple frameworks:
  SwiftUI, Foundation, CryptoKit, CommonCrypto, ImageIO, Core Image,
  AVFoundation, PhotosUI, UniformTypeIdentifiers.
- Swift Concurrency: `async/await`, `actor` cho cache, `@MainActor` cho store;
  bật `SWIFT_STRICT_CONCURRENCY: targeted` từ đầu, siết dần lên `complete`.
- Mọi bí mật (mật khẩu, key dẫn xuất) chỉ nằm trong bộ nhớ, zeroize khi khoá;
  không ghi log, không lưu Keychain trừ khi có quyết định riêng.
- Session: `URLSession` + `HTTPCookieStorage` (cookie HttpOnly do server set);
  CSRF lấy từ `/auth/me` hoặc response login, giữ trong bộ nhớ.

---

## 4. Quyết định kỹ thuật chính

| # | Quyết định | Lý do |
| --- | --- | --- |
| D1 | **iOS 17.0+**, Xcode 16.4 (Swift 5 language mode, sẵn sàng Swift 6) | Có `ScrollPosition`, `Observable`, `NavigationSplitView` ổn định; thiết bị cũ vẫn phủ tốt |
| D2 | **Pure Swift crypto**, không nhúng Rust/UniFFI | Yêu cầu "toàn bộ qua Swift"; KAT làm cổng chặn (mục 9) |
| D3 | **XcodeGen** sinh project, commit `project.yml`, không commit `.xcodeproj` | Tránh conflict; CI tái lập 100% |
| D4 | **GitHub Actions macOS** là nơi build/test chính | Máy dev hiện tại là Windows, không có Xcode |
| D5 | Không dùng thư viện mạng ngoài `URLSession` | Giảm rủi ro supply chain; cookie/CSRF kiểm soát trực tiếp |
| D6 | Media qua **AVAssetResourceLoaderDelegate** với scheme riêng | AVPlayer không tự gửi cookie/CSRF; cần Range để seek video |
| D7 | Ảnh thumbnail/preview cache đĩa riêng (actor + LRU) | Parity hành vi lazy-thumb, giảm tải server |
| D8 | UI tokens sinh từ `app.css` (light/dark), typography hệ thống | "Càng giống càng tốt" nhưng tôn trọng UX iOS |
| D9 | Phát hành theo bậc: simulator → ad-hoc/TestFlight → App Store | Không chặn phát triển bởi tài khoản Apple |
| D10 | Bám hợp đồng API của bản triển khai `0.3.1` + các slice hiện có; endpoint thiếu thì degrade trung thực | Giống PWA: "Chưa hỗ trợ", "Không khả dụng", không giả lập thành công |

---

## 5. Bản đồ chuyển đổi chi tiết

### 5.1 Rust/TS → Swift

| Nguồn (dòng ~) | Đích Swift | Ghi chú |
| --- | --- | --- |
| `ui/src/app.rs` (81) | `App/AppRoot.swift` | Boot → Login → Ready |
| `ui/src/components/login.rs` | `Features/Login/LoginView.swift`, `BootScreen.swift` | Cùng copy lỗi tiếng Việt |
| `ui/src/api.rs` (52 KB) | `MNGKit/APIModels.swift`, `MNGAPIClient.swift`, `Endpoints.swift` | DTO + query builder; lỗi map 1:1 |
| `ui/src/components/shell.rs` (382 KB) | Tách ~20 file (xem 5.2) | Không port 1:1 theo dòng; port theo view/state |
| `ui/src/components/vault_native.rs` (118 KB) | `Features/Vault/*` | Native vault, có ghi |
| `ui/src/components/vault.rs` | `Features/Vault/SeafileVaultView.swift` | Chỉ đọc |
| `ui/src/components/admin.rs` (51 KB) | `Features/Admin/*` | Mount lười |
| `ui/src/components/icloud.rs` (48 KB) | `Features/Icloud/*` | Poll 2,2 s khi job chạy |
| `crates/mng-wasm/src/lib.rs` | `MNGCore/Crypto/RepoKey.swift` API | `unlock/encryptBlock/decryptBlock/ciphertextLen/blockId` |
| `crates/mng-core/src/crypto/e2ee.rs` | `MNGCore/Crypto/RepoKey.swift` | PBKDF2-SHA256, AES-256-CBC, PKCS#7 |
| `crates/mng-core/src/crypto/vault.rs` | `MNGCore/Crypto/VaultKey.swift`, `VaultManifest.swift` | AES-256-GCM, AAD, NFKC |
| `crates/mng-core/src/search.rs` | `MNGCore/SearchFold.swift` | Bảng fold từng ký tự, không dùng `lowercased()` |
| `crates/mng-edit/src/lib.rs` | `MNGEdit/Editor.swift`, `Adjustments.swift` | Core Image; thứ tự rotate → flip → crop |
| `ui/assets/app.css` | `DesignSystem/Tokens.swift`, asset catalog | Bảng token ở mục 10.1 |
| `ui/index.html` | `Info.plist` + `Assets.xcassets` | Tên app, icon, màu nền launch |

### 5.2 Tách `shell.rs` (382 KB) thành các file Swift

| Nhóm chức năng | File Swift đề xuất |
| --- | --- |
| Khung/menu/tab bar/sidebar/toast | `ShellView.swift`, `ShellModel.swift`, `ToastCenter.swift` |
| Thư viện: Năm/Tháng/Tất cả, grid, cover collage, phân trang | `LibraryView.swift`, `LibraryModel.swift`, `MonthYearViews.swift`, `CoverCollage.swift` |
| Tile + menu + info + confirm | `TileView.swift`, `TileMenuSheet.swift`, `ItemInfoSheet.swift`, `DeleteConfirmSheet.swift` |
| Selection (Chọn, bulk, marquee) | `SelectionBar.swift`, `MarqueeOverlay.swift` |
| Viewer | `ViewerView.swift`, `ViewerModel.swift`, `Filmstrip.swift`, `ZoomableImage.swift`, `LivePhotoView.swift` |
| Album (7 section, sort, density, morph) | `AlbumsView.swift`, `AlbumSectionView.swift`, `AlbumGrid.swift` |
| Search | `SearchView.swift`, `SearchModel.swift` |
| Connections sheet | `ConnectionsSheet.swift`, `CloudCardView.swift` |
| Settings | `SettingsView.swift`, `SettingsActions.swift` |
| Duplicates | `DuplicatesView.swift` |
| ZIP download | `BulkDownloadService.swift` |

### 5.3 Màn hình ↔ endpoint (hợp đồng API)

| Màn hình | Endpoint chính |
| --- | --- |
| Boot/Login | `GET /auth/me`, `POST /auth/login`, `POST /auth/logout` (`X-CSRF-Token`) |
| Shell/Bootstrap | `GET /bootstrap` (alias `/state`), `GET /stats` |
| Thư viện | `GET /items` (`cloud,type,favorite,album,year,month,person,province,district,q,limit=120,offset`), `GET /years`, `GET /months`, `GET /items/{id}`, `POST /items/{id}/favorite`, `POST /items/{id}/delete`, `POST /items/zip` |
| Media | `GET /items/{id}/thumb?size=`, `/preview`, `/media` (Range, `download=1`, `live=1`) |
| Viewer/Editor | `POST /items/{id}/edit` (multipart), `POST /items/{id}/download` |
| Albums | `GET /albums`, `GET /people`, `GET /places`, `GET /duplicates`, `GET /faces/{id}/cover`, `POST /people/{id}/rename` |
| Search | `GET /items?q=…&limit=300` |
| Connections | `GET /clouds`, `POST /clouds/active`, `POST /clouds/test`, `GET /bootstrap` |
| Settings | `POST /scans`, `POST /thumbs/retry`, `POST /cache/tmp/clear`, `POST /clouds/test` |
| Vault (native, có ghi) | `GET/POST /vaults`, `GET /vaults/{id}`, `GET/PUT /vaults/{id}/manifest` (CAS `prev_sha256`), `GET/PUT /vaults/{id}/blobs/{block}`, `POST /vaults/{id}/files`, `POST /vaults/{id}/delete`, `POST /vaults/{id}/rename` |
| Seafile E2EE (chỉ đọc) | `GET /e2ee/libraries`, `GET /e2ee/repos/{id}`, `/dir`, `/blocks`, `/files/{fid}/blocks/{bid}/link`, `/download-link` |
| Admin | `GET /admin/users`, `GET /admin/users/{id}`, `POST /admin/users…` (create/reset/activate/admin/delete/scan) |
| iCloud | `GET /icloud/status`, `POST /icloud/login`, `…/2fa`, `…/start`, `…/save`, `…/pause`, `…/resume`, `…/cancel`, `…/logout` |

> Ghi chú: danh sách đầy đủ và ngữ nghĩa lỗi nằm ở `mng-cloud-rs/docs/ARCHITECTURE.md`
> và `docs/UI_PARITY.md`. Khi server đổi, cập nhật `docs/API.md` của repo mới.

---

## 6. Cấu trúc repo `mng-cloud-sw`

```
mng-cloud-sw/
├── project.yml                      # XcodeGen (nguồn sự thật)
├── ExportOptions.plist.example
├── README.md
├── PLAN.md                          # tài liệu này
├── .gitignore
├── .swiftlint.yml                   # tuỳ chọn
├── docs/
│   ├── API.md                       # snapshot hợp đồng API
│   ├── PARITY.md                    # checklist parity theo phase
│   └── CRYPTO.md                    # KAT + quy ước bảo mật
├── App/
│   ├── App.swift                    # @main, AppRoot
│   ├── AppRoot.swift
│   ├── Features/
│   │   ├── Login/  Shell/  Library/  Viewer/  Albums/
│   │   ├── Search/ Vault/  Settings/ Admin/  Icloud/
│   │   └── Shared/                  # Tile, sheets, toast, error views
│   ├── DesignSystem/
│   │   ├── Tokens.swift             # màu, spacing, radius, motion
│   │   ├── Components.swift         # card, pill, seg, glass, spinner
│   │   └── Strings.swift            # toàn bộ chuỗi tiếng Việt 1:1
│   ├── Services/
│   │   ├── SessionStore.swift
│   │   ├── ThumbCache.swift
│   │   ├── MediaLoader.swift        # AVAssetResourceLoaderDelegate
│   │   └── Uploader.swift
│   └── Resources/
│       ├── Assets.xcassets/         # AppIcon, màu, logo
│       └── Info.plist               # do XcodeGen sinh
├── Packages/
│   ├── MNGCore/
│   │   ├── Package.swift
│   │   ├── Sources/MNGCore/
│   │   │   ├── Crypto/RepoKey.swift
│   │   │   ├── Crypto/VaultKey.swift
│   │   │   ├── Crypto/VaultManifest.swift
│   │   │   ├── Crypto/SecureBytes.swift
│   │   │   ├── Crypto/PBKDF2.swift
│   │   │   ├── SearchFold.swift
│   │   │   └── Hex.swift
│   │   └── Tests/MNGCoreTests/
│   │       ├── Fixtures/e2ee_kat.json
│   │       ├── Fixtures/vault_kat.json
│   │       ├── RepoKeyTests.swift
│   │       ├── VaultKeyTests.swift
│   │       └── SearchFoldTests.swift
│   ├── MNGKit/
│   │   ├── Package.swift
│   │   ├── Sources/MNGKit/
│   │   │   ├── MNGAPIClient.swift
│   │   │   ├── APIModels.swift
│   │   │   ├── APIError.swift
│   │   │   ├── Query.swift
│   │   │   └── Multipart.swift
│   │   └── Tests/MNGKitTests/       # decode fixtures, query, error mapping
│   └── MNGEdit/
│       ├── Package.swift
│       ├── Sources/MNGEdit/Editor.swift
│       └── Tests/MNGEditTests/
├── Tests/
│   └── MNGCloudTests/               # test app-level (session, view models)
└── .github/
    └── workflows/
        ├── ci.yml
        └── release.yml
```

---

## 7. XcodeGen — `project.yml`

```yaml
name: MNGCloud

options:
  bundleIdPrefix: com.mngcloud
  deploymentTarget:
    iOS: "17.0"
  createIntermediateGroups: true
  groupSortPosition: top
  generateEmptyDirectories: true

packages:
  MNGCore:
    path: Packages/MNGCore
  MNGKit:
    path: Packages/MNGKit
  MNGEdit:
    path: Packages/MNGEdit

settings:
  base:
    SWIFT_VERSION: "5.10"
    IPHONEOS_DEPLOYMENT_TARGET: "17.0"
    SWIFT_STRICT_CONCURRENCY: targeted
    ENABLE_USER_SCRIPT_SANDBOXING: YES
    CODE_SIGN_STYLE: Automatic
    DEVELOPMENT_TEAM: ""          # CI/người dùng điền khi ký
    MARKETING_VERSION: "1.0.0"
    CURRENT_PROJECT_VERSION: "1"

targets:
  MNGCloud:
    type: application
    platform: iOS
    sources:
      - path: App
    resources:
      - path: App/Resources
    info:
      path: App/Resources/Info.plist
      properties:
        CFBundleDisplayName: MNG Cloud
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        UILaunchScreen: {}
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
          - UIInterfaceOrientationLandscapeLeft
          - UIInterfaceOrientationLandscapeRight
        UISupportedInterfaceOrientations~ipad:
          - UIInterfaceOrientationPortrait
          - UIInterfaceOrientationPortraitUpsideDown
          - UIInterfaceOrientationLandscapeLeft
          - UIInterfaceOrientationLandscapeRight
        NSPhotoLibraryUsageDescription: "Chọn ảnh và video để tải lên kho mã hóa."
        NSPhotoLibraryAddUsageDescription: "Lưu ảnh và video về thư viện ảnh."
        NSAppTransportSecurity:
          NSAllowsLocalNetworking: true
        ITSAppUsesNonExemptEncryption: false
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.mngcloud.app
        TARGETED_DEVICE_FAMILY: "1,2"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        GENERATE_INFOPLIST_FILE: NO
        SUPPORTS_MACCATALYST: NO
        SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO
    dependencies:
      - package: MNGCore
      - package: MNGKit
      - package: MNGEdit
    scheme:
      testTargets:
        - MNGCloudTests
      gatherCoverageData: true
      coverageTargets:
        - MNGCloud
        - MNGCore
        - MNGKit

  MNGCloudTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: Tests/MNGCloudTests
    dependencies:
      - target: MNGCloud
      - package: MNGCore
      - package: MNGKit
```

`Packages/MNGCore/Package.swift` mẫu:

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MNGCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "MNGCore", targets: ["MNGCore"])],
    targets: [
        .target(name: "MNGCore"),
        .testTarget(
            name: "MNGCoreTests",
            dependencies: ["MNGCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
```

Lệnh local (trên macOS):

```bash
brew install xcodegen
xcodegen generate
open MNGCloud.xcodeproj
```

Trên Windows (máy hiện tại) không chạy được `xcodegen`; dùng CI:

```powershell
gh workflow run ci.yml
gh run watch
```

---

## 8. GitHub Actions

### 8.1 `ci.yml` — chạy mọi push/PR

```yaml
name: ci

on:
  push:
    branches: ["**"]
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  ios:
    runs-on: macos-15
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: "16.4"

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Cache SwiftPM and DerivedData
        uses: actions/cache@v4
        with:
          path: |
            ~/Library/Caches/org.swift.swiftpm
            Packages/**/.build
            build
          key: ios-${{ runner.os }}-${{ hashFiles('Packages/**/Package.swift', 'project.yml') }}

      - name: Generate project
        run: xcodegen generate

      - name: MNGCore tests (macOS, nhanh)
        run: swift test --package-path Packages/MNGCore

      - name: MNGKit tests (macOS)
        run: swift test --package-path Packages/MNGKit

      - name: Build simulator (unsigned)
        run: |
          xcodebuild -project MNGCloud.xcodeproj -scheme MNGCloud \
            -configuration Debug \
            -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
            -derivedDataPath build \
            CODE_SIGNING_ALLOWED=NO build

      - name: Test simulator
        run: |
          xcodebuild -project MNGCloud.xcodeproj -scheme MNGCloud \
            -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
            -derivedDataPath build \
            CODE_SIGNING_ALLOWED=NO test

      - name: Upload simulator app
        uses: actions/upload-artifact@v4
        with:
          name: MNGCloud-simulator
          path: build/Build/Products/Debug-iphonesimulator/MNGCloud.app
          if-no-files-found: error
```

> Lưu ý: runner macOS tính phút ×10. Giữ CI gọn: chỉ `swift test` cho package
> core, không chạy UI test mỗi push; UI test để workflow riêng/nightly.

### 8.2 `release.yml` — khi push tag `v*`

```yaml
name: release

on:
  push:
    tags: ["v*"]

permissions:
  contents: write

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false

jobs:
  detect-signing:
    runs-on: ubuntu-latest
    outputs:
      signed: ${{ steps.check.outputs.signed }}
    steps:
      - id: check
        env:
          P12: ${{ secrets.BUILD_CERTIFICATE_BASE64 }}
        run: |
          if [ -n "$P12" ]; then
            echo "signed=true" >> "$GITHUB_OUTPUT"
          else
            echo "signed=false" >> "$GITHUB_OUTPUT"
          fi

  build:
    needs: detect-signing
    runs-on: macos-15
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v4
      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: "16.4"
      - run: brew install xcodegen
      - run: xcodegen generate

      - name: Import signing identity
        if: needs.detect-signing.outputs.signed == 'true'
        env:
          P12_BASE64: ${{ secrets.BUILD_CERTIFICATE_BASE64 }}
          P12_PASSWORD: ${{ secrets.BUILD_CERTIFICATE_PASSWORD }}
          PROFILE_BASE64: ${{ secrets.PROVISIONING_PROFILE_BASE64 }}
          KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}
        run: |
          echo "$P12_BASE64" | base64 -d > /tmp/build.p12
          security create-keychain -p "$KEYCHAIN_PASSWORD" build.keychain
          security default-keychain -s build.keychain
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" build.keychain
          security import /tmp/build.p12 -k build.keychain \
            -P "$P12_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple: \
            -k "$KEYCHAIN_PASSWORD" build.keychain
          mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
          echo "$PROFILE_BASE64" | base64 -d \
            > ~/Library/MobileDevice/Provisioning\ Profiles/profile.mobileprovision

      - name: Archive (signed)
        if: needs.detect-signing.outputs.signed == 'true'
        env:
          TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          PROFILE_NAME: ${{ secrets.PROVISIONING_PROFILE_SPECIFIER }}
        run: |
          xcodebuild -project MNGCloud.xcodeproj -scheme MNGCloud \
            -configuration Release -destination 'generic/platform=iOS' \
            -archivePath build/MNGCloud.xcarchive \
            DEVELOPMENT_TEAM="$TEAM_ID" \
            CODE_SIGN_STYLE=Manual \
            PROVISIONING_PROFILE_SPECIFIER="$PROFILE_NAME" \
            archive

      - name: Export IPA
        if: needs.detect-signing.outputs.signed == 'true'
        run: |
          cp ExportOptions.plist.example ExportOptions.plist
          xcodebuild -exportArchive \
            -archivePath build/MNGCloud.xcarchive \
            -exportPath build/export \
            -exportOptionsPlist ExportOptions.plist \
            -allowProvisioningUpdates

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: MNGCloud-release
          path: |
            build/export/*.ipa
            build/MNGCloud.xcarchive
          if-no-files-found: warn

      # Tuỳ chọn: TestFlight (bỏ comment khi đã có App Store Connect API key)
      # - name: Upload to TestFlight
      #   if: needs.detect-signing.outputs.signed == 'true'
      #   env:
      #     ASC_KEY_ID: ${{ secrets.APPSTORE_KEY_ID }}
      #     ASC_ISSUER_ID: ${{ secrets.APPSTORE_ISSUER_ID }}
      #     ASC_KEY_PATH: /tmp/AuthKey.p8
      #   run: |
      #     echo "${{ secrets.APPSTORE_PRIVATE_KEY }}" > "$ASC_KEY_PATH"
      #     cp ExportOptions.plist.example ExportOptions.plist
      #     /usr/libexec/PlistBuddy -c "Set :destination upload" ExportOptions.plist
      #     xcodebuild -exportArchive \
      #       -archivePath build/MNGCloud.xcarchive \
      #       -exportPath build/upload \
      #       -exportOptionsPlist ExportOptions.plist \
      #       -authenticationKeyPath "$ASC_KEY_PATH" \
      #       -authenticationKeyID "$ASC_KEY_ID" \
      #       -authenticationKeyIssuerID "$ASC_ISSUER_ID"
```

`ExportOptions.plist.example`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>development</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>compileBitcode</key>
  <false/>
</dict>
</plist>
```

### 8.3 Secrets cần chuẩn bị (khi muốn bản cài được trên máy thật)

| Secret | Ý nghĩa |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | file `.p12` (development hoặc distribution), base64 |
| `BUILD_CERTIFICATE_PASSWORD` | mật khẩu `.p12` |
| `KEYCHAIN_PASSWORD` | mật khẩu keychain tạm trên runner |
| `PROVISIONING_PROFILE_BASE64` | `.mobileprovision` base64 |
| `PROVISIONING_PROFILE_SPECIFIER` | tên profile |
| `APPLE_TEAM_ID` | Team ID |
| `APPSTORE_KEY_ID` / `APPSTORE_ISSUER_ID` / `APPSTORE_PRIVATE_KEY` | API key TestFlight (tuỳ chọn) |

Không có secrets → CI vẫn xanh với bản simulator (dùng để QA giao diện, chụp
screenshot, test logic).

---

## 9. Tương thích crypto (cổng chặn quan trọng nhất)

### 9.1 Seafile E2EE (giữ nguyên format trên đĩa)

Nguồn: `crates/mng-core/src/crypto/e2ee.rs`, KAT: `tests/fixtures/e2ee_kat.json`.

| Tham số | Giá trị |
| --- | --- |
| Salt v2 | cố định `da9045c306c7cc26` |
| Salt v3 | 32 byte ngẫu nhiên lưu cùng thư viện |
| Key | `PBKDF2-SHA256(password, salt, 1000, 32)` |
| Magic | `PBKDF2-SHA256(repo_id ‖ password, salt, 1000, 32)` |
| Key IV | `PBKDF2-SHA256(key, salt, 10, 16)` |
| Random key | `AES-256-CBC(key, keyIV, secret)` — secret 32 byte |
| Content key | `PBKDF2-SHA256(secret, salt, 1000, 32)` |
| Content IV | `PBKDF2-SHA256(contentKey, salt, 10, 16)` |
| Block | `AES-256-CBC(contentKey, contentIV, PKCS#7)`, tối đa 8 MiB plaintext |
| Block id | `SHA-1(ciphertext)` hex thường |
| `ciphertextLen(n)` | `n + 16 - (n % 16)` |

Yêu cầu test:

- Mở khoá v2 và v3 bằng `e2ee_kat.json` → `content_key_hex`, `content_iv_hex`
  khớp từng byte.
- Encrypt `plain_hex` → đúng `cipher_hex`; `blockId(cipher)` → đúng `block_id`.
- Empty block → `empty_cipher_hex`, `empty_block_id`.
- Sai mật khẩu → lỗi `WrongPassword` (không tiết lộ chi tiết), so sánh
  constant-time.
- `decryptBlock` từ chối ciphertext rỗng, không chia hết 16, quá
  `BLOCK_BYTES + 16`.

### 9.2 Native vault (`mng-vault/v1`)

Nguồn: `crates/mng-core/src/crypto/vault.rs`, KAT: `vault_kat.json`.

| Tham số | Giá trị |
| --- | --- |
| KDF | `PBKDF2-SHA256`, 310.000 vòng, mật khẩu NFKC-normalized |
| Mã hoá | `AES-256-GCM`, nonce 12 byte ngẫu nhiên, tag 16 |
| Blob | `iv ‖ ciphertext ‖ tag` |
| AAD manifest | `mng-vault/v1/{uid}/manifest` |
| AAD verifier | `mng-vault/v1/{uid}/verifier` |
| AAD chunk | `mng-vault/v1/{uid}/file/{file_id}/chunk/{index}/{total}` |
| AAD thumb | `mng-vault/v1/{uid}/file/{file_id}/thumb` |
| Chunk plaintext | 4 MiB |
| Manifest CAS | `PUT /vaults/{id}/manifest` kèm `prev_sha256` + `bytes`; `409 stale` → refetch, giải mã, áp lại một lần rồi retry |
| Giới hạn | 32 vault/owner, file ≤ 16 GiB |

Yêu cầu test: unlock bằng `vault_kat.json` → verifier khớp; decrypt
`manifest_b64` → đúng `manifest_json`; decrypt `chunk_b64` với đúng AAD →
`chunk_plain`; decrypt `thumb_b64` → `thumb_plain`; sai AAD/nonce/tag → lỗi.

### 9.3 Quy ước bảo mật trong Swift

- `SecureBytes`: wrapper cấp phát thô, zeroize bằng `memset_s`, không copy
  ngầm; key/IV/secret chỉ sống trong wrapper này.
- Không dùng `String` để giữ key; mật khẩu người dùng đọc từ `UITextField`
  (secure entry), chuyển sang `[UInt8]`, xoá ngay sau khi derive.
- So sánh magic/verifier bằng `CryptoKit` constant-time hoặc
  `timingsafe_bcmp`-tương đương tự viết (XOR tích luỹ, không early-return).
- PBKDF2: CommonCrypto `CCKeyDerivationPBKDF` (nhanh, ổn định); AES-CBC:
  CommonCrypto `CCCrypt` không bật padding, PKCS#7 được thêm và kiểm tra thủ
  công để từ chối padding sai như Rust; AES-GCM: CryptoKit.
- Hash: `CryptoKit.Insecure.SHA1` (chỉ để tương thích block id, không dùng
  cho bảo mật mới).
- Không log mật khẩu/key/plaintext; log lỗi chỉ mã lỗi.
- Ảnh/plaintext tạm khi preview: ghi file tạm trong container, xoá khi đóng;
  đặt `isExcludedFromBackup`.

### 9.4 Cổng chặn trong CI

- `MNGCoreTests` chạy trên macOS (nhanh) và iOS Simulator (xác nhận build
  Apple platform).
- KAT fixtures copy nguyên văn từ `mng-cloud-rs` — không sửa giá trị kỳ vọng.
- PR nào chạm `Packages/MNGCore/Crypto/**` bắt buộc KAT xanh + review bảo mật.

---

## 10. Tương thích UI

### 10.1 Design tokens (trích `ui/assets/app.css`)

| Token | Dark | Light |
| --- | --- | --- |
| `bg` | `#07090d` | `#ffffff` |
| `bg-grouped` | `#0b0f15` | `#f2f2f7` |
| `bg-elev` | `#10151d` | `#ffffff` |
| `text` | `#f2f5f9` | `#000000` |
| `text-muted` | `#9aa7b6` | `#6e6e73` |
| `sep` | `rgba(255,255,255,.12)` | `rgba(60,60,67,.22)` |
| `fill` | `rgba(255,255,255,.08)` | `rgba(120,120,128,.12)` |
| `accent` | `#7dd3fc` | `#007aff` |
| `accent-strong` | `#38bdf8` | `#0066d6` |
| `danger` | `#fb7185` | `#ff3b30` |
| `green` | `#34d399` | `#34c759` |
| `orange` | `#fbbf24` | `#ff9500` |
| `brand-blue` | `#38bdf8` | `#0082c9` |
| `sf` (Seafile) | `#2dd4bf` | `#0a7c74` |
| `icloud` | `#60a5fa` | `#1c8bfa` |
| Radius | `8 / 12 / 16 / 28` | như trên |
| Glass | blur 24, saturate 185%, viền trắng 0.18 | blur 24, saturate 185%, viền trắng 0.62 |
| Motion | `cubic-bezier(0.32,0.72,0,1)`; spring `(0.34,1.4,0.64,1)` | như trên |

Chuyển thành asset catalog color set có Any/Dark; một enum `Tokens` cung cấp
`Color.bg`, `Color.card`, `Tokens.radiusL`… Không hard-code màu trong view.

### 10.2 Bố cục & điều hướng

| Web (Leptos) | iOS |
| --- | --- |
| Sidebar 264 px khi ≥ 861 px | `NavigationSplitView` ở regular width (iPad, iPhone landscape Plus/Max) |
| Mobile header + tabbar 4 tab khi ≤ 860 px | `TabView` 4 tab: Thư viện, Album, Kho mã hóa, Cài đặt; nút tìm kiếm trên header |
| Nút "Thêm" đã bị bỏ ở bản 0.3.1 | Không có |
| Admin mở từ Settings/sidebar | Navigation từ Settings, mount lười |
| Dialog/sheet web | `.sheet`, `.fullScreenCover`, `.confirmationDialog` |
| Right-click/150+170 ms long-press menu | `.contextMenu` + sheet hành động |
| Marquee chọn ảnh (desktop) | Chế độ "Chọn" + tap; iPad: kéo chọn (phase 11) |
| FLIP filter/sort/group morph | `matchedGeometryEffect` + animation 300 ms, tôn trọng Reduce Motion |
| Glassmorphism CSS | `.ultraThinMaterial`/custom material + stroke |
| Web font hệ thống | SF Pro (Dynamic Type) |

### 10.3 Chuỗi tiếng Việt

Tập trung tại `DesignSystem/Strings.swift`; copy nguyên văn từ shell/PWA:

- Điều hướng: `Thư viện`, `Album`, `Kho mã hóa`, `Cài đặt`, `Quản trị`.
- Thư viện: `Năm`, `Tháng`, `Tất cả`, `Ảnh`, `Video`, `Live`, `Yêu thích`, `Chọn`.
- Viewer: `Thông tin`, `Tải xuống`, `Chỉnh sửa`, `Xóa`, `Hủy`.
- Trạng thái: `Đang kiểm tra…`, `Kết nối tốt`, `Không phản hồi`, `Chưa kiểm tra`,
  `Đã sao chép liên kết WebDAV.`, `Đã xếp hàng quét thư viện.`,
  `Hàng đợi tác vụ chưa được bật.`, `Thao tác ghi chưa được bật.`,
  `Đã xóa N tệp tạm.`, `Không có tệp tạm nào để xóa.`,
  `Kho đã tự khóa sau 15 phút không hoạt động.`, `Mật khẩu không đúng.`,
  `Chưa hỗ trợ trên máy chủ này`, `Không khả dụng`.
- Lỗi API map 1:1: `network` → `Không kết nối được máy chủ.`,
  `invalid_response` → `Máy trả về dữ liệu không hợp lệ.`, 401 → logout,
  403 CSRF → thông báo phiên hết hạn.

Không dịch máy; giữ đúng dấu tiếng Việt và cách viết số `1.966 mục`, `13.1 GB`
(theo định dạng `vi-VN`).

### 10.4 Khác biệt chấp nhận được

- Không thể pixel-perfect 100% giữa CSS và SwiftUI; mục tiêu là **tương đương
  thị giác**: màu, khoảng cách, thứ tự, nhãn, trạng thái, chuyển động.
- Hành vi nền tảng: share sheet, Photos picker, Files, notification, haptics.
- Không có hover; long-press thay right-click.
- Bàn phím cứng (iPad) hỗ trợ mũi tên/Escape ở viewer (phase 11).

---

## 11. Lộ trình 12 giai đoạn

> Ước lượng theo "tuần người" cho 1 dev quen Swift; có thể song song hoá P1/P2.

| Phase | Nội dung | Ước lượng |
| --- | --- | --- |
| P0 | Khung dự án + XcodeGen + CI xanh | 0.5 tuần |
| P1 | `MNGCore` crypto + KAT + SearchFold | 1–1.5 tuần |
| P2 | `MNGKit` API + session + Login/Boot | 1 tuần |
| P3 | Shell + Thư viện + tile actions | 2 tuần |
| P4 | Viewer (ảnh/video/live, zoom, filmstrip) | 1.5 tuần |
| P5 | Albums + Search + Connections | 1.5 tuần |
| P6 | Settings + actions + Duplicates | 1 tuần |
| P7 | Vault native + Seafile E2EE | 2.5 tuần |
| P8 | Editor ảnh | 1 tuần |
| P9 | Admin | 1 tuần |
| P10 | iCloud sheet | 0.5 tuần |
| P11 | Parity extras + performance + release | 2 tuần |
| **Tổng** | | **~15.5 tuần** |

### P0 — Khung dự án & CI (0.5 tuần)

Việc chính:

- `git init`, `.gitignore` (Xcode, `build/`, `DerivedData/`, `.build/`,
  `*.xcuserstate`, `.DS_Store`, `ExportOptions.plist`).
- `project.yml`, `App/Resources/Info.plist` (XcodeGen sinh), `Assets.xcassets`
  (AppIcon lấy từ `icon-512.png`, AccentColor, LaunchBackground).
- 3 package rỗng + 1 test "hello" mỗi package.
- `App/App.swift` + `AppRoot` hiển thị BootScreen tĩnh.
- `ci.yml` chạy xanh.

Nghiệm thu: tag `v0.1.0-ci`; CI build + test < 20 phút; artifact simulator tải
được.

### P1 — MNGCore: crypto & KAT (1–1.5 tuần)

Việc chính:

- `SecureBytes`, `PBKDF2` (CommonCrypto), `AES-CBC` (CommonCrypto),
  `AES-GCM` (CryptoKit), `SHA1`, hex/base64, constant-time compare.
- `RepoKey`: `unlock(encVersion:repoId:password:magicHex:randomKeyHex:saltHex:)`,
  `encryptBlock`, `decryptBlock`, `ciphertextLen`, `blockId`.
- `VaultKey`: derive 310k NFKC, verifier, encrypt/decrypt blob với AAD,
  encode/decode chunk, manifest Codable.
- `SearchFold.fold` + `rawurldecode` (bảng fold từng ký tự như Rust).
- Copy 2 file KAT vào test resources; viết test khớp từng hex.
- Test fold: `"  Ảnh   Đà-Lạt (2024)!!  "` → `"anh da lat 2024"`,
  `"Đường Trần Hưng Đạo"` → `"duong tran hung dao"`, decomposed `a\u{301}n\u{300}`
  → `"an"`.

Nghiệm thu: `swift test --package-path Packages/MNGCore` xanh trên macOS và
simulator; 100% KAT; không force-unwrap; không log bí mật.

Trạng thái (2026-11-10): đã port `SecureBytes`, PBKDF2/AES-CBC/AES-GCM,
`RepoKey`, `VaultKey` + manifest, `SearchFold`; đã viết KAT v2/v3, vault và
fold tests. Type-check Swift 5.10 bằng Compiler Explorer với stub framework
Apple đạt; CI macOS run 42850116522 (2026-11-10) đã chạy toàn bộ KAT xanh.

### P2 — MNGKit API + Session/Login (1 tuần)

Việc chính:

- `MNGAPIClient`: base URL từ `UserDefaults` (màn hình login cho nhập, mặc
  định lưu lần trước), `URLSessionConfiguration` với `httpCookieStorage`,
  `httpShouldSetCookies = true`, `requestCachePolicy = .reloadIgnoringLocalCacheData`.
- `APIError` với `status/code/message`, map lỗi mạng/401/403/503 đúng câu
  tiếng Việt.
- DTO Codable: `Me`, `AuthResponse`, `Bootstrap`, `CloudCard`, `CloudCounts`,
  `CloudHealth`, `Item`, `ItemDetail`, `ItemFilters`, `YearBucket`, `MonthBucket`,
  `Album`, `Person`, `Place`, `DuplicateGroup`, `VaultMeta`, `E2eeLibrary`,
  `AdminUser`, `IcloudStatus`, `Stats`, `ScanStatus`… (đối chiếu `api.rs`).
- Endpoint methods + query builder (`cloud, type, favorite, album, year, month,
  q, person, province, district, limit, offset`).
- `SessionStore`: `checking → login/ready`; `me()` khi khởi động; CSRF trong
  bộ nhớ; logout gọi `POST /auth/logout` kèm header rồi xoá cookie.
- `LoginView` (card, logo, lỗi), `BootScreen` (thử lại).

Nghiệm thu: đăng nhập box staging; relaunch vẫn còn phiên (cookie); logout;
mutation gửi `X-CSRF-Token`; sai mật khẩu hiển thị đúng câu; không log bí mật.

Trạng thái (2026-11-10): đã port `APIError`, chuẩn hoá origin và `/api/v1`,
query builder, DTO đọc, `MNGAPIClient` (cookie + CSRF), `SessionStore`,
`LoginView`/`BootScreen`. Type-check Swift 5.10 và runtime harness
(`URLProtocol`) trên Compiler Explorer đạt; CI macOS run 42850116522 đã chạy
92 test MNGKit và build/test simulator xanh.

### P3 — Shell + Thư viện + tile actions (2 tuần)

Việc chính:

- `RootView`: regular = `NavigationSplitView` sidebar 264; compact = `TabView`
  4 tab + header + nút tìm kiếm.
- `LibraryView`: Năm/Tháng/Tất cả; filter Ảnh/Video/Live/Yêu thích; drill-down
  năm → tháng; phân trang 120 mục; giữ vị trí cuộn khi nạp trang cũ; cover
  collage 4 ảnh; lưới adaptive.
- `ThumbCache` actor: `NSCache` + đĩa LRU trong `Caches/`, key theo URL,
  placeholder khi thiếu; prefetch quanh viewport; xoá khi logout.
- Tile: long-press menu (Yêu thích/Thông tin/Tải xuống/Chỉnh sửa/Xóa), info
  sheet (fetch `/items/{id}`), favorite optimistic + rollback + toast, delete
  confirm, chế độ Chọn (đếm, favorite/download/delete/cancel, Escape).
- ZIP nhiều ảnh: `POST /items/zip` form `csrf` + `ids[]`, giới hạn 100 mục/2 GiB,
  tải về rồi share sheet (phase 11 hoàn thiện UI chọn nhiều).

Nghiệm thu: parity checklist 390/768/1440 pt tương đương, light/dark, không
tràn ngang; 1.966 mục hiển thị đúng; favorite/delete rollback khi 503
`writer_unavailable`; nhãn tiếng Việt đúng.

Trạng thái (2026-11-10): đã port shell compact (header 36pt + tab bar nổi 4 tab +
nút tìm kiếm) và regular (sidebar 264pt + 5 mục), cloud picker, toast; thư viện
Năm/Tháng/Tất cả, chip Ảnh/Video/Live, phân trang 120 mục, collage 4 ảnh, lưới
3 cột/adaptive, skeleton/empty/error, kéo để tải lại; tile mở info sheet (viewer
ở P4), menu ngữ cảnh, favorite/delete optimistic + rollback theo chunk 4, chế độ
Chọn và ZIP qua share sheet. Logic thuần nằm trong `MNGKit` (`LibrarySupport`,
`MNGFormat`, `ItemMedia`) và đã type-check Swift 5.10 trên Compiler Explorer;
CI macOS run 42850116522 đã build simulator, chạy test và upload artifact xanh.
Kiểm tra trên thiết bị còn chờ: thứ tự đóng info sheet → alert xoá, share sheet
ngay sau khi đóng sheet, và header dính của timeline.

### P4 — Viewer (1.5 tuần)

Việc chính:

- `ViewerView` full-screen: title/sub, stage, prev/next, filmstrip lazy +
  scroll tới item hiện tại.
- Ảnh: pinch zoom, double-tap, pan, swipe xuống để đóng (khi zoom 1x).
- Video: `AVPlayer` + `MediaLoader` scheme riêng (cookie + CSRF + Range);
  poster là thumbnail; HEIC preview 404 → fallback thumbnail 360.
- Live Photo: nút/giữ để phát companion `?live=1`, badge LIVE, dừng khi đóng.
- Favorite optimistic, info sheet, download (share sheet/Photos), edit (P8),
  delete confirm + chuyển sang ảnh kế, đóng khi hết danh sách.
- Hỗ trợ `AVAudioSession` phù hợp, dừng phát khi background.

Nghiệm thu: seek video mượt trên box staging; Live Photo; zoom/pan/đóng;
filmstrip 100+ ảnh không tụt FPS; rời màn hình dừng tải.

Trạng thái (2026-11-10): đã port `ViewerView` full-screen với top chrome
(đóng/tiêu đề/URL phụ/favorite/info), stage ảnh, prev/next trên iPad, filmstrip
lazy 46pt tự căn giữa, footer LIVE/tải xuống/xóa; pinch 1–5×, double-tap 2.4×,
pan, vuốt ngang chuyển ảnh và vuốt xuống đóng đúng ngưỡng PWA. Ảnh dùng preview
cache riêng, fallback thumbnail 360 và retry một lần sau 4,5 giây. Video/Live
Photo dùng `AVPlayer` với cookie phiên qua `AVURLAssetHTTPCookiesKey` (không cần
scheme `MediaLoader` riêng; AVFoundation tự xử lý Range/seek), poster thumbnail,
dừng khi background hoặc đóng viewer. Favorite/info/download/delete dùng chung
`LibraryModel`; xóa optimistic chuyển ảnh kế và đóng khi hết danh sách, rollback
toàn bộ snapshot viewer khi lỗi. Logic thuần nằm trong `MNGKit`
(`ViewerCollection`, `ViewerRemoval`, `MNGFormat.viewerTitle/viewerSubtitle`) và
đã type-check Swift 5.10 trên Compiler Explorer; CI macOS run 42850116522 đã
build/test simulator xanh. Kiểm tra trên thiết bị còn chờ:
pinch/double-tap, căn giữa filmstrip, seek video, Live Photo, thứ tự info sheet
trên viewer và dừng phát khi vào background.

### P5 — Albums + Search + Connections (1.5 tuần)

Việc chính:

- Albums 7 section gập/mở: Ảnh gần đây, Ảnh yêu thích, Bộ sưu tập, Năm, Mọi
  người, Địa điểm, Quận/huyện; preview 9 ảnh + `Xem tất cả`/`Thu gọn`; sort và
  density `Lớn/Vừa/Nhỏ`; morph `matchedGeometryEffect` (Reduce Motion → không
  animation).
- Search: debounce 280 ms, 5 chip (Tất cả/Ảnh/Video/Live/Yêu thích), 4 gợi ý
  (Năm 2022, Yêu thích, Video, Live Photo), lưới phẳng, cap 300, back đúng đích.
- Connections sheet: card cloud (màu, label, `username · root`, count vi-VN,
  health dot, check active, WebDAV + Sao chép), iCloud row mở sheet; active
  cloud lưu `UserDefaults`, request kèm `cloud=`; không POST `set_cloud` (parity
  bản triển khai).
- Cloud picker pill trên header mobile.

Nghiệm thu: số liệu khớp fixture (87 people, 8 provinces, 15 districts — dùng
snapshot test); tìm `q=20221231` 1 kết quả, `q=IMG` 300/1.814; dark/light;
không gọi admin users khi vào app.

Trạng thái (2026-11-10): đã port tab Albums với 7 section gập/mở đúng thứ tự,
preview 9 ảnh + `Xem tất cả`/`Thu gọn`, sort/density riêng từng section, lưới
ảnh/người/địa điểm theo `app.css`, banner AI + poll 20 giây theo signature 5 bộ
đếm, skeleton/empty/error và đổi tên người optimistic + rollback. Search có
debounce 280 ms, 5 chip, 4 gợi ý, cap 300, meta `n kết quả cho "q"` (chuyển sang
số dòng đã tải sau khi xoá) và mở album với tab quay lại đúng. Connections thay
cloud picker cũ: card cloud + health + sao chép WebDAV, hàng iCloud chỉ đọc
(importer đầy đủ để P7). Album mở ngay trong tab Library với toolbar/footer/
selection/paging tắt; back trả về Albums hoặc Search, tab highlight theo
`album_return`. Favorite/delete từ Library được đồng bộ sang Search/Albums bằng
snapshot + rollback. Logic thuần nằm trong `MNGKit/AlbumSupport` kèm
`AlbumSupportTests`; `mngkit_typecheck`, model harness và app parse đã xanh,
CI macOS run 42850116522 đã build/test simulator xanh. Chưa port morph FLIP
(`matchedGeometryEffect`) giữa album card và lưới Library; vì chưa có animation
chuyển album nên Reduce Motion không cần xử lý riêng. Kiểm tra thiết bị còn chờ:
số liệu fixture, `q=20221231`/`q=IMG`, back target, đổi cloud, đổi tên người và
info/xoá từ Search/Albums.

### P6 — Settings + actions + Duplicates (1 tuần)

Việc chính:

- Settings đúng thứ tự: Kết nối, iCloud, Thư viện, Tài khoản, Giới thiệu.
- Hàng cloud: health (`Kết nối tốt · N ms`, `Không phản hồi`, `Chưa kiểm tra`),
  counts, màu icon, link Seafile, tổng đã index, dung lượng trống, vault switch,
  admin link, đăng xuất.
- Actions: kiểm tra kết nối (`POST /clouds/test`), quét lại (`POST /scans`
  `{"cloud":"all"}`), tạo lại thumbnail lỗi (`POST /thumbs/retry`), xoá tệp tạm
  (`POST /cache/tmp/clear`); trạng thái busy, thông báo đúng khi 503/202/200.
- Duplicates: summary legacy, 30 nhóm/trang, `Xem thêm N nhóm`, mở viewer với
  toàn bộ item trong nhóm.
- 401 → đăng xuất; 403 CSRF → thông báo phiên.

Nghiệm thu: với box không bật writer/queue hiển thị đúng câu 503; với queue bật
tạo đúng 1 request và báo trùng; số tệp tạm đã xoá; free space `13.1 GB`.

Trạng thái (2026-11-10): đã port Settings đầy đủ theo thứ tự PWA (Kết nối →
iCloud → Thư viện → Công cụ → Tài khoản → Giới thiệu). Mỗi cloud card hiển thị
`username · N mục`, health dot và tap để `POST /clouds/test`; hàng "Mở máy
chủ" mở `/seafile/` qua `openURL`. Các action `POST /scans` (`cloud=all`), `/thumbs/retry`,
`/cache/tmp/clear` có busy riêng từng hàng, giữ nguyên câu lỗi 503/writer của
server qua `APIMessages.settingsAction`, refresh bootstrap sau khi xong. iCloud
row refresh mỗi lần mở Settings nhưng không poll. Duplicates sheet đọc
`/duplicates`, summary `hashed/total`, mở 30 nhóm/trang, grid thumbnail 128 pt,
mở viewer với đúng danh sách nhóm và giữ nút `Xem thêm N nhóm`. Đã thêm DTO +
client method + test request/CSRF/decode; CI P6 run 42858021122 (2026-11-11)
xanh toàn bộ: MNGCore, MNGKit, MNGEdit, build và test simulator. Chưa có hàng
Admin (P9) và action "Dung lượng" chỉ đọc.

### P7 — Vault native + Seafile E2EE (2.5 tuần)

Việc chính (native, có ghi):

- Danh sách vault, tạo vault (uid 32 hex, salt, verifier, manifest rỗng mã hoá),
  unlock PBKDF2 310k (NFKC), breadcrumb, tree, search theo tên (file hit hiện
  đường dẫn cha), preview text/ảnh/video, thumbnail giải mã.
- Upload: chia 4 MiB plaintext, AES-GCM với AAD chunk, `PUT /vaults/{id}/blobs/{block}`
  (block = SHA-1 40 hex của ciphertext), commit `POST /vaults/{id}/files`, cập
  nhật manifest với `prev_sha256`/`bytes`, retry một lần khi `409 stale`.
- Tạo thư mục, xoá file (manifest + xoá remote + writer), đổi tên vault, xoá
  vault: xác nhận bằng mật khẩu, verify local trước, server ping preflight.
- Auto-lock 15 phút không tương tác + khi `scenePhase` background; xoá key,
  huỷ file tạm/thumbnail; giới hạn 32 vault.
- Seafile E2EE (chỉ đọc): danh sách thư viện mã hoá, unlock `RepoKey` v2/v3,
  duyệt `/dir`, lấy `/blocks`, tải one-shot `/link`, xác minh SHA-1 trước khi
  giải mã AES-CBC, preview text/ảnh/video, khoá thủ công.

Nghiệm thu: KAT unlock; kịch bản fixture: sai mật khẩu → đúng câu, unlock →
Album → Tài liệu → ảnh → text → khoá; upload file nhỏ/4 MiB/4 MiB+1; CAS 409
retry; xoá vault đòi mật khẩu; không log/không gửi mật khẩu hay key; tự khoá
sau 15 phút.

P7.2 (2026-11-11): tải lên từ Files (document picker) hoặc thư viện ảnh
(PhotosPicker); mỗi tệp chia 4 MiB, mỗi khối mã hóa AES-256-GCM với AAD
`chunk/{index}/{total}`, block id = SHA-1 40 hex của ciphertext (server tự
kiểm tra lại), `PUT /blobs/{block}` rồi `POST /files` commit và ghi vào manifest
bằng CAS. Xem trước: tải từng khối, giải mã, ghép lại; ảnh hiện trực tiếp, video
phát bằng `AVPlayer` từ file tạm (xoá khi đóng), text hiện 2 MiB/200k ký tự,
định dạng khác hiện "không xem trước được". Thumbnail giải mã khi manifest có
`thumb`. Còn lại P7.3: đổi tên kho, sinh thumbnail mới khi tải lên, chuyển ảnh
từ thư viện sang kho. Trình duyệt E2EE Seafile đã bị PWA gỡ khỏi UI
(`vault.rs` chỉ còn native vault) nên không port sang iOS; crypto `RepoKey` v2/v3
vẫn nằm trong MNGCore với KAT.

Trạng thái (2026-11-11) — P7.1 xong: tab Kho thay placeholder bằng màn hình
thật (danh sách → mở khoá → duyệt). Tạo kho sinh uid 32 hex + salt 16 byte,
mã hoá verifier và manifest rỗng bằng AES-256-GCM rồi `POST /vaults`; mật
khẩu chỉ chạy PBKDF2 310k (ngoài main actor) và không rời thiết bị. Mở khoá
verify verifier rồi giải mã manifest (chỉ dùng `sanitizeManifest`). Cây thư
mục dùng đúng thứ tự sort fold của PWA, tìm kiếm fold theo tên, breadcrumb và
đường dẫn cha. Tạo/xoá thư mục và xoá tệp đi qua manifest CAS (`prev_sha256`/
`bytes`) và retry một lần khi `409 stale`; xoá kho xác nhận bằng mật khẩu và
verify local trước khi gọi server. Khoá tự động khi rời tab, sau 15 phút không
tương tác và khi app vào nền. MNGKit đã có đủ route vault (list/create/manifest
CAS/prepare/commit/blob upload/binary download/delete/rename) kèm test.
P7.3 (2026-11-11): đổi tên kho (`POST /vaults/{id}/rename`) và chuyển ảnh từ
thư viện sang kho ("Chuyển vào kho mã hóa" trong menu ô và thanh chọn nhiều):
tải media của mục, mã hóa/chia khối y như tải lên, ghi manifest rồi mới xoá bản
gốc trên cloud. Yêu cầu chờ cho tới khi mở khoá một kho, giống `move_request`
của PWA. Còn lại: sinh thumbnail mới khi tải lên (PWA web không tạo thumbnail
nên chưa xác minh được giao thức) và trình duyệt E2EE Seafile đã bị PWA gỡ
khỏi UI (`vault.rs` chỉ còn native vault) nên không port sang iOS; crypto
`RepoKey` v2/v3 vẫn nằm trong MNGCore với KAT.

### P8 — Editor ảnh (1 tuần)

Việc chính:

- `MNGEdit/Editor`: decode ảnh (downsample preview 1600), geometry rotate 0/90/
  180/270, flip H/V, crop chuẩn hoá; thứ tự **rotate → flip → crop**.
- Adjustments: brightness, contrast, saturation, exposure, warmth, tint,
  highlights, shadows, vignette (giới hạn như Rust: ±100, vignette 0…100).
- Filters: `original`, `vivid`, `warm`, `cool`, `mono`, `fade` (hệ số như
  `mng-edit` để màu gần nhất).
- Export `jpeg`/`png`/`webp` (thử ImageIO WebP; nếu thiết bị không hỗ trợ thì
   báo lỗi rõ hoặc fallback JPEG), quality; multipart `POST /items/{id}/edit`;
  progress + lỗi.
- Giới hạn: cạnh ≤ 20.000 px, tổng điểm ảnh ≤ 120 triệu.

Nghiệm thu: ảnh xoay đúng EXIF; so sánh mắt thường với PWA; lưu xong cập nhật
danh sách; huỷ giữa chừng không hỏng dữ liệu.

### P9 — Admin (1 tuần)

Việc chính:

- `AdminView` mount lười từ Settings (không request khi vào app).
- Stats, danh sách user, tạo user, reset/reprovision mật khẩu cloud, bật/tắt,
  cấp/thu admin, xoá user (tuỳ chọn xoá dữ liệu cloud), scan theo hàng đợi
  Scan → Thumbs → pHash.
- Xử lý invariant (primary admin, self, last admin) và lỗi 403/409.

Nghiệm thu: fixture admin; vào app 0 request admin; mở/đóng console đúng 1
request; xoá user có/không dữ liệu cloud.

### P10 — iCloud sheet (0.5 tuần)

Việc chính:

- Status refresh khi mở; poll 2,2 s chỉ khi job đang chạy; đóng sheet dừng poll.
- Login Apple ID + mật khẩu, 2FA 6 số, start (số ảnh gần đây, tuỳ chọn xoá sau
  khi lưu), save, pause/resume/cancel, logout; sequence-guard cho save.
- Degrade trung thực: 404/405/501 → `Chưa hỗ trợ trên máy chủ này` + giải thích
  + nút thử lại; lỗi mạng → `Không kiểm tra được`.

Nghiệm thu: box không có endpoint → đúng trạng thái, không giả connected;
không poll khi sheet đóng.

### P11 — Parity extras, hiệu năng, phát hành (2 tuần)

Việc chính:

- Hoàn thiện multi-select + ZIP + share; marquee iPad; hardware keyboard
  (←/→/Escape) cho viewer; haptics.
- Dynamic Type, VoiceOver label, Reduce Motion, contrast; localization `vi`
  (mặc định) + `en` (tuỳ chọn).
- Hiệu năng: thư viện 2.000+ mục, prefetch thumbnail, memory warning, decode
  ảnh lớn, video 4K; `os_signpost` đo.
- Offline/error states, retry, refresh kéo xuống; xử lý app background.
- Icon/launch screen, screenshot iPhone 15 + SE + iPad, TestFlight, metadata
  (nếu phát hành công khai: privacy manifest, account deletion…).

Nghiệm thu: TestFlight build cài được; không crash trong 30 phút duyệt thư
viện; bộ screenshot parity đủ; hiệu năng cuộn 60 fps trên thiết bị thật.

---

## 12. Test plan

### 12.1 Unit (chạy mỗi PR)

- `MNGCoreTests`: toàn bộ KAT e2ee + vault, fold, hex, constant-time,
  ciphertext length, lỗi biên.
- `MNGKitTests`: decode fixture JSON thật (thu bằng `curl` từ box staging, lưu
  `Tests/Fixtures/*.json`), query builder, error mapping, multipart boundary.
- `MNGEditTests`: kích thước output, thứ tự geometry, filter mono, export.
- `MNGCloudTests`: view model thuần (sort, filter, page merge, selection).

### 12.2 Integration (thủ công/định kỳ, không đưa credentials vào CI)

Kịch bản trên box staging:

1. Boot → login sai → đúng câu; login đúng → bootstrap.
2. Thư viện: 3 chế độ, filter, phân trang, thumbnail, viewer ảnh/video.
3. Favorite/delete (có writer) và rollback (không writer).
4. Album/section/search với dữ liệu thật.
5. Vault: tạo → upload → preview → xoá file → xoá vault; Seafile E2EE unlock +
   preview.
6. Settings actions, admin (nếu có quyền), iCloud degrade.
7. Mất mạng giữa request; 401 giữa phiên; app vào background.

### 12.3 UI test (nightly/tuỳ chọn)

- Login smoke, library load (stub URLProtocol), mở/đóng viewer, mở Settings.
- Snapshot screenshot đính kèm PR cho các phase UI.

### 12.4 Cổng chất lượng CI

- Build + test xanh, không warning mới.
- Không secret trong repo/log.
- KAT không đổi giá trị kỳ vọng.
- PR template có checklist parity + ảnh chụp light/dark.

---

## 13. Rủi ro & giảm thiểu

| Rủi ro | Mức | Giảm thiểu |
| --- | --- | --- |
| Crypto lệch Rust (padding, NFKC, thứ tự PBKDF2) | Cao | KAT từ P1; test từng field; nếu bế tắc tạm dùng UniFFI bridge `mng-core` (phương án dự phòng, không phải mặc định) |
| AVPlayer không gửi cookie/CSRF | Cao | Resource loader scheme riêng từ P4; test seek/HTTP 206/416; fallback tải file nhỏ |
| `shell.rs` 382 KB khó bóc tách | Trung bình | Bản đồ 5.2; port theo màn hình + checklist, không dịch máy từng dòng |
| Khác biệt CSS ↔ SwiftUI | Trung bình | Tokens + screenshot; chấp nhận khác biệt nền tảng có chủ đích |
| iOS kill app/background upload | Trung bình | Upload foreground ở P7; bổ sung `URLSession` background + BGProcessingTask ở P11 nếu cần |
| Ký/TestFlight cần tài khoản Apple | Trung bình | CI simulator trước; chuẩn bị secrets sớm; ad-hoc cho máy nội bộ |
| Dev trên Windows không build local | Trung bình | CI là compiler; PR nhỏ; `swift test` core chạy macOS runner; cân nhắc Mac thuê/VM khi cần debug UI |
| ATS/chứng chỉ tự ký | Trung bình | Ưu tiên HTTPS hợp lệ; `NSAllowsLocalNetworking` cho dev; không tắt ATS toàn cục |
| WebP encode trên iOS | Thấp | ImageIO nếu hỗ trợ; fallback JPEG + thông báo |
| Bộ nhớ ảnh lớn/video 4K | Trung bình | Downsample, `autoreleasepool`, chunk 4 MiB, giới hạn cache |
| API server tiến hoá | Trung bình | Snapshot `docs/API.md`; degrade trung thực; test fixture cập nhật có chủ đích |
| App Review (nếu công khai) | Thấp | TestFlight nội bộ trước; chuẩn bị privacy/account deletion |

---

## 14. Definition of Done (mỗi phase)

- [ ] `xcodegen generate` + build simulator xanh trên CI.
- [ ] Unit test liên quan xanh; KAT không đổi.
- [ ] Không có chuỗi tiếng Anh lẫn trong UI (trừ tên riêng).
- [ ] Light/dark, iPhone SE/15, iPad 11" không tràn layout.
- [ ] Không log mật khẩu/key/plaintext; không lưu secret ngoài bộ nhớ.
- [ ] Trạng thái lỗi/loading/empty trung thực, không giả thành công.
- [ ] Screenshot + mô tả parity đính kèm PR.
- [ ] `docs/PARITY.md` cập nhật trạng thái màn hình.

---

## 15. Ước lượng & thứ tự thực hiện

- **Đường găng:** P0 → P1 → P2 → P3 → P4 → P7 → P11.
- P5/P6/P8/P9/P10 có thể làm song song sau P4 nếu có thêm người.
- Tổng ~15,5 tuần người; bản dùng được nội bộ (login + thư viện + viewer +
  vault) đạt khoảng tuần 7–8.

---

## 16. Việc cần làm ngay (checklist P0)

1. `git init` trong `D:\rk3229\mng-cloud-sw`, tạo `.gitignore`.
2. Tạo `project.yml`, `App/`, `Packages/{MNGCore,MNGKit,MNGEdit}`, `Tests/`.
3. Thêm `Assets.xcassets` (AppIcon từ `ui/assets/icon-512.png`, AccentColor).
4. Viết `App/App.swift` + BootScreen tĩnh.
5. Viết `.github/workflows/ci.yml`.
6. Push lên GitHub, bật Actions, chạy `workflow_dispatch` kiểm tra.
7. Copy 2 file KAT + viết test khung (sẽ hoàn thiện ở P1).
8. Tạo `docs/PARITY.md` từ bảng mục 5.3 + `docs/API.md` snapshot.

Khi P0 xanh, bắt đầu P1 (crypto) ngay — đây là phần rủi ro cao nhất và là
điều kiện để mọi phần sau (vault, viewer E2EE) hoạt động đúng.
