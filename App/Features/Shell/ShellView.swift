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
                VStack(spacing: 0) {
                    CompactShellHeader(model: model)
                    content
                        .safeAreaInset(edge: .bottom) {
                            compactBottomChrome
                                .animation(Tokens.Motion.fade, value: model.tab)
                                .animation(Tokens.Motion.fade, value: model.library.selectionMode)
                                .animation(Tokens.Motion.fade, value: model.isTabBarCompact)
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
        if model.tab == .library, model.library.selectionMode {
            SelectionBar(model: model)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            CompactTabBar(model: model)
                .transition(.move(edge: .bottom).combined(with: .opacity))
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

    private var showsBack: Bool {
        model.canGoBack
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if showsBack {
                Button {
                    Task { await model.goBack() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(Font.mng(15, weight: .semibold))
                        .foregroundStyle(Palette.text2)
                        .frame(width: 36, height: 36)
                        .background(Palette.fill, in: Circle())
                        .overlay {
                            Circle().stroke(Palette.hairline, lineWidth: 0.5)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.back)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(model.title)
                    .font(Font.mng(36, weight: .semibold))
                    .tracking(-0.035)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if !model.library.selectionMode {
                    Text(model.subtitle)
                        .font(Font.mng(13, weight: .medium))
                        .foregroundStyle(Palette.text3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // The right side of the header carries the two controls the
            // native shell keeps there: the server picker in the settings
            // and the multi-select button in the library.
            if model.tab == .settings {
                Button {
                    model.presentConnections()
                } label: {
                    Image(systemName: "cloud.fill")
                        .font(Font.mng(15, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 36, height: 36)
                        .background(Palette.accentSoft, in: Circle())
                        .overlay {
                            Circle().stroke(Palette.hairline, lineWidth: 0.5)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Strings.switchCloud) · \(model.activeCloudLabel)")
            } else if model.tab == .library,
                      model.library.canSelect,
                      !model.library.selectionMode {
                Button {
                    model.library.enterSelection()
                } label: {
                    Text(Strings.select)
                        .font(Font.mng(13, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .padding(.horizontal, 13)
                        .frame(height: 36)
                        .background(Palette.fill, in: Capsule())
                        .overlay {
                            Capsule().stroke(Palette.hairline, lineWidth: 0.5)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.select)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }
}

/// The bottom bar of the compact layout.
///
/// It is a full-width bar with the three tabs and the search circle. While
/// the person walks back in time through the library it collapses into a
/// pill that shows the date of the photos on screen instead of the tab
/// labels, the same way the native shell does.
private struct CompactTabBar: View {
    let model: ShellModel

    /// The bar is a pill while the library is scrolled back in time.
    private var isCompact: Bool { model.isTabBarCompact }

    /// The pill only keeps the tab that is open.
    private var visibleTabs: [ShellTab] {
        guard isCompact else { return ShellTab.tabBarTabs }
        let active = ShellTab.tabBarTabs.first { model.isTabActive($0) }
        return active.map { [$0] } ?? [model.tab]
    }

    /// The date the pill shows instead of the tab labels.
    private var compactLabel: String {
        model.library.timelineTopDate ?? model.subtitle
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(visibleTabs) { tab in
                    let active = model.isTabActive(tab)
                    Button {
                        model.selectTab(tab)
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tab.icon)
                                .font(Font.mng(20, weight: .medium))
                            Text(tab.tabLabel)
                                .font(Font.mng(10, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(active ? Palette.accent : Palette.text3)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
            .padding(4)
            .background(
                Palette.bgElevated,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Palette.hairline, lineWidth: 0.5)
            }

            // The date of the photos on screen, in place of the tab labels
            // while the bar is a pill.
            if isCompact {
                Text(compactLabel)
                    .font(Font.mng(13, weight: .semibold))
                    .foregroundStyle(Palette.text3)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            let searchActive = model.isTabActive(.search)
            Button {
                model.selectTab(.search)
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(Font.mng(19, weight: .medium))
                    .foregroundStyle(searchActive ? Palette.accent : Palette.text2)
                    .frame(width: 44, height: 44)
                    .background(Palette.bgElevated, in: Circle())
                    .overlay {
                        Circle().stroke(Palette.hairline, lineWidth: 0.5)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.navSearch)
            .accessibilityAddTraits(searchActive ? .isSelected : [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
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
