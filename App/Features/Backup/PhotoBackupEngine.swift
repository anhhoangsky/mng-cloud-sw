import Foundation
import MNGKit
import Observation
import Photos
import UIKit

/// Automatic backup of the device photo library into the cloud library.
///
/// The engine keeps a durable queue of the assets that still have to reach the
/// server. The transfer itself runs in a background `URLSession`, so an upload
/// keeps going after the app is suspended and iOS relaunches the app to
/// deliver the result. A `BGProcessingTask` wakes the app when the device is
/// idle so new photos are picked up, and the queue survives a termination.
///
/// This is the part that is better than the Seafile client: Seafile relies on
/// the short background windows iOS grants a `BGTask`, so a large backlog is
/// constantly interrupted. Here the bytes travel in a session the system owns,
/// the queue is persistent, and only photos that are actually new are looked
/// at.
@MainActor
@Observable
final class PhotoBackupEngine {
    enum Status: Equatable {
        case off
        case waitingForPermission
        case idle
        case scanning
        case uploading(done: Int, total: Int)
        case failed(String)
    }

    /// One asset waiting to reach the library.
    struct Job: Codable, Identifiable, Equatable {
        let id: UUID
        /// The `PHAsset` local identifier, so the file can be staged again
        /// after the app was terminated.
        let localIdentifier: String
        let name: String
        let mime: String
        let creationDate: Date
        let size: Int64
        let isLivePhoto: Bool
        /// The background tasks that carry the upload, once they are running.
        /// A Live Photo is two files, so there can be more than one.
        var taskIDs: Set<Int>
        /// How many times the transfer failed.
        var attempts: Int
        /// The earliest moment the next attempt may start.
        var nextAttempt: Date?
    }

    /// What the user can change.
    struct Settings: Codable, Equatable {
        var isEnabled = false
        /// Only back up on Wi-Fi.
        var wifiOnly = true
        var includeVideos = true

        static let storageKey = "mng.backup.settings.v1"
    }

    /// How many times a job is tried before it is given up on.
    private static let maximumAttempts = 5

    static let shared = PhotoBackupEngine()

    // MARK: - State

    private(set) var status: Status = .off
    private(set) var uploaded = 0
    private(set) var skipped = 0
    private(set) var failed = 0
    private(set) var lastRun: Date?
    /// The assets that still have to reach the library.
    private(set) var queue: [Job] = []
    /// The scan only looks at photos that are at least this old.
    private(set) var scannedUntil: Date?
    /// The assets that are already in the library, with their capture date.
    /// Only the ones near the scan boundary are kept, so the map stays small.
    private(set) var handled: [String: Date] = [:]

    private var settings = Settings()
    private var runTask: Task<Void, Never>?
    private var changeObserver: PhotoLibraryObserver?
    /// The fetch result keeps the observer registered, so it has to stay alive.
    private var changeFetch: Any?
    /// The staged files of the running jobs, so they can be removed when the
    /// transfer is done.
    private var stagedFiles: [UUID: [URL]] = [:]

    /// The client is owned by the shell; without a session there is nothing to
    /// upload to.
    var client: MNGAPIClient?

    private init() {
        settings = Self.loadSettings()
        let state = Self.loadState()
        queue = state.jobs
        scannedUntil = state.scannedUntil
        handled = state.handled
        uploaded = state.uploaded
        skipped = state.skipped
        failed = state.failed
        lastRun = state.lastRun
        status = settings.isEnabled ? .idle : .off
        // The staging directory holds the leftovers of a run that was killed.
        Self.purgeStaging()
    }

    // MARK: - Settings

    var isEnabled: Bool { settings.isEnabled }
    var wifiOnly: Bool { settings.wifiOnly }
    var includeVideos: Bool { settings.includeVideos }
    var pendingCount: Int { queue.count }

    func setEnabled(_ value: Bool) {
        settings.isEnabled = value
        saveSettings()
        status = value ? .idle : .off
        if value {
            startObserving()
            BackgroundTaskCoordinator.shared.schedule()
        } else {
            stopObserving()
        }
    }

    func setWifiOnly(_ value: Bool) {
        settings.wifiOnly = value
        saveSettings()
    }

    func setIncludeVideos(_ value: Bool) {
        settings.includeVideos = value
        saveSettings()
    }

    // MARK: - Library changes

    /// Watch the photo library so a new photo is backed up within minutes
    /// instead of at the next background window.
    func startObserving() {
        guard settings.isEnabled else { return }
        guard changeObserver == nil else { return }
        let observer = PhotoLibraryObserver { [weak self] in
            Task { @MainActor in
                await self?.run()
            }
        }
        // The fetch result keeps the registration alive; the observer only
        // learns that something changed.
        changeFetch = PHPhotoLibrary.shared().registerChangeObserver(for: observer)
        changeObserver = observer
    }

    func stopObserving() {
        guard let observer = changeObserver else { return }
        PHPhotoLibrary.shared().unregisterChangeObserver(observer)
        changeObserver = nil
        changeFetch = nil
    }

    // MARK: - Permission

    /// The photo library permission the automatic backup needs.
    ///
    /// The picker used by "Lưu vào thư viện" runs out of process and needs no
    /// permission, but an automatic backup has to read the library itself.
    func requestAuthorization() async -> PHAuthorizationStatus {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            return await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        return status
    }

    var authorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    var hasPermission: Bool {
        let status = authorizationStatus
        return status == .authorized || status == .limited
    }

    // MARK: - Running

    /// Pick up new photos and hand them to the uploader.
    ///
    /// The call is safe to make from a background task: it never touches the
    /// user interface and it returns as soon as the queue is filled.
    @discardableResult
    func run() async -> Bool {
        guard settings.isEnabled else { return false }
        guard let client = await resolveClient() else { return false }
        guard hasPermission else {
            status = .waitingForPermission
            return false
        }

        // A run that is already going on must not start a second one.
        guard runTask == nil else { return true }
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.performRun(client: client)
        }
        runTask = task
        await task.value
        runTask = nil
        return true
    }

    /// The client of the signed-in session.
    ///
    /// The engine can rebuild it after a relaunch: the server is in the
    /// defaults and the session cookie is in the shared jar. This is what lets
    /// a background run work when iOS woke the app up without the user
    /// opening it.
    private func resolveClient() async -> MNGAPIClient? {
        if let client { return client }
        guard let saved = UserDefaults.standard.string(forKey: SessionStore.serverKey),
              let server = MNGServer(string: saved)
        else {
            return nil
        }
        let client = MNGAPIClient(server: server)
        do {
            // The call refreshes the CSRF token the upload needs.
            _ = try await client.me()
        } catch {
            return nil
        }
        self.client = client
        return client
    }

    private func performRun(client: MNGAPIClient) async {
        status = .scanning
        // A task the system no longer knows about must not block the queue.
        await reconcileRunningTasks()
        let discovered = discover()
        merge(discovered)
        pruneHandled()

        let due = queue.filter { job in
            guard job.taskIDs.isEmpty else { return false }
            guard let next = job.nextAttempt else { return true }
            return next <= Date()
        }
        guard !due.isEmpty else {
            status = .idle
            lastRun = Date()
            saveState()
            return
        }

        let total = due.count
        status = .uploading(done: 0, total: total)
        var done = 0
        for job in due {
            await upload(job: job, client: client)
            done += 1
            status = .uploading(done: done, total: total)
        }
        lastRun = Date()
        status = .idle
        saveState()
    }

    /// Drop the task ids of the transfers the system does not run any more.
    ///
    /// The task identifier of a background session is only unique inside one
    /// session instance, so the ids of a relaunch do not match. The job id in
    /// the task description does, so the running tasks are matched by it.
    private func reconcileRunningTasks() async {
        let running = await BackgroundUploadSession.shared.runningJobIDs()
        guard !running.isEmpty else { return }
        for index in queue.indices where !queue[index].taskIDs.isEmpty {
            if !running.contains(queue[index].id) {
                queue[index].taskIDs.removeAll()
            }
        }
        saveState()
    }

    /// The photos that are newer than the last scan.
    private func discover() -> [Job] {
        let options = PHFetchOptions()
        if let scannedUntil {
            // The boundary is inclusive: a Live Photo still and its movie
            // share the capture date and must both be found.
            options.predicate = NSPredicate(
                format: "creationDate >= %@",
                scannedUntil as NSDate
            )
        }
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        var jobs: [Job] = []
        PHAsset.fetchAssets(with: .image, options: options)
            .enumerateObjects { asset, _, _ in
                jobs.append(Self.job(for: asset, isVideo: false))
            }
        if settings.includeVideos {
            PHAsset.fetchAssets(with: .video, options: options)
                .enumerateObjects { asset, _, _ in
                    jobs.append(Self.job(for: asset, isVideo: true))
                }
        }
        // The scan boundary moves to the newest photo that was seen.
        if let newest = jobs.map(\.creationDate).max() {
            scannedUntil = newest
        }
        return jobs
    }

    /// Add the newly discovered assets to the queue.
    private func merge(_ discovered: [Job]) {
        var known = Set(queue.map(\.localIdentifier))
        for job in discovered where !known.contains(job.localIdentifier) {
            // An asset that is already in the library is not sent again.
            if handled[job.localIdentifier] != nil { continue }
            queue.append(job)
            known.insert(job.localIdentifier)
        }
        queue.sort { $0.creationDate < $1.creationDate }
    }

    /// Only the assets near the scan boundary have to be remembered; the older
    /// ones are never discovered again.
    private func pruneHandled() {
        guard let boundary = scannedUntil else { return }
        handled = handled.filter { $0.value >= boundary }
    }

    private static func job(for asset: PHAsset, isVideo: Bool) -> Job {
        let resources = PHAssetResource.assetResources(for: asset)
        let primary = resources.first {
            isVideo ? $0.type == .video : $0.type == .photo
        } ?? resources.first
        let name = primary?.originalFilename
            ?? (isVideo
                ? "video-\(asset.localIdentifier).mov"
                : "IMG-\(asset.localIdentifier).jpg")
        let isLive = !isVideo && resources.contains { $0.type == .pairedVideo }
        let size = Int64(resources.reduce(0) { $0 + $1.fileSize })
        return Job(
            id: UUID(),
            localIdentifier: asset.localIdentifier,
            name: name,
            mime: mime(for: name, isVideo: isVideo),
            creationDate: asset.creationDate ?? Date(),
            size: size,
            isLivePhoto: isLive,
            taskIDs: [],
            attempts: 0,
            nextAttempt: nil
        )
    }

    private static func mime(for name: String, isVideo: Bool) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "heic", "heif": return "image/heic"
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        case "mov": return "video/quicktime"
        case "m4v", "mp4", "3gp": return "video/mp4"
        default: return isVideo ? "video/mp4" : "image/jpeg"
        }
    }

    // MARK: - Staging and uploading

    /// Write the original file of an asset into the staging directory.
    ///
    /// A Live Photo produces two files: the still and its paired movie. They
    /// share a stem, so the worker pairs them into a Live Photo again.
    private func stage(_ job: Job) async -> [StagedFile] {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [job.localIdentifier],
            options: nil
        ).firstObject else {
            return []
        }
        let resources = PHAssetResource.assetResources(for: asset)
        let wanted: [PHAssetResource]
        if job.isLivePhoto {
            wanted = resources.filter { $0.type == .photo || $0.type == .pairedVideo }
        } else {
            wanted = Array(resources.prefix(1))
        }
        guard !wanted.isEmpty else { return [] }

        var staged: [StagedFile] = []
        for resource in wanted {
            let name = resource.originalFilename
            guard let target = await Self.write(
                resource: resource,
                to: Self.stagingURL(for: name)
            ) else {
                continue
            }
            let isCompanion = resource.type == .pairedVideo
            let fileName = isCompanion
                ? "\(MNGNames.stem(of: job.name)).mov"
                : job.name
            staged.append(
                StagedFile(
                    name: fileName,
                    mime: Self.mime(for: fileName, isVideo: isCompanion),
                    url: target
                )
            )
        }
        return staged
    }

    /// The staging directory.
    ///
    /// It lives in Application Support, not in the temporary directory: the
    /// system may purge the temporary directory while the app is not running,
    /// and the upload still has to find the file.
    static var stagingDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("mng-backup-stage", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        // The staged files are copies, not user data.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = directory
        try? mutable.setResourceValues(values)
        return directory
    }

    static func purgeStaging() {
        let directory = stagingDirectory
        let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for url in contents ?? [] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func stagingURL(for name: String) -> URL {
        stagingDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension((name as NSString).pathExtension)
    }

    private static func write(
        resource: PHAssetResource,
        to url: URL
    ) async -> URL? {
        await withCheckedContinuation { continuation in
            PHAssetResourceManager.default().writeData(
                for: resource,
                toFile: url,
                options: nil
            ) { error in
                if error != nil {
                    try? FileManager.default.removeItem(at: url)
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: url)
            }
        }
    }

    /// Stage one job and hand it to the background session.
    private func upload(job: Job, client: MNGAPIClient) async {
        // The server knows what is already in the library; asking it first
        // saves the transfer of a photo the user uploaded from another device.
        let takenAt = MNGNames.takenAt(
            from: job.name,
            mtime: job.creationDate.timeIntervalSince1970 > 0
                ? Int64(job.creationDate.timeIntervalSince1970)
                : 0
        )
        if takenAt > 0, job.size > 0,
           (try? await client.mediaMatch(takenAt: takenAt, size: job.size)) == true {
            skipped += 1
            markHandled(job)
            removeFromQueue(job.id)
            saveState()
            return
        }

        let staged = await stage(job)
        guard !staged.isEmpty else {
            recordFailure(job)
            return
        }
        // The scratch files are remembered before the first transfer starts,
        // so they are removed even when the second one fails.
        var scratch = staged.map(\.url)
        stagedFiles[job.id] = scratch
        for file in staged {
            do {
                let prepared = try await client.mediaUploadRequest(
                    name: file.name,
                    fileURL: file.url,
                    mime: file.mime
                )
                scratch.append(prepared.bodyFile)
                stagedFiles[job.id] = scratch
                BackgroundUploadSession.shared.enqueue(
                    jobID: job.id,
                    request: prepared.request,
                    bodyFile: prepared.bodyFile
                ) { [weak self] taskID in
                    self?.addTaskID(taskID, for: job.id)
                }            } catch {
                recordFailure(job)
                removeStagedFiles(job.id)
                return
            }
        }
    }

    private func addTaskID(_ taskID: Int, for jobID: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == jobID }) else { return }
        queue[index].taskIDs.insert(taskID)
        saveState()
    }

    private func markHandled(_ job: Job) {
        handled[job.localIdentifier] = job.creationDate
    }

    private func recordFailure(_ job: Job) {
        guard let index = queue.firstIndex(where: { $0.id == job.id }) else { return }
        queue[index].attempts += 1
        if queue[index].attempts >= Self.maximumAttempts {
            // The file cannot be read (it may live only in iCloud); give up
            // instead of retrying forever.
            failed += 1
            removeFromQueue(job.id)
            return
        }
        // A transient failure waits a little longer every time.
        let delay = min(
            6 * 60 * 60,
            60 * pow(2.0, Double(min(queue[index].attempts, 6)))
        )
        queue[index].nextAttempt = Date().addingTimeInterval(delay)
        saveState()
    }

    private func removeFromQueue(_ id: UUID) {
        queue.removeAll { $0.id == id }
        removeStagedFiles(id)
    }

    /// Remove the scratch files of a job.
    private func removeStagedFiles(_ id: UUID) {
        stagedFiles[id]?.forEach { try? FileManager.default.removeItem(at: $0) }
        stagedFiles[id] = nil
    }

    // MARK: - Completion

    /// The background session finished one upload.
    func handleCompletion(jobID: UUID, taskID: Int, succeeded: Bool) {
        guard let index = queue.firstIndex(where: { $0.id == jobID }) else { return }
        // A completion of a task this job does not know any more is stale.
        guard queue[index].taskIDs.remove(taskID) != nil else { return }
        if succeeded {
            // The job is only done when every part of it arrived; a Live Photo
            // is two files.
            if queue[index].taskIDs.isEmpty {
                uploaded += 1
                markHandled(queue[index])
                removeFromQueue(jobID)
            }
        } else {
            queue[index].attempts += 1
            if queue[index].attempts >= Self.maximumAttempts {
                failed += 1
                removeFromQueue(jobID)
            } else {
                let delay = min(
                    6 * 60 * 60,
                    60 * pow(2.0, Double(min(queue[index].attempts, 6)))
                )
                queue[index].nextAttempt = Date().addingTimeInterval(delay)
            }
        }
        if status != .off {
            status = .idle
        }
        saveState()
    }

    // MARK: - Persistence

    private struct State: Codable {
        var jobs: [Job] = []
        var scannedUntil: Date?
        var handled: [String: Date] = [:]
        var uploaded = 0
        var skipped = 0
        var failed = 0
        var lastRun: Date?
    }

    private static var stateURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mng-backup-state.json")
    }

    private func saveState() {
        let state = State(
            jobs: queue,
            scannedUntil: scannedUntil,
            handled: handled,
            uploaded: uploaded,
            skipped: skipped,
            failed: failed,
            lastRun: lastRun
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        let url = Self.stateURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private static func loadState() -> State {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(State.self, from: data)
        else {
            return State()
        }
        return state
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Settings.storageKey)
    }

    private static func loadSettings() -> Settings {
        guard let data = UserDefaults.standard.data(forKey: Settings.storageKey),
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else {
            return Settings()
        }
        return settings
    }
}

/// One file that is about to be uploaded.
struct StagedFile {
    let name: String
    let mime: String
    let url: URL
}

/// Watches the photo library for new assets.
private final class PhotoLibraryObserver: NSObject, PHPhotoLibraryChangeObserver {
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange()
    }
}
