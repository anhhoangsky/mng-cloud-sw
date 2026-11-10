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

    /// Progress of one encrypted upload.
    struct UploadProgress: Equatable {
        let name: String
        let done: Int
        let total: Int
    }

    /// Decrypted preview of one vault file. The bytes stay in the model; the
    /// view turns them into an image or a player.
    enum PreviewState: Equatable {
        case idle
        case loading
        case image(Data)
        case video(URL)
        case text(String)
        case file
        case failed(String)
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
    private(set) var upload: UploadProgress?
    private(set) var preview: PreviewState = .idle
    private(set) var previewFile: VaultFile?
    private(set) var previewNote = ""
    private(set) var thumbnails: [String: Data] = [:]

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

    /// Show one operation error in the browse screen.
    func reportOperationError(_ message: String) {
        operationError = message
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
        guard let trimmed = VaultModel.cleanEntryName(name, maxCharacters: 80) else {
            operationError = Strings.vaultFolderInvalid
            return false
        }
        let parent = folder
        if manifest?.folders.contains(where: {
            $0.parent == parent && SearchFold.fold($0.name) == SearchFold.fold(trimmed)
        }) == true {
            operationError = Strings.vaultFolderExists
            return false
        }
        isWorking = true
        operationError = ""
        do {
            let entry = VaultFolder(
                id: Hex.encode(SecureRandom.bytes(count: 16)),
                name: trimmed,
                parent: parent,
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
            notice = Strings.vaultFolderCreated(trimmed)
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

    // MARK: - Upload and preview

    /// Encrypt one file in 4 MiB chunks, upload every block and merge the new
    /// entry into the encrypted manifest. Only one plaintext and one ciphertext
    /// chunk are in memory at a time.
    func upload(_ source: VaultUploadSource) async {
        guard let vault = currentVault, let key else { return }
        guard let name = VaultModel.cleanEntryName(source.name, maxCharacters: 255) else {
            operationError = Strings.vaultFileInvalid
            return
        }
        let size = source.size
        guard size > 0 else {
            operationError = Strings.vaultFileEmpty
            return
        }
        let chunkSize = VaultKey.chunkBytes
        let total = Int((size + Int64(chunkSize) - 1) / Int64(chunkSize))
        guard total <= 4096 else {
            operationError = Strings.vaultFileTooLarge
            return
        }

        isWorking = true
        operationError = ""
        notice = ""
        upload = UploadProgress(name: name, done: 0, total: total)

        var handle: FileHandle?
        var scopedURL: URL?
        if case .file(_, _, _, let url) = source {
            if url.startAccessingSecurityScopedResource() {
                scopedURL = url
            }
            handle = try? FileHandle(forReadingFrom: url)
            if handle == nil {
                if let scopedURL {
                    scopedURL.stopAccessingSecurityScopedResource()
                }
                isWorking = false
                upload = nil
                operationError = Strings.vaultFileUnreadable
                return
            }
        }
        defer {
            try? handle?.close()
            scopedURL?.stopAccessingSecurityScopedResource()
        }

        let readChunk: (Int) throws -> Data = { index in
            switch source {
            case .file:
                guard let handle else { return Data() }
                try handle.seek(toOffset: UInt64(index * chunkSize))
                return try handle.read(upToCount: chunkSize) ?? Data()
            case .memory(_, _, let data):
                let start = index * chunkSize
                let end = min(start + chunkSize, data.count)
                guard start < end else { return Data() }
                return data.subdata(in: start..<end)
            }
        }

        let fileID = Hex.encode(SecureRandom.bytes(count: 16))
        var chunks: [VaultChunk] = []
        var blockIDs: [String] = []
        var cipherBytes: Int64 = 0

        do {
            for index in 0..<total {
                let plain = try readChunk(index)
                let cipher = try key.encryptChunk(
                    uid: vault.uid,
                    fileID: fileID,
                    index: index,
                    total: total,
                    nonce: VaultKey.randomNonce(),
                    plaintext: [UInt8](plain)
                )
                let blockID = SHA1.hex(cipher)
                try await client.uploadNativeBlock(
                    id: vault.id,
                    block: blockID,
                    data: Data(cipher)
                )
                chunks.append(VaultChunk(id: blockID, size: Int64(plain.count)))
                blockIDs.append(blockID)
                cipherBytes += Int64(cipher.count)
                upload = UploadProgress(name: name, done: index + 1, total: total)
            }

            let remote = "f-\(fileID).bin"
            let committed = try await client.commitNativeFile(
                id: vault.id,
                name: remote,
                size: cipherBytes,
                blocks: blockIDs
            )
            let now = Int64(Date().timeIntervalSince1970)
            let entry = VaultFile(
                id: fileID,
                remote: remote,
                fileID: committed,
                name: name,
                folder: folder,
                size: size,
                mime: source.mime,
                kind: VaultModel.classifyKind(name: name, mime: source.mime),
                created: now,
                added: now,
                chunks: chunks
            )
            let result = try await applyManifestChange(vault: vault, key: key) { document in
                if document.files.contains(where: { $0.id == entry.id }) {
                    return false
                }
                document.files.append(entry)
                return true
            }
            manifest = result.manifest
            upsert(result.vault)
            isWorking = false
            upload = nil
            notice = Strings.vaultUploaded(name)
        } catch let error as APIError {
            isWorking = false
            upload = nil
            if error.status == 401 {
                onUnauthorized?()
                return
            }
            operationError = error.message
        } catch {
            isWorking = false
            upload = nil
            operationError = unlockMessage(error)
        }
    }

    /// Download and decrypt one vault file for the preview sheet.
    func openPreview(_ file: VaultFile) async {
        guard let vault = currentVault, let key else { return }
        previewFile = file
        preview = .loading
        previewNote = Strings.vaultDecrypting(0, file.chunks.count)
        do {
            var plain = Data()
            let total = file.chunks.count
            for (index, chunk) in file.chunks.enumerated() {
                let data = try await downloadBlob(vault: vault, file: file, blob: chunk.id)
                let decrypted = try key.decryptChunk(
                    uid: vault.uid,
                    fileID: file.id,
                    index: index,
                    total: total,
                    data: [UInt8](data)
                )
                plain.append(contentsOf: decrypted.copyBytes())
                previewNote = Strings.vaultDecrypting(index + 1, total)
            }
            preview = VaultModel.makePreview(file: file, bytes: plain)
            previewNote = Strings.vaultDecoded(bytes: file.size)
        } catch let error as APIError {
            if error.status == 401 {
                onUnauthorized?()
                return
            }
            preview = .failed(error.message)
            previewNote = Strings.vaultDecryptFailed
        } catch {
            preview = .failed(unlockMessage(error))
            previewNote = Strings.vaultDecryptFailed
        }
    }

    /// Close the preview and delete the decrypted temporary file.
    func closePreview() {
        if case .video(let url) = preview {
            try? FileManager.default.removeItem(at: url)
        }
        preview = .idle
        previewFile = nil
        previewNote = ""
    }

    /// Decrypted thumbnail of one vault file, when the manifest has one.
    func thumbnail(for file: VaultFile) async -> Data? {
        if let cached = thumbnails[file.id] {
            return cached
        }
        let blob = file.thumb?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !blob.isEmpty, let vault = currentVault, let key else { return nil }
        do {
            let data = try await client.nativeBlobBytes(id: vault.id, blob: blob)
            let plain = try key.decryptThumb(
                uid: vault.uid,
                fileID: file.id,
                data: [UInt8](data)
            )
            let bytes = Data(plain.copyBytes())
            thumbnails[file.id] = bytes
            return bytes
        } catch {
            return nil
        }
    }

    /// One ciphertext block of a vault file. New manifests store 40-hex Seafile
    /// block ids; older read-only manifests used 32-hex local blob ids.
    private func downloadBlob(
        vault: NativeVault,
        file: VaultFile,
        blob: String
    ) async throws -> Data {
        if file.fileID.count == 40, blob.count == 40 {
            return try await client.nativeFileBlockBytes(
                id: vault.id,
                fileID: file.fileID,
                block: blob
            )
        }
        return try await client.nativeBlobBytes(id: vault.id, blob: blob)
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
    static func subtreeFolderIDs(_ document: VaultManifest, root: String) -> Set<String> {        var ids = Set<String>()
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

    /// Port of the PWA's `clean_entry_name`: trim, reject empty names, control
    /// characters, path separators and the `.`/`..` entries.
    static func cleanEntryName(_ raw: String, maxCharacters: Int) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard value.count <= maxCharacters else { return nil }
        guard value != "." && value != ".." else { return nil }
        guard !value.contains("/"), !value.contains("\\") else { return nil }
        guard !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return nil
        }
        return value
    }

    /// Legacy caps text previews at 2 MiB and 200,000 characters.
    static let textPreviewBytes = 2 * 1024 * 1024
    static let textPreviewCharacters = 200_000

    /// Port of the PWA's `classify_kind`: the mime type wins, the file
    /// extension is the fallback.
    static func kind(for file: VaultFile) -> String {
        let stored = file.kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !stored.isEmpty {
            return stored
        }
        return classifyKind(name: file.name, mime: file.mime)
    }

    static func classifyKind(name: String, mime: String) -> String {
        let lower = mime.lowercased()
        if lower.hasPrefix("video/") || isVideoExtension(name) {
            return "video"
        }
        if lower.hasPrefix("image/") || isImageExtension(name) {
            return "image"
        }
        return "file"
    }

    static func fileExtension(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else {
            return ""
        }
        return String(name[name.index(after: dot)...]).lowercased()
    }

    static func isVideoExtension(_ name: String) -> Bool {
        switch fileExtension(name) {
        case "mp4", "m4v", "mov", "webm", "mkv", "avi", "3gp":
            return true
        default:
            return false
        }
    }

    static func isImageExtension(_ name: String) -> Bool {
        switch fileExtension(name) {
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif", "bmp",
             "tif", "tiff":
            return true
        default:
            return false
        }
    }

    static func isTextFile(_ file: VaultFile) -> Bool {
        let mime = file.mime.lowercased()
        if mime.hasPrefix("text/") {
            return true
        }
        if ["application/json", "application/xml", "application/javascript",
            "application/x-yaml"].contains(mime) {
            return true
        }
        switch fileExtension(file.name) {
        case "txt", "md", "markdown", "json", "csv", "tsv", "log", "xml", "yml",
             "yaml", "ini", "conf", "html", "htm", "css", "js", "ts", "php",
             "py", "sh", "rs", "toml":
            return true
        default:
            return false
        }
    }

    /// Mime type used by the preview, mirroring the PWA's `preview_mime`.
    static func previewMime(for file: VaultFile) -> String {
        let mime = file.mime.trimmingCharacters(in: .whitespacesAndNewlines)
        if !mime.isEmpty {
            return mime
        }
        switch fileExtension(file.name) {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "avif": return "image/avif"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        case "mkv": return "video/x-matroska"
        default: return "application/octet-stream"
        }
    }

    /// Turn the decrypted bytes into the preview body.
    static func makePreview(file: VaultFile, bytes: Data) -> PreviewState {
        let mime = previewMime(for: file)
        if mime.hasPrefix("image/") {
            return .image(bytes)
        }
        if mime.hasPrefix("video/") {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("mng-vault", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let ext = fileExtension(file.name).isEmpty ? "mp4" : fileExtension(file.name)
            let target = directory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            do {
                try bytes.write(to: target, options: .atomic)
                return .video(target)
            } catch {
                return .file
            }
        }
        if bytes.count <= textPreviewBytes, isTextFile(file) {
            let text = String(decoding: bytes, as: UTF8.self)
            return .text(String(text.prefix(textPreviewCharacters)))
        }
        return .file
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}
