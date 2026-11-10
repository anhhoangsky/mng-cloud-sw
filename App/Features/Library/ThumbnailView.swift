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
                    .font(.mng(18, weight: .regular))
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

        let data = await ThumbCache.shared.data(for: path, client: client)
        guard !Task.isCancelled else { return }

        if let data, let decoded = Signpost.decode("thumb-decode", { UIImage(data: data) }) {
            image = decoded
            failed = false
        } else {
            failed = true
        }
        loadedPath = path
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
