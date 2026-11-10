import MNGKit
import SwiftUI

/// Full-screen viewer overlay: top chrome, media stage, side navigation and
/// the filmstrip/action footer. The PWA keeps the viewer above every shell
/// surface, so this view is rendered at the root of `ShellView`.
struct ViewerView: View {
    let model: ShellModel

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var editingItem: Item?
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
                    chromeHidden: viewer.chromeHidden
                )
                .ignoresSafeArea()
                .zIndex(1)

                topBar(item)
                navigation
                footer(item)
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
        .sheet(item: $editingItem) { item in
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
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .zIndex(6)
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

// MARK: - Footer

private struct ViewerFooter: View {
    let client: MNGAPIClient
    let viewer: ViewerModel
    let item: Item
    let chromeHidden: Bool
    let onSelect: (Int) -> Void

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
                    if item.live, !viewer.liveMode {
                        liveButton
                    }

                    ViewerCircleButton(
                        icon: "arrow.down.to.line",
                        label: Strings.download,
                        action: viewer.downloadCurrent
                    )

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
                viewer.activateLive()
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
            .background(Color.white.opacity(0.14), in: Capsule())
        }
        .buttonStyle(ViewerPressStyle())
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
            kind: .nav,
            action: action
        )
        .opacity(enabled ? 1 : 0)
        .disabled(!enabled)
        .accessibilityHidden(!enabled)
    }
}

private struct ViewerCircleButton: View {
    enum Kind {
        case glass
        case nav
    }

    let icon: String
    var tint: Color = .white
    let label: String
    var kind: Kind = .glass
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)

                Circle()
                    .fill(Color.white.opacity(kind == .nav ? 0.1 : 0.14))

                if kind == .glass {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                }

                Image(systemName: icon)
                    .font(Font.mng(17, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 44, height: 44)
            .shadow(
                color: kind == .glass ? .black.opacity(0.26) : .clear,
                radius: 11,
                x: 0,
                y: 6
            )
        }
        .buttonStyle(ViewerPressStyle())
        .accessibilityLabel(label)
    }
}

private struct ViewerPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
