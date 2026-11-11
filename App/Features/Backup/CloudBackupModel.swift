import Foundation
import MNGKit
import Observation

/// Uploads photos and videos from the device into the owner's cloud library.
///
/// The server owns the Seafile credentials, so the app never speaks the
/// Seafile upload protocol: it uses the same `POST /api/v1/media/upload`
/// route the web client uses, and the server does the WebDAV `PUT` and the
/// indexing.
///
/// A Live Photo is two files with the same stem (`IMG_0001.HEIC` and
/// `IMG_0001.MOV`). The worker pairs them the same way it pairs a scanned
/// pair, so both files are uploaded and the still becomes a Live Photo again.
@MainActor
@Observable
final class CloudBackupModel {
    /// One file waiting to be uploaded.
    struct Job: Identifiable {
        let id = UUID()
        let name: String
        let mime: String
        let url: URL
        let size: Int64
    }

    private(set) var isRunning = false
    private(set) var isFinished = false
    private(set) var total = 0
    private(set) var completed = 0
    private(set) var uploaded = 0
    private(set) var skipped = 0
    private(set) var failed = 0
    /// Name of the file being transferred right now.
    private(set) var currentName: String?

    var onUnauthorized: (() -> Void)?
    var onToast: ((String) -> Void)?

    /// Upload every job, one after the other.
    ///
    /// A photo the library already carries is skipped before the transfer
    /// starts, and the server answers `matched` when an identical object was
    /// already at the target path.
    func upload(_ jobs: [Job], client: MNGAPIClient) async {
        guard !isRunning, !jobs.isEmpty else { return }
        isRunning = true
        isFinished = false
        total = jobs.count
        completed = 0
        uploaded = 0
        skipped = 0
        failed = 0
        currentName = nil

        for job in jobs {
            currentName = job.name
            do {
                // The capture date travels with the upload: a phone names its
                // photos `IMG_1234.HEIC`, so the name carries no date and the
                // server would file the photo under the time of the upload.
                let takenAt = MNGNames.takenAt(
                    from: job.name,
                    mtime: CloudBackupModel.modificationDate(of: job.url)
                )
                if try await client.mediaMatch(takenAt: takenAt, size: job.size) {
                    skipped += 1
                } else {
                    let response = try await client.mediaUpload(
                        name: job.name,
                        fileURL: job.url,
                        mime: job.mime,
                        takenAt: takenAt
                    )
                    if response.matched {
                        skipped += 1
                    } else {
                        uploaded += 1
                    }
                }
                completed += 1
            } catch let error as APIError {
                completed += 1
                if error.status == 401 {
                    failed += 1
                    onUnauthorized?()
                    break
                }
                failed += 1
            } catch {
                completed += 1
                failed += 1
            }
        }

        currentName = nil
        isRunning = false
        isFinished = true
        onToast?(summary)
    }

    /// Drop the finished state so the card disappears.
    func dismiss() {
        guard !isRunning else { return }
        isFinished = false
    }

    var summary: String {
        Strings.backupSummary(
            uploaded: uploaded,
            skipped: skipped,
            failed: failed
        )
    }

    /// The modification time of a file, as the server stores it.
    ///
    /// The server keeps a date as a UTC epoch that carries the local
    /// wall-clock time, so the same conversion the capture date uses applies
    /// here.
    private static func modificationDate(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let date = values?.contentModificationDate else { return 0 }
        return MNGNames.captureTimestamp(from: date)
    }
}
