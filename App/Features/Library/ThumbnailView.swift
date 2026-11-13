import MNGKit
import SwiftUI
import UIKit

/// Authenticated thumbnail loader backed by `ThumbCache`.
struct ThumbnailView: View {
    let client: MNGAPIClient
    let path: String
    var contentMode: ContentMode = .fill
    /// Viewer surfaces sit on black, so they pass a dark placeholder instead of
    /// the timeline's default fill.
    var placeholder: Color = Palette.fill

    @State private var image: UIImage?
    @State private var failed = false
    @State private var loadedPath = ""

    var body: some View {
        ZStack {
            placeholder

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else if failed {
                Image(systemName: "photo")
                    .font(Font.mng(18, weight: .regular))
                    .foregroundStyle(Palette.text4)
            }
        }
        .clipped()
        .animation(.easeOut(duration: 0.28), value: image != nil)
        .task(id: path) {
            await load()
        }
    }

    private func load() async {
        guard loadedPath != path else { return }
        image = nil
        failed = false

        // An older row can point at a thumbnail the server has not written
        // yet: `/thumb` answers with its placeholder SVG and a 404 in that
        // window. One failed load used to leave the tile on the fallback icon
        // until the cell was destroyed, so retry with a short backoff while
        // the tile is still on screen. A successful load is cached.
        let delays: [UInt64] = [0, 900_000_000, 3_000_000_000]
        for delay in delays {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
            }
            let data = await ThumbCache.shared.data(
                for: path,
                client: client
            )
            guard !Task.isCancelled else { return }
            if let data,
               let decoded = Signpost.decode(
                   "thumb-decode",
                   { UIImage(data: data) }
               ) {
                image = decoded
                failed = false
                // Only a success pins the path, so scrolling the tile away
                // and back re-attempts a thumbnail that is still missing.
                loadedPath = path
                return
            }
        }
        failed = true
    }
}

/// Shared square/rect placeholder used by skeletons and empty covers.
struct ShimmerTile: View {
    var body: some View {
        Palette.fill
            .overlay {
                LinearGradient(
                    colors: [.clear, Palette.fill2, .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
    }
}
