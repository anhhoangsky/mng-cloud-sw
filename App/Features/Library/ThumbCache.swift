import ImageIO
import MNGKit
import Observation
import UIKit

/// Session-scoped thumbnail cache.
///
/// Requests are coalesced per path so a year card and the timeline never
/// download the same cover twice. The cache stores decoded images, not the
/// compressed bytes: a tile that scrolls back into view can draw immediately
/// instead of decoding on the main thread during a scroll.
@MainActor
final class ThumbCache {
    static let shared = ThumbCache()

    /// One thumbnail to warm, plus the preview/original paths that stand in
    /// while the server has not written the real thumbnail yet.
    struct Request {
        let path: String
        let fallbacks: [String]
    }

    private let images = NSCache<NSString, UIImage>()
    private var inflight: [String: Task<UIImage?, Never>] = [:]
    /// A path that failed every source is left alone for a while, so a scroll
    /// over a row of older photos cannot fire the same 404s on every pass.
    private var cooldownUntil: [String: TimeInterval] = [:]
    private let cooldown: TimeInterval = 25

    private init() {
        images.countLimit = 400
        images.totalCostLimit = 96 * 1024 * 1024
    }

    /// Synchronous probe for a bitmap that is already decoded. The viewer
    /// uses it to put a real frame on screen before the async preview lands.
    func cachedImage(for path: String) -> UIImage? {
        images.object(forKey: path as NSString)
    }

    /// Load and decode one thumbnail. When the thumbnail route answers 404
    /// (the worker has not generated it yet) the fallback paths are tried in
    /// order; a preview or the original still gives the person a real photo.
    func image(
        for path: String,
        client: MNGAPIClient,
        fallbacks: [String] = [],
        cooldownOnFailure: Bool = true
    ) async -> UIImage? {
        let key = path as NSString
        if let cached = images.object(forKey: key) {
            return cached
        }
        if isCoolingDown(path) {
            return nil
        }
        if let running = inflight[path] {
            let image = await running.value
            if image == nil, cooldownOnFailure {
                startCooldown(path)
            }
            return image
        }

        let task = Task<UIImage?, Never> { [client] in
            if let data = try? await client.mediaData(path: path),
               let decoded = await ThumbCache.decodeOffMain(data) {
                return decoded
            }
            for fallback in fallbacks where !fallback.isEmpty && fallback != path {
                guard !Task.isCancelled else { return nil }
                if let data = try? await client.mediaData(path: fallback),
                   let decoded = await ThumbCache.decodeOffMain(data) {
                    return decoded
                }
            }
            return nil
        }
        inflight[path] = task
        let image = await task.value
        inflight[path] = nil
        if let image {
            images.setObject(image, forKey: key, cost: Self.cost(of: image))
            cooldownUntil[path] = nil
        } else if cooldownOnFailure {
            startCooldown(path)
        }
        return image
    }

    func clear() {
        images.removeAllObjects()
        for task in inflight.values {
            task.cancel()
        }
        inflight.removeAll()
        cooldownUntil.removeAll()
    }

    /// Warm the cache for rows that are about to scroll into view.
    ///
    /// The downloads run one after another so a big library never floods the
    /// connection while the user is still scrolling. A prefetch failure does
    /// not start the cooldown: the visible tile may still find the photo
    /// through a larger fallback path.
    func prefetch(_ requests: [Request], client: MNGAPIClient) {
        guard !requests.isEmpty else { return }
        Task { [weak self] in
            for request in requests {
                guard let self, !Task.isCancelled else { return }
                _ = await self.image(
                    for: request.path,
                    client: client,
                    fallbacks: request.fallbacks,
                    cooldownOnFailure: false
                )
            }
        }
    }

    private func isCoolingDown(_ path: String) -> Bool {
        guard let until = cooldownUntil[path] else { return false }
        if until <= Date().timeIntervalSince1970 {
            cooldownUntil[path] = nil
            return false
        }
        return true
    }

    private func startCooldown(_ path: String) {
        cooldownUntil[path] = Date().timeIntervalSince1970 + cooldown
        // The dictionary only holds temporary failures; keep a scroll over a
        // huge library from growing it without bound.
        if cooldownUntil.count > 400 {
            let now = Date().timeIntervalSince1970
            cooldownUntil = cooldownUntil.filter { $0.value > now }
        }
    }

    private static func cost(of image: UIImage) -> Int {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        return max(1, Int(width * height * 4))
    }

    /// Decode and downsample away from the main actor. ImageIO reads HEIC and
    /// WebP too, and bounding the bitmap means an original fallback cannot
    /// allocate tens of megabytes inside a grid.
    private nonisolated static func decodeOffMain(_ data: Data) async -> UIImage? {
        await Task.detached(priority: .utility) {
            Signpost.decode("thumb-decode") {
                guard let source = CGImageSourceCreateWithData(
                    data as CFData,
                    nil
                ), CGImageSourceGetCount(source) > 0 else {
                    return nil
                }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 480,
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
