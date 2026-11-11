import Foundation
import MNGKit
import UIKit

/// The background session that carries the backup uploads.
///
/// A background session belongs to the system, not to the app: the transfer
/// keeps running while the app is suspended, and iOS relaunches the app in the
/// background to deliver the result. That is what lets a backup finish
/// quietly instead of being cut off at the end of a short background window.
///
/// The request carries the session cookie and the CSRF token explicitly,
/// because the system replays it long after the app was suspended and the
/// cookie jar of a background session is not the app's. The job identifier
/// travels in the task description, so the completion still finds its job
/// after a relaunch.
final class BackgroundUploadSession: NSObject, @unchecked Sendable {
    static let shared = BackgroundUploadSession()

    /// The identifier is stable: iOS uses it to reconnect the session after a
    /// relaunch.
    static let identifier = "com.mngcloud.app.backup.upload"

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(
            withIdentifier: Self.identifier
        )
        // The system wakes the app when the transfer finishes.
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.allowsCellularAccess = true
        // The cookie travels in the request header instead, so the transfer
        // does not depend on a cookie jar that is not there yet.
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60
        return URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
    }()

    private let lock = NSLock()
    private var backgroundHandlers: [String: () -> Void] = [:]

    /// Hand one upload to the system.
    @discardableResult
    func enqueue(
        jobID: UUID,
        request: URLRequest,
        bodyFile: URL
    ) -> Int {
        let task = session.uploadTask(with: request, fromFile: bodyFile)
        // The description survives the relaunch, so the completion still finds
        // the job it belongs to.
        task.taskDescription = jobID.uuidString
        task.resume()
        return task.taskIdentifier
    }

    /// The uploads that are still running.
    func runningTaskIDs() async -> [Int] {
        await withCheckedContinuation { continuation in
            session.getAllTasks { tasks in
                continuation.resume(returning: tasks.map(\.taskIdentifier))
            }
        }
    }

    /// Remember the handler iOS waits for when it woke the app up.
    ///
    /// Creating the session here reconnects it to the transfers the system
    /// kept running; without it the delegate never hears from them.
    func setBackgroundCompletionHandler(
        _ handler: @escaping () -> Void,
        for identifier: String
    ) {
        _ = session
        lock.lock()
        backgroundHandlers[identifier] = handler
        lock.unlock()
    }
}

extension BackgroundUploadSession: URLSessionDataDelegate, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {}

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        let succeeded = error == nil && (200..<300).contains(status)
        guard let raw = task.taskDescription,
              let jobID = UUID(uuidString: raw)
        else {
            return
        }
        Task { @MainActor in
            PhotoBackupEngine.shared.handleCompletion(
                jobID: jobID,
                taskID: task.taskIdentifier,
                succeeded: succeeded
            )
        }
    }

    /// Every event of the session has been delivered; iOS may put the app back
    /// to sleep.
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let identifier = session.configuration.identifier ?? Self.identifier
        lock.lock()
        let handler = backgroundHandlers.removeValue(forKey: identifier)
        lock.unlock()
        handler?()
    }
}
