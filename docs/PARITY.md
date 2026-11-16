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
| Editor | rotate → flip → crop, adjustments, filters, text, AI, JPEG/PNG/WebP export | 🟡 ported: `mng-edit` pixel pipeline, six native tabs (Tinh chỉnh / Chân dung / Bộ lọc / Chữ / AI / Cắt), twenty-six sliders across the two parameter decks, twenty-nine Aurum presets decoded from the shared `filters.json` spec with six categories and the seven-slider tone tune, saved personal presets, text layers with CoreText export burn and an on-photo frame, continuous ±180° crop rotation with cover fill, ratio + screen presets, crop scrim/grid/bevel handles, perspective correction, an on-device Vision AI tab (background remove/person/blur/white, five retouch passes, model picker, mask brush with live blur/retouch preview, progress/cancel and AI-only undo), hold-to-compare, export sheet with quality and the two save modes, multipart upload; the six portrait reshape sliders are wired through the shared warp engine (Vision landmarks, preview/export identical), the four beauty sliders run through a line-by-line port of the web's R/G/B mask builder and `main.glsl` portrait pass (the mask builds in the same Vision task as the anchors), the Chân dung tab applies the three chain presets decoded from the shared `presets.json` spec, the free-liquify field plus its 640-dab history are ported (`LiquifyField`, RG = drag in source UV, preview/export identical) with a native source-space brush (1–20 % size, gold ring, one undo step per stroke, clear), and clarity/sharpen/denoise run through `DetailKernel` (sections 1–3 of `main.glsl`); device check pending |
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
- Difference: the web's AI runs downloaded ONNX models (ISNet/BiRefNet/
  MODNet, Real-ESRGAN, AI Retouch). The native AI tab runs Apple Vision
  on-device by default: subject and person segmentation, face landmarks, and
  Core Image compositing for the same background and retouch actions. Four
  paths can download a pinned Core ML model instead: Balanced offers MODNet 512
  when the Vision probe finds a person, Quality offers BiRefNet Lite 512 for
  general subjects, Maximum offers ISNet 1024 (the exact web Quality model)
  and falls back to BiRefNet, and the hair retouch offers BiSeNet face parsing
  for every tier. Vision stays the fallback, so no tier requires a download.
  Like the web, a pass first returns a soft mask to a brush step (add/erase,
  size, stroke undo, invert, transparent background) and the blur/retouch
  sliders stay live until "Hoàn tất"; the mask is then baked into the source.
  The beauty and liquify passes now live in `MNGEdit` (`BeautyKernel`,
  `LiquifyField`), but their native pane and the `EditorModel` wiring are still
  phase A6. Details are in [`AI_NATIVE_ENGINE.md`](AI_NATIVE_ENGINE.md).

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
- Still native-only gaps: the beauty/liquify tools and the web's separate text
  textarea in the deck.

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
- The AI tab uses the same actions as `ui.ts` ("Xoá phông", "Tách người", "Mờ
  phông", "Nền trắng", then the five retouch passes) but currently runs Apple
  Vision on the device instead of downloading ONNX models. Vision only
  produces the soft mask; the full-source brush step then refines it and
  previews the live blur and retouch settings. "Hoàn tất" bakes the result into
  a new source bitmap while the crop, geometry, colour stack and text stay in
  place; the rows are kept top-down through `EditorBitmap`, so the photo does
  not flip. The history restarts and "Hoàn tác AI" restores the previous
  source. The native model plan and its measured quality audit are in
  [`AI_NATIVE_ENGINE.md`](AI_NATIVE_ENGINE.md); the device protocol is in
  [`AI_BENCHMARK.md`](AI_BENCHMARK.md).

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

## Round 7 notes

- The six portrait reshape sliders (`faceSlim`, `jawline`, `chin`, `eyeSize`,
  `noseSize`, `mouthSize`) now decode into `EditorAdjustments` and reach the
  pixels through `FaceWarp`, a line-by-line port of `warpFace()` from the web
  shader. The preview and the full-resolution export call the same
  `renderRGBA` with the same frozen `FaceWarpSampler`, so a reshape is identical
  at every zoom; a neutral slider stays byte-identical, and a pixel outside
  every face ellipse is never resampled.
- `FaceAnchorDetector` turns Vision face landmarks into the web's anchor
  contract: top-down boxes, face-local eye/nose/mouth positions clamped to
  ±0.92, radii 0.02–0.6, strongest four. It runs off the main actor once per
  loaded photo, and the preview rerenders when the anchors arrive. Without a
  detectable face the warp uses the web's default feature positions; nothing
  is fabricated.
- Vision's box is not MediaPipe's mesh box, so the exact ellipse can differ
  from the web for the same photo. The packing rule, the falloffs and the
  clamp/limit behaviour are shared, which is what the cross-client contract
  promises; a pixel-parity pass on device is still pending.
- The reshape stays a CPU sampler inside `MNGEdit`'s one renderer instead of a
  second Metal pipeline. The app renderer is CPU-based; adding a GPU kernel now
  would create a path that cannot be checked on the Windows workstation and
  would only be used once the renderer itself moves to the GPU. The sampler is
  the reference the future kernel will be tested against.
- `MNGEdit` on macOS now runs 16 warp/render tests: identity bytes, cheek and
  eye direction, outside-the-face zero diff, anchor sorting/cap, JSON
  round-trip and clamp, and the frozen sampler matching `FaceWarp.warp`.

## Round 8 notes

- The four portrait sliders (`smoothSkin`, `blemish`, `skinTexture`, `skinTone`)
  now decode into `EditorAdjustments` with the web's ranges (0…100 for the
  three amounts, −100…100 for the tone) and run in `BeautyKernel`, a
  line-by-line port of section 4 of `main.glsl`: the eight edge-aware taps at
  0.0045 UV used by the export path, the 0.011 UV blemish ring, the relative
  dark/red spot test and the up-to-3.5 % tone shifts. Tap radii are UV
  distances, so a preview and a full-resolution export smooth the same facial
  area.
- `EditorBeautyMaskBuilder` ports `src/beauty/mask.ts` instead of reusing the
  one-channel app mask: R = skin (a skin-chroma gate around the median cheek
  reference, constrained to the face ellipses), G = protected eyes, brows,
  hair and beard, B = lips, with the web's 2 px feather. The shader samples it
  bilinearly; a zero mask is byte-identical, and a missing mask falls back to
  the procedural `skinWeight` of `portrait.glsl`. Like the web, protect is
  applied twice (the mask R channel already subtracts it and the pass uses
  `R·(1−G)`); the port keeps that behaviour on purpose.
- The pass runs after the face warp and before the colour stack, in stored
  source UV, where the Vision boxes and the mask live. `skinTexture` only
  modulates an active smoothing, exactly like the shader's early-out.
- The mask build is opt-in (`Editor.setBeautyMask` / `buildBeautyMask`) and the
  app does not call it yet: the native portrait pane and the `EditorModel`
  wiring are phase A6, after liquify (A4) and the clarity/sharpen/denoise
  sliders (A5).
- `MNGEdit` now runs 44 test methods on macOS, eight of them new for this pass:
  mask statistics and cheek/eye protection, identity bytes with a mask, a zero
  mask at maximum sliders, cheek-vs-eye smoothing, `skinTexture` variance,
  blemish luma, skin-tone r/b direction, preview/export PSNR > 45 dB and the
  JSON round-trip/clamp. CI run `43813535925` is green at `a559914`.

## Round 9 notes

- Free liquify is a source-UV displacement field, ported line by line from
  `src/core/liquify.ts`: 64 texels across, 24…128 rows from the source aspect,
  radius measured on the source width (`radiusY = radius/aspect`), a squared
  `(1−d²)²` falloff, and `shift = min(0.09, max·1.02)`. R/G encode the signed
  drag as `128 + value/shift·127`, so an untouched texel is exactly 128 and
  decodes to zero; B stays 0 and A 255.
- `Editor.setLiquifyDabs` / `addLiquifyDab` follow the web state clamp: finite
  values only, `|dx|+|dy| >= 1e-6`, x/y 0…1, drag ±0.25, radius 0.002…0.35,
  and only the newest 640 dabs survive. The field is rebuilt when the history
  changes, not per rendered frame.
- `Editor.sourcePoint` pushes the source UV through the field first, clamps the
  result to 0…1, then applies the face reshape — the same order as
  `warpFace()`. `sourcePixel`, `sampleBilinear` and `mappedSourceUV` share it,
  so the beauty taps and the base colour see the same pushed UV, and
  `exactCopy` is disabled while a field exists. Clearing the dabs restores the
  identity bytes, and `replacingSource` carries the history to the new bitmap.
- `MNGEdit` now runs 53 test methods on macOS, nine of them new: field
  dimensions/aspect, the neutral 128 corner, malformed/zero-dab drops, the
  0.09 shift cap, centre move with an untouched corner, clear-to-identity,
  clamp/newest-640, and the web JSON round-trip. CI run `43814818535` is green
  at `bca2c5f`; the native brush and ruler are still phase A6.

## Round 10 notes

- Clarity, sharpen and denoise now decode into `EditorAdjustments` with the web
  ranges (−100…100 for clarity, 0…100 for the two amounts) and run in
  `DetailKernel`, a line-by-line port of sections 1–3 of `main.glsl`. Denoise
  uses the eight edge-aware taps of the export path at 2.5 texels, clarity the
  eight-tap 10-texel blur with the −0.18…0.18 halo limit and the 0.72 highlight
  mid mask, and sharpening the four 1-texel taps with the 0.006…0.022 noise
  floor. The pass runs after warp/liquify and before beauty and the colour
  stack.
- Tap radii are source-texel distances converted through the source size, so
  the preview and a full-resolution export sharpen the same detail. The app
  always takes the export-quality path instead of dropping taps on a small
  preview; the trade is CPU time, which the device check has to measure.
- The three passes only wake when their own values are non-zero, and a
  flat photo stays byte-identical at clarity/sharpen 100 because the detail and
  halo terms collapse to zero. Colour identity no longer includes them, so a
  detail-only edit skips the colour round-trip without skipping the kernel.
- The Adjust pane gains the "Chi tiết" group with the three chips, Vietnamese
  labels and short names, zero-based ruler and unsigned value chip. The tone
  tune clamps through the same `minimum` rule instead of special-casing
  vignette.
- `MNGEdit` now runs 61 test methods on macOS, eight of them new: identity
  bytes with the detail sliders neutral, a flat photo staying neutral, denoise
  lowering flat variance while preserving a hard edge, clarity/sharpen
  expanding a low-contrast step, the noise floor under ±1 LSB grain, a monotone
  ramp never inverting at maximum values, preview/export PSNR > 45 dB and the
  JSON round-trip/clamp. CI run `43816541257` is green at `4c4a675`, including
  the simulator build, device build, simulator test and both upload steps.

## Round 11 notes

- The editor now has six tabs. "Chân dung" sits right after "Tinh chỉnh" and
  uses the same `paramDeck` builder as the adjust tab: the three chain chips
  first, then the "Chân dung" group (smooth skin, skin texture, blemish, skin
  tone) and the "Dáng mặt" group (face slim, jawline, chin, eye size, nose
  size, mouth size). Every slider starts at zero except `skinTexture` at 55,
  matching `EditorModel.defaultAdjustments` on the web, and the value chip
  resets one slider back to zero.
- The chain names and values come from `App/Resources/presets.json`, a
  byte-for-byte copy of the web's `specs/presets.json` (same hash). The
  XcodeGen resource phase bundles it, `ChainPreset` decodes it, and
  `applyChainPreset` only writes the keys the spec names, clamps each value
  and records one undo step; the toast says "Đã áp dụng làm đẹp: <tên>".
  Unknown keys are ignored instead of failing the whole chain.
- The beauty mask now builds in the same task as the Vision anchors:
  `detectFaceAnchors` runs Vision and `buildBeautyMask` together and publishes
  the anchors and the mask in one update, so the first portrait render already
  has skin protection. The R/G/B layout, the double-protect and the procedural
  `skinWeight` fallback when no face is found are the web's, unchanged.
- The free-liquify field has a native brush. Dabs store source UV and the
  displacement between two source points, so preview and export bend the same
  pixels; the pointer maps to the source through the display geometry only
  (crop, quarter turn, flip, fine rotation, perspective), never through the
  current warp, so a stroke cannot chase itself. Brush size is 1–20 % of the
  source width, dabs are spaced 0.35 × the ring radius with at most 48 per
  event, and each stroke is one `beginEdit`/`endEdit` undo step with a clear
  action. While the brush is on, the stage pan, pinch and double tap are
  disabled and the value ruler is replaced by the brush-size rail, so entering
  the mode cannot move the photo.
- The gold ring samples `sourceUV` at the centre of the output and 0.01 away,
  then converts the source radius to a fraction of the fitted preview, so a
  cropped or turned photo shows the true brush footprint instead of a fixed
  screen circle.
- `MNGEdit` runs 65 test methods on macOS, four of them new: identity mapping
  with edge clamping and no warp feedback, both quarter turns, an offset crop
  and a horizontal flip. CI run `43819610301` is green at `9d7a6b5`, including
  the simulator build, the unsigned device build, the simulator test and both
  upload steps. The device check still has to measure the export-quality
  `DetailKernel` taps and the beauty mask build on a real phone.

## Round 12 notes

- `specs/filters.json` v1 is now the shared filter catalog: 29 tones in the
  existing order, each with its Vietnamese and English name, category, final
  row-major 3×3 matrix, per-channel offset, Canvas2D fallback and hint. The
  matrices were extracted from the release `PRESETS` and the extracted file was
  checked against a six-swatch palette captured before the move, so no tone
  changed.
- The web reads the JSON in `src/core/color.ts` instead of rebuilding 29
  recipes from helper functions. `PRESETS`, `presetById` and
  `buildColorTransform` keep their public shape, so the filter rail,
  thumbnails, saved presets and the shader uniform path did not change.
  `test-filters.html` runs 17 checks: count and order, unique ids, category
  counts, matrix/offset shape and finiteness, identity original, CSS presence,
  hint placement, zero-adjustment matrix equality, the mandatory 8-bit palette
  for every tone on six swatches, alpha preservation, unknown-filter fallback
  and object lookup — ALL PASS.
- `MNGEdit` bundles a byte-for-byte copy under
  `Packages/MNGEdit/Sources/MNGEdit/Resources/filters.json`, and
  `EditorFilterSpec` decodes it with `Bundle.module`: version 1, nine matrix
  values, three offsets, finite numbers, unique ids. `Editor.presetTransform`
  now looks up the spec and the 170 lines of recipe helpers are gone, so the app
  and the browser cannot drift. The localized filter names and hints stay in
  `Strings.swift`; only the numbers and the catalog order come from the JSON.
- Four new tests in `FilterSpecTests` cover the decoded catalog (29 filters,
  enum/spec order, category counts, shape and finite checks), every
  `EditorFilter` resolving to its matrix, the six-swatch golden palette
  (accepting one LSB because Swift keeps Float while the browser evaluates
  Double) and the five legacy aliases. `MNGEdit` runs 69 test methods; CI run
  `43852777832` is green at `b90fd85`, including both builds, the simulator test
  and both uploads.

## Round 13 notes

- The web editor now has a fourth tab, **Hiệu ứng vùng** (region effects),
  between Chân dung and Bộ lọc. It paints mosaic or blur with one brush and
  one mask, matching the reference app's "mosaic brush" flow: pick a style, the
  brush arms itself, drag on the photo and each stroke is one undo step. Size
  (1–20 % of the source width) and strength (0–100 %) are live globals, so
  changing them re-renders the whole painted region the way a mosaic-size
  slider does; clearing removes stamps but keeps the brush settings.
- State stays v2-compatible and additive: `retouch.effects = { dabs[],
  size, strength }`, where every dab is `{ kind: 'mosaic' | 'blur', x, y,
  radius }` in source UV with a width-normalised radius. The importer clamps
  coordinates and radii, drops unknown kinds, keeps the newest 1600 stamps and
  treats a missing block as the default 8 % / 60 state. Older v1 and v2 states
  without `effects` load unchanged.
- Stamps rasterise into one RGBA8 mask whose longest side is at most 1024 px:
  R = mosaic, G = blur, alpha = 255. Every stamp is a solid core with a linear
  35 % feather; overlaps accumulate with `max`, so restrokes do not build up.
  The mask is cached by dab-array identity and source size, and is rebuilt only
  when either changes.
- Shader uniforms are derived from the live settings: `blockPx =
  max(2, round(size * srcW * 0.55))`, `grid = [srcW/blockPx, srcH/blockPx]`,
  and `blur = [size * 0.42, size * 0.42 * srcW / srcH]` so the blur stays
  circular on non-square photos. Mosaic samples one texel at the centre of each
  grid cell; blur averages nine taps. Both read the source texture in source UV
  after `warpFace` and before detail and colour, so preview and every export
  tile land on the same pixels, and mask 0 is a true pixel-identical bypass.
- The mask is uploaded as texture unit 6 and the shader variants are unchanged:
  the new code is unconditional, with `u_effectStrength = 0` on tools that have
  no mask. The tab bar was tightened to 9 px labels with `nowrap` (8.5 px below
  380 px) because seven Vietnamese labels wrapped at the old 10 px.
- `test-effects.html` runs 33 checks: default state, normalize/clamp/cap,
  byte JSON round-trip, mask channels/feather/1024 cap/empty dabs, block and
  grid geometry, render diff inside/outside, flat mosaic cells, preview/export
  PSNR, clear, blur energy loss, undo, strength 0 bypass and restore — ALL
  PASS. `test-effects-ui.html` runs 14 checks on the 390 px layout: tab and
  pane, chips, brush arming, stroke dabs at 8 % radius, export change, one-step
  undo, both rulers, style switch, clear and leaving the tab — ALL PASS. The
  7-tab bar renders every label on one line at 390 px.
- Swift port is the next B2 step: a CPU mask builder and mosaic/blur pass inside
  `Editor.renderRGBA` (after warp, before detail/colour), the same state fields,
  and the tab/pane/brush UI. Until that lands, the Swift editor intentionally
  has no effect tab; the state decoder ignores the optional block.

## Visual checks per UI phase

- iPhone SE (compact, 375 pt), iPhone 15/16 (393 pt), iPad 11" portrait and
  landscape.
- Light and dark schemes, plus Increased Contrast where relevant.
- Dynamic Type at default and one step up.
- No horizontal overflow; Vietnamese strings unchanged; numbers formatted
  `vi-VN` (`1.966 mục`, `13.1 GB`).
- Reduce Motion disables the album/cover morph.
