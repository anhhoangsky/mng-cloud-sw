import MNGKit
import SwiftUI

/// Albums tab: seven collapsible sections in the PWA's order, with per-section
/// sorting and density, the AI progress banner and the people/place grids.
struct AlbumsView: View {
    let model: ShellModel

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var albums: AlbumsModel { model.albums }
    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        ScrollView {
            // Lazy sections keep the off-screen grids (and their thumbnails)
            // out of the layout until they are needed. With a plain VStack
            // every grid below the fold was created at once on tab entry,
            // which is where the scroll used to stutter.
            LazyVStack(alignment: .leading, spacing: isCompact ? 26 : 32) {
                AIProgressBanner(status: albums.ai)

                if let message = albums.exploreError {
                    AlbumPageError(message: message) {
                        Task { await albums.retryExplore() }
                    }
                }

                recentSection
                favoritesSection
                collectionsSection
                yearsSection
                peopleSection
                placesSection
                districtsSection

                if let message = albums.albumsError {
                    AlbumPageError(message: message) {
                        Task { await albums.retryAlbums() }
                    }
                }
            }
            .padding(.horizontal, isCompact ? 16 : 32)
            .padding(.top, isCompact ? 6 : 26)
            .padding(.bottom, isCompact ? 154 : 60)
            .frame(maxWidth: Tokens.Layout.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Palette.bg.ignoresSafeArea())
        .task {
            await albums.loadIfNeeded()
        }
        .task(id: albums.shouldPollExplore) {
            guard albums.shouldPollExplore else { return }
            await albums.pollExplore()
        }
    }

    private var recentSection: some View {
        AlbumPhotoSection(
            model: model,
            title: Strings.albumRecent,
            scope: "recent",
            items: albums.recent,
            status: albums.recentState,
            open: pref(\.recentOpen),
            sort: pref(\.recentSort),
            grid: pref(\.recentGrid),
            previewLimit: 9,
            emptyTitle: Strings.albumRecentEmpty,
            emptyBody: Strings.albumRecentEmptyBody,
            retry: { Task { await albums.retryRecent() } }
        )
    }

    private var favoritesSection: some View {
        AlbumPhotoSection(
            model: model,
            title: Strings.albumFavorites,
            scope: "favorites",
            items: albums.favorites,
            status: albums.favoritesState,
            open: pref(\.favoritesOpen),
            sort: pref(\.favoritesSort),
            grid: pref(\.favoritesGrid),
            previewLimit: 9,
            emptyTitle: Strings.albumFavoritesEmpty,
            emptyBody: Strings.albumFavoritesEmptyBody,
            retry: { Task { await albums.retryFavorites() } }
        )
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            AlbumSectionHead(
                title: Strings.albumCollections,
                count: albums.collections.count,
                open: pref(\.collectionsOpen),
                sort: pref(\.collectionsSort),
                grid: pref(\.collectionsGrid)
            )

            if albums.collectionsOpen {
                if !albums.collections.isEmpty {
                    LazyVGrid(columns: smartColumns(albums.collectionsGrid), spacing: 12) {
                        ForEach(albums.collections) { album in
                            SmartAlbumRow(model: model, album: album) {
                                model.openAlbum(albums.album(for: album))
                            }
                        }
                    }
                } else if albums.albumsState == .ready {
                    AlbumSectionEmpty(
                        icon: "rectangle.stack",
                        title: Strings.albumCollections,
                        message: Strings.albumCollectionsEmpty
                    )
                } else if albums.albums.isEmpty, albums.albumsState == .loading {
                    LazyVGrid(columns: collectionSkeletonColumns, spacing: 12) {
                        ForEach(0..<4, id: \.self) { _ in
                            ShimmerTile()
                                .frame(height: 78)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
        }
    }

    private var yearsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            AlbumSectionHead(
                title: Strings.albumYears,
                count: albums.years.count,
                open: pref(\.yearsOpen),
                sort: pref(\.yearsSort),
                grid: pref(\.yearsGrid)
            )

            if albums.yearsOpen {
                if !albums.years.isEmpty {
                    LazyVGrid(columns: albumColumns(albums.yearsGrid), spacing: cardGap) {
                        ForEach(albums.years) { album in
                            AlbumCard(model: model, album: album) {
                                model.openAlbum(albums.album(for: album))
                            }
                        }
                    }
                } else if albums.albumsState == .ready {
                    AlbumSectionEmpty(
                        icon: "photo.on.rectangle.angled",
                        title: Strings.albumYears,
                        message: Strings.albumYearsEmpty
                    )
                } else if albums.albumsState == .loading {
                    yearsSkeleton
                }
            }
        }
    }

    /// One row of year cards. The cover block is a square because the four
    /// thumbnails inside it are, so replacing the skeleton with the real card
    /// keeps the page height unchanged.
    private var yearsSkeleton: some View {
        LazyVGrid(columns: albumColumns(albums.yearsGrid), spacing: cardGap) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 0) {
                    ShimmerTile()
                        .aspectRatio(1, contentMode: .fit)
                    VStack(alignment: .leading, spacing: 5) {
                        ShimmerTile()
                            .frame(width: 78, height: 14)
                            .clipShape(Capsule())
                        ShimmerTile()
                            .frame(width: 48, height: 10)
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                }
                .background(
                    Palette.bgElevated2,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
        }
        .accessibilityHidden(true)
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            AlbumSectionHead(
                title: Strings.albumPeople,
                count: albums.people.count,
                open: pref(\.peopleOpen),
                sort: pref(\.peopleSort),
                grid: pref(\.peopleGrid)
            )

            if albums.peopleOpen {
                if !albums.people.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        // The strip can hold hundreds of faces; a lazy row
                        // only builds the cards that are actually on screen.
                        LazyHStack(spacing: 14) {
                            ForEach(albums.sortedPeople) { person in
                                PersonCard(
                                    model: model,
                                    person: person,
                                    size: personSize(albums.peopleGrid)
                                )
                            }
                        }
                        .padding(.bottom, 10)
                    }
                } else if albums.exploreState == .loading {
                    peopleSkeleton
                } else if albums.exploreLoaded {
                    AlbumSectionEmpty(
                        icon: "person.crop.circle",
                        title: Strings.albumPeople,
                        message: Strings.albumPeopleEmpty
                    )
                }
            }
        }
    }

    /// Six face placeholders at the same size as a real card. Explore fills
    /// the strip in place instead of replacing one large block above the
    /// whole page with a different one.
    private var peopleSkeleton: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(0..<6, id: \.self) { _ in
                    PersonCardSkeleton(size: personSize(albums.peopleGrid))
                }
            }
            .padding(.bottom, 10)
        }
        .scrollDisabled(true)
        .accessibilityHidden(true)
    }

    private var placesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            AlbumSectionHead(
                title: Strings.albumPlaces,
                count: albums.places.provinces.count,
                open: pref(\.placesOpen),
                sort: pref(\.placesSort),
                grid: pref(\.placesGrid)
            )

            if albums.placesOpen {
                if !albums.places.provinces.isEmpty {
                    LazyVGrid(columns: placeColumns(albums.placesGrid), spacing: 12) {
                        ForEach(albums.sortedPlaces, id: \.province) { place in
                            PlaceCard(model: model, place: place) {
                                model.openAlbum(albums.album(for: place))
                            }
                        }
                    }
                } else if albums.exploreState == .loading {
                    placesSkeleton
                } else if albums.exploreLoaded {
                    AlbumSectionEmpty(
                        icon: "mappin.and.ellipse",
                        title: Strings.albumPlaces,
                        message: Strings.albumPlacesEmpty
                    )
                }
            }
        }
    }

    private var placesSkeleton: some View {
        LazyVGrid(columns: placeColumns(albums.placesGrid), spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                ShimmerTile()
                    .aspectRatio(1.42, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .accessibilityHidden(true)
    }

    private var districtsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            AlbumSectionHead(
                title: Strings.albumDistricts,
                count: albums.places.districts.count,
                open: pref(\.districtsOpen),
                sort: pref(\.districtsSort),
                grid: pref(\.districtsGrid)
            )

            if albums.districtsOpen {
                if !albums.places.districts.isEmpty {
                    LazyVGrid(columns: districtColumns(albums.districtsGrid), spacing: 12) {
                        ForEach(albums.sortedDistricts, id: \.self) { place in
                            DistrictRow(model: model, place: place) {
                                model.openAlbum(albums.album(for: place))
                            }
                        }
                    }
                } else if albums.exploreState == .loading {
                    districtsSkeleton
                } else if albums.exploreLoaded {
                    AlbumSectionEmpty(
                        icon: "mappin.and.ellipse",
                        title: Strings.albumDistricts,
                        message: Strings.albumDistrictsEmpty
                    )
                }
            }
        }
    }

    private var districtsSkeleton: some View {
        LazyVGrid(columns: districtColumns(albums.districtsGrid), spacing: 12) {
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 13) {
                    ShimmerTile()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        ShimmerTile()
                            .frame(width: 118, height: 13)
                            .clipShape(Capsule())
                        ShimmerTile()
                            .frame(width: 82, height: 10)
                            .clipShape(Capsule())
                    }
                    Spacer(minLength: 0)
                }
                .padding(11)
                .background(
                    Palette.bgGrouped,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Bindings

    /// `AlbumsModel` is a reference type owned by `ShellModel`, so section
    /// preferences are reachable through a key path instead of `$albums.x`.
    private func pref<Value>(
        _ path: ReferenceWritableKeyPath<AlbumsModel, Value>
    ) -> Binding<Value> {
        Binding(
            get: { albums[keyPath: path] },
            set: { albums[keyPath: path] = $0 }
        )
    }

    // MARK: - Grid metrics

    private var cardGap: CGFloat {
        isCompact ? 14 : 22
    }

    /// `.album-grid` — years. Two columns on phones, `330/260/200` when wide.
    private func albumColumns(_ grid: AlbumGrid) -> [GridItem] {
        if isCompact {
            return Array(
                repeating: GridItem(.flexible(), spacing: cardGap),
                count: 2
            )
        }
        let minimum: CGFloat
        switch grid {
        case .large: minimum = 330
        case .medium: minimum = 260
        case .small: minimum = 200
        }
        return [GridItem(.adaptive(minimum: minimum), spacing: cardGap)]
    }

    /// `.smart-albums` — collections and districts. One column on phones,
    /// `290/220/180` when wide.
    private func smartColumns(_ grid: AlbumGrid) -> [GridItem] {
        if isCompact {
            return [GridItem(.flexible())]
        }
        let minimum: CGFloat
        switch grid {
        case .large: minimum = 290
        case .medium: minimum = 220
        case .small: minimum = 180
        }
        return [GridItem(.adaptive(minimum: minimum), spacing: 12)]
    }

    private func districtColumns(_ grid: AlbumGrid) -> [GridItem] {
        smartColumns(grid)
    }

    /// `.album-skeleton-row` — row placeholders while albums load.
    private var collectionSkeletonColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 220), spacing: 12)]
    }

    /// `.place-grid` — `230/170/136` at every width.
    private func placeColumns(_ grid: AlbumGrid) -> [GridItem] {
        let minimum: CGFloat
        switch grid {
        case .large: minimum = 230
        case .medium: minimum = 170
        case .small: minimum = 136
        }
        return [GridItem(.adaptive(minimum: minimum), spacing: 12)]
    }

    private func personSize(_ grid: AlbumGrid) -> CGFloat {
        switch grid {
        case .large: 116
        case .medium: 96
        case .small: 74
        }
    }
}

// MARK: - Section head

private struct AlbumSectionHead: View {
    let title: String
    let count: Int
    @Binding var open: Bool
    @Binding var sort: AlbumSort
    @Binding var grid: AlbumGrid

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(Tokens.Motion.fade) {
                        open.toggle()
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "chevron.down")
                            .font(Font.mng(13, weight: .semibold))
                            .foregroundStyle(Palette.text3)
                            .rotationEffect(.degrees(open ? 0 : -90))
                        Text(title)
                            .font(Font.mng(22, weight: .bold))
                            .tracking(-0.02)
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                        Text("\(count)")
                            .font(Font.mng(13))
                            .foregroundStyle(Palette.textMuted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(open ? .isSelected : [])

                Spacer(minLength: 0)

                if open, !isCompact {
                    tools
                }
            }

            if open, isCompact {
                HStack {
                    Spacer(minLength: 0)
                    tools
                }
            }
        }
        .frame(minHeight: 44)
        .padding(.bottom, 6)
    }

    private var tools: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(AlbumSort.allCases, id: \.self) { option in
                    Button {
                        sort = option
                    } label: {
                        if sort == option {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                pill(icon: "arrow.up.arrow.down", text: sort.label)
            }
            .accessibilityLabel(Strings.albumSortLabel)
            .accessibilityValue(sort.label)

            Menu {
                ForEach(AlbumGrid.allCases, id: \.self) { option in
                    Button {
                        grid = option
                    } label: {
                        if grid == option {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                pill(icon: "square.grid.2x2", text: grid.label)
            }
            .accessibilityLabel(Strings.albumGridLabel)
            .accessibilityValue(grid.label)
        }
    }

    private func pill(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(Font.mng(10, weight: .semibold))
            Text(text)
                .font(Font.mng(13, weight: .medium))
        }
        .foregroundStyle(Palette.text2)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Palette.fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

// MARK: - Photo section

private struct AlbumPhotoSection: View {
    let model: ShellModel
    let title: String
    let scope: String
    let items: [Item]
    let status: AlbumsModel.LoadState
    @Binding var open: Bool
    @Binding var sort: AlbumSort
    @Binding var grid: AlbumGrid
    let previewLimit: Int?
    let emptyTitle: String
    let emptyBody: String
    let retry: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var expanded = false

    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AlbumSectionHead(
                title: title,
                count: items.count,
                open: $open,
                sort: $sort,
                grid: $grid
            )

            if open {
                if items.isEmpty, status == .loading {
                    skeleton
                } else if items.isEmpty, case .failed(let message) = status {
                    AlbumSectionEmpty(
                        icon: "exclamationmark.triangle",
                        title: Strings.albumErrorTitle,
                        message: message,
                        retry: retry
                    )
                } else if items.isEmpty, status == .ready {
                    AlbumSectionEmpty(
                        icon: "photo.on.rectangle.angled",
                        title: emptyTitle,
                        message: emptyBody
                    )
                } else if !items.isEmpty {
                    photoGrid
                    if let previewLimit, items.count > previewLimit {
                        Button {
                            withAnimation(Tokens.Motion.fade) {
                                expanded.toggle()
                            }
                        } label: {
                            Text(expanded ? Strings.albumShowLess : Strings.albumShowAll)
                                .font(Font.mng(14, weight: .semibold))
                                .foregroundStyle(Palette.accent)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 44)
                                .background(Palette.accentSoft.opacity(expanded ? 0.6 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 10)
                    }
                }
            }
        }
    }

    private var sorted: [Item] {
        AlbumSorting.items(items, sort: sort)
    }

    /// The skeleton uses the same number of cells as the preview grid, so
    /// swapping the shimmer for the first page does not change the height of
    /// the section and cannot push the page under the finger.
    private var skeleton: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: columns, spacing: grid.spacing) {
                ForEach(0..<(previewLimit ?? 12), id: \.self) { _ in
                    ShimmerTile()
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
            if previewLimit != nil {
                // Reserve the "Xem tất cả" row that appears with the data.
                Color.clear.frame(height: 54)
            }
        }
        .accessibilityHidden(true)
    }

    private var photoGrid: some View {
        let list = sorted
        let limit = previewLimit ?? list.count
        let shown = expanded ? list.count : min(limit, list.count)
        return LazyVGrid(columns: columns, spacing: grid.spacing) {
            ForEach(Array(list.prefix(shown))) { item in
                AlbumPhotoTile(model: model, item: item) {
                    model.library.openViewer(items: list, id: item.id)
                }
            }
        }
    }

    private var columns: [GridItem] {
        if isCompact {
            let count: Int
            switch grid {
            case .large: count = 2
            case .medium, .small: count = 3
            }
            return Array(
                repeating: GridItem(.flexible(), spacing: grid.spacing),
                count: count
            )
        }
        return [GridItem(.adaptive(minimum: CGFloat(grid.minimumWidth)), spacing: grid.spacing)]
    }
}

private struct AlbumPhotoTile: View {
    let model: ShellModel
    let item: Item
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ZStack(alignment: .bottomLeading) {
                        ThumbnailView(
                            client: model.client,
                            path: item.thumbnailPath(size: 360),
                            fallbacks: item.thumbnailFallbackPaths
                        )

                        HStack(spacing: 5) {
                            if item.isVideo {
                                badge(icon: "play.fill", text: MNGFormat.duration(item.duration))
                            }
                            if item.live {
                                badge(icon: "livephoto", text: "LIVE")
                            }
                            Spacer(minLength: 0)
                            if item.favorite {
                                Image(systemName: "heart.fill")
                                    .font(Font.mng(11, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.horizontal, 5)
                        .padding(.bottom, 5)
                        .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
                    }
                    .clipped()
                }
                .background(Palette.fill)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.name.isEmpty ? Strings.kindPhoto : item.name)
    }

    private func badge(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(Font.mng(8, weight: .bold))
            Text(text)
                .font(Font.mng(10, weight: .bold))
        }
        .foregroundStyle(.white)
    }
}

// MARK: - Collections, years, people, places

private struct SmartAlbumRow: View {
    let model: ShellModel
    let album: Album
    let onOpen: () -> Void

    private var cover: Item? { album.covers.first }
    private var title: String {
        let trimmed = album.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Strings.albumFallback : trimmed
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 13) {
                ZStack {
                    Palette.fill
                    if let cover {
                        ThumbnailView(
                            client: model.client,
                            path: cover.thumbnailPath(size: 360),
                            fallbacks: cover.thumbnailFallbackPaths
                        )
                    } else {
                        Image(systemName: "rectangle.stack")
                            .font(Font.mng(20))
                            .foregroundStyle(Palette.text4)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Font.mng(15, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Text(Strings.albumItemSub(album.count, sub: album.sub))
                        .font(Font.mng(12))
                        .foregroundStyle(Palette.text3)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(Font.mng(11, weight: .semibold))
                    .foregroundStyle(Palette.text4)
            }
            .padding(11)
            .background(Palette.bgGrouped, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct AlbumCard: View {
    let model: ShellModel
    let album: Album
    let onOpen: () -> Void

    private var title: String {
        let trimmed = album.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Strings.albumFallback : trimmed
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                // Four fixed covers do not need a lazy grid. Two greedy rows
                // split the card width evenly and keep every cover square,
                // without another lazy container to measure inside the page.
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        cover(slot: 0)
                        cover(slot: 1)
                    }
                    HStack(spacing: 2) {
                        cover(slot: 2)
                        cover(slot: 3)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Font.mng(15, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Text(Strings.albumYearSub(album.count))
                        .font(Font.mng(12))
                        .foregroundStyle(Palette.text3)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
            }
            .background(Palette.bgElevated2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func cover(slot: Int) -> some View {
        ZStack {
            Palette.fill2
            if slot < album.covers.count {
                ThumbnailView(
                    client: model.client,
                    path: album.covers[slot].thumbnailPath(size: 360),
                    fallbacks: album.covers[slot].thumbnailFallbackPaths
                )
            } else {
                Image(systemName: "photo")
                    .font(Font.mng(18))
                    .foregroundStyle(Palette.text4)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct PersonCard: View {
    let model: ShellModel
    let person: Person
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                model.openAlbum(model.albums.album(for: person))
            } label: {
                VStack(spacing: 7) {
                    ZStack {
                        Palette.fill
                        if !person.cover.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ThumbnailView(client: model.client, path: person.cover)
                        } else {
                            Image(systemName: "person.fill")
                                .font(Font.mng(max(20, size * 0.3)))
                                .foregroundStyle(Palette.text4)
                        }
                    }
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay {
                        Circle().stroke(Palette.hairline, lineWidth: 0.5)
                    }

                    Text(AlbumCatalog.personTitle(person))
                        .font(Font.mng(13, weight: .medium))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                        .frame(maxWidth: size + 8)

                    Text(Strings.albumPhotoCount(person.itemCount))
                        .font(Font.mng(11))
                        .foregroundStyle(Palette.text3)
                }
            }
            .buttonStyle(.plain)

            Button {
                model.presentPersonEdit(person)
            } label: {
                Image(systemName: "pencil")
                    .font(Font.mng(10, weight: .bold))
                    .foregroundStyle(Palette.text2)
                    .frame(width: 24, height: 24)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle().stroke(Palette.hairline, lineWidth: 0.5)
                    }
            }
            .buttonStyle(.plain)
            .offset(x: -2, y: 2)
            .accessibilityLabel("\(Strings.personRenameTitle) \(AlbumCatalog.personTitle(person))")
        }
        .frame(width: size + 8)
    }
}

private struct PersonCardSkeleton: View {
    let size: CGFloat

    var body: some View {
        VStack(spacing: 7) {
            Circle()
                .fill(Palette.fill2)
                .frame(width: size, height: size)

            ShimmerTile()
                .frame(width: size * 0.62, height: 16)
                .clipShape(Capsule())

            ShimmerTile()
                .frame(width: size * 0.42, height: 13)
                .clipShape(Capsule())
        }
        .frame(width: size + 8)
    }
}

private struct PlaceCard: View {
    let model: ShellModel
    let place: PlaceProvince
    let onOpen: () -> Void

    private var coverPath: String? {
        place.coverID > 0 ? "/api/v1/items/\(place.coverID)/thumb?size=360" : nil
    }

    var body: some View {
        Button(action: onOpen) {
            ZStack(alignment: .bottomLeading) {
                if let coverPath {
                    ThumbnailView(client: model.client, path: coverPath)
                } else {
                    Palette.fill
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(place.province.isEmpty ? Strings.albumUnknownProvince : place.province)
                        .font(Font.mng(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(Strings.albumPhotoCount(place.count))
                        .font(Font.mng(11))
                        .foregroundStyle(.white.opacity(0.82))
                }
                .padding(11)
            }
            .aspectRatio(1.42, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct DistrictRow: View {
    let model: ShellModel
    let place: PlaceDistrict
    let onOpen: () -> Void

    private var coverPath: String? {
        place.coverID > 0 ? "/api/v1/items/\(place.coverID)/thumb?size=360" : nil
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 13) {
                ZStack {
                    Palette.fill
                    if let coverPath {
                        ThumbnailView(client: model.client, path: coverPath)
                    } else {
                        Image(systemName: "mappin.and.ellipse")
                            .font(Font.mng(18))
                            .foregroundStyle(Palette.text4)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(place.district)
                        .font(Font.mng(15, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Text(Strings.albumPlaceSub(province: place.province, count: place.count))
                        .font(Font.mng(12))
                        .foregroundStyle(Palette.text3)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(Font.mng(11, weight: .semibold))
                    .foregroundStyle(Palette.text4)
            }
            .padding(11)
            .background(Palette.bgGrouped, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AI banner and states

private struct AIProgressBanner: View {
    let status: AiStatus?

    var body: some View {
        Group {
            if let status {
                let faces = max(0, status.stats.facesPending)
                let places = max(0, status.stats.placePending)
                if faces == 0, places == 0 {
                    note(
                        icon: "checkmark.circle.fill",
                        iconColor: Palette.accent,
                        title: Strings.aiDoneTitle,
                        body: Strings.aiDoneBody(status.stats.facesDone),
                        dot: false,
                        running: false
                    )
                } else {
                    note(
                        icon: nil,
                        iconColor: Palette.text4,
                        title: status.running ? Strings.aiRunningTitle : Strings.aiPausedTitle,
                        body: Strings.aiPendingBody(faces: faces, places: places),
                        dot: true,
                        running: status.running
                    )
                }
            } else {
                note(
                    icon: nil,
                    iconColor: Palette.text4,
                    title: Strings.aiConnectingTitle,
                    body: Strings.aiConnectingBody,
                    dot: true,
                    running: false
                )
            }
        }
    }

    private func note(
        icon: String?,
        iconColor: Color,
        title: String,
        body: String,
        dot: Bool,
        running: Bool
    ) -> some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(Font.mng(21, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 22)
            } else if dot {
                Circle()
                    .fill(running ? Palette.accent : Palette.text4)
                    .frame(width: 9, height: 9)
                    .overlay {
                        Circle()
                            .stroke(running ? Palette.accentSoft : Color.clear, lineWidth: 4)
                    }
                    .frame(width: 22)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Font.mng(14, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                // Reserve the second line even while the sentence is short.
                // The AI counters change the sentence every few seconds, and
                // a banner that grows a line would push the whole page down
                // under the person's finger.
                Text(body)
                    .font(Font.mng(12))
                    .foregroundStyle(Palette.text3)
                    .lineLimit(2, reservesSpace: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Palette.bgGrouped, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct AlbumSectionEmpty: View {
    let icon: String
    let title: String
    let message: String
    var retry: (() -> Void)? = nil

    private var isError: Bool { retry != nil }

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(Font.mng(24))
                .foregroundStyle(isError ? Palette.danger : Palette.text4)
            Text(title)
                .font(Font.mng(14, weight: .semibold))
                .foregroundStyle(isError ? Palette.danger : Palette.text2)
            Text(message)
                .font(Font.mng(13))
                .foregroundStyle(Palette.text3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let retry {
                Button(Strings.retry, action: retry)
                    .font(Font.mng(13, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            isError ? Palette.dangerSoft : Palette.bgGrouped,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

private struct AlbumPageError: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(Font.mng(18))
                .foregroundStyle(Palette.danger)
            Text(message)
                .font(Font.mng(13))
                .foregroundStyle(Palette.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(Strings.retry, action: retry)
                .font(Font.mng(13, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .buttonStyle(.plain)
        }
        .padding(12)
        .background(Palette.dangerSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
