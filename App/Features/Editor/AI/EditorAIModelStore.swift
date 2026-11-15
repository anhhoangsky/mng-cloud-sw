import CoreML
import CryptoKit
import Foundation
import ZIPFoundation

enum EditorAIModelStoreError: LocalizedError {
    case notInstalled
    case downloadFailed
    case needsWiFi
    case checksumMismatch
    case wrongSize(expected: Int64, actual: Int64)
    case unpackFailed
    case incompatibleArchive
    case insufficientDisk(requiredMB: Int, availableMB: Int)
    case compileFailed
    case corrupt

    var errorDescription: String? {
        switch self {
        case .notInstalled: return Strings.editorAIModelNotInstalled
        case .downloadFailed: return Strings.editorAIDownloadFailed
        case .needsWiFi: return Strings.editorAIModelNeedsWiFi
        case .checksumMismatch: return Strings.editorAIModelChecksum
        case .wrongSize: return Strings.editorAIModelWrongSize
        case .unpackFailed: return Strings.editorAIModelUnpack
        case .incompatibleArchive: return Strings.editorAIModelIncompatible
        case .insufficientDisk(let requiredMB, let availableMB):
            return Strings.editorAIModelDisk(
                required: requiredMB,
                available: availableMB
            )
        case .compileFailed: return Strings.editorAIModelCompile
        case .corrupt: return Strings.editorAIModelCorrupt
        }
    }
}

/// Downloads, verifies, unpacks and compiles the Core ML archives.
///
/// Layout: `Application Support/AIModels/<id>/<version>/`, with the package,
/// the compiled model, the license, the conversion metadata and an
/// `installed.json` commit marker. The directory is excluded from iCloud
/// backup: model weights must not be uploaded to the user's backup.
actor EditorAIModelStore {
    static let shared = EditorAIModelStore()

    private let fileManager = FileManager.default
    private let root: URL

    init() {
        root = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIModels", isDirectory: true)
    }

    func isInstalled(_ descriptor: EditorAIModelDescriptor) -> Bool {
        guard let directory = try? installedVersionDirectory(descriptor) else {
            return false
        }
        // The marker alone is not enough: a cleanup or a failed move can
        // leave it without weights, and the engine must fall back to Vision
        // instead of treating the tier as installed.
        let compiled = directory.appendingPathComponent(
            descriptor.compiledDirectoryName,
            isDirectory: true
        )
        let package = directory.appendingPathComponent(
            descriptor.packageDirectoryName,
            isDirectory: true
        )
        return fileManager.fileExists(atPath: compiled.path)
            || fileManager.fileExists(atPath: package.path)
    }

    /// The `.mlmodelc` the runtime loads. Compiles on first use if the
    /// compiled directory is missing, which happens after an OS update.
    func compiledModelURL(
        _ descriptor: EditorAIModelDescriptor
    ) throws -> URL {
        let directory = try installedVersionDirectory(descriptor)
        let compiled = directory.appendingPathComponent(
            descriptor.compiledDirectoryName,
            isDirectory: true
        )
        if fileManager.fileExists(atPath: compiled.path) {
            return compiled
        }
        let package = directory.appendingPathComponent(
            descriptor.packageDirectoryName,
            isDirectory: true
        )
        guard fileManager.fileExists(atPath: package.path) else {
            throw EditorAIModelStoreError.corrupt
        }
        let temporary: URL
        do {
            temporary = try Self.compile(package)
        } catch {
            throw EditorAIModelStoreError.compileFailed
        }
        try? fileManager.removeItem(at: compiled)
        try fileManager.moveItem(at: temporary, to: compiled)
        return compiled
    }

    /// Keep compilation synchronous on the actor. The async overload suspends
    /// at the call, which would let a second install touch the same staging
    /// directory while this one is still committing.
    private static func compile(_ package: URL) throws -> URL {
        try MLModel.compileModel(at: package)
    }

    func install(
        _ descriptor: EditorAIModelDescriptor,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        if isInstalled(descriptor) { return }
        try ensureRoot()
        try checkDisk(for: descriptor)

        let directory = versionDirectory(descriptor)
        let parent = directory.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        let staging = parent.appendingPathComponent(
            "\(descriptor.version).staging-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: staging,
            withIntermediateDirectories: true
        )
        var committed = false
        defer {
            if !committed {
                try? fileManager.removeItem(at: staging)
            }
        }

        let archive = staging.appendingPathComponent("archive.zip")
        try await download(descriptor, to: archive, progress: progress)
        try Task.checkCancellation()

        let attributes = try fileManager.attributesOfItem(
            atPath: archive.path
        )
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard size == descriptor.archiveBytes else {
            throw EditorAIModelStoreError.wrongSize(
                expected: descriptor.archiveBytes,
                actual: size
            )
        }
        let digest = try Self.sha256(of: archive)
        guard digest.caseInsensitiveCompare(descriptor.archiveSHA256)
            == .orderedSame else {
            throw EditorAIModelStoreError.checksumMismatch
        }
        progress(1)

        let unpacked = staging.appendingPathComponent(
            "unpacked",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: unpacked,
            withIntermediateDirectories: true
        )
        do {
            try fileManager.unzipItem(at: archive, to: unpacked)
        } catch {
            throw EditorAIModelStoreError.unpackFailed
        }
        let package = unpacked.appendingPathComponent(
            descriptor.packageDirectoryName,
            isDirectory: true
        )
        guard fileManager.fileExists(
            atPath: package.appendingPathComponent("Manifest.json").path
        ) else {
            throw EditorAIModelStoreError.incompatibleArchive
        }
        try verifyMetadata(descriptor, in: unpacked)

        for name in ["metadata.json", "LICENSE.txt"] {
            let source = unpacked.appendingPathComponent(name)
            if fileManager.fileExists(atPath: source.path) {
                try fileManager.moveItem(
                    at: source,
                    to: staging.appendingPathComponent(name)
                )
            }
        }

        let compiled: URL
        do {
            compiled = try Self.compile(package)
        } catch {
            throw EditorAIModelStoreError.compileFailed
        }
        try Task.checkCancellation()
        try fileManager.moveItem(
            at: package,
            to: staging.appendingPathComponent(
                descriptor.packageDirectoryName,
                isDirectory: true
            )
        )
        try fileManager.moveItem(
            at: compiled,
            to: staging.appendingPathComponent(
                descriptor.compiledDirectoryName,
                isDirectory: true
            )
        )
        try? fileManager.removeItem(at: unpacked)
        try? fileManager.removeItem(at: archive)

        let record = InstallRecord(
            id: descriptor.id,
            version: descriptor.version,
            archiveSHA256: descriptor.archiveSHA256,
            installedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(
            to: staging.appendingPathComponent("installed.json"),
            options: .atomic
        )

        if fileManager.fileExists(atPath: directory.path) {
            try? fileManager.removeItem(at: directory)
        }
        try fileManager.moveItem(at: staging, to: directory)
        committed = true
        excludeFromBackup(directory)
        removeStaleVersions(descriptor)
    }

    func remove(_ descriptor: EditorAIModelDescriptor) throws {
        let directory = versionDirectory(descriptor)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    // MARK: - Paths and checks

    private func versionDirectory(
        _ descriptor: EditorAIModelDescriptor
    ) -> URL {
        root
            .appendingPathComponent(descriptor.id, isDirectory: true)
            .appendingPathComponent(descriptor.version, isDirectory: true)
    }

    private func installedVersionDirectory(
        _ descriptor: EditorAIModelDescriptor
    ) throws -> URL {
        let directory = versionDirectory(descriptor)
        let marker = directory.appendingPathComponent("installed.json")
        guard fileManager.fileExists(atPath: marker.path) else {
            throw EditorAIModelStoreError.notInstalled
        }
        guard let data = try? Data(contentsOf: marker) else {
            throw EditorAIModelStoreError.corrupt
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let record = try? decoder.decode(InstallRecord.self, from: data)
        else {
            throw EditorAIModelStoreError.corrupt
        }
        guard record.id == descriptor.id,
              record.version == descriptor.version,
              record.archiveSHA256 == descriptor.archiveSHA256 else {
            throw EditorAIModelStoreError.incompatibleArchive
        }
        return directory
    }

    private func removeStaleVersions(
        _ descriptor: EditorAIModelDescriptor
    ) {
        let parent = root.appendingPathComponent(
            descriptor.id,
            isDirectory: true
        )
        guard let children = try? fileManager.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        for child in children
        where child.lastPathComponent != descriptor.version {
            try? fileManager.removeItem(at: child)
        }
    }

    private func verifyMetadata(
        _ descriptor: EditorAIModelDescriptor,
        in directory: URL
    ) throws {
        let url = directory.appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let metadata = object as? [String: Any] else {
            throw EditorAIModelStoreError.incompatibleArchive
        }
        guard metadata["id"] as? String == descriptor.id,
              metadata["version"] as? String == descriptor.version else {
            throw EditorAIModelStoreError.incompatibleArchive
        }
    }

    private func ensureRoot() throws {
        if !fileManager.fileExists(atPath: root.path) {
            try fileManager.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
        }
        excludeFromBackup(root)
    }

    private func excludeFromBackup(_ url: URL) {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }

    private func checkDisk(
        for descriptor: EditorAIModelDescriptor
    ) throws {
        let required = Int64(Double(descriptor.archiveBytes) * 2.5)
            + 200 * 1_048_576
        let values = try? root.resourceValues(
            forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey,
            ]
        )
        let available = values?.volumeAvailableCapacityForImportantUsage
            ?? Int64(values?.volumeAvailableCapacity ?? 0)
        guard available >= required else {
            throw EditorAIModelStoreError.insufficientDisk(
                requiredMB: Int(required / 1_048_576),
                availableMB: Int(available / 1_048_576)
            )
        }
    }

    // MARK: - Network and hashing

    private func download(
        _ descriptor: EditorAIModelDescriptor,
        to url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        var request = URLRequest(url: descriptor.archiveURL)
        request.timeoutInterval = 120
        request.allowsCellularAccess = !descriptor.requiresWiFi
        let delegate = DownloadProgressDelegate(progress: progress)
        let temporary: URL
        let response: URLResponse
        do {
            (temporary, response) = try await URLSession.shared.download(
                for: request,
                delegate: delegate
            )
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .dataNotAllowed {
            // The descriptor requires Wi-Fi and the device is on cellular.
            throw EditorAIModelStoreError.needsWiFi
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw EditorAIModelStoreError.downloadFailed
        }
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw EditorAIModelStoreError.downloadFailed
        }
        try? fileManager.removeItem(at: url)
        try fileManager.moveItem(at: temporary, to: url)
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private struct InstallRecord: Codable, Sendable {
    let id: String
    let version: String
    let archiveSHA256: String
    let installedAt: Date
}

private final class DownloadProgressDelegate: NSObject,
    URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Double) -> Void

    init(progress: @escaping @Sendable (Double) -> Void) {
        self.progress = progress
    }

    /// Required by the protocol. The async `download(for:delegate:)` call
    /// hands the temporary file back to the caller, so the delegate itself
    /// must not move it.
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expected = totalBytesExpectedToWrite > 0
            ? totalBytesExpectedToWrite
            : downloadTask.countOfBytesExpectedToReceive
        guard expected > 0 else { return }
        progress(min(1, max(0, Double(totalBytesWritten) / Double(expected))))
    }
}
