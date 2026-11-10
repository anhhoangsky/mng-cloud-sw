# UI parity checklist

Source of truth: `mng-cloud-rs/docs/UI_PARITY.md` and the deployed native shell
(`0.3.1`). Parity means the same structure, order, labels, states and motion —
not identical DOM. Platform conventions (share sheet, Photos picker, tab bar)
are intentional differences.

Legend: ✅ done · 🟡 in progress · ⏳ not started · ➖ not applicable on iOS

| Area | Target | Status |
| --- | --- | --- |
| Boot | logo, spinner, retry + exact error copy | 🟡 wired to `SessionStore`, CI pending |
| Login | card, cloud mark, error copy, CSRF session | 🟡 card + validation + CSRF session, CI pending |
| App shell | 4 tabs compact / 264 pt sidebar regular, search button | 🟡 ported: floating compact header/tab bar + search circle, 264 pt sidebar + 5 entries, cloud picker, toast; CI/device check pending |
| Library | Năm / Tháng / Tất cả, Ảnh/Video/Live/Yêu thích, 120-item pages, scroll anchor | 🟡 ported: segmented Năm/Tháng/Tất cả, kind chips, 120-item paging, year/month collage, skeleton/empty/error, pull-to-refresh; no favorites chip in the 0.3.1 shell |
| Tiles | long-press menu, info sheet, favorite optimistic, delete confirm, selection mode | 🟡 ported: context menu, info sheet, tap opens viewer, optimistic favorite/delete + rollback, selection bar; device presentation order pending |
| Viewer | filmstrip, swipe, pinch/double-tap zoom, swipe-down dismiss, video Range, Live Photo | 🟡 ported: full-screen stage, lazy auto-centered filmstrip, pinch/double-tap/pan, swipe navigation and dismiss, cookie-authenticated AVPlayer, LIVE companion, HEIC preview fallback, optimistic favorite/info/download/delete; device gesture and seek check pending |
| Albums | 7 collapsible sections, 9-photo preview, sort/density, cover morph | ⏳ |
| Search | 280 ms debounce, 5 chips, 4 hints, 300-result cap, return target | ⏳ |
| Connections | cloud cards, health dot, active check, WebDAV copy, iCloud row | ⏳ |
| Settings | Kết nối / iCloud / Thư viện / Tài khoản / Giới thiệu; test, rescan, retry thumbs, clear temp | 🟡 P3 minimal: account, server/free space, thumbnail-cache clear, version, logout; full actions at P6 |
| Duplicates | legacy summary, 30 groups per page, open group in viewer | ⏳ |
| Vault | native list/unlock/browse/upload/folder/delete/auto-lock + Seafile E2EE read-only | ⏳ |
| Editor | rotate → flip → crop, adjustments, filters, JPEG/PNG/WebP export | ⏳ |
| Admin | lazy mount, users, password, activate, admin, delete, scan | ⏳ |
| iCloud | honest status, 2.2 s job poll, login/2FA/start/save/pause/cancel/logout | ⏳ |
| PWA-only surfaces | service worker, Trusted Types, extension | ➖ |
| ZIP multi-select | POST form, 100 items / 2 GiB cap, share sheet | 🟡 ported: chunked streaming to a temp file, 100-id guard, share sheet; 2 GiB remains a server limit |
| Marquee | iPad pointer selection only | ⏳ |

## P3 notes

- The compact shell keeps the PWA's 36 pt floating title, 13 pt subtitle,
  transparent library header, 4-tab dock and separate search button; the
  subtitle hides in selection mode like `body.selection-mode`.
- The segmented control changes grouping and clears the year/month drill-down
  but keeps the kind chip; a kind chip returns to the timeline while keeping the
  drill-down, matching `set_layout()` / kind transitions.
- Older pages are appended below the current page, so the scroll anchor stays
  put without FLIP; date-filtered timelines paginate as well.
- Favorite and delete requests run four at a time. Only failed ids are rolled
  back; partial-failure toasts reuse the PWA copy.
- Info-sheet download dismisses first and shares when the stream is ready;
  info-sheet delete dismisses first, then asks for confirmation after the sheet
  animation. Both need a real-device check.
- Deliberate platform differences: share sheet, `UIActivityViewController` temp
  files, SF Symbols, and a native `.contextMenu` in place of the web menu.

## P4 notes

- The viewer is a root overlay above the shell, matching the PWA modal. Its
  snapshot list is independent of the timeline page, so paging or filtering
  cannot reorder an open viewer.
- Viewer title/subtitle copy follows `viewer_title_text()` /
  `viewer_sub_text()`: dimensions or duration + size, then cloud · date · UTC
  time. The subtitle intentionally keeps the trailing separator when the
  timestamp is unknown.
- Photos use `preview` with the same 360px thumbnail fallback and one delayed
  retry after 4.5 s. The strip uses 160px thumbnails and centers the active
  frame on open and navigation.
- Pinch is clamped to 1–5×, double tap toggles 2.4×, and swipe dismiss only
  applies at 1×. Vertical and horizontal thresholds match `shell.rs`
  (`max(stage*0.2, 96)` and `max(stage*0.16, 56)`).
- Video uses `AVURLAssetHTTPCookiesKey` with the session cookies instead of a
  custom Range loader; AVFoundation owns Range, buffering and seeking. The
  thumbnail is the poster, and the player pauses on background.
- Live Photo stays still until the LIVE pill is pressed, then streams the
  companion `?live=1` with autoplay. The badge is hidden while the companion
  plays, and playback stops when the item changes or the viewer closes.
- Delete removes the row optimistically, advances to the nearest neighbour and
  closes the viewer when the snapshot empties. A failed delete restores the
  whole viewer snapshot, matching the PWA backup.
- Deliberate platform differences: native video controls, SF Symbols, and the
  share sheet. The P8 edit button is omitted until the editor exists.

## Visual checks per UI phase

- iPhone SE (compact, 375 pt), iPhone 15/16 (393 pt), iPad 11" portrait and
  landscape.
- Light and dark schemes, plus Increased Contrast where relevant.
- Dynamic Type at default and one step up.
- No horizontal overflow; Vietnamese strings unchanged; numbers formatted
  `vi-VN` (`1.966 mục`, `13.1 GB`).
- Reduce Motion disables the album/cover morph.
