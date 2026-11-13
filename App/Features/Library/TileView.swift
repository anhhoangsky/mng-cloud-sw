import MNGKit
import SwiftUI

/// One square library tile with its PWA badges, context menu and optimistic
/// favorite/delete actions. Selection is drawn as a square accent border, the
/// way the iOS library marks a photo; there is no tick or circle overlay.
struct TileView: View {
    let model: ShellModel
    let item: Item
    /// The marquee drag swallows the tap that ends the drag, like the web's
    /// `suppress_click_until` guard.
    var isTapSuppressed: () -> Bool = { false }
    /// Search seeds the viewer with its own result list; Library keeps using
    /// the current timeline page.
    var onOpen: (() -> Void)? = nil

    private var library: LibraryModel { model.library }

    var body: some View {
        Button {
            guard !isTapSuppressed() else { return }
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
            // The square is driven by the aspect ratio, not by the thumbnail,
            // so every row of the grid keeps the same height even while the
            // images load at different sizes.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ZStack(alignment: .topTrailing) {
                        ThumbnailView(
                            client: model.client,
                            path: item.thumbnailPath(size: 360),
                            fallbacks: item.thumbnailFallbackPaths
                        )

                        badges
                    }
                    .clipped()
                }
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
                        .font(Font.mng(12, weight: .semibold))
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
                .font(Font.mng(8, weight: .bold))
            Text(text)
                .font(Font.mng(10, weight: .bold))
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var menu: some View {
        // Native Photos starts the selection from the context menu, so the
        // header does not need a permanent "Chọn" button.
        if library.canSelect {
            Button {
                library.enterSelection()
                library.toggleSelection(item.id)
            } label: {
                Label(Strings.select, systemImage: "checkmark.circle")
            }

            Divider()
        }

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
