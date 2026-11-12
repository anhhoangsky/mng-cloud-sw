import MNGKit
import SwiftUI
import UIKit

/// Library screen: grouping toolbar, 120-item timeline paging, kind filters,
/// year/month cards and empty/error/skeleton states.
///
/// The timeline is chronological and starts at the newest photo, so the grid
/// grows upwards: the newest photo sits at the bottom of the screen and
/// scrolling up walks back in time, exactly like the native shell.
struct LibraryView: View {
    let model: ShellModel

    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Scroll offset of the library grid, used to swap the header subtitle
    /// between the item count and the date of the photo at the top.
    @State private var scrollOffset: CGFloat = 0
    /// The web keeps the item count until the first scroll gesture: the
    /// initial jump to the newest photo does not count. Only then does the
    /// header start following the top photo.
    @State private var hasScrolled = false
    /// The offset of the previous scroll callback, for the direction of the
    /// gesture.
    @State private var lastScrollOffset: CGFloat = 0
    /// Height of the scrollable content, for the iOS 17 fallback metrics.
    @State private var contentHeight: CGFloat = 0
    /// Height of the scroll viewport, for the iOS 17 fallback metrics.
    @State private var viewportHeight: CGFloat = 0
    /// Width of the scroll viewport, used to map a scroll offset back to a
    /// row of the full-length placeholder grid.
    @State private var viewportWidth: CGFloat = 0
    /// The largest possible scroll offset, so "at the newest photo" is a
    /// real measurement instead of a guess.
    @State private var maxScrollOffset: CGFloat = 0
    /// The underlying scroll view, so opening the filter dropdown can stop
    /// a deceleration that would otherwise close it again.
    @State private var hostScrollView: UIScrollView?
    /// True when a filter or grouping change is settling. The dock stays
    /// condensed through that transition even if the new page clamps the
    /// offset back to the newest photo.
    @State private var dockPinnedCompact = false
    /// The photo under the header when the filter changed, plus the metrics
    /// needed to put that photo back after the new page arrives.
    @State private var pendingFilterAnchor: FilterAnchor?
    /// A failed older-page request may be retried after this moment, without
    /// having to scroll all the way back to the newest photos first.
    @State private var olderRetryAt = Date.distantPast
    /// Guards the one programmatic `contentOffset` write against re-entering
    /// the scroll observer while the scroll view is still reporting it.
    @State private var isApplyingScroll = false
    /// Global top edge of the scroll content, from the iOS 17 fallback probe.
    @State private var contentTopGlobalY: CGFloat?
    /// The fallback probe has reported at least once.
    @State private var hasContentTop = false
    /// The first page has to be placed at the newest photo explicitly: the
    /// skeleton is replaced after the initial layout, so the scroll anchor
    /// cannot be left to SwiftUI's default. While this is true the scroll
    /// callbacks are only used to find the bottom, never as gestures.
    @State private var initialAnchorPending = true
    /// A deadline so a failed anchor can never lock the chrome forever.
    @State private var initialAnchorDeadline = Date.distantFuture
    /// The anchor is scheduled once per view lifetime.
    @State private var initialAnchorScheduled = false
    /// Suppresses the scroll accumulator while a replaced page clamps the
    /// offset, matching the web's `scroll_guard`.
    @State private var scrollGuardUntil = Date.distantPast
    /// Set after one older page is requested; re-armed once the person scrolls
    /// away from the top, so a journal replacement cannot cascade.
    @State private var olderRequestArmed = true
    /// The tile to keep under the header when an older page is prepended.
    @State private var pendingOlderAnchorID: Int64?
    /// The bottom edge of the scroll view in screen coordinates.
    @State private var viewportGlobalMaxY: CGFloat = 0
    /// Frames of the realized timeline tiles, in screen coordinates.
    @State private var tileFrames: [Int64: CGRect] = [:]
    /// The ids of the current page, so a stale frame from a replaced page can
    /// never become the header date or the older-page anchor.
    @State private var knownItemIDs: Set<Int64> = []
    /// The marquee drag in selection mode. The band is not painted; every
    /// intersected tile joins the selection, like the web's `Marquee`.
    @State private var marquee: MarqueeState?
    /// The tap that ends a marquee drag must not toggle its starting tile.
    @State private var suppressTileTapUntil = Date.distantPast
    /// The photo picker for "save into the library".
    @State private var backupPickerOpen = false

    private var library: LibraryModel { model.library }
    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        VStack(spacing: 0) {
            // The toolbar is pinned above the grid. The compact layout has
            // none: the filters live in the dropdown of the header and the
            // switcher of the layout floats above the dock, the way the
            // native shell does.
            if !library.isAlbumOpen, !isCompact {
                LibraryToolbar(model: model) {
                    backupPickerOpen = true
                }
                .padding(.horizontal, isCompact ? 16 : 0)
                .padding(.top, isCompact ? 6 : 0)
                .padding(.bottom, 12)
            }

            ScrollViewReader { scrollProxy in
                observingScroll(
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // Scroll probe for the iOS 17 fallback. On iOS 18
                            // the native scroll geometry reports the offset
                            // without a preference round-trip.
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: TimelineScrollOffsetKey.self,
                                    value: proxy.frame(in: .global).minY
                                )
                            }
                            .frame(height: 0)

                            // A horizontal-only pan on the scroll view
                            // drives the marquee, so vertical drags keep
                            // scrolling while selection mode is on.
                            TimelineMarqueeBridge(
                                isActive: library.selectionMode,
                                begin: beginMarquee(at:),
                                update: updateMarquee(to:),
                                end: endMarquee,
                                onScrollView: { scrollView in
                                    if hostScrollView !== scrollView {
                                        hostScrollView = scrollView
                                        // The iOS 17 fallback needs the real
                                        // insets, which only exist once the
                                        // scroll view is attached.
                                        if !usesNativeScrollGeometry {
                                            refreshFallbackMaxOffset()
                                            refreshFallbackOffset()
                                        }
                                    }
                                }
                            )
                            .frame(width: 0, height: 0)

                            bodyContent

                            // The dock takes 70 pt of the safe area; the web's
                            // content keeps another 84 pt below the last row
                            // (154 in total). The spacer carries that padding
                            // so `TimelineAnchor.bottom` is the real end of the
                            // scrollable content and "newest photo" can be
                            // restored without guessing.
                            Color.clear
                                .frame(height: isCompact ? 84 : 60)
                                .id(TimelineAnchor.bottom)
                        }
                        .padding(.horizontal, isCompact ? 0 : 32)
                        .padding(.top, isCompact ? 0 : 26)
                        .frame(maxWidth: Tokens.Layout.contentMaxWidth, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: TimelineContentHeightKey.self,
                                    value: proxy.size.height
                                )
                            }
                        }
                    }
                    .refreshable {
                        await library.reload()
                    }
                )
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TimelineViewportKey.self,
                            value: proxy.frame(in: .global)
                        )
                    }
                }
                .coordinateSpace(name: TimelineSpace.name)
                .onChange(of: library.revision) { _, _ in
                    // The new page just replaced the old one. Whatever offset
                    // change follows is the browser-style clamp of a shorter
                    // page, not a drag.
                    scrollGuardUntil = Date().addingTimeInterval(0.6)
                    lastScrollOffset = scrollOffset
                    pendingOlderAnchorID = nil
                    olderRequestArmed = true
                    knownItemIDs = Set(library.page.items.map(\.id))

                    // A filter or grouping change captured the photo that was
                    // under the header. Put that photo back once the new page
                    // has been laid out, instead of leaving the old pixel
                    // offset pointing at a completely different time.
                    if let anchor = pendingFilterAnchor {
                        pendingFilterAnchor = nil
                        restoreFilterAnchor(anchor)
                    }
                }
                .onChange(of: library.page.count) { old, new in
                    knownItemIDs = Set(library.page.items.map(\.id))
                    olderRequestArmed = true

                    // The first page replaces the skeleton after the initial
                    // layout. SwiftUI's default anchor cannot follow that
                    // replacement, so jump to the newest photo once the grid
                    // has been laid out.
                    if old == 0, new > 0, library.filters.isTimeline {
                        positionTimelineAtLatest(scrollProxy)
                    }

                    guard new > old else { return }

                    // With the full-length grid the prepended page never
                    // changes the content height, so there is nothing to
                    // re-anchor. Ask for the next page only if the viewport
                    // is still sitting over the placeholders.
                    if usesTimelinePlaceholders {
                        pendingOlderAnchorID = nil
                        olderRetryAt = Date().addingTimeInterval(0.2)
                        maybeLoadOlderPage()
                        return
                    }

                    // An older page is inserted above the viewport. Keep the
                    // photo the person was reading where it was, like the
                    // web's `anchor_y + delta` restore after a page prepend.
                    guard let anchor = pendingOlderAnchorID else {
                        return
                    }
                    pendingOlderAnchorID = nil
                    scrollGuardUntil = Date().addingTimeInterval(0.45)
                    Task { @MainActor in
                        // Let the lazy grid realize the prepended rows before
                        // anchoring, otherwise the scroll view clamps the jump.
                        await Task.yield()
                        try? await Task.sleep(nanoseconds: 40_000_000)
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            scrollProxy.scrollTo(anchor, anchor: .top)
                        }
                    }
                }
                .onAppear {
                    knownItemIDs = Set(library.page.items.map(\.id))
                    // The filter changes are initiated by the model, so the
                    // screen hooks itself in while it owns the scroll view.
                    library.onFilterWillChange = {
                        captureFilterAnchor()
                    }
                    if library.filters.isTimeline {
                        positionTimelineAtLatest(scrollProxy)
                    } else {
                        // A persisted years/months layout opens at the newest
                        // card, which is the bottom of the chronological list.
                        let hasBuckets = library.filters.layout == .years
                            ? !library.years.isEmpty
                            : !library.months.isEmpty
                        if hasBuckets {
                            // The data is already loaded when the tab is
                            // re-entered, so no revision change will arrive.
                            pendingFilterAnchor = nil
                            positionBucketsAtLatest()
                        } else if pendingFilterAnchor == nil {
                            pendingFilterAnchor = FilterAnchor(
                                id: nil,
                                takenAt: nil,
                                screenY: 0
                            )
                        }
                    }
                }
                .onDisappear {
                    library.onFilterWillChange = nil
                }
            }
        }
        .background(Palette.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            if model.backup.isRunning || model.backup.isFinished {
                BackupProgressCard(model: model.backup) {
                    model.backup.dismiss()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .fullScreenCover(isPresented: $backupPickerOpen) {
            BackupPicker { picked in
                backupPickerOpen = false
                guard !picked.isEmpty else {
                    model.notify(Strings.backupEmpty)
                    return
                }
                let jobs = picked.map {
                    CloudBackupModel.Job(
                        name: $0.name,
                        mime: $0.mime,
                        url: $0.url,
                        size: $0.size
                    )
                }
                Task {
                    await model.backup.upload(jobs, client: model.client)
                    await library.reload()
                }
            }
            .ignoresSafeArea()
        }
        .onPreferenceChange(TimelineTileFramesKey.self) { frames in
            tileFrames = frames.frames
            updateTimelineTopDate()
        }
        .onPreferenceChange(TimelineViewportKey.self) { rect in
            if abs(rect.maxY - viewportGlobalMaxY) > 0.5 {
                viewportGlobalMaxY = rect.maxY
                updateTimelineTopDate()
            }
            if abs(rect.width - viewportWidth) > 0.5 {
                viewportWidth = rect.width
            }
            if abs(rect.height - viewportHeight) > 0.5 {
                viewportHeight = rect.height
                if !usesNativeScrollGeometry {
                    refreshFallbackMaxOffset()
                    refreshFallbackOffset()
                }
            }
        }
        .onPreferenceChange(TimelineContentHeightKey.self) { height in
            guard abs(height - contentHeight) > 0.5 else { return }
            contentHeight = height
            if !usesNativeScrollGeometry {
                refreshFallbackMaxOffset()
            }
        }
        .onPreferenceChange(TimelineScrollOffsetKey.self) { top in
            guard !usesNativeScrollGeometry else { return }
            contentTopGlobalY = top
            hasContentTop = true
            refreshFallbackOffset()
        }
        .onChange(of: model.headerBottom) { _, _ in
            updateTimelineTopDate()
        }
        .onChange(of: library.filters) { _, filters in
            // A filter keeps the grid at the same offset until the new page
            // arrives, exactly like the web's `keep_scroll` reload.
            lastScrollOffset = scrollOffset
            pendingOlderAnchorID = nil
            olderRequestArmed = true
            model.isFilterMenuOpen = false
            if !filters.isTimeline {
                // Choosing Năm or Tháng never opens the dock. It stays
                // condensed until the person taps its handle.
                model.isTabBarCompact = true
                library.setTimelineTopDate(nil)
            }
        }
        .onChange(of: model.isUploadRequested) { _, requested in
            guard requested else { return }
            model.isUploadRequested = false
            backupPickerOpen = true
        }
        .onChange(of: model.isFilterMenuOpen) { _, open in
            // Opening the menu over a decelerating grid would otherwise let
            // the remaining momentum close it on the next scroll callback.
            guard open, let scrollView = hostScrollView else { return }
            scrollView.setContentOffset(scrollView.contentOffset, animated: false)
        }
    }

    // MARK: - Scroll measurement

    /// iOS 18 reports the real scroll geometry during the gesture. The old
    /// preference probe stays as the iOS 17 fallback.
    @ViewBuilder
    private func observingScroll<Content: View>(_ content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: TimelineScrollMetrics.self) { geometry in
                let top = geometry.contentInsets.top
                let bottom = geometry.contentInsets.bottom
                let height = geometry.contentSize.height + top + bottom
                return TimelineScrollMetrics(
                    offset: max(0, geometry.contentOffset.y + top),
                    maxOffset: max(0, height - geometry.containerSize.height),
                    contentHeight: height,
                    viewportHeight: geometry.containerSize.height
                )
            } action: { _, metrics in
                contentHeight = metrics.contentHeight
                viewportHeight = metrics.viewportHeight
                if abs(metrics.maxOffset - maxScrollOffset) > 0.5 {
                    maxScrollOffset = metrics.maxOffset
                }
                handleScroll(offset: metrics.offset)
            }
        } else {
            // iOS 17 uses the probe preference handled by the outer view;
            // its global top and the measured viewport produce the same
            // normalized offset as the iOS 18 scroll geometry.
            content
        }
    }

    private var usesNativeScrollGeometry: Bool {
        if #available(iOS 18.0, *) { return true }
        return false
    }

    private func refreshFallbackMaxOffset() {
        // Match the iOS 18 `contentSize + insets - container` maths: the
        // fallback offset is normalized with the top inset, so its maximum
        // has to include both insets as well.
        let insetTop = hostScrollView?.adjustedContentInset.top ?? 0
        let insetBottom = hostScrollView?.adjustedContentInset.bottom ?? 0
        let next = max(0, contentHeight + insetTop + insetBottom - viewportHeight)
        guard abs(next - maxScrollOffset) > 0.5 else { return }
        maxScrollOffset = next
        handleScroll(offset: scrollOffset)
    }

    private func refreshFallbackOffset() {
        guard !usesNativeScrollGeometry,
              hasContentTop,
              let contentTopGlobalY,
              viewportHeight > 0,
              viewportGlobalMaxY > 0
        else { return }
        let viewportTop = viewportGlobalMaxY - viewportHeight
        let insetTop = hostScrollView?.adjustedContentInset.top ?? 0
        handleScroll(offset: max(0, viewportTop - contentTopGlobalY + insetTop))
    }

    /// The first page must open at the newest photo. The skeleton is replaced
    /// after the first layout, so the jump is explicit and retried once; the
    /// offset callbacks are not gestures until it lands.
    private func positionTimelineAtLatest(_ proxy: ScrollViewProxy) {
        guard initialAnchorPending,
              !initialAnchorScheduled,
              library.filters.isTimeline,
              !library.page.items.isEmpty
        else { return }
        initialAnchorScheduled = true
        initialAnchorDeadline = Date().addingTimeInterval(1.5)
        Task { @MainActor in
            await Task.yield()
            scrollTimelineToBottom(proxy)
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard initialAnchorPending else { return }
            scrollTimelineToBottom(proxy)
        }
    }

    private func scrollTimelineToBottom(_ proxy: ScrollViewProxy) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(TimelineAnchor.bottom, anchor: .bottom)
        }
    }

    private func handleScroll(offset: CGFloat) {
        guard !isApplyingScroll else { return }

        if initialAnchorPending {
            scrollOffset = offset
            lastScrollOffset = offset
            if !dockPinnedCompact {
                model.isTabBarCompact = false
            }
            library.setTimelineTopDate(nil)
            // The skeleton has no bottom to anchor to. Only start the
            // deadline once there is a real page, otherwise a slow network
            // would waste the allowance before the grid even exists.
            guard !library.page.items.isEmpty else { return }
            let landed = maxScrollOffset > 24 && offset >= maxScrollOffset - 30
            if landed || Date() >= initialAnchorDeadline {
                initialAnchorPending = false
                hasScrolled = false
                scrollGuardUntil = Date().addingTimeInterval(0.45)
            }
            return
        }

        // A deep fling (or a status-bar tap) can land far above the loaded
        // page. When that happens, stop at the boundary plus a small shimmer
        // buffer and let the pager fill the rest; otherwise the scroll can
        // sit in a placeholder-only region that is impossible to fill fast
        // enough.
        var effective = offset
        if let floor = timelineOldestAllowedOffset, offset < floor - 0.5 {
            effective = floor
            scrollGuardUntil = Date().addingTimeInterval(0.2)
            applyScrollOffset(floor)
        }

        updateChrome(offset: effective)
    }

    /// The dock expands only at the newest/bottom position. Moving toward
    /// older photos condenses it immediately, and a filter change keeps it
    /// condensed even if the shorter page clamps back to the bottom.
    ///
    /// The timeline is chronological and opens at the newest photo, so the
    /// scroll offset grows towards the past.
    private func updateChrome(offset: CGFloat) {
        let maxOffset = maxScrollOffset
        // Rubber-band travel beyond either end is not a scroll gesture.
        // Clamping it stops the spring from looking like a deliberate drag
        // toward older photos.
        let clamped = maxOffset > 1
            ? min(max(offset, 0), maxOffset)
            : max(offset, 0)
        let delta = clamped - lastScrollOffset
        lastScrollOffset = clamped
        scrollOffset = offset

        guard library.filters.isTimeline, !library.isAlbumOpen else {
            model.isTabBarCompact = true
            model.isHeaderFaded = false
            library.setTimelineTopDate(nil)
            if library.filters.layout != .all {
                hasScrolled = false
            }
            dockPinnedCompact = false
            return
        }

        // The header gets its material while the page scrolls under it.
        model.isHeaderFaded = clamped > 6

        let now = Date()
        let guarded = now < scrollGuardUntil || now < model.compactGuardUntil

        // The initial jump to the newest photo is not a gesture. Once the
        // guard has passed, any movement is a real scroll, including a
        // status-bar jump or a deep fling.
        if abs(delta) > 0.5, !guarded {
            hasScrolled = true
            // A real gesture releases the filter pin, so returning to the
            // newest photo expands the dock normally again.
            if abs(delta) > 6 {
                dockPinnedCompact = false
            }
        }

        let atNewest = maxOffset <= 24 || clamped >= maxOffset - 24
        if atNewest {
            if !dockPinnedCompact {
                model.isTabBarCompact = false
            }
        } else {
            model.isTabBarCompact = true
        }

        updateTimelineTopDate()

        // Silent paging: the grid knows the total item count, so it renders
        // a placeholder for every photo and asks for the next older page as
        // soon as the viewport reaches the boundary between the loaded page
        // and those placeholders. There is no visible footer.
        if usesTimelinePlaceholders {
            maybeLoadOlderPage()
        } else {
            if offset > 900 {
                olderRequestArmed = true
            }
            if library.olderState == .loading {
                // The response may take a moment; keep the anchor on whatever
                // the person is reading right now, like the web's capture at
                // render time rather than at request time.
                if let current = topVisibleTileID() {
                    pendingOlderAnchorID = current
                }
            } else if offset < 700,
                      olderRequestArmed,
                      !library.page.items.isEmpty,
                      library.page.hasMore,
                      !library.olderExhausted,
                      let anchor = topVisibleTileID() {
                olderRequestArmed = false
                pendingOlderAnchorID = anchor
                Task { await library.loadOlderIfNeeded() }
            }
        }
    }

    // MARK: - Timeline placeholders

    /// The total number of photos in the current timeline. The grid renders
    /// exactly this many cells, so the scrollable height is complete before
    /// every page has arrived and prepending older photos never moves the
    /// content under the finger.
    private var timelineTotal: Int {
        max(library.page.count, Int(clamping: library.page.total))
    }

    /// Placeholders only exist in the compact timeline grid; the regular
    /// adaptive grid keeps its incremental paging.
    private var usesTimelinePlaceholders: Bool {
        isCompact
            && !library.isAlbumOpen
            && library.filters.isTimeline
            && timelineTotal > library.page.count
    }

    /// The loaded page is newest first, while the grid is chronological with
    /// the newest photo at the bottom. Index 0 is the oldest photo.
    private func timelineItem(at index: Int) -> Item? {
        let apiIndex = timelineTotal - 1 - index
        guard apiIndex >= 0, apiIndex < library.page.items.count else {
            return nil
        }
        return library.page.items[apiIndex]
    }

    /// Ask for the page above the loaded one once the viewport gets within a
    /// few rows of the boundary. The same check runs after a page arrives and
    /// on every auto-scroll tick, so a fast fling or a marquee drag fills
    /// every placeholder it jumped over.
    ///
    /// The trigger uses both the offset maths and the realized tile frames.
    /// Frames are the safer of the two once the lazy grid has measured the
    /// visible photos; the offset is the fallback when the viewport sits on
    /// placeholders whose cells have no frame of their own.
    private func maybeLoadOlderPage() {
        guard !initialAnchorPending,
              library.filters.isTimeline,
              !library.isAlbumOpen,
              !library.page.items.isEmpty,
              library.page.hasMore,
              !library.olderExhausted,
              library.olderState != .loading
        else { return }

        guard timelineTotal > library.page.count else { return }

        if !olderRequestArmed {
            // A failed request used to wait for the person to walk all the
            // way back to the newest photos. Once the retry window passes,
            // arm again while the viewport is still near the boundary.
            guard Date() >= olderRetryAt else { return }
            olderRequestArmed = true
        }

        let boundary = timelineLoadedBoundary
        let byOffset = timelineFirstVisibleIndex()
        let byFrames = oldestVisibleTimelineIndex()
        let reach = min(byOffset ?? Int.max, byFrames ?? Int.max)
        guard reach != Int.max else { return }

        // Four extra rows give the network request enough lead time that a
        // stopped drag never shows an empty tile at the top of the screen.
        guard reach <= boundary + 12 else { return }

        olderRequestArmed = false
        olderRetryAt = Date().addingTimeInterval(1.6)
        Task { await library.loadOlderIfNeeded() }
    }

    /// The oldest loaded row in the full-length grid. Everything above it is
    /// still a placeholder.
    private var timelineLoadedBoundary: Int {
        max(0, timelineTotal - library.page.count)
    }

    private var timelineColumnsCount: Int { 3 }

    /// The height of one square row including the gap below it.
    private var timelineRowHeight: CGFloat {
        let gap = Tokens.Layout.gridGap
        guard viewportWidth > 1 else { return 1 }
        let itemWidth = (viewportWidth - gap * CGFloat(timelineColumnsCount - 1))
            / CGFloat(timelineColumnsCount)
        return max(1, itemWidth + gap)
    }

    /// The chronological index of the first row under the viewport top.
    private func timelineFirstVisibleIndex() -> Int? {
        guard viewportWidth > 1 else { return nil }
        let rowHeight = timelineRowHeight
        return Int(max(0, scrollOffset) / rowHeight) * timelineColumnsCount
    }

    /// The oldest chronological index among the realized tiles that are on
    /// screen. This is more accurate than the offset once the grid has
    /// measured the rows, and it keeps paging alive while the person drags a
    /// selection at the edge without moving the finger.
    private func oldestVisibleTimelineIndex() -> Int? {
        guard !tileFrames.isEmpty, viewportGlobalMaxY > 0 else { return nil }
        let headerBottom = model.headerBottom > 0 ? model.headerBottom : 0
        let viewportBottom = viewportGlobalMaxY
        let total = timelineTotal
        var apiIndices: [Int64: Int] = [:]
        for (index, item) in library.page.items.enumerated() {
            apiIndices[item.id] = index
        }
        var oldest: Int?
        for (id, frame) in tileFrames
        where knownItemIDs.contains(id)
            && frame.maxY > headerBottom + 1
            && frame.minY < viewportBottom {
            guard let apiIndex = apiIndices[id] else { continue }
            let index = total - 1 - apiIndex
            if oldest == nil || index < oldest! {
                oldest = index
            }
        }
        return oldest
    }

    /// How far above the loaded boundary the grid may be dragged while the
    /// older pages are still arriving. Six rows is about two screens of
    /// shimmer; any deeper fling is stopped here so the view can never sit on
    /// a placeholder that the sequential pager would need dozens of requests
    /// to reach.
    private var timelineOldestAllowedOffset: CGFloat? {
        guard usesTimelinePlaceholders,
              !initialAnchorPending,
              viewportWidth > 1
        else { return nil }
        let rowHeight = timelineRowHeight
        let boundaryRow = CGFloat(timelineLoadedBoundary / timelineColumnsCount)
        return max(0, boundaryRow * rowHeight - rowHeight * 6)
    }

    /// Move the underlying scroll view to a normalized offset (0 at the top
    /// of the content, `maxScrollOffset` at the newest photo).
    private func applyScrollOffset(_ normalized: CGFloat) {
        guard !isApplyingScroll, let scrollView = hostScrollView else { return }
        isApplyingScroll = true
        defer { isApplyingScroll = false }

        let top = scrollView.adjustedContentInset.top
        let bottom = scrollView.adjustedContentInset.bottom
        let minY = -top
        let maxY = max(
            minY,
            scrollView.contentSize.height + bottom - scrollView.bounds.height
        )
        let target = min(max(normalized - top, minY), maxY)
        guard abs(target - scrollView.contentOffset.y) > 0.01 else {
            scrollOffset = normalized
            lastScrollOffset = normalized
            return
        }
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: target),
            animated: false
        )
        scrollOffset = max(0, normalized)
        lastScrollOffset = scrollOffset
    }

    /// The offset that puts the last row of a years/months grid at the
    /// bottom of the viewport, so the newest card is the one you start on.
    private func positionBucketsAtLatest() {
        // The card layouts keep the dock condensed, like the filter choice
        // that opened them: the switcher stays in the dock's centre slot.
        model.isTabBarCompact = true
        // The cards open at the newest month/year, which is not a scroll.
        hasScrolled = false
        library.setTimelineTopDate(nil)
        Task { @MainActor in
            await Task.yield()
            scrollToTimelineBottom()
            try? await Task.sleep(nanoseconds: 120_000_000)
            scrollToTimelineBottom()
        }
    }

    private func scrollToTimelineBottom() {
        guard let scrollView = hostScrollView else { return }
        let top = scrollView.adjustedContentInset.top
        let bottom = scrollView.adjustedContentInset.bottom
        let maxY = max(
            -top,
            scrollView.contentSize.height + bottom - scrollView.bounds.height
        )
        guard abs(maxY - scrollView.contentOffset.y) > 0.5 else { return }
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: maxY),
            animated: false
        )
        scrollOffset = maxY + top
        lastScrollOffset = scrollOffset
    }

    /// The photo under the header when a filter starts changing. Captured
    /// before the model replaces the page, because after that the old tile
    /// ids no longer exist.
    private func captureFilterAnchor() {
        // A filter or grouping switch never opens the dock, even when the new
        // page is shorter and clamps to the bottom.
        dockPinnedCompact = true

        // The card grids (and any change between them and the timeline) open
        // at their newest item, which is the bottom. A nil anchor tells the
        // restore to do that after the new page arrives.
        guard library.filters.isTimeline, !library.isAlbumOpen else {
            pendingFilterAnchor = FilterAnchor(
                id: nil,
                takenAt: nil,
                screenY: 0
            )
            return
        }

        // The regular adaptive grid has a different row geometry and keeps
        // its own incremental paging; leave its offset alone across a kind
        // filter instead of applying the compact 3-column math.
        guard isCompact else {
            pendingFilterAnchor = nil
            return
        }

        guard let id = topVisibleTileID(),
              let frame = tileFrames[id],
              let item = library.page.item(id: id)
        else {
            pendingFilterAnchor = FilterAnchor(
                id: nil,
                takenAt: nil,
                screenY: 0
            )
            return
        }
        pendingFilterAnchor = FilterAnchor(
            id: id,
            takenAt: item.takenAt,
            screenY: frame.minY
        )
    }

    /// Put the captured photo back under the header after the new page has
    /// arrived. If the filter removed that photo, the nearest date in the new
    /// page is used; if the new page is shorter, the scroll clamps to its own
    /// bottom instead of jumping to a stale pixel offset.
    private func restoreFilterAnchor(_ anchor: FilterAnchor) {
        // The timeline is still empty (error or a very sparse filter):
        // keep the top, nothing to anchor to.
        if library.filters.isTimeline,
           !library.isAlbumOpen,
           library.page.items.isEmpty,
           library.page.total == 0 {
            return
        }

        Task { @MainActor in
            await Task.yield()
            applyFilterAnchor(anchor)
            // The lazy grid may not have realized the target row on the
            // first pass. One more attempt after layout is cheap and makes
            // the restore reliable on a cold, long timeline.
            try? await Task.sleep(nanoseconds: 140_000_000)
            applyFilterAnchor(anchor, final: true)
        }
    }

    private func applyFilterAnchor(_ anchor: FilterAnchor, final: Bool = false) {
        guard let scrollView = hostScrollView, scrollView.window != nil else { return }

        let top = scrollView.adjustedContentInset.top
        let bottom = scrollView.adjustedContentInset.bottom
        let minY = -top
        let maxY = max(
            minY,
            scrollView.contentSize.height + bottom - scrollView.bounds.height
        )
        let maxNormalized = maxY + top

        // Years and months are chronological cards too: the newest card is
        // at the bottom. A timeline that lost its anchor falls back there.
        var normalized: CGFloat = maxNormalized
        var anchored = false
        if library.filters.isTimeline,
           !library.isAlbumOpen,
           let index = filterAnchorIndex(anchor) {
            // `screenY` includes the space under the header. The normalized
            // offset is measured from the content top that already sits below
            // the header, so the inset has to be part of the viewport top or
            // the restored photo lands a header-height too low.
            let viewportTop = viewportGlobalMaxY > 0 && viewportHeight > 0
                ? viewportGlobalMaxY - viewportHeight + top
                : max(model.headerBottom, top)
            let screenY = anchor.screenY > 0
                ? anchor.screenY
                : model.headerBottom + 6
            normalized = CGFloat(index / timelineColumnsCount) * timelineRowHeight
                - (screenY - viewportTop)
            anchored = true
        }
        // A jump to the newest photo is not a scroll gesture: the header
        // returns to the item count until the person actually scrolls.
        if !anchored {
            hasScrolled = false
        }

        let floor = timelineOldestAllowedOffset ?? 0
        normalized = min(max(normalized, floor), maxNormalized)
        let contentY = normalized - top
        guard abs(contentY - scrollView.contentOffset.y) > 0.5 else {
            if !final {
                scrollOffset = normalized
                lastScrollOffset = normalized
            }
            return
        }
        // The second pass only corrects a measurable miss from the first.
        if final, abs(contentY - scrollView.contentOffset.y) < 6 { return }

        isApplyingScroll = true
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: contentY),
            animated: false
        )
        isApplyingScroll = false
        scrollOffset = max(0, normalized)
        lastScrollOffset = scrollOffset
        scrollGuardUntil = Date().addingTimeInterval(0.5)
    }

    /// The chronological row of the loaded photo nearest the captured date.
    /// When the captured time is older than the first page, the oldest loaded
    /// photo is returned; the pager then fills the rest as the person scrolls.
    private func filterAnchorIndex(_ anchor: FilterAnchor) -> Int? {
        let items = library.page.items
        guard !items.isEmpty, timelineTotal > 0 else { return nil }
        let total = timelineTotal
        let boundary = timelineLoadedBoundary

        if let id = anchor.id,
           let apiIndex = items.firstIndex(where: { $0.id == id }) {
            return max(boundary, total - 1 - apiIndex)
        }
        guard let takenAt = anchor.takenAt, takenAt > 0 else { return nil }

        var bestIndex: Int?
        var bestDistance = Int64.max
        for (apiIndex, item) in items.enumerated() where item.takenAt > 0 {
            let distance = abs(item.takenAt - takenAt)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = max(boundary, total - 1 - apiIndex)
            }
        }
        return bestIndex
    }

    /// The header shows the date of the photo at the top of the grid while the
    /// library is scrolled, and the item count otherwise.
    ///
    /// The web picks the first tile in DOM order whose bottom edge clears the
    /// sticky header. The grid is chronological, so that is the oldest photo
    /// on screen.
    private func updateTimelineTopDate() {
        guard library.filters.isTimeline,
              !library.isAlbumOpen,
              hasScrolled,
              scrollOffset > 6
        else {
            library.setTimelineTopDate(nil)
            return
        }
        guard let top = topVisibleTileID() else {
            library.setTimelineTopDate(nil)
            return
        }
        library.setTimelineTopDate(library.timelineDate(for: top))
    }

    /// The first tile, in grid order, whose bottom edge clears the header.
    /// The grid is chronological, so this is the oldest photo on screen.
    private func topVisibleTileID() -> Int64? {
        let headerBottom = model.headerBottom > 0 ? model.headerBottom : 120
        let viewportBottom = viewportGlobalMaxY > 0
            ? viewportGlobalMaxY
            : CGFloat.greatestFiniteMagnitude
        let visible = tileFrames.filter {
            knownItemIDs.contains($0.key)
                && $0.value.width > 1
                && $0.value.height > 1
        }
        let below = visible.filter {
            $0.value.maxY > headerBottom + 2 && $0.value.minY < viewportBottom
        }
        return below.min(by: { lhs, rhs in
            let dy = lhs.value.maxY - rhs.value.maxY
            if abs(dy) > 0.5 { return dy < 0 }
            return lhs.value.minX < rhs.value.minX
        })?.key
    }

    // MARK: - Body states

    @ViewBuilder
    private var bodyContent: some View {
        switch library.loadState {
        case .idle where isEmpty, .loading where isEmpty:
            SkeletonGrid(columns: timelineColumns)
        case .failed(let message) where isEmpty:
            LibraryEmptyState(
                icon: "exclamationmark.triangle",
                title: Strings.errorTitle,
                message: message,
                actionTitle: Strings.retry
            ) {
                Task { await library.retry() }
            }
        case _ where isEmpty:
            emptyState
        default:
            switch library.filters.layout {
            case .all:
                timeline
            case .years:
                yearsGrid
            case .months:
                monthsGrid
            }
        }
    }

    private var isEmpty: Bool {
        switch library.filters.layout {
        case .all: library.page.items.isEmpty
        case .years: library.years.isEmpty
        case .months: library.months.isEmpty
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch library.filters.layout {
        case .all:
            if library.isAlbumOpen {
                LibraryEmptyState(
                    icon: "photo.on.rectangle.angled",
                    title: Strings.albumEmptyTitle,
                    message: Strings.emptyItemsBody
                )
            } else if library.filters.summary != nil {
                LibraryEmptyState(
                    icon: "line.3.horizontal.decrease.circle",
                    title: Strings.emptyFilteredTitle,
                    message: Strings.emptyFilteredBody,
                    actionTitle: Strings.clearFilters
                ) {
                    Task { await library.clearFilters() }
                }
            } else {
                LibraryEmptyState(
                    icon: "photo.on.rectangle.angled",
                    title: Strings.emptyItemsTitle,
                    message: Strings.emptyItemsBody
                )
            }
        case .years:
            LibraryEmptyState(
                icon: "photo.on.rectangle.angled",
                title: Strings.emptyYearsTitle,
                message: Strings.emptyYearsBody
            )
        case .months:
            LibraryEmptyState(
                icon: "calendar",
                title: Strings.emptyMonthsTitle,
                message: Strings.emptyMonthsBody
            )
        }
    }

    // MARK: - Timeline

    /// One continuous grid: the month labels are gone, so the photos flow
    /// into each other and every row keeps the same height.
    ///
    /// The rows are chronological, so the newest photo is the last one and
    /// sits at the bottom of the screen. The scroll view opens there.
    ///
    /// The item count is known before the pages are, so the grid renders the
    /// full timeline up front: loaded photos for the tail of the list and
    /// placeholders for the oldest pages. This keeps the content height (and
    /// therefore the scroll position and the scrollbar) stable while older
    /// pages arrive, which is what the web gets by prepending and re-anchoring.
    private var timeline: some View {
        LazyVGrid(columns: timelineColumns, spacing: timelineGap) {
            if isCompact, !library.isAlbumOpen {
                ForEach(0..<timelineTotal, id: \.self) { index in
                    if let item = timelineItem(at: index) {
                        timelineTile(item)
                    } else {
                        ShimmerTile()
                            .aspectRatio(1, contentMode: .fill)
                            .accessibilityHidden(true)
                    }
                }
            } else {
                ForEach(library.page.items.reversed()) { item in
                    timelineTile(item)
                }
            }
        }
    }

    private func timelineTile(_ item: Item) -> some View {
        TileView(
            model: model,
            item: item,
            isTapSuppressed: { Date() < suppressTileTapUntil }
        )
        .id(item.id)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TimelineTileFramesKey.self,
                    value: TimelineTileFrames(frames: [
                        item.id: proxy.frame(in: .global)
                    ])
                )
            }
        }
    }

    /// Starts a marquee at `point` (window coordinates). The additive mode is
    /// taken from the tile under the finger, exactly like the web's snapshot
    /// at drag start.
    private func beginMarquee(at point: CGPoint) {
        guard library.selectionMode else { return }
        let hit = tileFrames.first {
            knownItemIDs.contains($0.key) && $0.value.contains(point)
        }?.key
        let additive = hit.map { !library.selection.contains($0) } ?? true
        let base = library.selection
        marquee = MarqueeState(
            base: base,
            additive: additive,
            start: point,
            moved: false,
            result: base
        )
    }

    /// Every tile whose rectangle intersects the drag path is added to (or
    /// removed from) the set. The result accumulates across the whole drag:
    /// the edge auto-scroll keeps moving new tiles under the finger, and
    /// recomputing from the current rectangle alone would drop every photo
    /// that has already scrolled off screen.
    private func updateMarquee(to point: CGPoint) {
        guard var state = marquee else { return }
        let rect = CGRect(
            x: min(state.start.x, point.x),
            y: min(state.start.y, point.y),
            width: abs(point.x - state.start.x),
            height: abs(point.y - state.start.y)
        )
        if !state.moved, rect.width > 4 || rect.height > 4 {
            state.moved = true
            // Stamp the guard once: writing a fresh date on every frame
            // would re-render the whole grid during the drag.
            suppressTileTapUntil = Date().addingTimeInterval(0.6)
        }

        var hits: Set<Int64> = []
        for (id, frame) in tileFrames
        where knownItemIDs.contains(id) && frame.intersects(rect) {
            hits.insert(id)
        }

        if state.additive {
            state.result.formUnion(hits)
        } else {
            state.result.subtract(hits)
        }
        library.replaceSelection(state.result)
        // Persist the accumulated set and the moved flag even when the
        // finger has not moved: the display link calls this at the edge.
        marquee = state

        // The edge auto-scroll moves the grid without the pan recognizer
        // receiving a new location, so paging has to be checked here too.
        if isCompact {
            maybeLoadOlderPage()
        }
    }

    private func endMarquee() {
        if let state = marquee, state.moved {
            suppressTileTapUntil = Date().addingTimeInterval(0.45)
        }
        marquee = nil
    }

    private var timelineColumns: [GridItem] {
        if isCompact {
            return Array(
                repeating: GridItem(.flexible(), spacing: Tokens.Layout.gridGap),
                count: 3
            )
        }
        return [GridItem(.adaptive(minimum: 150), spacing: 3)]
    }

    private var timelineGap: CGFloat {
        isCompact ? Tokens.Layout.gridGap : 3
    }

    // MARK: - Buckets

    private var yearsGrid: some View {
        LazyVGrid(columns: bucketColumns, spacing: bucketGap) {
            ForEach(library.years) { bucket in
                BucketCard(
                    title: "\(bucket.year)",
                    count: bucket.count,
                    covers: bucket.covers,
                    client: model.client
                ) {
                    Task { await library.open(year: bucket.year) }
                }
            }
        }
        .padding(.horizontal, isCompact ? 16 : 0)
    }

    private var monthsGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            if library.filters.year != nil {
                Button {
                    Task { await library.showAllYears() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(Font.mng(11, weight: .semibold))
                        Text(Strings.allYears)
                            .font(Font.mng(13, weight: .semibold))
                    }
                    .foregroundStyle(Palette.text2)
                    .padding(.horizontal, 13)
                    .frame(height: 32)
                    .background(Palette.fill, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, isCompact ? 16 : 0)
            }

            LazyVGrid(columns: bucketColumns, spacing: bucketGap) {
                ForEach(library.months) { bucket in
                    BucketCard(
                        title: bucket.label.isEmpty
                            ? MNGFormat.monthLabel(year: bucket.year, month: bucket.month)
                            : bucket.label,
                        count: bucket.count,
                        covers: bucket.covers,
                        client: model.client
                    ) {
                        Task { await library.open(year: bucket.year, month: bucket.month) }
                    }
                }
            }
            .padding(.horizontal, isCompact ? 16 : 0)
        }
    }

    private var bucketColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 260), spacing: bucketGap)]
    }

    private var bucketGap: CGFloat {
        isCompact ? 18 : 22
    }
}

// MARK: - Toolbar

private struct LibraryToolbar: View {
    let model: ShellModel
    /// Opens the photo picker for "save into the library".
    var onBackup: () -> Void = {}

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var library: LibraryModel { model.library }
    /// The compact layout keeps the multi-select button in the header, so the
    /// toolbar only carries it on the wide layout.
    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 12) {
                layoutSegment

                Spacer(minLength: 8)

                if !isCompact, library.canSelect, !library.selectionMode {
                    Button {
                        library.enterSelection()
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .font(Font.mng(15, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                            .frame(width: 32, height: 32)
                            .background(Palette.fill, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Strings.select)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(ItemKindFilter.allCases, id: \.self) { kind in
                        kindChip(kind)
                    }

                    // The upload is an icon chip in the filter row, the same
                    // place the native shell keeps it.
                    Button(action: onBackup) {
                        Image(systemName: "square.and.arrow.up")
                            .font(Font.mng(12, weight: .semibold))
                            .foregroundStyle(Palette.text2)
                            .frame(width: 32, height: 32)
                            .background(Palette.fill, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Strings.backupToLibrary)

                    if let summary = library.filters.summary {
                        Button {
                            Task { await library.clearFilters() }
                        } label: {
                            HStack(spacing: 5) {
                                Text(summary)
                                Image(systemName: "xmark")
                                    .font(Font.mng(9, weight: .bold))
                            }
                            .font(Font.mng(13, weight: .semibold))
                            .foregroundStyle(Palette.bg)
                            .padding(.horizontal, 13)
                            .frame(height: 32)
                            .background(Palette.text, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Strings.clearFilters)
                    }
                }
            }
        }
    }

    private var layoutSegment: some View {
        HStack(spacing: 2) {
            ForEach(LibraryLayout.allCases, id: \.self) { layout in
                Button {
                    Task { await library.selectLayout(layout) }
                } label: {
                    Text(layoutLabel(layout))
                        .font(Font.mng(13, weight: .semibold))
                        .foregroundStyle(
                            library.filters.layout == layout ? Palette.text : Palette.text2
                        )
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background {
                            if library.filters.layout == layout {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Palette.bgElevated)
                                    .shadow(color: .black.opacity(0.13), radius: 3, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(layoutLabel(layout))
                .accessibilityAddTraits(
                    library.filters.layout == layout ? .isSelected : []
                )
            }
        }
        .padding(2)
        .background(Palette.fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Strings.layoutLabel)
    }

    private func kindChip(_ kind: ItemKindFilter) -> some View {
        let active = library.filters.kind == kind
        return Button {
            Task { await library.selectKind(kind) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: kindIcon(kind))
                    .font(Font.mng(12, weight: .semibold))
                Text(kindLabel(kind))
                    .font(Font.mng(13, weight: .semibold))
            }
            .foregroundStyle(active ? Palette.bg : Palette.text2)
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background(active ? Palette.text : Palette.fill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func layoutLabel(_ layout: LibraryLayout) -> String {
        switch layout {
        case .years: Strings.layoutYears
        case .months: Strings.layoutMonths
        case .all: Strings.layoutAll
        }
    }

    private func kindLabel(_ kind: ItemKindFilter) -> String {
        switch kind {
        case .all: Strings.filterAll
        case .photo: Strings.filterPhotos
        case .video: Strings.filterVideos
        case .live: Strings.filterLive
        }
    }

    private func kindIcon(_ kind: ItemKindFilter) -> String {
        switch kind {
        case .all: "square.grid.2x2"
        case .photo: "photo"
        case .video: "video"
        case .live: "livephoto"
        }
    }
}

// MARK: - Sections and states

private struct LibraryEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(Font.mng(34, weight: .regular))
                .foregroundStyle(Palette.text4)

            Text(title)
                .font(Font.mng(18, weight: .semibold))
                .foregroundStyle(Palette.text2)

            Text(message)
                .font(Font.mng(13))
                .foregroundStyle(Palette.text3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(Font.mng(14, weight: .semibold))
                    .foregroundStyle(Palette.accentInk)
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background(Palette.accent, in: Capsule())
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 70)
    }
}

private struct SkeletonGrid: View {
    let columns: [GridItem]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(0..<48, id: \.self) { _ in
                ShimmerTile()
                    .aspectRatio(1, contentMode: .fill)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Scroll tracking

/// The coordinate space the library grid is measured in.
enum TimelineSpace {
    static let name = "mng.library.timeline"
}

/// The real end of the scroll content, including the gap the dock floats
/// over. Scrolling to this anchor opens the timeline at the newest photo.
enum TimelineAnchor {
    static let bottom = "mng.library.timeline.bottom"
}

/// One snapshot of the scroll view. Equatable so the iOS 18 observer only
/// calls back when the offset, the content size or the viewport changes.
struct TimelineScrollMetrics: Equatable {
    var offset: CGFloat
    var maxOffset: CGFloat
    var contentHeight: CGFloat
    var viewportHeight: CGFloat
}

/// The state of a selection drag. The band is invisible, but the base set and
/// the direction (add or remove) are captured once per gesture.
private struct MarqueeState {
    var base: Set<Int64>
    var additive: Bool
    var start: CGPoint
    var moved: Bool
    var result: Set<Int64>
}

/// The photo that was under the header when a filter or grouping change
/// started, plus where it sat on screen. `takenAt` is nil when the change did
/// not start from a photo (for example the years grid).
private struct FilterAnchor {
    var id: Int64?
    var takenAt: Int64?
    var screenY: CGFloat
}

/// Scroll offset of the library grid, measured from the top of the scroll
/// view.
private struct TimelineScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Frame of the scroll view in screen coordinates.
private struct TimelineViewportKey: PreferenceKey {
    static let defaultValue = CGRect.zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// Full height of the scrollable content, used to find the bottom of the
/// timeline without waiting for the person to scroll there.
private struct TimelineContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Frames of the realized timeline tiles.
private struct TimelineTileFrames: Equatable {
    var frames: [Int64: CGRect] = [:]
}

private struct TimelineTileFramesKey: PreferenceKey {
    static let defaultValue = TimelineTileFrames()

    static func reduce(value: inout TimelineTileFrames, nextValue: () -> TimelineTileFrames) {
        value.frames.merge(nextValue().frames) { _, new in new }
    }
}
