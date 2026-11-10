# UI parity checklist

Source of truth: `mng-cloud-rs/docs/UI_PARITY.md` and the deployed native shell
(`0.3.1`). Parity means the same structure, order, labels, states and motion —
not identical DOM. Platform conventions (share sheet, Photos picker, tab bar)
are intentional differences.

Legend: ✅ done · 🟡 in progress · ⏳ not started · ➖ not applicable on iOS

| Area | Target | Status |
| --- | --- | --- |
| Boot | logo, spinner, retry + exact error copy | 🟡 wired to `SessionStore`; device check pending |
| Login | card, cloud mark, error copy, CSRF session | 🟡 card + validation + CSRF session; device check pending |
| App shell | 4 tabs compact / 264 pt sidebar regular, search button | 🟡 ported: floating compact header/tab bar + search circle, 264 pt sidebar + 5 entries, cloud picker, toast; device check pending |
| Library | Năm / Tháng / Tất cả, Ảnh/Video/Live/Yêu thích, 120-item pages, scroll anchor | 🟡 ported: segmented Năm/Tháng/Tất cả, kind chips, 120-item paging, year/month collage, skeleton/empty/error, pull-to-refresh; no favorites chip in the 0.3.1 shell; device check pending |
| Tiles | long-press menu, info sheet, favorite optimistic, delete confirm, selection mode | 🟡 ported: context menu, info sheet, tap opens viewer, optimistic favorite/delete + rollback, selection bar; device presentation order pending |
| Viewer | filmstrip, swipe, pinch/double-tap zoom, swipe-down dismiss, video Range, Live Photo | 🟡 ported: full-screen stage, lazy auto-centered filmstrip, pinch/double-tap/pan, swipe navigation and dismiss, cookie-authenticated AVPlayer, LIVE companion, HEIC preview fallback, optimistic favorite/info/download/delete; device gesture and seek check pending |
| Albums | 7 collapsible sections, 9-photo preview, sort/density, cover morph | 🟡 ported: seven sections in PWA order, per-section sort/density, 9-photo preview + expand, AI banner/poll, rename, album drill-down in Library; FLIP cover morph not ported; device check pending |
| Search | 280 ms debounce, 5 chips, 4 hints, 300-result cap, return target | 🟡 ported: debounce/submit/chip paths, five chips, four album hints, 300 cap, delete-aware meta, Search/Albums return target; device check pending |
| Connections | cloud cards, health dot, active check, WebDAV copy, iCloud row | 🟡 ported: cloud cards with health dots, active check, WebDAV copy, read-only iCloud status; full iCloud importer at P7; device check pending |
| Settings | Kết nối / iCloud / Thư viện / Tài khoản / Giới thiệu; test, rescan, retry thumbs, clear temp | 🟡 ported: cloud probe rows, iCloud status, scan/thumbs/tmp actions, storage, duplicates entry, account/about; device check pending |
| Duplicates | legacy summary, 30 groups per page, open group in viewer | 🟡 ported: summary + pending-thumbnail note, 30 groups per page, 128 pt grid, group-seeded viewer; device check pending |
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

## P5 notes

- Albums loads collections/recent/favorites once per cloud and people/places
  from the AI signature (`people:places:faces_done:place_done:place_pending`);
  the 20 s poll only runs while Albums is visible and `ai.running` is true.
- A cloud switch invalidates Albums even from another tab, so the next visit
  cannot show cards from the previous library. Search keeps its typed query and
  reruns a non-empty query against the new cloud.
- Album sorting is stable and uses case-insensitive plain comparisons, matching
  Rust's `to_lowercase().cmp()`; count ties keep the server order for album,
  person and place sections.
- Grid metrics follow `app.css`: album photo grids 2/3/3 columns on phones and
  adaptive `220/140/92` when wide; years use `.album-grid` (`330/260/200`),
  collections/districts `.smart-albums` (`290/220/180`, one column on phones);
  places use `230/170/136`; people use `116/96/74` pt.
- Opening an album clears the kind chip, sets the year (only for `year:` keys),
  clears month, switches to All and sends `album=` (or plain `year=` for a year
  key). Person/province/district albums omit `cloud`; fixed albums keep it.
- Back from an album clears the album/date filters, restores layout All, reloads
  the library page and returns to Search or Albums based on `album_return`.
  Library toolbar, selection, paging and the older-items footer are hidden
  during an album drill-down.
- Search keeps the previous meta during the 280 ms debounce, then swaps to the
  skeleton; `search_deleted` only switches the meta to the loaded-row count when
  the delete happens while Search is visible (the PWA's `view == Search` guard).
- Connections and iCloud share one root sheet. iCloud is intentionally read-only
  until P7; the sheet shows the server's real `configured/authenticated/appleID`
  state and says the full importer is deferred.
- Deliberate platform differences: SF Symbols, native menus/sheets and the
  missing FLIP morph. The morph is a visual-only transition, not a data path.

## P6 notes

- Settings follows the PWA section order and copy. Cloud rows show
  `username · N mục` plus the last health dot and run `POST /clouds/test` on
  tap; the server's Vietnamese reason is shown instead of a generic failure.
- Scan (`cloud=all`), thumbnail retry and temp cleanup each own a busy flag and
  keep the other rows usable. Every success refreshes `/bootstrap`, so counts,
  storage and cloud health update in place.
- The iCloud row refreshes whenever Settings opens and never polls there; the
  detail sheet still owns the read-only status refresh.
- Duplicates reloads on every open, shows `hashed/total` and the pending-thumbnail
  suffix when `hashed < total`, reveals 30 groups at a time and opens the shared
  viewer seeded with the full group. Delete/favorite from that viewer flow through
  the same `LibraryModel` mutations and rollback path.
- The admin row is intentionally absent until P9; storage is read-only, matching
  the web UI.

## Visual checks per UI phase

- iPhone SE (compact, 375 pt), iPhone 15/16 (393 pt), iPad 11" portrait and
  landscape.
- Light and dark schemes, plus Increased Contrast where relevant.
- Dynamic Type at default and one step up.
- No horizontal overflow; Vietnamese strings unchanged; numbers formatted
  `vi-VN` (`1.966 mục`, `13.1 GB`).
- Reduce Motion disables the album/cover morph.
