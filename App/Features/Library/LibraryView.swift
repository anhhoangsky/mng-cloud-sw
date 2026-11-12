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
    /// Frames of the realized timeline tiles, in the library scroll space.
    @State private var tileFrames: [Int64: CGRect] = [:]
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

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Scroll probe. It sits directly above the content, so its
                    // frame in the named space is exactly the negated offset.
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TimelineScrollOffsetKey.self,
                            value: -proxy.frame(in: .named(TimelineSpace.name)).minY
                        )
                    }
                    .frame(height: 0)

                    bodyContent

                    if library.loadState == .ready, !library.isAlbumOpen {
                        olderFooter
                    }
                }
                .padding(.horizontal, isCompact ? 0 : 32)
                .padding(.top, isCompact ? 0 : 26)
                .padding(.bottom, isCompact ? 12 : 60)
                .frame(maxWidth: Tokens.Layout.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            // The timeline is chronological, so its last row is the newest
            // photo. The scroll view opens there and walks back in time as
            // the person scrolls up.
            .defaultScrollAnchor(library.filters.isTimeline ? .bottom : .top)
            .coordinateSpace(name: TimelineSpace.name)
            .refreshable {
                await library.reload()
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
        .onPreferenceChange(TimelineScrollOffsetKey.self) { offset in
            updateTabBarState(offset: offset)
            scrollOffset = offset
            updateTimelineTopDate()
        }
        .onPreferenceChange(TimelineTileFramesKey.self) { frames in
            tileFrames = frames.frames
            updateTimelineTopDate()
        }
        .onChange(of: model.isUploadRequested) { _, requested in
            guard requested else { return }
            model.isUploadRequested = false
            backupPickerOpen = true
        }
    }

    /// The bottom bar collapses into a pill while the person walks back in
    /// time and expands again when they come back to the present.
    ///
    /// The timeline is chronological and opens at the newest photo, so the
    /// scroll offset grows towards the past.
    private func updateTabBarState(offset: CGFloat) {
        guard library.filters.isTimeline, !library.isAlbumOpen else {
            model.isTabBarCompact = false
            model.isHeaderFaded = false
            return
        }
        let delta = offset - scrollOffset
        if delta < -12 {
            model.isTabBarCompact = true
        } else if delta > 12 {
            model.isTabBarCompact = false
        }
        // The header gets its material while the photos scroll under it.
        model.isHeaderFaded = offset > 6
    }

    /// The header shows the date of the photo at the top of the grid while the
    /// library is scrolled, and the item count otherwise.
    private func updateTimelineTopDate() {
        guard library.filters.isTimeline, !library.isAlbumOpen, scrollOffset > 6 else {
            library.setTimelineTopDate(nil)
            return
        }
        let visible = tileFrames.filter { $0.value.width > 0.5 && $0.value.height > 0.5 }
        guard !visible.isEmpty else {
            library.setTimelineTopDate(nil)
            return
        }
        // The topmost row: the smallest `minY` that still starts at or below
        // the top edge, and the leftmost tile of that row. The grid is
        // chronological, so this is the oldest photo on screen.
        let below = visible.filter { $0.value.minY >= -1 }
        let top = below.min { lhs, rhs in
            let dy = lhs.value.minY - rhs.value.minY
            if abs(dy) > 0.5 { return dy < 0 }
            return lhs.value.minX < rhs.value.minX
        } ?? visible.min { lhs, rhs in
            lhs.value.maxY < rhs.value.maxY
        }
        guard let top else { return }
        library.setTimelineTopDate(library.timelineDate(for: top.key))
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
                TileView(model: model, item: item)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: TimelineTileFramesKey.self,
                                value: TimelineTileFrames(frames: [
                                    item.id: proxy.frame(in: .named(TimelineSpace.name))
                                ])
                            )
                        }
                    }
                    .onAppear {
                        // The oldest photo of the page is the first row, so
                        // reaching it means the person walked back far enough
                        // to ask for the next page.
                        guard item.id == library.page.items.last?.id else { return }
                        Task { await library.loadOlderIfNeeded() }
                    }
            }
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

    @ViewBuilder
    private var olderFooter: some View {
        if library.filters.isTimeline, !library.page.items.isEmpty {
            if case .failed(let message) = library.olderState {
                VStack(spacing: 8) {
                    Text(message)
                        .font(Font.mng(13))
                        .foregroundStyle(Palette.text3)
                    Button(Strings.retry) {
                        Task { await library.loadOlder() }
                    }
                    .font(Font.mng(13, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
            } else if library.page.hasMore, !library.olderExhausted {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(Strings.loadOlder)
                        .font(Font.mng(12))
                        .foregroundStyle(Palette.text3)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .onAppear {
                    Task { await library.loadOlderIfNeeded() }
                }
            }
        }
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

/// Scroll offset of the library grid, measured from the top of the scroll
/// view.
private struct TimelineScrollOffsetKey: PreferenceKey {
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
