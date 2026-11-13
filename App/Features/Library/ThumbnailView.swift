import MNGKit
import SwiftUI
import UIKit

/// Authenticated thumbnail loader backed by `ThumbCache`.
struct ThumbnailView: View {
    let client: MNGAPIClient
    let path: String
    /// Preview and original sources tried when `/thumb` has not been
    /// generated yet. The library passes them for photos so an older row
    /// still shows the photo instead of the placeholder icon.
    var fallbacks: [String] = []
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
            } else if failed {
                Image(systemName: "photo")
                    .font(Font.mng(18, weight: .regular))
                    .foregroundStyle(Palette.text4)
            }
        }
        .clipped()
        .task(id: path) {
            await load()
        }
    }

    /// One request per appearance. A failed path is cooled down inside
    /// `ThumbCache`, so scrolling back and forth does not start a retry storm
    /// (and the sleeps and cross-fade that used to judder the album grid are
    /// gone).
    private func load() async {
        guard loadedPath != path else { return }
        image = nil
        failed = false
        let decoded = await ThumbCache.shared.image(
            for: path,
            client: client,
            fallbacks: fallbacks
        )
        guard !Task.isCancelled else { return }
        if let decoded {
            image = decoded
            failed = false
            loadedPath = path
        } else {
            failed = true
        }
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
