import MNGKit
import Observation
import UIKit

/// Session-scoped thumbnail cache. Requests are coalesced per path so a year
/// card and the timeline never download the same cover twice.
@MainActor
final class ThumbCache {
    static let shared = ThumbCache()

    private let cache = NSCache<NSString, NSData>()
    private var inflight: [String: Task<Data?, Never>] = [:]

    private init() {
        cache.countLimit = 512
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func data(for path: String, client: MNGAPIClient) async -> Data? {
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached as Data
        }
        if let running = inflight[path] {
            return await running.value
        }

        let task = Task { [client] in
            try? await client.mediaData(path: path)
        }
        inflight[path] = task
        let data = await task.value
        inflight[path] = nil
        if let data {
            cache.setObject(data as NSData, forKey: key, cost: data.count)
        }
        return data
    }

    func clear() {
        cache.removeAllObjects()
        for task in inflight.values {
            task.cancel()
        }
        inflight.removeAll()
    }

    /// Warm the cache for rows that are about to scroll into view.
    ///
    /// The downloads run one after another so a big library never floods the
    /// connection while the user is still scrolling.
    func prefetch(paths: [String], client: MNGAPIClient) {
        guard !paths.isEmpty else { return }
        Task { [weak self] in
            for path in paths {
                guard let self else { return }
                _ = await self.data(for: path, client: client)
            }
        }
    }
}
