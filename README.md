# mng-cloud-sw

iOS/iPadOS client for **MNG Cloud**, written in Swift/SwiftUI. It is a pure
client of the existing `mngd` `/api/v1` contract — the Seafile backend,
writer, worker and signing chain stay in `mng-cloud-rs`.

## Documents

- [PLAN.md](PLAN.md) — full migration plan, phases, architecture and parity rules
- [docs/API.md](docs/API.md) — API contract snapshot used by the client
- [docs/CRYPTO.md](docs/CRYPTO.md) — E2EE / vault crypto parity and KAT vectors
- [docs/PARITY.md](docs/PARITY.md) — per-screen parity checklist
- [docs/DEVICE_CHECKS.md](docs/DEVICE_CHECKS.md) — what still needs a real device
- [docs/INSTALL_ON_DEVICE.md](docs/INSTALL_ON_DEVICE.md) — step-by-step guide:
  build a signed `.ipa` on GitHub Actions and install it on an iPhone without a
  Mac (Apple keys, UDID, device registration, secrets, Sideloadly)

## Build

The project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
from `project.yml`. Do not edit or commit `MNGCloud.xcodeproj`.

```bash
brew install xcodegen
xcodegen generate
open MNGCloud.xcodeproj
```

CI (GitHub Actions, macOS) is the canonical build: it runs the package tests,
generates the project, builds and tests the iOS simulator target.

```bash
xcodebuild -project MNGCloud.xcodeproj -scheme MNGCloud \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Use `generic/platform=iOS Simulator` when no simulator device is installed; the
CI picks the first available device and falls back to `build-for-testing` when
the runner has no iOS runtime.

To try the app on a real iPhone without a Mac, run the **build-ios** workflow:
it signs a `.ipa` on the GitHub runner and publishes it as an artifact. The
step-by-step setup is in [docs/INSTALL_ON_DEVICE.md](docs/INSTALL_ON_DEVICE.md).

## Layout

| Path | Purpose |
| --- | --- |
| `App/` | SwiftUI app target (features, design system, services) |
| `Packages/MNGCore/` | Crypto (Seafile E2EE, `mng-vault/v1`) and search fold |
| `Packages/MNGKit/` | URLSession API client, DTOs, CSRF and multipart |
| `Packages/MNGEdit/` | Image editor pipeline |
| `Tests/` | App-level tests |
| `.github/workflows/` | CI and release pipelines |

## Phase status

All phases below are implemented and green on CI; the remaining work is the
device pass and the release polish.

- [x] **P0** — scaffold, XcodeGen, CI pipeline
- [x] **P1** — MNGCore crypto + KAT (Seafile E2EE, `mng-vault/v1`)
- [x] **P2** — MNGKit API + session/login
- [x] **P3** — shell + library + tile actions
- [x] **P4** — viewer, zoom/swipe, video and Live Photo
- [x] **P5** — albums, search and connections
- [x] **P6** — settings actions + duplicates browser
- [x] **P7** — native encrypted vault (create/unlock/browse/upload/preview)
- [x] **P8** — image editor (`mng-edit` pipeline + UI)
- [x] **P9** — administration console
- [x] **P10** — iCloud importer sheet
- [ ] **P11** — parity extras, performance and release (keyboard, haptics,
      Dynamic Type and `os_signpost` are done; marquee, prefetch and TestFlight
      are not)

