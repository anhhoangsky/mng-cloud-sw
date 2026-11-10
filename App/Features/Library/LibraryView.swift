import MNGKit
import SwiftUI

/// Library screen: grouping toolbar, 120-item timeline paging, kind filters,
/// year/month cards and empty/error/skeleton states.
struct LibraryView: View {
    let model: ShellModel

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var library: LibraryModel { model.library }
    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                if !library.isAlbumOpen {
                    LibraryToolbar(model: model)
                        .padding(.horizontal, isCompact ? 16 : 0)
                        .padding(.top, isCompact ? 6 : 0)
                        .padding(.bottom, 16)
                }

                bodyContent

                if library.loadState == .ready, !library.isAlbumOpen {
                    olderFooter
                }
            }
            .padding(.horizontal, isCompact ? 0 : 32)
            .padding(.top, isCompact ? 0 : 26)
            .padding(.bottom, isCompact ? 154 : 60)
            .frame(maxWidth: Tokens.Layout.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .refreshable {
            await library.reload()
        }
        .background(Palette.bg.ignoresSafeArea())
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

    private var timeline: some View {
        let sections = LibraryGrouping.byMonth(library.page.items)
        return ForEach(sections) { section in
            Section {
                LazyVGrid(columns: timelineColumns, spacing: timelineGap) {
                    ForEach(section.items) { item in
                        TileView(model: model, item: item)
                            .onAppear {
                                guard item.id == library.page.items.last?.id else { return }
                                Task { await library.loadOlderIfNeeded() }
                            }
                    }
                }
            } header: {
                MonthSectionHeader(
                    title: MNGFormat.monthLabel(year: section.year, month: section.month),
                    count: section.items.count
                )
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

    private var library: LibraryModel { model.library }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 12) {
                layoutSegment

                Spacer(minLength: 8)

                if library.canSelect, !library.selectionMode {
                    Button(Strings.select) {
                        library.enterSelection()
                    }
                    .font(Font.mng(13, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .buttonStyle(.plain)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(ItemKindFilter.allCases, id: \.self) { kind in
                        kindChip(kind)
                    }

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

private struct MonthSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(Font.mng(13, weight: .bold))
                .foregroundStyle(Palette.text2)
            Text(Strings.itemCount(count))
                .font(Font.mng(13))
                .foregroundStyle(Palette.text3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .padding(.top, 8)
        .padding(.bottom, 9)
        .background(Palette.bg.opacity(0.94))
    }
}

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
