import MNGKit
import UIKit

/// Decoded full-size previews for the viewer.
///
/// The thumbnail cache keeps the timeline small; previews can be several
/// megabytes each, so they live in a separate, smaller cache. Requests are
/// coalesced per path like `ThumbCache`.
@MainActor
final class PreviewCache {
    static let shared = PreviewCache()

    private let cache = NSCache<NSString, UIImage>()
    private var inflight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 12
        cache.totalCostLimit = 128 * 1024 * 1024
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
            return UIImage(data: data)
        }
        inflight[path] = task
        let image = await task.value
        inflight[path] = nil
        if let image {
            cache.setObject(image, forKey: key, cost: Self.cost(of: image))
        }
        return image
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
}
