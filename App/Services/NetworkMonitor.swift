import Foundation
import Network

/// The state of the network, watched so the prefetch does not spend the data
/// of the person on a line that asks for care.
///
/// The library prefetches the photos that are about to scroll into view. That
/// is worth the traffic on a home line and on a fast mobile line, but not on
/// a line the system marked as constrained: the person asked for less data.
final class NetworkMonitor: @unchecked Sendable {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "mng.cloud.network")
    private let lock = NSLock()
    private var constrained = false

    /// The system asks to be careful with the data of this connection.
    var isConstrained: Bool {
        lock.lock()
        defer { lock.unlock() }
        return constrained
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.constrained = path.isConstrained
            self.lock.unlock()
        }
        monitor.start(queue: queue)
    }
}
