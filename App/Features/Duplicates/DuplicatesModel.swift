import Foundation
import MNGKit
import Observation

/// Legacy duplicate browser: the server returns every group, while the sheet
/// reveals 30 at a time like `DUP_PAGE` in the PWA.
@MainActor
@Observable
final class DuplicatesModel {
    static let pageSize = 30

    enum State: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    let client: MNGAPIClient

    private(set) var state: State = .idle
    private(set) var groups: [DuplicateGroup] = []
    private(set) var stats = DuplicateStats()
    private(set) var shown = 0

    var onUnauthorized: (() -> Void)?

    @ObservationIgnored private var requestSeq = 0

    init(client: MNGAPIClient) {
        self.client = client
    }

    var visibleGroups: [DuplicateGroup] {
        Array(groups.prefix(shown))
    }

    var remaining: Int {
        max(0, groups.count - shown)
    }

    /// `open_duplicates`: every open reloads from scratch and resets paging.
    func load() async {
        requestSeq &+= 1
        let seq = requestSeq
        state = .loading
        groups = []
        stats = DuplicateStats()
        shown = 0
        do {
            let data = try await client.duplicates()
            guard seq == requestSeq else { return }
            groups = data.groups
            stats = data.stats
            shown = min(data.groups.count, Self.pageSize)
            state = .ready
        } catch let error as APIError {
            guard seq == requestSeq else { return }
            if error.status == 401 {
                state = .idle
                onUnauthorized?()
                return
            }
            state = .failed(error.message)
        } catch {
            guard seq == requestSeq else { return }
            state = .failed(APIMessages.network)
        }
    }

    /// `expand_duplicates`: reveal the next 30 groups.
    func expand() {
        shown = min(shown + Self.pageSize, groups.count)
    }
}
