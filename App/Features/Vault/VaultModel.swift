import Foundation
import MNGCore
import MNGKit
import Observation

/// Native client-side encrypted vault (`mng-vault/v1`).
///
/// The password only derives an AES-256-GCM key with PBKDF2-SHA256 on the
/// device. The server relays the public KDF parameters and the raw
/// `iv || ciphertext || tag` blobs; manifests and chunks are decrypted here
/// and never leave the app.
@MainActor
@Observable
final class VaultModel {
    enum Screen: Equatable {
        case list
        case unlock(NativeVault)
        case browse(NativeVault)
    }

    /// The PWA locks an idle vault after 15 minutes.
    static let idleLockSeconds: TimeInterval = 15 * 60
    static let idleCheckSeconds: TimeInterval = 15

    let client: MNGAPIClient

    private(set) var screen: Screen = .list
    private(set) var vaults: [NativeVault] = []
    private(set) var isLoadingList = false
    private(set) var listError = ""
    private(set) var isUnlocking = false
    private(set) var unlockError = ""
    private(set) var manifest: VaultManifest?
    private(set) var folder: String?
    private(set) var search = ""
    private(set) var notice = ""
    private(set) var operationError = ""
    private(set) var isWorking = false

    var onToast: ((String) -> Void)?
    var onUnauthorized: (() -> Void)?

    @ObservationIgnored private var key: VaultKey?
    @ObservationIgnored private var lastActivity = Date()
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var listSeq = 0
    /// Invalidates a pending derivation when the vault is locked or the tab
    /// is left, like the PWA's `unlock_seq`.
    @ObservationIgnored private var unlockSeq = 0

    init(client: MNGAPIClient) {
        self.client = client
    }

    // MARK: - Vault list

    /// Load every vault of the current owner. The list is empty until the
    /// server answers, exactly like the PWA.
    func loadVaults() async {
        listSeq &+= 1
        let seq = listSeq
        isLoadingList = true
        do {
            let response = try await client.nativeVaults()
            guard seq == listSeq else { return }
            isLoadingList = false
            listError = ""
            vaults = response.vaults
        } catch let error as APIError {
            guard seq == listSeq else { return }
            isLoadingList = false
            if error.status == 401 {
                onUnauthorized?()
                return
            }
            listError = error.message
        } catch {
            guard seq == listSeq else { return }
            isLoadingList = false
            listError = APIMessages.network
        }
    }

    /// Open one vault and ask for its password.
    func select(_ vault: NativeVault) {
        unlockError = ""
        screen = .unlock(vault)
    }

    func backToList() {
        lock()
    }

    /// Drop the derived key and every decrypted byte.
    func lock() {
        unlockSeq &+= 1
        key = nil
        manifest = nil
        folder = nil
        search = ""
        notice = ""
        operationError = ""
        isUnlocking = false
        idleTask?.cancel()
        idleTask = nil
        screen = .list
    }

    // MARK: - Unlock and create

    /// Derive the key, verify the password against the stored verifier and
    /// decrypt the manifest.
    func unlock(vault: NativeVault, password: String) async {
        guard !isUnlocking else { return }
        guard !password.isEmpty else {
            unlockError = Strings.vaultPasswordMissing
            return
        }
        isUnlocking = true
        unlockError = ""
        markActivity()
        unlockSeq &+= 1
        let seq = unlockSeq
        do {
            let derived = try await deriveKey(
                uid: vault.uid,
                password: password,
                salt: vault.salt,
                iterations: vault.iterations
            )
            guard seq == unlockSeq else { return }
            try derived.verify(uid: vault.uid, verifierBase64: vault.verifier)
            let bytes = try await client.nativeManifestBytes(id: vault.id)
            guard seq == unlockSeq else { return }
            var document = try derived.decryptManifest(
                uid: vault.uid,
                data: [UInt8](bytes)
            )
            sanitizeManifest(&document)
            key = derived
            manifest = document
            folder = nil
            search = ""
            notice = ""
            operationError = ""
            isUnlocking = false
            screen = .browse(vault)
            startIdleWatch()
        } catch let error as APIError {
            isUnlocking = false
            if error.status == 401 {
                onUnauthorized?()
                return
            }
            unlockError = error.message
        } catch {
            isUnlocking = false
            unlockError = unlockMessage(error)
        }
    }

    /// Create one vault: derive a key, encrypt the verifier and an empty
    /// manifest, then hand only the ciphertext to the server.
    func createVault(name: String, password: String, confirmation: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            unlockError = Strings.vaultNameMissing
            return false
        }
        guard password.count >= 8 else {
            unlockError = Strings.vaultPasswordShort
            return false
        }
        guard password == confirmation else {
            unlockError = Strings.vaultPasswordMismatch
            return false
        }

        isUnlocking = true
        unlockError = ""
        markActivity()
        unlockSeq &+= 1
        let seq = unlockSeq
        do {
            let uid = Hex.encode(SecureRandom.bytes(count: 16))
            let salt = SecureRandom.bytes(count: 16)
            let saltBase64 = Data(salt).base64EncodedString()
            let iterations = VaultKey.iterations

            let derived = try await deriveKey(
                uid: uid,
                password: password,
                salt: saltBase64,
                iterations: iterations
            )
            guard seq == unlockSeq else { return false }
            let verifierBlob = try derived.encrypt(
                aad: VaultKey.verifierAAD(uid: uid),
                nonce: VaultKey.randomNonce(),
                plaintext: [UInt8](VaultKey.verifierText(uid: uid).utf8)
            )
            let now = Int64(Date().timeIntervalSince1970)
            let document = VaultManifest(
                version: 1,
                uid: uid,
                name: trimmed,
                created: now,
                updated: now
            )
            let manifestBlob = try derived.encryptManifest(
                uid: uid,
                nonce: VaultKey.randomNonce(),
                manifest: document
            )

            let vault = try await client.createNativeVault(
                uid: uid,
                kdf: "PBKDF2-SHA256",
                iterations: iterations,
                salt: saltBase64,
                verifier: Data(verifierBlob).base64EncodedString(),
                manifest: Data(manifestBlob).base64EncodedString()
            )
            guard seq == unlockSeq else { return false }

            key = derived
            manifest = document
            folder = nil
            search = ""
            operationError = ""
            notice = Strings.vaultCreated
            isUnlocking = false
            screen = .browse(vault)
            upsert(vault)
            startIdleWatch()
            return true
        } catch let error as APIError {
            isUnlocking = false
            if error.status == 401 {
                onUnauthorized?()
                return false
            }
            unlockError = error.message
            return false
        } catch {
            isUnlocking = false
            unlockError = unlockMessage(error)
            return false
        }
    }

    /// Delete one vault. The password is verified locally first; the key is
    /// dropped before the server call.
    func deleteVault(_ vault: NativeVault, password: String) async -> Bool {
        guard !password.isEmpty else {
            operationError = Strings.vaultPasswordMissing
            return false
        }
        isWorking = true
        operationError = ""
        do {
            let derived = try await deriveKey(
                uid: vault.uid,
                password: password,
                salt: vault.salt,
                iterations: vault.iterations
            )
            try derived.verify(uid: vault.uid, verifierBase64: vault.verifier)
            try await client.deleteNativeVault(id: vault.id)
            isWorking = false
            vaults.removeAll { $0.id == vault.id }
            if case .browse(let current) = screen, current.id == vault.id {
                lock()
            }
            notice = Strings.vaultDeleted
            return true
        } catch let error as APIError {
            isWorking = false
            if error.status == 401 {
                onUnauthorized?()
                return false
            }
            operationError = error.message
            return false
        } catch {
            isWorking = false
            operationError = deleteUnlockMessage(error)
            return false
        }
    }

    // MARK: - Browse

    func navigate(to folderID: String?) {
        folder = folderID
        search = ""
        markActivity()
    }

    func updateSearch(_ value: String) {
        search = value
        markActivity()
    }

    /// Every touch keeps the vault unlocked, like the PWA's activity marker.
    func markActivity() {
        lastActivity = Date()
    }

    var currentVault: NativeVault? {
        if case .browse(let vault) = screen { return vault }
        return nil
    }

    var visibleFolders: [VaultFolder] {
        guard let manifest else { return [] }
        let query = SearchFold.fold(search.trimmingCharacters(in: .whitespacesAndNewlines))
        let entries: [VaultFolder]
        if query.isEmpty {
            entries = manifest.folders.filter { $0.parent == folder }
        } else {
            entries = manifest.folders.filter { SearchFold.fold($0.name).contains(query) }
        }
        return entries.sorted { lhs, rhs in
            let left = SearchFold.fold(lhs.name)
            let right = SearchFold.fold(rhs.name)
            if left != right { return left < right }
            return lhs.name < rhs.name
        }
    }

    var visibleFiles: [VaultFile] {
        guard let manifest else { return [] }
        let query = SearchFold.fold(search.trimmingCharacters(in: .whitespacesAndNewlines))
        let entries: [VaultFile]
        if query.isEmpty {
            entries = manifest.files.filter { $0.folder == folder }
        } else {
            entries = manifest.files.filter { SearchFold.fold($0.name).contains(query) }
        }
        return entries.sorted { lhs, rhs in
            let left = SearchFold.fold(lhs.name)
            let right = SearchFold.fold(rhs.name)
            if left != right { return left < right }
            return lhs.name < rhs.name
        }
    }

    /// Parents of the current folder, root first.
    var folderTrail: [VaultFolder] {
        folderTrail(for: folder)
    }

    func folderTrail(for id: String?) -> [VaultFolder] {
        guard let manifest else { return [] }
        var trail: [VaultFolder] = []
        var seen = Set<String>()
        var cursor = id
        while let current = cursor {
            if !seen.insert(current).inserted { break }
            guard let entry = manifest.folders.first(where: { $0.id == current }) else {
                break
            }
            trail.append(entry)
            cursor = entry.parent
        }
        return Array(trail.reversed())
    }

    /// "Kho" or the "A / B" path of one folder.
    func folderPath(_ id: String?) -> String {
        let trail = folderTrail(for: id)
        guard !trail.isEmpty else { return Strings.vaultRootName }
        return trail.map(\.name).joined(separator: " / ")
    }

    /// Number of files stored directly inside one folder.
    func fileCount(in folderID: String?) -> Int {
        manifest?.files.filter { $0.folder == folderID }.count ?? 0
    }

    var totalBytes: Int64 {
        manifest?.files.reduce(0) { $0 + max(0, $1.size) } ?? 0
    }

    // MARK: - Folders and files

    /// Create one folder in the current directory.
    func createFolder(name: String) async -> Bool {
        guard let vault = currentVault, let key else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            operationError = Strings.vaultFolderName
            return false
        }
        isWorking = true
        operationError = ""
        do {
            let entry = VaultFolder(
                id: Hex.encode(SecureRandom.bytes(count: 16)),
                name: trimmed,
                parent: folder,
                created: Int64(Date().timeIntervalSince1970)
            )
            let result = try await applyManifestChange(vault: vault, key: key) { document in
                if document.folders.contains(where: { $0.id == entry.id }) {
                    return false
                }
                document.folders.append(entry)
                return true
            }
            manifest = result.manifest
            upsert(result.vault)
            isWorking = false
            notice = Strings.vaultCreateFolder
            return true
        } catch let error as APIError {
            isWorking = false
            if error.status == 401 {
                onUnauthorized?()
                return false
            }
            operationError = error.message
            return false
        } catch {
            isWorking = false
            operationError = unlockMessage(error)
            return false
        }
    }

    /// Remove one file from the manifest and then from the blob library.
    func deleteFile(_ file: VaultFile) async {
        guard let vault = currentVault, let key else { return }
        isWorking = true
        operationError = ""
        do {
            let result = try await applyManifestChange(vault: vault, key: key) { document in
                let before = document.files.count
                document.files.removeAll { $0.id == file.id }
                return document.files.count != before
            }
            manifest = result.manifest
            upsert(result.vault)
            isWorking = false
            notice = Strings.vaultFileDeleted
            let remote = file.remote.trimmingCharacters(in: .whitespacesAndNewlines)
            if !remote.isEmpty {
                try? await client.deleteNativeFile(id: vault.id, name: remote)
            }
        } catch let error as APIError {
            isWorking = false
            if error.status == 401 {
                onUnauthorized?()
                return
            }
            operationError = error.message
        } catch {
            isWorking = false
            operationError = unlockMessage(error)
        }
    }

    /// Remove one folder with everything below it.
    func deleteFolder(_ entry: VaultFolder) async {
        guard let vault = currentVault, let key else { return }
        isWorking = true
        operationError = ""
        do {
            let result = try await applyManifestChange(vault: vault, key: key) { document in
                let ids = VaultModel.subtreeFolderIDs(document, root: entry.id)
                let beforeFiles = document.files.count
                let beforeFolders = document.folders.count
                document.files.removeAll { file in
                    guard let parent = file.folder else { return false }
                    return ids.contains(parent)
                }
                document.folders.removeAll { ids.contains($0.id) }
                return document.files.count != beforeFiles
                    || document.folders.count != beforeFolders
            }
            manifest = result.manifest
            upsert(result.vault)
            isWorking = false
            notice = Strings.vaultFolderDeleted
            if folder == entry.id {
                folder = nil
            }
        } catch let error as APIError {
            isWorking = false
            if error.status == 401 {
                onUnauthorized?()
                return
            }
            operationError = error.message
        } catch {
            isWorking = false
            operationError = unlockMessage(error)
        }
    }

    // MARK: - Manifest compare-and-swap

    /// Apply one manifest change with a SHA-256 compare-and-swap. A concurrent
    /// session that wins the race causes one refetch and one retry.
    private func applyManifestChange(
        vault: NativeVault,
        key: VaultKey,
        change: (inout VaultManifest) -> Bool
    ) async throws -> (vault: NativeVault, manifest: VaultManifest) {
        var meta = vault
        var cached: (manifest: VaultManifest, sha256: String)?

        for attempt in 0..<2 {
            let document: VaultManifest
            let previous: String
            if let cached {
                document = cached.manifest
                previous = cached.sha256
            } else {
                meta = try await client.nativeVault(id: vault.id)
                let bytes = try await client.nativeManifestBytes(id: vault.id)
                var decrypted = try key.decryptManifest(
                    uid: vault.uid,
                    data: [UInt8](bytes)
                )
                sanitizeManifest(&decrypted)
                document = decrypted
                previous = meta.manifestSHA256
            }

            var mutable = document
            guard change(&mutable) else {
                return (meta, mutable)
            }
            guard VaultModel.isSHA256(previous) else {
                cached = nil
                continue
            }
            mutable.updated = Int64(Date().timeIntervalSince1970)
            let blob = try key.encryptManifest(
                uid: vault.uid,
                nonce: VaultKey.randomNonce(),
                manifest: mutable
            )
            do {
                let updated = try await client.updateNativeManifest(
                    id: vault.id,
                    manifest: Data(blob).base64EncodedString(),
                    prevSHA256: previous,
                    bytes: Int64(blob.count)
                )
                return (updated, mutable)
            } catch let error as APIError where error.code == "stale" && attempt == 0 {
                cached = nil
            }
        }

        throw APIError(status: 0, code: "stale", message: Strings.vaultStale)
    }

    // MARK: - Private

    /// Derive the vault key off the main actor; PBKDF2 blocks for a moment.
    private func deriveKey(
        uid: String,
        password: String,
        salt: String,
        iterations: Int64
    ) async throws -> VaultKey {
        try await Task.detached(priority: .userInitiated) {
            try VaultKey.unlock(
                uid: uid,
                password: password,
                saltBase64: salt,
                iterations: iterations
            )
        }.value
    }

    private func upsert(_ vault: NativeVault) {
        if let index = vaults.firstIndex(where: { $0.id == vault.id }) {
            vaults[index] = vault
        } else {
            vaults.append(vault)
        }
    }

    /// Lock the vault after 15 idle minutes, like the PWA tab.
    private func startIdleWatch() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: UInt64(VaultModel.idleCheckSeconds * 1_000_000_000)
                )
                guard !Task.isCancelled else { return }
                guard let self else { return }
                let idle = Date().timeIntervalSince(self.lastActivity)
                if idle >= VaultModel.idleLockSeconds {
                    self.lock()
                    return
                }
            }
        }
    }

    private func unlockMessage(_ error: Error) -> String {
        guard let mngError = error as? MNGError else {
            return Strings.vaultUnlockFailed
        }
        switch mngError {
        case .wrongPassword:
            return Strings.vaultWrongPassword
        case .invalidVault(let field):
            switch field {
            case "iterations": return Strings.vaultInvalidIterations
            case "salt": return Strings.vaultInvalidSalt
            case "verifier": return Strings.vaultInvalidVerifier
            default: return Strings.vaultInvalidMetadata
            }
        default:
            return Strings.vaultUnlockFailed
        }
    }

    private func deleteUnlockMessage(_ error: Error) -> String {
        if let mngError = error as? MNGError, mngError == .wrongPassword {
            return Strings.vaultDeleteWrongPassword
        }
        return unlockMessage(error)
    }

    /// Every folder id in the subtree rooted at `root`.
    static func subtreeFolderIDs(_ document: VaultManifest, root: String) -> Set<String> {
        var ids = Set<String>()
        guard document.folders.contains(where: { $0.id == root }) else { return ids }
        ids.insert(root)
        var changed = true
        while changed {
            changed = false
            for entry in document.folders {
                guard let parent = entry.parent, ids.contains(parent) else { continue }
                if ids.insert(entry.id).inserted {
                    changed = true
                }
            }
        }
        return ids
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}
