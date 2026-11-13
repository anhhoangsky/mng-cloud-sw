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

    var errorMessage: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    /// `open_duplicates`: every open reloads from scratch and resets paging.
    ///
    /// The previous result stays in place while the refresh is in flight.
    /// Clearing it up front used to empty the list the instant the sheet
    /// appeared for the second time, which left the old rows looking at a
    /// collection that no longer had those indexes.
    func load() async {
        requestSeq &+= 1
        let seq = requestSeq
        state = .loading
        do {
            let data = try await client.duplicates()
            guard seq == requestSeq else { return }
            groups = data.groups
            stats = data.stats
            shown = min(data.groups.count, Self.pageSize)
            state = .ready
        } catch let error as APIError {
            guard seq == requestSeq, !Task.isCancelled else { return }
            if error.status == 401 {
                state = .idle
                onUnauthorized?()
                return
            }
            state = .failed(error.message)
        } catch {
            // Dismissing the sheet cancels the task. That cancellation is not
            // a failed refresh and must not overwrite the result.
            guard seq == requestSeq, !Task.isCancelled else { return }
            state = .failed(APIMessages.network)
        }
    }

    /// `expand_duplicates`: reveal the next 30 groups.
    func expand() {
        shown = min(shown + Self.pageSize, groups.count)
    }
}
