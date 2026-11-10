import MNGKit
import SwiftUI

/// One square library tile with its PWA badges, selection check, context menu
/// and optimistic favorite/delete actions.
struct TileView: View {
    let model: ShellModel
    let item: Item
    /// Search seeds the viewer with its own result list; Library keeps using
    /// the current timeline page.
    var onOpen: (() -> Void)? = nil

    private var library: LibraryModel { model.library }

    var body: some View {
        Button {
            if library.selectionMode {
                withAnimation(Tokens.Motion.fade) {
                    library.toggleSelection(item.id)
                }
            } else if let onOpen {
                onOpen()
            } else {
                library.openViewer(item)
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                ThumbnailView(
                    client: model.client,
                    path: item.thumbnailPath(size: 360)
                )

                badges

                if library.selectionMode {
                    selectionCheck
                        .padding(7)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .background(Palette.fill)
            .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
            .overlay {
                if library.isSelected(item.id) {
                    Rectangle()
                        .stroke(Palette.accent, lineWidth: 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(library.isSelected(item.id) ? .isSelected : [])
        // A light tap when the tile enters or leaves the selection.
        .sensoryFeedback(.selection, trigger: library.isSelected(item.id))
        .contextMenu {
            if !library.selectionMode {
                menu
            }
        }
    }

    private var badges: some View {
        VStack {
            Spacer(minLength: 0)
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
            .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
        }
        .allowsHitTesting(false)
    }

    private func badge(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(.white)
    }

    private var selectionCheck: some View {
        ZStack {
            Circle()
                .fill(
                    library.isSelected(item.id)
                        ? Palette.accent
                        : Color.white.opacity(0.18)
                )
            Circle()
                .stroke(.white, lineWidth: 2)
            if library.isSelected(item.id) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .shadow(color: .black.opacity(0.28), radius: 4, y: 1)
    }

    @ViewBuilder
    private var menu: some View {
        Button {
            library.toggleFavorite(item)
        } label: {
            Label(
                item.favorite ? Strings.unfavorite : Strings.favorite,
                systemImage: item.favorite ? "heart.fill" : "heart"
            )
        }

        Button {
            library.download(item)
        } label: {
            Label(Strings.download, systemImage: "arrow.down.to.line")
        }

        Button {
            library.openInfo(item)
        } label: {
            Label(Strings.info, systemImage: "info.circle")
        }

        Button {
            model.requestVaultMove([item.id])
        } label: {
            Label(Strings.moveToVault, systemImage: "lock")
        }

        Divider()

        Button(role: .destructive) {
            library.requestDelete(items: [item])
        } label: {
            Label(Strings.delete, systemImage: "trash")
        }
    }

    private var accessibilityLabel: String {
        let kind = item.isVideo ? Strings.kindVideo : Strings.kindPhoto
        let date = item.year > 0 && item.month > 0
            ? "\(item.day)/\(item.month)/\(item.year)"
            : Strings.shortUnknownDate
        var label = "\(kind) \(item.name), \(date)"
        if item.isVideo {
            label += ", \(MNGFormat.duration(item.duration))"
        }
        if item.live {
            label += ", Live Photo"
        }
        return label
    }
}
