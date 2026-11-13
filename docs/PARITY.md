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
| Library | Năm / Tháng / Tất cả, Ảnh/Video/Live/Yêu thích, 120-item pages, scroll anchor | 🟡 ported: segmented Năm/Tháng/Tất cả, kind chips, 120-item paging with a full-length placeholder timeline, year/month collage, skeleton/empty/error, pull-to-refresh, thumbnail retries; no favorites chip in the 0.3.1 shell; device check pending |
| Tiles | long-press menu, info sheet, favorite optimistic, delete confirm, selection mode | 🟡 ported: context menu, info sheet, tap opens viewer, optimistic favorite/delete + rollback, selection bar; device presentation order pending |
| Viewer | filmstrip, swipe, pinch/double-tap zoom, swipe-down dismiss, video Range, Live Photo | 🟡 ported: full-screen stage, lazy auto-centered filmstrip, pinch/double-tap/pan, swipe navigation and dismiss, cookie-authenticated AVPlayer, LIVE companion, HEIC preview fallback, optimistic favorite/info/download/delete; device gesture and seek check pending |
| Albums | 7 collapsible sections, 9-photo preview, sort/density, cover morph | 🟡 ported: seven sections in PWA order, per-section sort/density, 9-photo preview + expand, AI banner/poll, rename, album drill-down in Library; FLIP cover morph not ported; device check pending |
| Search | 280 ms debounce, 5 chips, 4 hints, 300-result cap, return target | 🟡 ported: debounce/submit/chip paths, five chips, four album hints, 300 cap, delete-aware meta, Search/Albums return target; device check pending |
| Connections | cloud cards, health dot, active check, WebDAV copy, iCloud row | 🟡 ported: cloud cards with health dots, active check, WebDAV copy and the full iCloud importer sheet; device check pending |
| Settings | Kết nối / iCloud / Thư viện / Tài khoản / Giới thiệu; test, rescan, retry thumbs, clear temp | 🟡 ported: cloud probe rows, iCloud status, scan/thumbs/tmp actions, storage, duplicates entry, account/about; device check pending |
| Duplicates | legacy summary, 30 groups per page, open group in viewer | 🟡 ported: summary + pending-thumbnail note, 30 groups per page, 128 pt grid, group-seeded viewer; device check pending |
| Vault | native list/unlock/browse/upload/folder/delete/auto-lock (the Seafile E2EE reader was removed from the web app) | 🟡 ported: vault list, unlock, browser with folders/search, 4 MiB chunked upload, encrypted preview, rename, delete, library → vault move, 15-minute auto-lock; device check pending |
| Editor | rotate → flip → crop, adjustments, filters, text, JPEG/PNG/WebP export | 🟡 ported: `mng-edit` pixel pipeline, four native tabs (Tinh chỉnh / Bộ lọc / Chữ / Cắt), thirteen sliders, twenty-nine Aurum presets with six categories and the seven-slider tone tune, saved personal presets, text layers with CoreText export burn and an on-photo frame, continuous ±180° crop rotation with cover fill, ratio + screen presets, crop scrim/grid/bevel handles, hold-to-compare, export sheet with quality and the two save modes, multipart upload; AI/beauty/perspective are not ported; device check pending |
| Admin | lazy mount, users, password, activate, admin, delete, scan | 🟡 ported: Settings row for admins only, lazy list, create/reset/reprovision/update/delete/scan; device check pending |
| iCloud | honest status, 2.2 s job poll, login/2FA/start/save/pause/cancel/logout | 🟡 ported: full importer sheet with the 2.2 s poll that stops with the sheet; device check pending |
| PWA-only surfaces | service worker, Trusted Types, extension | ➖ |
| ZIP multi-select | POST form, 100 items / 2 GiB cap, share sheet | 🟡 ported: chunked streaming to a temp file, 100-id guard, share sheet; 2 GiB remains a server limit |
| Marquee | iPad pointer selection only | 🟡 ported: horizontal-first pan on the scroll view, multiple tiles per drag, edge auto-scroll with an accumulated selection; pointer-only on the web, touch works on the phone; device check pending |

## P3 notes

- The compact shell keeps the PWA's 36 pt floating title, 13 pt subtitle,
  transparent library header, 4-tab dock and separate search button; the
  subtitle hides in selection mode like `body.selection-mode`.
- The segmented control changes grouping and clears the year/month drill-down
  but keeps the kind chip; a kind chip returns to the timeline while keeping the
  drill-down, matching `set_layout()` / kind transitions.
- The timeline is chronological bottom-up: the API page is newest first, the
  newest photo sits at the bottom and scrolling up walks into the past. The
  compact grid renders the known `page.total` up front, so older pages fill
  placeholders above the loaded range instead of shifting the content.
- The dock expands only at the newest/bottom position. A real scroll of more
  than 6 pt condenses it, and Năm / Tháng / Tất cả keep it condensed through
  the reload and the content clamp that follows.
- A filter change captures the photo under the header and puts it (or the
  nearest date in the new page) back after the reload, so a smaller or larger
  result does not leave a gap or jump to the top.
- Older pages load when the viewport reaches the loaded boundary. The header
  subtitle keeps the item count until a real scroll and then shows the date of
  the oldest photo on screen. The library viewer uses the chronological order,
  so its filmstrip and swipe direction follow the grid.
- Marquee selection runs on a horizontal-first pan recognizer attached to the
  scroll view; vertical drags still scroll, and the edge auto-scroll keeps the
  whole accumulated set (including photos that left the screen).
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
- CI run `42858021122` passed all package tests, the unsigned simulator build,
  the simulator test target and the artifact upload. Later runs
  (`42870517153`, `42874600019`, `42875999023`, `42878324010`) kept it green
  through the vault, editor, admin and iCloud phases.

## P7 notes

- The vault tab is the PWA's `NativeVaultSection`: a list of vaults, one
  unlock screen per vault and the encrypted file browser. The vault name, the
  row meta (`#id • N đã mã hóa` or `#id • Chưa có chỉ mục`) and the security
  notes follow the web copy.
- Creating a vault derives the key locally (PBKDF2-SHA256, 310k rounds,
  NFKC password), encrypts the verifier and an empty manifest with
  AES-256-GCM and only sends the ciphertext. The password is never sent.
- Unlocking verifies the stored verifier, decrypts the manifest and drops the
  key again when the tab is left, after 15 idle minutes or when the app goes to
  the background — the same lifecycle as the web tab.
- Folder and file changes go through the SHA-256 compare-and-swap manifest
  update with one retry on `409 stale`.
- Platform difference: the web copy says "trong trình duyệt"; the app says
  "trong ứng dụng này" because the key never lives in a browser.
- Still missing: generating a thumbnail for new uploads (the web client never
  creates one, so the protocol is unverified) and the Seafile encrypted-library
  browser, which is intentionally absent because the deployed web app no longer
  exposes it.
- Uploads encrypt 4 MiB chunks with AES-256-GCM (`chunk/{index}/{total}` AAD)
  and name every block with the SHA-1 of its ciphertext, exactly like the web
  client; the server verifies the digest itself. Files come from the document
  picker or the photo library.
- Previews decrypt the chunks again: images are shown inline, videos play from
  a temporary file that is deleted when the sheet closes, text is capped at
  2 MiB / 200,000 characters and other formats show the honest "cannot
  preview" state.
- Renaming a vault uses the server's rename route, and "Chuyển vào kho mã hóa"
  in the tile menu and the selection bar moves library items into the unlocked
  vault: the encrypted copy is stored first and only then is the original
  deleted, exactly like the web client.

## P8 notes

- The editor reuses the web editor's copy: the three tabs (Cắt, Chỉnh màu, Bộ
  lọc), the rotate/flip group, the six crop ratios, the thirteen sliders, the
  twelve filters, the hold-to-compare button and the export sheet with the two
  save modes. The adjustment ruler is the ported `.au-ticks` control: a glass
  rail, a fixed gold centre line, a sliding white tick track and a gold value
  chip that resets only the open slider. The quality slider uses the same
  control in direct mode and its value resets to 92.
- The ±90° buttons keep their quarter turns, and the rotation mode adds the
  web's continuous −180…180° ruler on top (1° steps, a tick every 3°, the gold
  zero mark). The engine rotates the oriented photo around its centre and
  cover-scales it just enough that the turned image still fills the frame, so
  the crop rectangle always samples real pixels. The mode label shows the
  combined angle (`turn × 90 + fine`), exactly like the web.
- The pixel pipeline is the ported `mng-edit` crate, so the preview and the
  exported file use the same order (rotate → flip → crop) and the same
  adjustment math. The container follows the source: PNG stays PNG, WebP stays
  WebP, everything else becomes JPEG; the export sheet shows the quality
  (10…100, default 92) for JPEG/WebP and hides it for PNG.
- The crop has four corner handles and four edge handles. A ratio preset keeps
  the frame centred and grows it symmetrically, the way the web crop works; a
  free frame moves one side at a time. The ratio is converted from pixels to
  the normalized image space, so 1:1 on a 3:2 photo is a real square. The
  scrim and frame sit inside the zoomed photo stack, so the dim sheet covers
  the whole image even when the stage is pinched or panned. The pane keeps the
  four web transforms (rotate left/right, flip horizontal/vertical) one tap
  away, has no "Xong" button, and applies the frame when another tab opens.
  A crop drag previews live and records one undo step on release.
- The source is decoded locally with ImageIO and the EXIF orientation applied,
  so HEIC works without the server's HEIC-only `edit-source` route.
- Difference: the web additionally offers AI 4×, background remove/blur/
  replace, person cutout, retouch, beauty and perspective. Those are not ported
  yet; the user-facing AI panel only appears on a deployment with the models
  installed.

## Round 4 notes

- The library header controls are 40 pt now (back, filter, select) with
  slightly larger glyphs. The library keeps a light top-down glass veil at all
  times so the floating title stays legible over a bright photo; the stronger
  scroll scrim on the other tabs is unchanged.
- The filter rail is the complete Aurum catalog: twenty-nine presets in the
  `all / root / meitu / xingtu / lr / mono` categories, the preset hint line,
  and the same colour-transform recipes as `src/core/color.ts` (gains,
  contrast, saturation and offsets). Tapping the active preset again returns
  to "Nguyên bản", exactly like the web rail. Legacy keys (`fade`, `natural`,
  `korea`, `japan`, `skin`) still decode.
- The filter pane's "Tùy chỉnh tone" section is collapsible and writes the same
  seven adjustments (`brightness`, `contrast`, `saturation`, `warmth`, `tint`,
  `vibrance`, `vignette`) back into the Adjust tab; the vignette range is
  0…100 and every other slider is −100…100.
- The Adjust pane keeps the gold "Tự động" action fixed on the left, scrolls
  the grouped parameter chips underneath it, and keeps the gold value/reset
  chip fixed on the right, like `.au-deck__row--adjust`.
- The text tab is a native overlay, not a web view. Layers use normalized
  centres and a size fraction of the export height, support the four quick
  styles, five fonts, colour, bold/italic/outline/shadow, opacity and rotation,
  and are dragged, pinched and rotated on the stage. "Chạm đặt" arms a one-shot
  tap-to-place mode; the redundant add-text button is gone. "Khung chữ" mirrors
  the web's `aurum:text-frame` toggle: the dashed frame hugs a measured text
  run and the rotate/scale handles stay visible while a layer is selected.
  Typing updates the photo live without tapping outside, and the keyboard never
  resizes the stage. Export burns the layers into the rendered bitmap with
  CoreText; an empty layer is removed so invisible text cannot reach the file.
- The crop tab exposes ratio and quarter-turn rotation modes. The ratio rail
  includes `free`, `1:1`, `4:3`, `3:4`, `16:9`, `9:16` and `screen`; `screen`
  uses the stage viewport. The scrim is a real glass sheet with a crop-shaped
  hole, the thirds grid only appears while the frame is dragged or rotated,
  and the corners are 24 pt bevelled gold handles with gold edge bars. Header
  and dock fade during a crop drag, a ratio change and a rotation, like
  `au-cropping` / `au-ratioing` / `au-rotating`.
- Saved filter presets follow the web model: the filter pane has a name field
  and "Lưu", the saved row shows apply/delete, a second tap restores the state
  from before the preset was applied, names are unique, empty names get a
  "Bộ lọc HH:mm" fallback, and the list is capped at 24 entries in
  `aurum:user-presets:v1`.
- Still native-only gaps: the AI/beauty/retouch tools, perspective crop and
  the web's separate text textarea in the deck.

## P9 notes

- The administration console is reachable from the Settings row
  "Quản trị người dùng", which only appears for administrators. The list is
  loaded when the console opens, so launching the app never calls the admin
  API.
- Every mutation maps to one server route: create, reset the MNG Cloud
  password, re-provision the cloud accounts, update the display name / active /
  admin flag, delete (with or without the cloud data) and queue a scan.
- The web console generates a random password and offers it for copying; the
  app generates one locally (16 readable characters from the system CSPRNG) and
  shows it in the create sheet.
- Server invariants (primary admin, deleting yourself, the last admin) and the
  403/409 answers are surfaced with the server's own sentence.

## P10 notes

- The iCloud sheet is the full importer: Apple ID sign-in, the six-digit 2FA
  prompt, the settings (how many recent photos, delete after the import), the
  start button, the job card (state, progress, log) with pause/resume/cancel
  and the sign-out action.
- Polling runs every 2.2 seconds, exactly like the web client, and only while
  a job is active; closing the sheet stops it.
- A server without the importer (404/405/501) shows the honest "máy chủ này chưa
  cung cấp trình tải iCloud" message with the hint that an administrator has
  to configure `icloudpd`; a network error shows "không kiểm tra được iCloud".
- The password never leaves the device: it is only sent to the server's login
  route and cleared from the form right after the request.

## P11 notes

- The fixed pixel sizes of the web client are kept, but every text style goes
  through `Font.mng(...)`, which scales it with the user's Dynamic Type
  setting (capped at 1.6× so the big headlines survive the accessibility
  sizes).
- The viewer answers the hardware keyboard: ← and → walk the library and
  Escape closes it.
- Tiles give a light haptic when they enter or leave the selection.
- `os_signpost` marks the thumbnail decode so the device profiling in Xcode
  shows where the time goes.
- The timeline warms the thumbnails of the next rows (eight at a time, one
  after another) so a long library scrolls without a flash of empty tiles.

## Round 5 notes

- The Album page is a `LazyVStack` of sections. Off-screen grids and the
  people strip (`LazyHStack`) are only built when they approach the viewport,
  so opening the tab no longer starts every thumbnail request at once.
- Section skeletons reserve the final height: the photo preview skeleton uses
  the same nine cells as the grid and a spacer for "Xem tất cả", people/places/
  districts shimmer inside their own sections, and the AI banner reserves its
  second text line. Data arriving during a scroll therefore replaces content in
  place instead of pushing the page under the finger.
- Year cards use a fixed two-by-two `Grid` for their four covers instead of a
  lazy grid inside the page grid, removing a measurement pass from every card.
- The duplicates sheet keeps the previous result visible while it reloads.
  Its list is keyed by group identity rather than array indexes, so replacing
  the groups on a second open can never index a collection that has already
  changed. A thumbnail asks the shell to open the viewer from the sheet's
  `onDismiss`, once the dismissal has finished.

## Round 6 notes

- Slider and text gestures use an explicit edit transaction: the first touch
  snapshots the state, every move previews live without touching the history,
  and lifting the finger records one undo step and rerenders at full quality.
  Slider renders are coalesced through a single preview loop, so a burst of
  drag events renders the newest state instead of queuing every intermediate
  frame; a drag renders smaller frames and the release gets the full preview.
- The filter pane can save the current tone and tune, like the web: the row of
  personal presets highlights the active one, its thumbnail toggles back to
  the pre-preset state, and the delete badge removes it from local storage.
- The crop tab's "Xong" button is gone; leaving the tab applies the frame.
  Outside the crop tab the preview is the cropped output, so text coordinates
  match the exported file; inside the tab the whole oriented photo is shown
  under the crop frame.
- The compact timeline keeps its full-length placeholder grid, but paging no
  longer depends only on scroll callbacks: while the viewport is within six
  rows of the loaded boundary a small pump retries the next page after a
  failed request or a stopped drag. Once the server reports no older page,
  the stale total is clamped to the loaded count so shimmer cannot remain
  above the last row.
- Thumbnail tiles retry a missing `/thumb` with a short backoff while they
  are on screen, and a failed tile is not pinned to its path, so scrolling it
  away and back asks again. This covers the server's 404 placeholder window
  while a thumbnail is still being written.

## Visual checks per UI phase

- iPhone SE (compact, 375 pt), iPhone 15/16 (393 pt), iPad 11" portrait and
  landscape.
- Light and dark schemes, plus Increased Contrast where relevant.
- Dynamic Type at default and one step up.
- No horizontal overflow; Vietnamese strings unchanged; numbers formatted
  `vi-VN` (`1.966 mục`, `13.1 GB`).
- Reduce Motion disables the album/cover morph.
