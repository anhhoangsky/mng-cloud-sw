import Foundation
import MNGKit
import Observation

/// iCloud status for the Connections sheet. P5 only reads and classifies the
/// server state; the importer actions arrive in P7.
@MainActor
@Observable
final class ICloudModel {
    enum State: Equatable {
        /// No status request has completed yet.
        case unknown
        /// The server answered with its real account/job state.
        case ready(IcloudStatus)
        /// The server has no iCloud endpoints yet (404/405/501).
        case unsupported(String)
        /// The feature exists but cannot be reached right now.
        case unavailable(String)
    }

    enum Dot {
        case none
        case ok
        case warn
        case bad
    }

    struct Row {
        let subtitle: String
        let value: String
        let dot: Dot
    }

    let client: MNGAPIClient
    private(set) var state: State = .unknown
    private(set) var isLoading = false

    var onUnauthorized: (() -> Void)?

    @ObservationIgnored private var requestSeq = 0

    init(client: MNGAPIClient) {
        self.client = client
    }

    var status: IcloudStatus? {
        if case .ready(let status) = state { return status }
        return nil
    }

    var appleID: String { status?.appleID ?? "" }
    var isConfigured: Bool { status?.configured ?? false }
    var isAuthenticated: Bool { status?.authenticated ?? false }

    /// Copy used by the Connections row and the iCloud detail card.
    var row: Row {
        switch state {
        case .unknown:
            return Row(
                subtitle: Strings.icloudUnknown,
                value: Strings.icloudStatusUnknown,
                dot: .none
            )
        case .ready(let status) where !status.configured:
            return Row(
                subtitle: Strings.icloudNotConfigured,
                value: Strings.icloudStatusNotConfigured,
                dot: .warn
            )
        case .ready(let status) where status.authenticated:
            return Row(
                subtitle: Strings.icloudConnected,
                value: Strings.icloudStatusConnected,
                dot: .ok
            )
        case .ready:
            return Row(
                subtitle: Strings.icloudDisconnected,
                value: Strings.icloudStatusUnknown,
                dot: .none
            )
        case .unsupported:
            return Row(
                subtitle: Strings.icloudUnsupported,
                value: Strings.icloudStatusUnsupported,
                dot: .warn
            )
        case .unavailable(let message):
            let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return Row(
                subtitle: text.isEmpty ? Strings.icloudUnavailable : text,
                value: Strings.icloudStatusUnavailable,
                dot: .bad
            )
        }
    }

    func load() async {
        requestSeq &+= 1
        let seq = requestSeq
        isLoading = true
        do {
            let status = try await client.icloudStatus()
            guard seq == requestSeq else { return }
            isLoading = false
            state = .ready(status)
        } catch let error as APIError {
            guard seq == requestSeq else { return }
            isLoading = false
            if error.status == 401 {
                onUnauthorized?()
                return
            }
            state = classify(error)
        } catch {
            guard seq == requestSeq else { return }
            isLoading = false
            state = .unavailable(APIMessages.network)
        }
    }

    private func classify(_ error: APIError) -> State {
        switch error.status {
        case 404, 405, 501:
            return .unsupported(Strings.icloudUnsupported)
        case 0:
            return .unavailable(APIMessages.network)
        default:
            let text = error.message.trimmingCharacters(in: .whitespacesAndNewlines)
            return .unavailable(text.isEmpty ? Strings.icloudUnavailable : text)
        }
    }
}
