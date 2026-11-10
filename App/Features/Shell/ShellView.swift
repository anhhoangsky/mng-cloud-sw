import MNGKit
import SwiftUI

/// Authenticated shell: a four-tab compact layout on iPhone and a 264 pt
/// sidebar on iPad, mirroring the PWA's `shell.rs` breakpoints.
struct ShellView: View {
    @State private var model: ShellModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(store: SessionStore) {
        _model = State(initialValue: ShellModel(store: store))
    }

    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.bgGrouped.ignoresSafeArea()

            if isCompact {
                VStack(spacing: 0) {
                    CompactShellHeader(model: model)
                    content
                }
                .overlay(alignment: .bottom) {
                    compactBottomChrome
                        .animation(Tokens.Motion.fade, value: model.tab)
                        .animation(Tokens.Motion.fade, value: model.library.selectionMode)
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
        .sheet(isPresented: $model.isCloudPickerPresented) {
            CloudPickerSheet(model: model)
        }
        .sheet(item: shareBinding) { file in
            ActivityView(url: file.url)
                .ignoresSafeArea()
        }
        .task {
            await model.start()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.tab {
        case .library:
            LibraryView(model: model)
        case .settings:
            SettingsView(model: model)
        case .albums, .search, .vault:
            PlaceholderPage(tab: model.tab)
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
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
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
}

// MARK: - Compact chrome

private struct CompactShellHeader: View {
    let model: ShellModel

    private var showsBack: Bool {
        model.tab == .library && model.library.filters.hasDateFilter
    }

    private var showsSelect: Bool {
        model.tab == .library
            && model.library.canSelect
            && !model.library.selectionMode
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if showsBack {
                Button {
                    Task { await model.library.goBack() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.text2)
                        .frame(width: 36, height: 36)
                        .background(Palette.fill, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.back)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(model.title)
                    .font(.system(size: 36, weight: .semibold))
                    .tracking(-0.03)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if !model.library.selectionMode {
                    Text(model.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.text3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsSelect {
                Button(Strings.select) {
                    model.library.enterSelection()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, 4)
                .frame(minHeight: 36)
                .buttonStyle(.plain)
            }

            Button {
                model.isCloudPickerPresented = true
            } label: {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 36, height: 36)
                    .background(Palette.accentSoft, in: Circle())
                    .overlay {
                        Circle().stroke(Palette.hairline, lineWidth: 0.5)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(Strings.switchCloud) · \(model.activeCloudLabel)")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }
}

private struct CompactTabBar: View {
    let model: ShellModel

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(ShellTab.tabBarTabs) { tab in
                    Button {
                        model.selectTab(tab)
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 21, weight: .medium))
                            Text(tab.tabLabel)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(model.tab == tab ? Palette.accent : Palette.text3)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.tab == tab ? .isSelected : [])
                }
            }
            .padding(5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().stroke(Palette.hairline, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.16), radius: 18, y: 8)

            Button {
                model.selectTab(.search)
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(model.tab == .search ? Palette.accent : Palette.text2)
                    .frame(width: 60, height: 60)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle().stroke(Palette.hairline, lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.navSearch)
        }
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
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(-0.015)
                        .foregroundStyle(Palette.text)
                    Text(Strings.brandSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.text3)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 2)
            .padding(.bottom, 22)

            ForEach(ShellTab.sidebarTabs) { tab in
                Button {
                    model.selectTab(tab)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 22)
                        Text(tab.label)
                            .font(.system(size: 14, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(model.tab == tab ? Palette.accent : Palette.text2)
                    .padding(.horizontal, 10)
                    .frame(height: 40)
                    .background(
                        model.tab == tab ? Palette.accentSoft : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.tab == tab ? .isSelected : [])
            }

            Spacer(minLength: 16)

            cloudCard
                .padding(.bottom, 10)

            Text(model.sidebarFoot)
                .font(.system(size: 11))
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
            model.isCloudPickerPresented = true
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Palette.accentSoft)
                            .frame(width: 30, height: 30)
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.activeCloudLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                        Text(model.cloudSubtitleText)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.text3)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.text4)
                }

                HStack(spacing: 6) {
                    Text(MNGFormat.count(model.activeCloudTotal))
                    Spacer(minLength: 4)
                    if let free = model.storageFreeText {
                        Text(free)
                    }
                }
                .font(.system(size: 11))
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
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.bg)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Palette.text, in: Capsule())
            .shadow(color: .black.opacity(0.24), radius: 16, y: 8)
            .accessibilityAddTraits(.isStaticText)
    }
}

private struct CloudPickerSheet: View {
    let model: ShellModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if model.clouds.isEmpty {
                    Text(Strings.connecting)
                        .foregroundStyle(Palette.text3)
                } else {
                    Section {
                        ForEach(model.clouds, id: \.key) { cloud in
                            Button {
                                Task {
                                    await model.switchCloud(cloud.key)
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "cloud.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(
                                            cloud.key == model.activeCloud
                                                ? Palette.accent
                                                : Palette.text3
                                        )
                                        .frame(width: 26)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(cloud.label.isEmpty ? cloud.key : cloud.label)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(Palette.text)
                                        Text(model.cloudSubtitle(for: cloud))
                                            .font(.system(size: 12))
                                            .foregroundStyle(Palette.text3)
                                    }

                                    Spacer(minLength: 8)

                                    Text(MNGFormat.count(cloud.counts.total))
                                        .font(.system(size: 12))
                                        .foregroundStyle(Palette.text3)

                                    if cloud.key == model.activeCloud {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(Palette.accent)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bgGrouped)
            .navigationTitle(Strings.switchCloud)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Strings.close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
