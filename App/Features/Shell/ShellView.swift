import MNGKit
import SwiftUI

/// Authenticated shell: a four-tab compact layout on iPhone and a 264 pt
/// sidebar on iPad, mirroring the PWA's `shell.rs` breakpoints.
struct ShellView: View {
    @State private var model: ShellModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    init(store: SessionStore) {
        _model = State(initialValue: ShellModel(store: store))
    }

    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        shell
            .sheet(item: $model.activeSheet) { sheet in
                switch sheet {
                case .connections:
                    ConnectionsSheet(model: model)
                case .icloud:
                    ConnectionsSheet(model: model, initial: .icloud)
                case .info:
                    ItemInfoSheet(model: model)
                case .person:
                    PersonRenameSheet(model: model)
                case .duplicates:
                    DuplicatesView(model: model)
                case .admin:
                    AdminView(model: model)
                }
            }
            .alert(
                model.library.pendingDelete?.title ?? "",
                isPresented: deleteBinding,
                presenting: model.library.pendingDelete
            ) { prompt in
                Button(Strings.cancel, role: .cancel) {
                    model.library.cancelDelete()
                }
                Button(prompt.confirmLabel, role: .destructive) {
                    model.library.confirmDelete()
                }
            } message: { prompt in
                Text(prompt.message)
            }
            .task {
                await model.start()
            }
            .onChange(of: scenePhase) { _, phase in
                // The derived vault key never survives the app going to the
                // background.
                if phase != .active {
                    model.vault.lock()
                }
            }
    }

    /// Root layout. The share sheet is attached here and the modal sheet in
    /// `body`, so each presentation hangs off its own view: stacked `.sheet`
    /// modifiers on a single view can collapse into one presentation.
    private var shell: some View {
        ZStack(alignment: .bottom) {
            Palette.bgGrouped.ignoresSafeArea()

            if isCompact {
                content
                    // The header is a sticky inset: the first photo starts
                    // below it, and the grid slides underneath the floating
                    // title as soon as the person scrolls, exactly like the
                    // web's `position: sticky` header.
                    .safeAreaInset(edge: .top, spacing: 0) {
                        CompactShellHeader(model: model)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        compactBottomChrome
                            .animation(Tokens.Motion.fade, value: model.tab)
                            .animation(
                                Tokens.Motion.fade,
                                value: model.library.selectionMode
                            )
                    }
                    // The switcher of the year/month cards floats above the
                    // dock; in the timeline it takes the dock's centre slot.
                    .overlay(alignment: .bottom) {
                        floatingLayoutSwitcher
                    }
                    .onPreferenceChange(ShellHeaderBottomKey.self) { bottom in
                        // The library needs the measured header edge to pick
                        // the photo that is visible underneath the title.
                        if bottom > 0, abs(bottom - model.headerBottom) > 0.5 {
                            model.headerBottom = bottom
                        }
                    }
            } else {
                HStack(spacing: 0) {
                    ShellSidebar(model: model)
                        .frame(width: Tokens.Layout.sidebarWidth)
                    Rectangle()
                        .fill(Palette.sep)
                        .frame(width: 0.5)
                        .ignoresSafeArea()
                    content
                }
                .overlay(alignment: .bottom) { regularBottomChrome }
            }

            ZStack {
                if model.library.viewer.isOpen {
                    ViewerView(model: model)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.985)),
                                removal: .opacity.combined(with: .scale(scale: 0.98))
                            )
                        )
                }
            }
            .animation(Tokens.Motion.viewer, value: model.library.viewer.isOpen)
            .zIndex(20)

            if let toast = model.toast {
                ToastBubble(message: toast)
                    .padding(.horizontal, 24)
                    .padding(.bottom, isCompact ? 104 : 34)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .zIndex(30)
            }
        }
        .animation(Tokens.Motion.fade, value: model.toast)
        .sheet(item: shareBinding) { file in
            ActivityView(url: file.url)
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.tab {
        case .library:
            LibraryView(model: model)
        case .albums:
            AlbumsView(model: model)
        case .search:
            SearchView(model: model)
        case .settings:
            SettingsView(model: model)
        case .vault:
            VaultView(model: model)
        }
    }

    @ViewBuilder
    private var compactBottomChrome: some View {
        ZStack(alignment: .bottom) {
            if model.tab == .library, model.library.selectionMode {
                SelectionBar(model: model)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                CompactTabBar(model: model)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // The content padding in the web is constant (154 px) while the dock
        // changes shape, so the inset keeps the height of the expanded dock
        // and only the bar inside it condenses.
        .frame(height: 70, alignment: .bottom)
        .frame(maxWidth: .infinity)
    }

    /// The layout switcher floats above the dock in the year/month cards.
    /// The timeline keeps it inside the dock's centre slot instead.
    @ViewBuilder
    private var floatingLayoutSwitcher: some View {
        if model.tab == .library,
           !model.library.selectionMode,
           model.library.filters.layout != .all {
            LibraryLayoutSwitcher(model: model)
                .padding(.bottom, 78)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(Tokens.Motion.fade, value: model.library.filters.layout)
        }
    }

    @ViewBuilder
    private var regularBottomChrome: some View {
        if model.tab == .library, model.library.selectionMode {
            SelectionBar(model: model)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var shareBinding: Binding<DownloadedFile?> {
        Binding(
            get: { model.shareFile },
            set: { next in
                if next == nil {
                    model.dismissShare()
                }
            }
        )
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { model.library.pendingDelete != nil },
            set: { presented in
                if !presented {
                    model.library.cancelDelete()
                }
            }
        )
    }
}

// MARK: - Compact chrome

private struct CompactShellHeader: View {
    let model: ShellModel

    /// The measured height of the whole header, used to hang the filter
    /// dropdown below it.
    @State private var height: CGFloat = 79

    private var library: LibraryModel { model.library }

    private var showsBack: Bool { model.canGoBack }

    private var showsFilter: Bool {
        model.tab == .library
            && !library.selectionMode
            && !library.isAlbumOpen
    }

    private var showsSelect: Bool {
        model.tab == .library
            && library.canSelect
            && !library.selectionMode
    }

    var body: some View {
        // The web header is a three-column grid: back, title, actions, with
        // the subtitle and the filter summary spanning the title and action
        // columns underneath. A SwiftUI `Grid` keeps the same geometry.
        Grid(horizontalSpacing: 8, verticalSpacing: 3) {
            GridRow {
                leftControls
                    .gridColumnAlignment(.leading)

                Text(model.title)
                    .font(Font.mng(36, weight: .semibold))
                    // `letter-spacing: -0.035em` at 36 px.
                    .tracking(-1.26)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    // The title floats over the photo grid, so it needs the
                    // soft halo the native shell puts behind it.
                    .shadow(
                        color: Palette.bg.opacity(0.86),
                        radius: 6
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                rightControls
                    .gridColumnAlignment(.trailing)
            }

            if !library.selectionMode {
                GridRow {
                    Color.clear
                        .frame(width: 0, height: 0)
                    Text(model.subtitle)
                        .font(Font.mng(13, weight: .medium))
                        .tracking(-0.13)
                        .foregroundStyle(Palette.text3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .shadow(
                            color: Palette.bg.opacity(0.86),
                            radius: 5
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .gridCellColumns(2)
                }

                // The active filter summary lives in its own row under the
                // count, matching `.mh-filter-summary` in the web.
                if let summary = library.filters.summary,
                   model.tab == .library,
                   !library.isAlbumOpen {
                    GridRow {
                        Color.clear
                            .frame(width: 0, height: 0)
                        HStack(spacing: 0) {
                            filterSummaryChip(summary)
                            Spacer(minLength: 0)
                        }
                        .gridCellColumns(2)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        // The inset itself already starts below the status bar, which is the
        // web's `max(10px, env(safe-area-inset-top))`, so no extra top pad.
        .padding(.top, 0)
        .padding(.bottom, library.selectionMode ? 10 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) { headerScrim }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: ShellHeaderHeightKey.self,
                        value: proxy.size.height
                    )
                    .preference(
                        key: ShellHeaderBottomKey.self,
                        value: proxy.frame(in: .global).maxY
                    )
            }
        }
        .onPreferenceChange(ShellHeaderHeightKey.self) { value in
            if value > 0, abs(value - height) > 0.5 {
                height = value
            }
        }
        .overlay(alignment: .topTrailing) {
            // The dropdown hangs under the whole header, like the fixed
            // `#libraryFilters` panel in the web.
            if showsFilter, model.isFilterMenuOpen {
                LibraryFilterMenu(model: model)
                    .padding(.top, height + 2)
                    .padding(.trailing, 12)
                    .transition(
                        .opacity.combined(
                            with: .scale(scale: 0.96, anchor: .topTrailing)
                        )
                    )
            }
        }
        .animation(Tokens.Motion.fade, value: model.isFilterMenuOpen)
    }

    /// The web header keeps the back button in the left column and hides it
    /// when there is nowhere to return to.
    @ViewBuilder
    private var leftControls: some View {
        if showsBack {
            Button {
                model.isFilterMenuOpen = false
                Task { await model.goBack() }
            } label: {
                ZStack {
                    GlassSurface(shape: Circle())
                    Image(systemName: "chevron.left")
                        .font(Font.mng(20, weight: .semibold))
                        .foregroundStyle(Palette.text2)
                }
                .frame(width: 36, height: 36)
                .contentShape(Circle())
            }
            .buttonStyle(GlassPressStyle(scale: 0.93))
            .accessibilityLabel(Strings.back)
        }
    }

    /// The right side only carries the two controls the compact web header
    /// has: the filter button and "Chọn".
    @ViewBuilder
    private var rightControls: some View {
        HStack(spacing: 4) {
            if showsFilter {
                filterButton
            }
            if showsSelect {
                selectButton
            }
        }
    }

    /// The translucent gradient behind the header on every view except the
    /// Library. The library floats its title directly over the photos.
    @ViewBuilder
    private var headerScrim: some View {
        if model.tab != .library {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(
                    stops: [
                        .init(color: Palette.bg.opacity(0.96), location: 0),
                        .init(color: Palette.bg.opacity(0.88), location: 0.72),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.78),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            // The web header paints from the top of the screen, behind the
            // status bar. The inset starts below it, so reach back up.
            .ignoresSafeArea(edges: .top)
            .opacity(model.isHeaderFaded ? 1 : 0)
            .animation(.easeOut(duration: 0.18), value: model.isHeaderFaded)
            .allowsHitTesting(false)
        }
    }

    private var filterButton: some View {
        Button {
            model.isFilterMenuOpen.toggle()
        } label: {
            ZStack {
                GlassSurface(shape: Circle())
                Image(systemName: "line.3.horizontal.decrease")
                    .font(Font.mng(19, weight: .semibold))
                    .foregroundStyle(
                        model.isFilterMenuOpen ? Palette.accent : Palette.text2
                    )
                    .rotationEffect(.degrees(model.isFilterMenuOpen ? 90 : 0))
            }
            .frame(width: 36, height: 36)
            .overlay(alignment: .topTrailing) {
                if library.filters.summary != nil {
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: 6, height: 6)
                        .overlay {
                            Circle().stroke(Palette.bgElevated, lineWidth: 2)
                        }
                        .padding(7)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(GlassPressStyle())
        .animation(
            .spring(response: 0.32, dampingFraction: 0.7),
            value: model.isFilterMenuOpen
        )
        .accessibilityLabel(Strings.editorFilterTab)
    }

    private var selectButton: some View {
        Button {
            model.isFilterMenuOpen = false
            library.enterSelection()
        } label: {
            Text(Strings.select)
                .font(Font.mng(13, weight: .semibold))
                .tracking(-0.13)
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 13)
                .frame(height: 36)
                .background { GlassSurface(shape: Capsule()) }
                .contentShape(Capsule())
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel(Strings.select)
    }

    private func filterSummaryChip(_ summary: String) -> some View {
        Button {
            model.isFilterMenuOpen = false
            Task { await library.clearFilters() }
        } label: {
            HStack(spacing: 4) {
                Text(summary)
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(Font.mng(9, weight: .bold))
            }
            .font(Font.mng(12, weight: .semibold))
            .tracking(-0.12)
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, 9)
            .frame(height: 27)
            .background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(Palette.accent.opacity(0.14))
                    Capsule().stroke(
                        Palette.accent.opacity(0.24),
                        lineWidth: 0.5
                    )
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(GlassPressStyle(scale: 0.96))
        .accessibilityLabel(Strings.clearFilters)
    }
}

/// Height of the compact header, consumed by the filter dropdown.
struct ShellHeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 79

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Bottom edge of the compact header in screen coordinates, consumed by the
/// library to find the first photo that clears the title.
struct ShellHeaderBottomKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The dropdown of the filters: the kinds of the photo and the upload.
private struct LibraryFilterMenu: View {
    let model: ShellModel

    private var library: LibraryModel { model.library }

    var body: some View {
        VStack(spacing: 3) {
            ForEach(ItemKindFilter.allCases, id: \.self) { kind in
                let active = library.filters.kind == kind
                Button {
                    Task { await library.selectKind(kind) }
                    model.isFilterMenuOpen = false
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: kindIcon(kind))
                            .font(Font.mng(16, weight: .semibold))
                            .frame(width: 18)
                        Text(kindLabel(kind))
                            .font(Font.mng(14, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(active ? Palette.accent : Palette.text2)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        active ? Palette.accentSoft : Palette.fill,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .contentShape(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }

            // The upload is an icon-only chip at the end of the filter row,
            // in the same place the web keeps it.
            Button {
                model.isUploadRequested = true
                model.isFilterMenuOpen = false
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "square.and.arrow.up")
                        .font(Font.mng(16, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Palette.text2)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    Palette.fill,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .contentShape(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.backupToLibrary)
        }
        .padding(6)
        .frame(width: 182)
        .background {
            GlassSurface(
                shape: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
    }

    private func kindIcon(_ kind: ItemKindFilter) -> String {
        switch kind {
        case .all: return "square.grid.2x2"
        case .photo: return "photo"
        case .video: return "video"
        case .live: return "livephoto"
        }
    }

    private func kindLabel(_ kind: ItemKindFilter) -> String {
        switch kind {
        case .all: return Strings.filterAll
        case .photo: return Strings.filterPhotos
        case .video: return Strings.filterVideos
        case .live: return Strings.filterLive
        }
    }
}

/// The switcher of the layout, floating above the dock or sitting in its
/// centre slot while the dock is condensed.
private struct LibraryLayoutSwitcher: View {
    let model: ShellModel

    @Namespace private var thumb

    private var library: LibraryModel { model.library }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(LibraryLayout.allCases, id: \.self) { layout in
                let active = library.filters.layout == layout
                Button {
                    guard !active else { return }
                    // Leaving the timeline expands the dock and clears the
                    // date the condensed bar was showing.
                    model.isTabBarCompact = false
                    model.isFilterMenuOpen = false
                    model.compactGuardUntil = Date().addingTimeInterval(1.2)
                    library.setTimelineTopDate(nil)
                    Task { await library.selectLayout(layout) }
                } label: {
                    Text(title(layout))
                        .font(Font.mng(12.5, weight: .semibold))
                        .tracking(-0.12)
                        .foregroundStyle(active ? Palette.text : Palette.text3)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background {
                            if active {
                                Capsule()
                                    .fill(Palette.bgElevated.opacity(0.86))
                                    .shadow(
                                        color: .black.opacity(0.13),
                                        radius: 3,
                                        y: 1
                                    )
                                    .overlay {
                                        Capsule().stroke(
                                            Color.white.opacity(0.3),
                                            lineWidth: 0.5
                                        )
                                    }
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(height: 40)
        .background { GlassSurface(shape: Capsule()) }
        .animation(Tokens.Motion.glass, value: library.filters.layout)
    }

    private func title(_ layout: LibraryLayout) -> String {
        switch layout {
        case .years: return Strings.layoutYears
        case .months: return Strings.layoutMonths
        case .all: return Strings.layoutAll
        }
    }
}

/// The bottom bar of the compact layout.
///
/// The web dock is two separate glass objects, a tab capsule and a search
/// circle, and the condensed form keeps only the open tab on the left, the
/// layout switcher in the centre and the search circle on the right.
private struct CompactTabBar: View {
    let model: ShellModel

    @Namespace private var thumb

    /// The dock is condensed while the person walks back in time.
    private var isCompact: Bool { model.isTabBarCompact }

    /// The only tab the condensed dock keeps.
    private var activeTab: ShellTab {
        ShellTab.tabBarTabs.first { model.isTabActive($0) } ?? model.tab
    }

    private var searchActive: Bool { model.isTabActive(.search) }

    var body: some View {
        HStack(spacing: isCompact ? 6 : 8) {
            tabGroup

            if isCompact {
                // The switcher takes the centre slot of the dock, between
                // the open tab and the search circle, exactly like the
                // fixed `#layoutSegment` over the condensed bar.
                Spacer(minLength: 0)
                LibraryLayoutSwitcher(model: model)
                    .layoutPriority(1)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                Spacer(minLength: 0)
            }

            searchButton
        }
        .padding(.horizontal, isCompact ? 16 : 12)
        // The outer width is the web's `min(430px, 100vw - 24px)` and
        // `min(366px, 100vw - 32px)`.
        .frame(maxWidth: isCompact ? 398 : 454)
        .frame(maxWidth: .infinity)
        .animation(Tokens.Motion.glass, value: isCompact)
        .animation(Tokens.Motion.spring, value: model.tab)
    }

    // MARK: - Tab group

    private var tabGroup: some View {
        HStack(spacing: 0) {
            if isCompact {
                compactTab(activeTab)
                    .transition(.opacity)
            } else {
                ForEach(ShellTab.tabBarTabs) { tab in
                    fullTab(tab)
                        .transition(.opacity)
                }
            }
        }
        .padding(isCompact ? 4 : 5)
        // The condensed group is a 48 pt square; the expanded one fills the
        // row beside the 60 pt search circle.
        .frame(maxWidth: isCompact ? 48 : .infinity)
        .frame(height: isCompact ? 48 : 60)
        .background {
            GlassSurface(
                shape: RoundedRectangle(cornerRadius: 999, style: .continuous)
            )
        }
        .animation(Tokens.Motion.spring, value: model.tab)
    }

    /// A tab of the expanded dock: icon over a 10 pt label, with the rounded
    /// accent thumb sliding behind the open one.
    private func fullTab(_ tab: ShellTab) -> some View {
        let active = model.isTabActive(tab)
        return Button {
            tap(tab)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.icon)
                    .font(Font.mng(23, weight: .medium))
                Text(tab.tabLabel)
                    .font(Font.mng(10, weight: .semibold))
                    .tracking(-0.1)
                    .lineLimit(1)
                    .frame(maxWidth: 82)
            }
            .foregroundStyle(active ? Palette.accent : Palette.text3)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background {
                if active {
                    Capsule()
                        .fill(Palette.accent.opacity(0.14))
                        .overlay {
                            Capsule().stroke(
                                Palette.accent.opacity(0.24),
                                lineWidth: 0.5
                            )
                        }
                        .matchedGeometryEffect(id: "thumb", in: thumb)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    /// The condensed dock only keeps the open tab, as a glass circle with the
    /// icon of that tab.
    private func compactTab(_ tab: ShellTab) -> some View {
        Button {
            tap(tab)
        } label: {
            Image(systemName: tab.icon)
                .font(Font.mng(22, weight: .medium))
                .foregroundStyle(Palette.accent)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(GlassPressStyle(scale: 0.92))
        .accessibilityLabel(tab.tabLabel)
        .accessibilityAddTraits(.isSelected)
    }

    // MARK: - Search

    private var searchButton: some View {
        Button {
            if isCompact, searchActive { return }
            model.selectTab(.search)
        } label: {
            ZStack {
                GlassSurface(shape: Circle())
                if searchActive {
                    Circle().fill(Palette.accent.opacity(0.14))
                }
                Image(systemName: "magnifyingglass")
                    .font(Font.mng(isCompact ? 22 : 24, weight: .medium))
                    .foregroundStyle(
                        searchActive ? Palette.accent : Palette.text2
                    )
            }
            .frame(
                width: isCompact ? 48 : 60,
                height: isCompact ? 48 : 60
            )
            .contentShape(Circle())
        }
        .buttonStyle(GlassPressStyle(scale: 0.94))
        .accessibilityLabel(Strings.navSearch)
        .accessibilityAddTraits(searchActive ? .isSelected : [])
    }

    // MARK: - Actions

    private func tap(_ tab: ShellTab) {
        // Tapping the open tab of a condensed dock brings the full dock back
        // instead of leaving the screen, and the guard keeps the scroll
        // gesture from condensing it again, like `scroll_guard` in the web.
        if isCompact, model.isTabActive(tab) {
            model.isTabBarCompact = false
            model.compactGuardUntil = Date().addingTimeInterval(1.2)
            return
        }
        model.selectTab(tab)
    }
}

// MARK: - Regular sidebar

private struct ShellSidebar: View {
    let model: ShellModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 11) {
                AppMark(size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Strings.appName)
                        .font(Font.mng(16, weight: .semibold))
                        .tracking(-0.015)
                        .foregroundStyle(Palette.text)
                    Text(Strings.brandSubtitle)
                        .font(Font.mng(11))
                        .foregroundStyle(Palette.text3)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 2)
            .padding(.bottom, 22)

            ForEach(ShellTab.sidebarTabs) { tab in
                let active = model.isTabActive(tab)
                Button {
                    model.selectTab(tab)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: tab.icon)
                            .font(Font.mng(17, weight: .medium))
                            .frame(width: 22)
                        Text(tab.label)
                            .font(Font.mng(14, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(active ? Palette.accent : Palette.text2)
                    .padding(.horizontal, 10)
                    .frame(height: 40)
                    .background(
                        active ? Palette.accentSoft : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }

            Spacer(minLength: 16)

            cloudCard
                .padding(.bottom, 10)

            Text(model.sidebarFoot)
                .font(Font.mng(11))
                .foregroundStyle(Palette.text4)
                .lineLimit(1)
                .padding(.horizontal, 8)
        }
        .padding(.horizontal, 14)
        .padding(.top, 26)
        .padding(.bottom, 18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.bgGrouped.ignoresSafeArea())
    }

    private var cloudCard: some View {
        Button {
            model.presentConnections()
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Palette.accentSoft)
                            .frame(width: 30, height: 30)
                        Image(systemName: "cloud.fill")
                            .font(Font.mng(14, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.activeCloudLabel)
                            .font(Font.mng(13, weight: .semibold))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                        Text(model.cloudSubtitleText)
                            .font(Font.mng(11))
                            .foregroundStyle(Palette.text3)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(Font.mng(11, weight: .semibold))
                        .foregroundStyle(Palette.text4)
                }

                HStack(spacing: 6) {
                    Text(MNGFormat.count(model.activeCloudTotal))
                    Spacer(minLength: 4)
                    if let free = model.storageFreeText {
                        Text(free)
                    }
                }
                .font(Font.mng(11))
                .foregroundStyle(Palette.text3)
            }
            .padding(11)
            .background(Palette.bgElevated, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Palette.hairline, lineWidth: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared chrome

struct ToastBubble: View {
    let message: String

    var body: some View {
        Text(message)
            .font(Font.mng(13, weight: .medium))
            .foregroundStyle(Palette.bg)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Palette.text, in: Capsule())
            .shadow(color: .black.opacity(0.24), radius: 16, y: 8)
            .accessibilityAddTraits(.isStaticText)
    }
}
