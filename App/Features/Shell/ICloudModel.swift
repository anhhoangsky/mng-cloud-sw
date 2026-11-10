import Foundation
import MNGKit
import Observation

/// iCloud importer (`mngd` → the Python worker).
///
/// The sheet polls the status every 2.2 seconds while a job is running and
/// stops as soon as it closes.
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

    /// Poll interval of the web client (`POLL_MS`).
    static let pollSeconds: TimeInterval = 2.2

    let client: MNGAPIClient

    private(set) var state: State = .unknown
    private(set) var isLoading = false
    private(set) var isWorking = false
    private(set) var actionError = ""
    private(set) var notice = ""

    /// Form state. The Apple ID field is prefilled from the server status.
    var appleID = ""
    var password = ""
    var mfaCode = ""
    var recent: Int64 = 200
    var deleteAfter = false

    var onToast: ((String) -> Void)?
    var onUnauthorized: (() -> Void)?

    @ObservationIgnored private var requestSeq = 0
    @ObservationIgnored private var saveSeq = 0
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init(client: MNGAPIClient) {
        self.client = client
    }

    // MARK: - State

    var status: IcloudStatus? {
        if case .ready(let status) = state { return status }
        return nil
    }

    var appleIDHint: String {
        status?.appleID ?? ""
    }

    var isConfigured: Bool {
        status?.configured ?? false
    }

    var isAuthenticated: Bool {
        status?.authenticated ?? false
    }

    /// The job the sheet renders: the active one, then the download, then the
    /// authentication job.
    var job: IcloudJob? {
        status?.job
    }

    var isWorkingJob: Bool {
        job?.isActive ?? false
    }

    /// True when the server waits for the two-factor code.
    var needsMFA: Bool {
        job?.state == "awaiting_mfa"
    }

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
            syncForm(status)
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

    /// Keep the form in sync with the server without overwriting what the user
    /// typed.
    private func syncForm(_ status: IcloudStatus) {
        if appleID.isEmpty {
            appleID = status.appleID
        }
        recent = status.settings.recent
        deleteAfter = status.settings.deleteAfter
    }

    // MARK: - Polling

    /// Poll the status while a job is running.
    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: UInt64(ICloudModel.pollSeconds * 1_000_000_000)
                )
                guard !Task.isCancelled else { return }
                guard let self else { return }
                await self.load()
                if !self.isWorkingJob {
                    return
                }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Actions

    /// Log in with the Apple ID and the password.
    func login() async {
        guard !isWorking else { return }
        isWorking = true
        actionError = ""
        do {
            _ = try await client.icloudLogin(
                appleID: appleID.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            password = ""
            isWorking = false
            await load()
            startPolling()
        } catch let error as APIError {
            isWorking = false
            if error.status == 401 {
                onUnauthorized?()
                return
            }
            actionError = actionMessage(error)
        } catch {
            isWorking = false
            actionError = Strings.icloudUnavailable
        }
    }

    /// Answer the two-factor prompt.
    func submitMFA() async {
        guard !isWorking else { return }
        isWorking = true
        actionError = ""
        do {
            _ = try await client.icloudMFA(code: mfaCode.trimmingCharacters(in: .whitespacesAndNewlines))
            mfaCode = ""
            isWorking = false
            await load()
            startPolling()
        } catch let error as APIError {
            isWorking = false
            if error.status == 401 {
                onUnauthorized?()
                return
            }
            actionError = actionMessage(error)
        } catch {
            isWorking = false
            actionError = Strings.icloudUnavailable
        }
    }

    /// Store the importer settings.
    func save() async {
        guard !isWorking else { return }
        saveSeq &+= 1
        let seq = saveSeq
        isWorking = true
        actionError = ""
        do {
            _ = try await client.icloudSave(
                appleID: appleID.trimmingCharacters(in: .whitespacesAndNewlines),
                recent: recent,
                deleteAfter: deleteAfter
            )
            guard seq == saveSeq else { return }
            isWorking = false
            await load()
        } catch let error as APIError {
            guard seq == saveSeq else { return }
            isWorking = false
            if error.status == 401 {
                onUnauthorized?()
                return
            }
            actionError = actionMessage(error)
        } catch {
            guard seq == saveSeq else { return }
            isWorking = false
            actionError = Strings.icloudUnavailable
        }
    }

    /// Queue the import job.
    func start() async {
        guard !isWorking else { return }
        isWorking = true
        actionError = ""
        do {
            _ = try await client.icloudStart(recent: recent, deleteAfter: deleteAfter)
            isWorking = false
            await load()
            startPolling()
        } catch let error as APIError {
            isWorking = false
            if error.status == 401 {
                onUnauthorized?()
                return
            }
            actionError = actionMessage(error)
        } catch {
            isWorking = false
            actionError = Strings.icloudUnavailable
        }
    }

    /// Pause, resume or cancel the running job.
    func control(_ command: String) async {
        guard let job, !isWorking else { return }
        isWorking = true
        actionError = ""
        do {
            _ = try await client.icloudControl(command: command, jobID: job.id)
            isWorking = false
            await load()
            startPolling()
        } catch let error as APIError {
            isWorking = false
            if error.status == 401 {
                onUnauthorized?()
                return
            }
            actionError = actionMessage(error)
        } catch {
            isWorking = false
            actionError = Strings.icloudUnavailable
        }
    }

    /// Forget the Apple ID session on the server.
    func logout() async {
        guard !isWorking else { return }
        isWorking = true
        actionError = ""
        do {
            _ = try await client.icloudLogout()
            isWorking = false
            password = ""
            mfaCode = ""
            notice = Strings.icloudLoggedOut
            await load()
        } catch let error as APIError {
            isWorking = false
            if error.status == 401 {
                onUnauthorized?()
                return
            }
            actionError = actionMessage(error)
        } catch {
            isWorking = false
            actionError = Strings.icloudUnavailable
        }
    }

    // MARK: - Copy

    /// The label of a job state, matching the web client.
    static func jobStateLabel(_ state: String) -> String {
        switch state {
        case "queued": return Strings.icloudStateQueued
        case "running": return Strings.icloudStateRunning
        case "awaiting_mfa": return Strings.icloudStateAwaitingMFA
        case "awaiting_password": return Strings.icloudStateAwaitingPassword
        case "paused": return Strings.icloudStatePaused
        case "importing": return Strings.icloudStateImporting
        case "done": return Strings.icloudStateDone
        case "error": return Strings.icloudStateError
        case "cancelled": return Strings.icloudStateCancelled
        case "auth_required": return Strings.icloudStateAuthRequired
        case "authenticated": return Strings.icloudStateAuthenticated
        default: return Strings.icloudStateWaiting
        }
    }

    private func classify(_ error: APIError) -> State {
        switch error.status {
        case 404, 405, 501:
            return .unsupported(Strings.icloudUnsupportedServer)
        case 0:
            return .unavailable(Strings.icloudNetworkFailed)
        default:
            let message = error.message.trimmingCharacters(in: .whitespacesAndNewlines)
            return .unavailable(
                message.isEmpty ? Strings.icloudCheckFailed : message
            )
        }
    }

    private func actionMessage(_ error: APIError) -> String {
        switch error.status {
        case 0:
            return Strings.icloudNetworkFailed
        case 404, 405, 501:
            return Strings.icloudUnsupportedAction
        default:
            let message = error.message.trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty
                ? String(format: Strings.icloudServerError, error.status)
                : message
        }
    }
}
