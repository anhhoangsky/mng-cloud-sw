# mng-cloud-sw

iOS/iPadOS client for **MNG Cloud**, written in Swift/SwiftUI. It is a pure
client of the existing `mngd` `/api/v1` contract — the Seafile backend,
writer, worker and signing chain stay in `mng-cloud-rs`.

## Documents

- [PLAN.md](PLAN.md) — full migration plan, phases, architecture and parity rules
- [docs/API.md](docs/API.md) — API contract snapshot used by the client
- [docs/CRYPTO.md](docs/CRYPTO.md) — E2EE / vault crypto parity and KAT vectors
- [docs/PARITY.md](docs/PARITY.md) — per-screen parity checklist

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
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  CODE_SIGNING_ALLOWED=NO build
```

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

- [x] **P0** — scaffold, XcodeGen, CI pipeline (first CI run pending)
- [x] **P1** — MNGCore crypto + KAT (ported; macOS CI run pending)
- [x] **P2** — MNGKit API + session/login (ported; macOS CI run pending)
- [x] **P3** — shell + library + tile actions (ported; macOS CI run pending)
- [ ] P4+ — see `PLAN.md`
