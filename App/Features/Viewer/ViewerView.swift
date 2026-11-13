import MNGKit
import SwiftUI

/// Full-screen viewer overlay: top chrome, media stage, side navigation and
/// the filmstrip/action footer. The PWA keeps the viewer above every shell
/// surface, so this view is rendered at the root of `ShellView`.
struct ViewerView: View {
    let model: ShellModel

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var editingItem: Item?
    @State private var liveText: LiveTextOutcome?
    @FocusState private var isFocused: Bool

    private var viewer: ViewerModel { model.library.viewer }
    private var isRegular: Bool { sizeClass == .regular }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if let item = viewer.current {
                ViewerStage(
                    model: viewer,
                    client: model.client,
                    server: model.server,
                    item: item,
                    chromeHidden: viewer.chromeHidden,
                    onLiveText: { outcome in
                        withAnimation(Tokens.Motion.fade) {
                            liveText = outcome
                        }
                    }
                )
                .ignoresSafeArea()
                .zIndex(1)

                topBar(item)
                navigation
                footer(item)
                liveTextPanel
            }
        }
        .background(Color.black.ignoresSafeArea())
        .animation(Tokens.Motion.viewer, value: viewer.chromeHidden)
        .focusable()
        .focused($isFocused)
        .onAppear {
            isFocused = true
        }
        // Hardware keyboard: the arrow keys walk the library and Escape closes
        // the viewer, like the web viewer.
        .onKeyPress(.leftArrow) {
            viewer.goPrevious()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            viewer.goNext()
            return .handled
        }
        .onKeyPress(.escape) {
            close()
            return .handled
        }
        .fullScreenCover(item: $editingItem) { item in
            EditorView(model: model, item: item)
        }
    }

    private func topBar(_ item: Item) -> some View {
        ViewerTopBar(
            title: MNGFormat.viewerTitle(item),
            subtitle: MNGFormat.viewerSubtitle(
                item,
                cloud: model.library.cloudLabel(item.cloud)
            ),
            isFavorite: item.favorite,
            chromeHidden: viewer.chromeHidden,
            onClose: close,
            onFavorite: viewer.toggleFavorite,
            onInfo: viewer.openInfo,
            canEdit: canEdit(item),
            onEdit: { editingItem = item }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .zIndex(6)
    }

    /// The web viewer only offers the editor for photos the server can edit.
    private func canEdit(_ item: Item) -> Bool {
        !item.edit.isEmpty && !item.isVideo
    }

    @ViewBuilder
    private var navigation: some View {
        if isRegular {
            HStack(spacing: 0) {
                ViewerNavButton(
                    icon: "chevron.left",
                    label: Strings.viewerPrevious,
                    enabled: viewer.canGoPrevious,
                    action: viewer.goPrevious
                )

                Spacer(minLength: 0)

                ViewerNavButton(
                    icon: "chevron.right",
                    label: Strings.viewerNext,
                    enabled: viewer.canGoNext,
                    action: viewer.goNext
                )
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(viewer.chromeHidden ? 0 : 1)
            .allowsHitTesting(!viewer.chromeHidden)
            .accessibilityHidden(viewer.chromeHidden)
            .zIndex(5)
        }
    }

    private func footer(_ item: Item) -> some View {
        ViewerFooter(
            client: model.client,
            viewer: viewer,
            item: item,
            chromeHidden: viewer.chromeHidden,
            onSelect: { index in
                viewer.select(index: index)
            },
            onShare: {
                viewer.shareCurrent()
            },
            onSave: {
                saveToPhotos(item)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .zIndex(6)
    }

    /// The recognised text of the photo, shown over the image.
    @ViewBuilder
    private var liveTextPanel: some View {
        if let liveText {
            VStack {
                Spacer(minLength: 0)
                LiveTextPanel(outcome: liveText) {
                    withAnimation(Tokens.Motion.fade) {
                        self.liveText = nil
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .zIndex(7)
        }
    }

    /// Save the photo into the system photo library.
    private func saveToPhotos(_ item: Item) {
        guard !item.isVideo else {
            viewer.shareCurrent()
            return
        }
        Task { @MainActor in
            guard let image = await PhotoLibrarySaver.loadImage(
                path: item.mediaPath(),
                client: model.client
            ) else {
                model.notify(Strings.saveToPhotosFailed)
                return
            }
            let saved = await PhotoLibrarySaver.save(image)
            model.notify(saved ? Strings.savedToPhotos : Strings.saveToPhotosFailed)
        }
    }

    private func close() {
        withAnimation(Tokens.Motion.viewer) {
            viewer.close()
        }
    }
}

// MARK: - Top chrome

private struct ViewerTopBar: View {
    let title: String
    let subtitle: String
    let isFavorite: Bool
    let chromeHidden: Bool
    let onClose: () -> Void
    let onFavorite: () -> Void
    let onInfo: () -> Void
    var canEdit = false
    var onEdit: () -> Void = {}

    private let favoriteColor = Color(red: 1, green: 55.0 / 255.0, blue: 95.0 / 255.0)

    var body: some View {
        HStack(spacing: 10) {
            ViewerCircleButton(
                icon: "xmark",
                label: Strings.close,
                action: onClose
            )

            VStack(spacing: 2) {
                Text(title)
                    .font(Font.mng(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(subtitle)
                    .font(Font.mng(11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)

            HStack(spacing: 6) {
                ViewerCircleButton(
                    icon: isFavorite ? "heart.fill" : "heart",
                    tint: isFavorite ? favoriteColor : .white,
                    label: isFavorite ? Strings.unfavorite : Strings.favorite,
                    action: onFavorite
                )

                ViewerCircleButton(
                    icon: "info.circle",
                    label: Strings.info,
                    action: onInfo
                )

                if canEdit {
                    ViewerCircleButton(
                        icon: "pencil",
                        label: Strings.editorEditAction,
                        action: onEdit
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 34)
        .background {
            LinearGradient(
                colors: [.black.opacity(0.72), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
        .opacity(chromeHidden ? 0 : 1)
        .offset(y: chromeHidden ? -16 : 0)
        .allowsHitTesting(!chromeHidden)
        .accessibilityHidden(chromeHidden)
    }
}

// MARK: - Live Text

/// The text Vision found in the photo.
private struct LiveTextPanel: View {
    let outcome: LiveTextOutcome
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "text.viewfinder")
                    .font(Font.mng(13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(Strings.viewerLiveText)
                    .font(Font.mng(13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(Font.mng(11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.close)
            }

            switch outcome {
            case .working:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text(Strings.viewerLiveTextWorking)
                        .font(Font.mng(12))
                        .foregroundStyle(.white.opacity(0.75))
                }
            case .text(let text):
                Text(text)
                    .font(Font.mng(13))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .empty:
                Text(Strings.viewerLiveTextEmpty)
                    .font(Font.mng(12))
                    .foregroundStyle(.white.opacity(0.75))
            case .failed:
                Text(Strings.viewerLiveTextFailed)
                    .font(Font.mng(12))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(14)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.5)
        }
    }
}

// MARK: - Footer

private struct ViewerFooter: View {
    let client: MNGAPIClient
    let viewer: ViewerModel
    let item: Item
    let chromeHidden: Bool
    let onSelect: (Int) -> Void
    let onShare: () -> Void
    let onSave: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            ViewerFilmstrip(
                client: client,
                items: viewer.items,
                index: viewer.index,
                onSelect: onSelect
            )

            HStack(spacing: 12) {
                Spacer(minLength: 0)

                HStack(spacing: 7) {
                    if item.live {
                        liveButton
                    }

                    ViewerCircleButton(
                        icon: "square.and.arrow.up",
                        label: Strings.viewerShare,
                        action: onShare
                    )

                    if !item.isVideo {
                        ViewerCircleButton(
                            icon: "square.and.arrow.down",
                            label: Strings.viewerSaveToPhotos,
                            action: onSave
                        )
                    }

                    ViewerCircleButton(
                        icon: "trash",
                        tint: Palette.danger,
                        label: Strings.delete,
                        action: viewer.deleteCurrent
                    )
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.top, 34)
        .padding(.bottom, 14)
        .background {
            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
        .opacity(chromeHidden ? 0 : 1)
        .offset(y: chromeHidden ? 20 : 0)
        .allowsHitTesting(!chromeHidden)
        .accessibilityHidden(chromeHidden)
    }

    private var liveButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                viewer.toggleLive()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "livephoto")
                    .font(Font.mng(13, weight: .semibold))

                Text(Strings.liveBadge)
                    .font(Font.mng(11, weight: .bold))
                    .tracking(0.55)
            }
            .foregroundStyle(.white)
            .frame(height: 32)
            .padding(.horizontal, 11)
            .background { GlassSurface(shape: Capsule()) }
            .contentShape(Capsule())
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel(Strings.livePhoto)
    }
}

// MARK: - Controls

private struct ViewerNavButton: View {
    let icon: String
    let label: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        ViewerCircleButton(
            icon: icon,
            label: label,
            action: action
        )
        .opacity(enabled ? 1 : 0)
        .disabled(!enabled)
        .accessibilityHidden(!enabled)
    }
}

private struct ViewerCircleButton: View {
    let icon: String
    var tint: Color = .white
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // The same liquid glass as the shell header and the editor:
                // real system glass on iOS 26, the layered rim/ sheen
                // approximation on earlier releases.
                GlassSurface(shape: Circle())

                Image(systemName: icon)
                    .font(Font.mng(17, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(GlassPressStyle(scale: 0.93))
        .accessibilityLabel(label)
    }
}
