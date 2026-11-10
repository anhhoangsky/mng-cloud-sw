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

- [ ] The timeline groups by year/month with 120-item pages; "Tải thêm" adds
      the next page and keeps the scroll anchor.
- [ ] The kind chips (Ảnh/Video/Live/Yêu thích) filter instantly.
- [ ] Long press opens the tile menu: yêu thích, tải xuống, thông tin, chuyển
      vào kho mã hóa, xoá.
- [ ] The info sheet closes first and the delete confirmation appears after it.
- [ ] Favorite is optimistic and rolls back when the server refuses.
- [ ] Multi-select shows the selection bar; delete asks once for the whole
      selection.

## Viewer

- [ ] Swiping moves to the next photo; the filmstrip scrolls to the current
      item and stays centered.
- [ ] Pinch and double tap zoom; double tap again resets.
- [ ] Swiping down dismisses the viewer.
- [ ] A video plays with the correct range requests and can be seeked.
- [ ] A Live Photo shows the video companion.
- [ ] Share exports the file and opens the system share sheet.

## Albums and search

- [ ] The seven sections collapse and expand; the sort and density controls
      apply per section.
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

## Release checks (P11)

- [ ] Dynamic Type at the default size and one step up.
- [ ] VoiceOver labels on the tiles, the viewer and the vault rows.
- [ ] Reduce Motion and Increased Contrast.
- [ ] Dark mode on every screen.
- [ ] A 30-minute browse session without a crash or a memory warning.
