# UI parity checklist

Source of truth: `mng-cloud-rs/docs/UI_PARITY.md` and the deployed native shell
(`0.3.1`). Parity means the same structure, order, labels, states and motion —
not identical DOM. Platform conventions (share sheet, Photos picker, tab bar)
are intentional differences.

Legend: ✅ done · 🟡 in progress · ⏳ not started · ➖ not applicable on iOS

| Area | Target | Status |
| --- | --- | --- |
| Boot | logo, spinner, retry + exact error copy | 🟡 static screen done |
| Login | card, cloud mark, error copy, CSRF session | ⏳ |
| App shell | 4 tabs compact / 264 pt sidebar regular, search button | ⏳ |
| Library | Năm / Tháng / Tất cả, Ảnh/Video/Live/Yêu thích, 120-item pages, scroll anchor | ⏳ |
| Tiles | long-press menu, info sheet, favorite optimistic, delete confirm, selection mode | ⏳ |
| Viewer | filmstrip, swipe, pinch/double-tap zoom, swipe-down dismiss, video Range, Live Photo | ⏳ |
| Albums | 7 collapsible sections, 9-photo preview, sort/density, cover morph | ⏳ |
| Search | 280 ms debounce, 5 chips, 4 hints, 300-result cap, return target | ⏳ |
| Connections | cloud cards, health dot, active check, WebDAV copy, iCloud row | ⏳ |
| Settings | Kết nối / iCloud / Thư viện / Tài khoản / Giới thiệu; test, rescan, retry thumbs, clear temp | ⏳ |
| Duplicates | legacy summary, 30 groups per page, open group in viewer | ⏳ |
| Vault | native list/unlock/browse/upload/folder/delete/auto-lock + Seafile E2EE read-only | ⏳ |
| Editor | rotate → flip → crop, adjustments, filters, JPEG/PNG/WebP export | ⏳ |
| Admin | lazy mount, users, password, activate, admin, delete, scan | ⏳ |
| iCloud | honest status, 2.2 s job poll, login/2FA/start/save/pause/cancel/logout | ⏳ |
| PWA-only surfaces | service worker, Trusted Types, extension | ➖ |
| ZIP multi-select | POST form, 100 items / 2 GiB cap, share sheet | ⏳ |
| Marquee | iPad pointer selection only | ⏳ |

## Visual checks per UI phase

- iPhone SE (compact, 375 pt), iPhone 15/16 (393 pt), iPad 11" portrait and
  landscape.
- Light and dark schemes, plus Increased Contrast where relevant.
- Dynamic Type at default and one step up.
- No horizontal overflow; Vietnamese strings unchanged; numbers formatted
  `vi-VN` (`1.966 mục`, `13.1 GB`).
- Reduce Motion disables the album/cover morph.
