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
}
