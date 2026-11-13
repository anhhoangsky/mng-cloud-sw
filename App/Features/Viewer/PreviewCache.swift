import ImageIO
import MNGKit
import UIKit

/// Decoded full-size previews for the viewer.
///
/// The thumbnail cache keeps the timeline small; previews can be several
/// megabytes each, so they live in a separate, smaller cache. Requests are
/// coalesced per path like `ThumbCache`.
///
/// Decoding happens off the main actor and the resulting `UIImage` is backed
/// by an already-decoded `CGImage`, so changing pages only swaps a bitmap.
/// Decoding a 1600px preview while the viewer is animating was the main source
/// of the stutter when swiping between photos.
@MainActor
final class PreviewCache {
    static let shared = PreviewCache()

    private let cache = NSCache<NSString, UIImage>()
    private var inflight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 12
        cache.totalCostLimit = 128 * 1024 * 1024
    }

    /// Synchronous cache probe used while building the page. A neighbour that
    /// was prefetched is ready to draw on the first frame after a swipe.
    func cachedImage(for path: String) -> UIImage? {
        cache.object(forKey: path as NSString)
    }

    func image(for path: String, client: MNGAPIClient) async -> UIImage? {
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        if let running = inflight[path] {
            return await running.value
        }

        let task = Task<UIImage?, Never> { [client] in
            guard let data = try? await client.mediaData(path: path) else {
                return nil
            }
            return await Self.decodeOffMain(data)
        }
        inflight[path] = task
        let image = await task.value
        inflight[path] = nil
        if let image {
            cache.setObject(image, forKey: key, cost: Self.cost(of: image))
        }
        return image
    }

    /// Warm the neighbours of the current page. The requests run one after
    /// another so a swipe never floods the connection, and an already cached
    /// path returns immediately.
    func prefetch(_ paths: [String], client: MNGAPIClient) {
        let missing = paths.filter {
            !$0.isEmpty && cache.object(forKey: $0 as NSString) == nil
                && inflight[$0] == nil
        }
        guard !missing.isEmpty else { return }
        Task { [weak self, client] in
            for path in missing {
                guard let self, !Task.isCancelled else { return }
                _ = await self.image(for: path, client: client)
            }
        }
    }

    func clear() {
        cache.removeAllObjects()
        for task in inflight.values {
            task.cancel()
        }
        inflight.removeAll()
    }

    private static func cost(of image: UIImage) -> Int {
        let width = max(1, image.size.width * image.scale)
        let height = max(1, image.size.height * image.scale)
        return Int(width * height * 4)
    }

    /// Decode and downsample away from the main actor. The server preview is
    /// 1600px, so the bound only guards against a fallback original.
    private nonisolated static func decodeOffMain(_ data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            Signpost.decode("preview-decode") {
                guard let source = CGImageSourceCreateWithData(
                    data as CFData,
                    nil
                ), CGImageSourceGetCount(source) > 0 else {
                    return nil
                }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2400,
                ]
                if let image = CGImageSourceCreateThumbnailAtIndex(
                    source,
                    0,
                    options as CFDictionary
                ) {
                    return UIImage(cgImage: image)
                }
                return UIImage(data: data)
            }
        }.value
    }
}
