import Foundation
import MNGKit
import Observation

/// Administration console: the user list and every account mutation the
/// server exposes under `/v1/admin`.
///
/// The screen is mounted lazily from Settings, so opening the app never calls
/// the admin API.
@MainActor
@Observable
final class AdminModel {
    enum State: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    let client: MNGAPIClient

    private(set) var state: State = .idle
    private(set) var users: [AdminUser] = []
    private(set) var isWorking = false
    private(set) var error = ""
    private(set) var notice = ""

    var onToast: ((String) -> Void)?
    var onUnauthorized: (() -> Void)?

    @ObservationIgnored private var loadSeq = 0

    init(client: MNGAPIClient) {
        self.client = client
    }

    // MARK: - List

    func load() async {
        loadSeq &+= 1
        let seq = loadSeq
        state = .loading
        do {
            let response = try await client.adminUsers()
            guard seq == loadSeq else { return }
            users = response.users
            state = .ready
        } catch let error as APIError {
            guard seq == loadSeq else { return }
            if error.status == 401 {
                onUnauthorized?()
                return
            }
            state = .failed(error.message)
        } catch {
            guard seq == loadSeq else { return }
            state = .failed(APIMessages.network)
        }
    }

    // MARK: - Mutations

    /// Create one user. The server answers with the new account and, when
    /// `provision` is set, the result of every cloud account.
    func create(
        username: String,
        displayName: String,
        password: String,
        provision: Bool
    ) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        error = ""
        do {
            let response = try await client.createAdminUser(
                username: username,
                displayName: displayName,
                password: password,
                provision: provision
            )
            isWorking = false
            notice = Strings.adminCreated(username)
            onToast?(notice)
            await load()
            return response.user != nil
        } catch let error as APIError {
            isWorking = false
            if error.status == 401 {
                onUnauthorized?()
                return false
            }
            self.error = error.message
            onToast?(error.message)
            return false
        } catch {
            isWorking = false
            self.error = Strings.adminCreateFailed
            onToast?(self.error)
            return false
        }
    }

    func resetPassword(for user: AdminUser, password: String) async {
        await mutate(Strings.adminPasswordUpdated(user.username)) {
            try await self.client.resetAdminUserPassword(id: user.id, password: password)
        }
    }

    func reprovision(for user: AdminUser, password: String) async {
        await mutate(Strings.adminReprovisioned(user.username)) {
            try await self.client.reprovisionAdminUser(id: user.id, password: password)
        }
    }

    func setActive(_ active: Bool, for user: AdminUser) async {
        let message = active
            ? Strings.adminUnlocked(user.username)
            : Strings.adminLocked(user.username)
        await mutate(message) {
            try await self.client.updateAdminUser(
                id: user.id,
                displayName: nil,
                active: active,
                isAdmin: nil
            )
        }
    }

    func setAdmin(_ isAdmin: Bool, for user: AdminUser) async {
        let message = isAdmin
            ? Strings.adminGranted(user.username)
            : Strings.adminRevoked(user.username)
        await mutate(message) {
            try await self.client.updateAdminUser(
                id: user.id,
                displayName: nil,
                active: nil,
                isAdmin: isAdmin
            )
        }
    }

    func rename(_ displayName: String, for user: AdminUser) async {
        await mutate(Strings.adminRenamed(user.username)) {
            try await self.client.updateAdminUser(
                id: user.id,
                displayName: displayName,
                active: nil,
                isAdmin: nil
            )
        }
    }

    func delete(_ user: AdminUser, deleteCloudData: Bool) async {
        await mutate(Strings.adminDeleted(user.username)) {
            try await self.client.deleteAdminUser(
                id: user.id,
                deleteCloudData: deleteCloudData
            )
        }
    }

    func scan(_ user: AdminUser) async {
        guard !isWorking else { return }
        isWorking = true
        error = ""
        do {
            _ = try await client.scanAdminUser(id: user.id)
            isWorking = false
            notice = Strings.adminScanQueued(user.username)
            onToast?(notice)
        } catch let error as APIError {
            isWorking = false
            if error.status == 401 {
                onUnauthorized?()
                return
            }
            self.error = error.message
            onToast?(error.message)
        } catch {
            isWorking = false
            self.error = Strings.adminScanFailed
            onToast?(self.error)
        }
    }

    /// Run one admin mutation and refresh the list.
    private func mutate(
        _ message: String,
        _ operation: () async throws -> AdminMutationResponse
    ) async {
        guard !isWorking else { return }
        isWorking = true
        error = ""
        do {
            _ = try await operation()
            isWorking = false
            notice = message
            onToast?(message)
            await load()
        } catch let apiError as APIError {
            isWorking = false
            if apiError.status == 401 {
                onUnauthorized?()
                return
            }
            error = apiError.message
            onToast?(apiError.message)
        } catch {
            isWorking = false
            self.error = Strings.adminActionFailed
            onToast?(self.error)
        }
    }
}
