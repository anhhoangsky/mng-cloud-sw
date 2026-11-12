import MNGKit
import SwiftUI

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
    /// The accumulated drag, so the dock condenses after a deliberate
    /// 26 pt move toward older photos, like the web's `scroll_accum`.
    @State private var scrollAccum: CGFloat = 0
    /// Height of the scrollable content, for the iOS 17 fallback metrics.
    @State private var contentHeight: CGFloat = 0
    /// Height of the scroll viewport, for the iOS 17 fallback metrics.
    @State private var viewportHeight: CGFloat = 0
    /// The largest possible scroll offset, so "at the newest photo" is a
    /// real measurement instead of a guess.
    @State private var maxScrollOffset: CGFloat = 0
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
    /// A vertical drag must keep scrolling; once a gesture is classified as a
    /// scroll it stays a scroll until the finger lifts.
    @State private var marqueeRejected = false
    /// Where the rejected drag started, so a cancelled gesture cannot keep
    /// the marquee disabled for the next one.
    @State private var marqueeRejectedStart: CGPoint?
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
                                    value: -proxy.frame(in: .named(TimelineSpace.name)).minY
                                )
                            }
                            .frame(height: 0)

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
                    scrollGuardUntil = Date().addingTimeInterval(0.35)
                    scrollAccum = 0
                    lastScrollOffset = scrollOffset
                    pendingOlderAnchorID = nil
                    olderRequestArmed = true
                    knownItemIDs = Set(library.page.items.map(\.id))
                }
                .onChange(of: library.page.count) { old, new in
                    knownItemIDs = Set(library.page.items.map(\.id))

                    // The first page replaces the skeleton after the initial
                    // layout. SwiftUI's default anchor cannot follow that
                    // replacement, so jump to the newest photo once the grid
                    // has been laid out.
                    if old == 0, new > 0, library.filters.isTimeline {
                        positionTimelineAtLatest(scrollProxy)
                    }

                    // An older page is inserted above the viewport. Keep the
                    // photo the person was reading where it was, like the
                    // web's `anchor_y + delta` restore after a page prepend.
                    guard new > old, let anchor = pendingOlderAnchorID else {
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
                    positionTimelineAtLatest(scrollProxy)
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
            if abs(rect.height - viewportHeight) > 0.5 {
                viewportHeight = rect.height
                if !usesNativeScrollGeometry {
                    refreshFallbackMaxOffset()
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
        .onChange(of: model.headerBottom) { _, _ in
            updateTimelineTopDate()
        }
        .onChange(of: library.filters) { _, filters in
            // A filter keeps the grid at the same offset until the new page
            // arrives, exactly like the web's `keep_scroll` reload.
            scrollAccum = 0
            lastScrollOffset = scrollOffset
            pendingOlderAnchorID = nil
            olderRequestArmed = true
            model.isFilterMenuOpen = false
            if !filters.isTimeline {
                model.isTabBarCompact = false
                library.setTimelineTopDate(nil)
            }
        }
        .onChange(of: model.isUploadRequested) { _, requested in
            guard requested else { return }
            model.isUploadRequested = false
            backupPickerOpen = true
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
            content.onPreferenceChange(TimelineScrollOffsetKey.self) { offset in
                handleScroll(offset: offset)
            }
        }
    }

    private var usesNativeScrollGeometry: Bool {
        if #available(iOS 18.0, *) { return true }
        return false
    }

    private func refreshFallbackMaxOffset() {
        let next = max(0, contentHeight - viewportHeight)
        guard abs(next - maxScrollOffset) > 0.5 else { return }
        maxScrollOffset = next
        handleScroll(offset: scrollOffset)
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
        scrollOffset = offset

        if initialAnchorPending {
            lastScrollOffset = offset
            scrollAccum = 0
            model.isTabBarCompact = false
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

        updateChrome(offset: offset)
    }

    /// The dock condenses after a deliberate drag toward older photos and
    /// expands at either end of the timeline or when the person scrolls back
    /// toward the present, mirroring the web's scroll accumulator.
    ///
    /// The timeline is chronological and opens at the newest photo, so the
    /// scroll offset grows towards the past.
    private func updateChrome(offset: CGFloat) {
        let delta = offset - lastScrollOffset
        lastScrollOffset = offset
        scrollOffset = offset
        let maxOffset = maxScrollOffset

        guard library.filters.isTimeline, !library.isAlbumOpen else {
            scrollAccum = 0
            model.isTabBarCompact = false
            model.isHeaderFaded = false
            library.setTimelineTopDate(nil)
            return
        }

        // The header gets its material while the page scrolls under it.
        model.isHeaderFaded = offset > 6

        // The initial jump to the newest photo is not a gesture. Any smaller
        // movement afterwards is a real scroll and starts the date readout.
        if abs(delta) > 0.5,
           abs(delta) < 320,
           Date() >= scrollGuardUntil,
           Date() >= model.compactGuardUntil {
            hasScrolled = true
        }

        if abs(delta) > 0.5 {
            model.isFilterMenuOpen = false
        }

        if offset <= 40 {
            // Back at the oldest loaded photo: show the full dock again.
            scrollAccum = 0
            model.isTabBarCompact = false
        } else if Date() < scrollGuardUntil || Date() < model.compactGuardUntil {
            // A page was just replaced, an older page was anchored, or the
            // dock was just expanded from its handle. Ignore the offset jump;
            // a clamp to a shorter page still lands at the new bottom.
            scrollAccum = 0
            if maxOffset > 24, offset >= maxOffset - 24 {
                model.isTabBarCompact = false
            }
        } else if maxOffset > 24, offset >= maxOffset - 24 {
            // The newest photo is in view.
            scrollAccum = 0
            model.isTabBarCompact = false
        } else {
            let sameDirection = (delta >= 0 && scrollAccum >= 0)
                || (delta < 0 && scrollAccum < 0)
            if sameDirection {
                scrollAccum += delta
            } else {
                scrollAccum = delta
            }
            if scrollAccum > 26 {
                scrollAccum = 0
                model.isTabBarCompact = false
            } else if scrollAccum < -26 {
                scrollAccum = 0
                model.isTabBarCompact = true
            }
        }

        updateTimelineTopDate()

        // Silent paging: the web asks for the page above when it gets near
        // the top of the loaded timeline. There is no visible footer.
        if offset > 900 {
            olderRequestArmed = true
        }
        if library.olderState == .loading {
            // The response may take a moment; keep the anchor on whatever the
            // person is reading right now, like the web's capture at render
            // time rather than at request time.
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
    private var timeline: some View {
        LazyVGrid(columns: timelineColumns, spacing: timelineGap) {
            ForEach(library.page.items.reversed()) { item in
                TileView(
                    model: model,
                    item: item,
                    isTapSuppressed: { Date() < suppressTileTapUntil }
                )
                .id(item.id)
                .simultaneousGesture(
                    marqueeGesture(for: item),
                    including: library.selectionMode ? .all : .none
                )
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
        }
    }

    /// Horizontal drag in selection mode. It never paints a band: every tile
    /// whose rectangle intersects the path is added to (or removed from) the
    /// selection snapshot taken when the drag started, exactly like the web's
    /// marquee.
    private func marqueeGesture(for item: Item) -> some Gesture {
        DragGesture(minimumDistance: 7, coordinateSpace: .global)
            .onChanged { value in
                guard library.selectionMode else { return }

                if marquee == nil {
                    if marqueeRejected {
                        // A cancelled drag must not lock the marquee forever:
                        // a new start location means a new gesture.
                        if let last = marqueeRejectedStart {
                            let dx = value.startLocation.x - last.x
                            let dy = value.startLocation.y - last.y
                            if dx * dx + dy * dy > 16 {
                                marqueeRejected = false
                                marqueeRejectedStart = nil
                            } else {
                                return
                            }
                        } else {
                            return
                        }
                    }
                    guard !marqueeRejected else { return }
                    let dx = value.translation.width
                    let dy = value.translation.height
                    if abs(dx) > abs(dy) {
                        marquee = MarqueeState(
                            base: library.selection,
                            additive: !library.selection.contains(item.id),
                            start: value.startLocation,
                            moved: false
                        )
                    } else if abs(dy) > 7 {
                        // A vertical drag belongs to the scroll view.
                        marqueeRejected = true
                        marqueeRejectedStart = value.startLocation
                    }
                    guard marquee != nil else { return }
                }

                guard var state = marquee else { return }
                let current = value.location
                let rect = CGRect(
                    x: min(state.start.x, current.x),
                    y: min(state.start.y, current.y),
                    width: abs(current.x - state.start.x),
                    height: abs(current.y - state.start.y)
                )
                if !state.moved, rect.width > 4 || rect.height > 4 {
                    state.moved = true
                    // Stamp the guard once: writing a fresh date on every
                    // frame would re-render the whole grid during the drag.
                    suppressTileTapUntil = Date().addingTimeInterval(0.6)
                }

                var hits: Set<Int64> = []
                for (id, frame) in tileFrames
                where knownItemIDs.contains(id) && frame.intersects(rect) {
                    hits.insert(id)
                }

                var next = state.base
                if state.additive {
                    next.formUnion(hits)
                } else {
                    next.subtract(hits)
                }
                library.replaceSelection(next)
                marquee = state
            }
            .onEnded { _ in
                if let state = marquee, state.moved {
                    suppressTileTapUntil = Date().addingTimeInterval(0.45)
                }
                marquee = nil
                marqueeRejected = false
                marqueeRejectedStart = nil
            }
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
