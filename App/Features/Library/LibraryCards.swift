import MNGKit
import SwiftUI

/// Year/month bucket card: 1.62-aspect four-cover mosaic plus the bucket's
/// label and item count.
struct BucketCard: View {
    let title: String
    let count: Int64
    let covers: [Item]
    let client: MNGAPIClient
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                CollageView(covers: covers, client: client)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title)
                        .font(Font.mng(22, weight: .semibold))
                        .tracking(-0.02)
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer(minLength: 8)

                    Text(MNGFormat.count(count))
                        .font(Font.mng(12))
                        .foregroundStyle(Palette.text3)
                        .lineLimit(1)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
            }
            .background(Palette.bgElevated2)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.m, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.m, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Four-cover collage: the first cover spans all three rows, the remaining
/// three stack on the right. Missing slots repeat the first cover, matching
/// `collage_covers()` in the PWA.
struct CollageView: View {
    let covers: [Item]
    let client: MNGAPIClient

    private let gap: CGFloat = 2

    var body: some View {
        Color.clear
            .aspectRatio(1.62, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    let leftWidth = max(0, (proxy.size.width - gap) * (1.6 / 2.6))
                    HStack(spacing: gap) {
                        cover(at: 0)
                            .frame(width: leftWidth)
                        VStack(spacing: gap) {
                            cover(at: 1)
                            cover(at: 2)
                            cover(at: 3)
                        }
                    }
                }
            }
            .background(Palette.fill)
            .clipped()
    }

    @ViewBuilder
    private func cover(at index: Int) -> some View {
        if let item = slotItem(index) {
            ThumbnailView(
                client: client,
                path: item.thumbnailPath(size: 360),
                fallbacks: item.thumbnailFallbackPaths
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        } else {
            ZStack {
                Palette.fill2
                Image(systemName: "photo")
                    .font(Font.mng(20, weight: .regular))
                    .foregroundStyle(Palette.text4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func slotItem(_ index: Int) -> Item? {
        guard !covers.isEmpty else { return nil }
        return covers[min(index, covers.count - 1)]
    }
}
