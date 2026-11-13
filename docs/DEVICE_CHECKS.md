# Device check list

Everything in this file needs a real iPhone or iPad: the simulator cannot
validate the share sheet, the camera roll, drag gestures, haptics or the
auto-lock timer. Run it after every phase lands.

Build the app from `MNGCloud.xcodeproj` (generated with `xcodegen generate`)
and sign it with a development team. The CI artifact is unsigned and only
usable in the simulator.

## Session and shell

- [ ] Login with a real account; the CSRF token is stored in memory only.
- [ ] Wrong password shows the server's Vietnamese sentence.
- [ ] The four compact tabs switch without a flash; the iPad sidebar shows five
      entries (Thư viện, Album, Tìm kiếm, Kho, Cài đặt).
- [ ] The cloud pill opens the Connections sheet; picking a cloud reloads the
      timeline and shows the toast "Đang xem …".
- [ ] Pull to refresh reloads the current page.

## Library

- [ ] The timeline loads older photos as the grid is scrolled, without a
      "Tải thêm" footer; the scroll position and the scrollbar stay put while a
      page arrives.
- [ ] Scrolling a large "Tất cả" timeline stays smooth well past the first
      page: only the rows around the viewport are created, and a deep fling
      stops at the shimmer boundary instead of leaving the pager dozens of
      requests behind.
- [ ] The grid keeps three full-width columns at every scroll position; no
      row collapses to a thin column at the left edge.
- [ ] The kind chips (Ảnh/Video/Live/Yêu thích) filter instantly.
- [ ] Long press opens the tile menu: yêu thích, tải xuống, thông tin, chuyển
      vào kho mã hóa, xoá.
- [ ] The info sheet closes first and the delete confirmation appears after it.
- [ ] Favorite is optimistic and rolls back when the server refuses.
- [ ] Multi-select shows the selection bar; delete asks once for the whole
      selection.
- [ ] Scrolling up to older photos fills the shimmer cells with real photos
      even when the server has not written their thumbnail yet: the tile falls
      back to the preview/original instead of staying on an icon.
- [ ] Scrolling a row of missing thumbnails back and forth stays smooth; a
      failed path cools down for 25 s instead of retrying and cross-fading on
      every pass.

## Viewer

- [ ] Swiping moves to the next photo smoothly: the next page is drawn from the
      prefetched bitmap, without a black flash or a jump at the end of the
      slide, including when swiping quickly through several photos.
- [ ] The filmstrip scrolls to the current item and stays centered.
- [ ] Pinch and double tap zoom; double tap again resets.
- [ ] Swiping down dismisses the viewer.
- [ ] Every viewer button (close, favorite, info, edit, previous/next, share,
      save, delete, LIVE) uses the same liquid glass as the shell header.
- [ ] A video plays with the correct range requests and can be seeked.
- [ ] Swiping or jumping (filmstrip, arrow keys) from a playing video to any
      other photo or video stops the previous audio immediately.
- [ ] A Live Photo shows the video companion, and turning LIVE off stops it.
- [ ] Share exports the file and opens the system share sheet.

## Albums and search

- [ ] The seven sections collapse and expand; the sort and density controls
      apply per section.
- [ ] Scrolling the Album tab is smooth while the AI/people/places sections
      load: the page does not jump under the finger when the skeletons are
      replaced, and the cover grid does not judder while thumbnails decode.
- [ ] Album photo tiles and collection covers whose thumbnail is missing fall
      back to the preview/original with a real photo.
- [ ] The people grid shows 87 people, 8 provinces and 15 districts on the
      reference library.
- [ ] The search field waits 280 ms, shows the five chips and the four hints.
- [ ] `q=20221231` returns the expected day; `q=IMG` caps the result list at
      300 entries (1.814 in the reference library).
- [ ] Back from a search album returns to the search results.

## Settings

- [ ] The sections follow the PWA order: Kết nối, iCloud, Thư viện, Công cụ,
      Tài khoản, Giới thiệu.
- [ ] Tapping a cloud runs the WebDAV probe and shows "Kết nối tốt · N ms" or
      the server's failure sentence.
- [ ] "Quét lại thư viện", "Tạo lại ảnh thu nhỏ lỗi" and "Xóa tệp tạm" each
      show their own spinner and keep the other rows usable.
- [ ] A box without the writer or queue enabled shows the honest 503 sentence.
- [ ] "Mở máy chủ" opens `/seafile/` in the browser.
- [ ] The iCloud row refreshes when Settings opens and never polls.

## Duplicates

- [ ] The sheet shows `hashed/total` and the pending-thumbnail note when
      `hashed < total`.
- [ ] "Xem thêm N nhóm" reveals 30 more groups at a time.
- [ ] Tapping a thumbnail opens the viewer with the whole group.
- [ ] Closing and opening the duplicate sheet a second time does not crash;
      the previous groups stay visible while the new list loads.
- [ ] Deleting from that viewer removes the item and updates the library.

## Vault (`mng-vault/v1`)

- [ ] Creating a vault asks for a name and a password of at least 8 characters;
      the password is never sent to the server.
- [ ] Unlocking with the wrong password shows "Mật khẩu không đúng."; the
      correct one opens the browser.
- [ ] A vault without an encrypted manifest shows the honest "chưa có chỉ mục"
      state.
- [ ] Uploading a file encrypts it in 4 MiB chunks; the progress bar counts the
      chunks; the file appears in the manifest.
- [ ] The preview decrypts the file again: an image renders, a video plays, a
      text file shows its content, an unknown format shows the honest
      "cannot preview" state.
- [ ] "Chuyển vào kho mã hóa" moves library items into the vault and only then
      deletes the original.
- [ ] Leaving the tab, idling for 15 minutes or backgrounding the app drops the
      key and asks for the password again.

## Editor

- [ ] The pencil in the viewer opens the editor for photos but not for videos.
- [ ] The header rotate/flip buttons, the six crop ratios, the four crop modes
      and the nine sliders update the preview immediately; the crop rectangle
      can be dragged.
- [ ] Dragging a slider previews on the photo while the finger moves, and one
      undo tap returns to the value from before the drag.
- [ ] The filter chips match the web editor (Nguyên bản, Rực rỡ, Ấm áp, Mát
      lạnh, Đen trắng, Mờ ảo).
- [ ] A named filter preset saves, appears at the head of the filter rail,
      applies and can be deleted; the "Mặc định" hairline separates it from the
      built-in filters; the save form lives inside "Tùy chỉnh tone"; tapping
      the active preset restores the earlier look; the list survives a
      relaunch.
- [ ] The text tab has no add-text button; "Chạm đặt" places a layer at the
      tap, typing updates the photo without tapping outside, and the keyboard
      does not resize the stage.
- [ ] Tapping the photo outside the text field commits the draft and keeps the
      selected frame, so the text stays on the canvas.
- [ ] "Khung chữ" shows the dashed measured frame; the rotate and scale
      handles stay usable, the frame follows the glyphs while scaling, and a
      drag starts without a jump. The rotate handle keeps turning past ±180°
      instead of stopping at the limit, the text orbits its own centre rather
      than the stage, and the 44 pt target is easy to catch.
- [ ] The crop rail has exactly four modes (Tỉ lệ, Xoay, Trên / dưới,
      Trái / phải); the rotate/flip buttons are not repeated inside it.
- [ ] The crop ruler covers −180…180° with the gold zero and there is no
      "Xong" button.
- [ ] Dragging "Trên / dưới" to the right grows the top edge; dragging
      "Trái / phải" to the right grows the left edge. Negative values mirror
      the effect. Each drag previews live and is one undo step.
- [ ] At ±100 on either perspective axis no empty corner appears inside the
      crop frame; the frame stays covered.
- [ ] While the rotation ruler or either perspective ruler is held the area
      outside the frame loses its blur and keeps only the dim (the photo stays
      sharp); releasing restores the glass. The rotate and perspective
      previews follow the finger without visible stutter.
- [ ] Pinching the photo in the crop tab keeps the dim scrim over the whole
      image; the frame still samples the zoomed pixels.
- [ ] Leaving the crop tab applies the frame, and returning to it keeps the
      frame, the angle and both perspective values.
- [ ] "Lưu ảnh" with "Ghi đè ảnh gốc" replaces the file and refreshes the
      library; "Lưu thành bản sao" keeps the original.
- [ ] A cancelled or failed save leaves the original untouched.
- [ ] The AI tab sits between "Chữ" and "Cắt"; the model picker expands to
      Chất lượng / Cân bằng / Nhanh.
- [ ] An AI background pass opens the brush step instead of baking at once:
      "Thêm"/"Xoá", the size slider, the stroke undo, "Đảo mask" and "Nền
      trong suốt" all update the full-source preview under the finger.
- [ ] The brush preview is the whole source (not the cropped view), and the
      photo stays upright before and after "Hoàn tất"; it does not flip.
- [ ] "Mờ phông" keeps its "Độ mờ" slider live in the brush step; moving it
      changes the blur before "Hoàn tất".
- [ ] The retouch sliders (strength, tone, hair colour) stay adjustable in the
      brush step and update the preview without rerunning Vision.
- [ ] "Hoàn tất" bakes the painted mask; "Huỷ" leaves the photo untouched.
      Leaving the AI tab while refining also discards the mask.
- [ ] "Xoá phông" and "Tách người" cut the subject out; a PNG/WebP item keeps
      the transparent corners, and a JPEG item shows the alpha warning in the
      export sheet.
- [ ] "Mờ phông" blurs the background and "Nền trắng" paints it white while
      the subject stays untouched.
- [ ] The five retouch actions (Trắng da, Mịn da, Xóa mụn, Tông da, Đổi màu
      tóc) apply to a portrait, and a photo without a face reports "Không tìm
      thấy khuôn mặt rõ nét."
- [ ] The progress dialog reports the live step, and "Hủy AI" closes it
      without changing the photo.
- [ ] After an AI pass the crop, geometry, colour and text are unchanged, the
      undo history restarts, and "Hoàn tác AI" restores the source from before
      the pass.
- [ ] While the brush step is open the save button, undo/redo and the geometry
      tools are disabled, and the text layers and hold-to-compare are hidden.
- [ ] All AI actions work in airplane mode (Vision runs on the device).

The Core ML model phase adds a separate download/fallback/hair-parity matrix;
run the checklist in [`AI_BENCHMARK.md`](AI_BENCHMARK.md) §9 when it lands.
The current picker is Chất lượng / Cân bằng / Nhanh; the planned one adds
Tối đa and names the engine in the detail line.

## Administration (admin account only)

- [ ] The Settings row "Quản trị người dùng" only appears for administrators.
- [ ] Opening the console loads the user list exactly once; the app itself
      never calls the admin API.
- [ ] Creating a user works with and without cloud provisioning.
- [ ] Locking, unlocking, granting and revoking the admin role all update the
      row in place.
- [ ] Deleting a user asks once and works with and without the cloud data.
- [ ] The server's refusals (primary admin, self delete, last admin) are shown
      with the server's own sentence.

## iCloud importer

- [ ] A server without the importer shows "Máy chủ này chưa cung cấp trình tải
      iCloud" instead of a fake connected state.
- [ ] Signing in with an Apple ID asks for the six-digit 2FA code when the
      account needs it.
- [ ] The settings (50/200/500/1000 photos, delete after the import) are saved
      and survive a reopen.
- [ ] The job card follows the state, the progress and the log, and
      pause/resume/cancel work.
- [ ] The sheet stops polling when it is closed.

## Release checks (P11)

- [ ] Dynamic Type at the default size and one step up.
- [ ] VoiceOver labels on the tiles, the viewer and the vault rows.
- [ ] Reduce Motion and Increased Contrast.
- [ ] Dark mode on every screen.
- [ ] A 30-minute browse session without a crash or a memory warning.
